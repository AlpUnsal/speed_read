import SwiftUI
import UIKit

/// Renders one paragraph with TextKit (instead of SwiftUI `Text`) so word-level
/// hit testing and highlight rects come from the SAME layout engine that draws
/// the glyphs — taps and highlights are exact even at line-wrap boundaries.
///
/// Token indices in the callbacks are LOCAL to this paragraph's text; callers
/// convert to global word indices via the paragraph's wordStartIndex. Local
/// tokenization here reproduces the paragraph's slice of the global words
/// array 1:1 (both come from the same TextTokenizer pass over the same text).
struct ParagraphTextKitView: UIViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: UIColor
    let tracking: CGFloat
    let lineSpacing: CGFloat
    let alignment: NSTextAlignment
    let availableWidth: CGFloat
    /// True when `text` is tokens joined by single spaces (chunked paragraphs)
    /// — token ranges then come from a plain space split, which is exact.
    var isTokenJoined: Bool = false
    var highlightedTokenIndex: Int? = nil
    var highlightColor: UIColor = .clear
    /// Fired for any tap inside the paragraph, with the nearest token index.
    var onWordTapped: ((Int) -> Void)? = nil
    var onWordLongPressed: ((Int) -> Void)? = nil

    func makeUIView(context: Context) -> TextKitParagraphUIView {
        let view = TextKitParagraphUIView()

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.35
        view.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.require(toFail: longPress)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: TextKitParagraphUIView, context: Context) {
        uiView.configure(
            text: text,
            font: Self.resolveFont(name: fontName, size: fontSize),
            textColor: textColor,
            tracking: tracking,
            lineSpacing: lineSpacing,
            alignment: alignment,
            width: availableWidth,
            isTokenJoined: isTokenJoined
        )
        uiView.setHighlight(tokenIndex: highlightedTokenIndex, color: highlightColor)
        context.coordinator.onWordTapped = onWordTapped
        context.coordinator.onWordLongPressed = onWordLongPressed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWordTapped: onWordTapped, onWordLongPressed: onWordLongPressed)
    }

    static func resolveFont(name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }

    // MARK: - Height Measurement

    // Shared measuring stack — same TextKit configuration as the rendering
    // views, so measured heights match drawn heights exactly. Main thread only.
    private static let measuringStorage = NSTextStorage()
    private static let measuringLayoutManager = NSLayoutManager()
    private static let measuringContainer: NSTextContainer = {
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        measuringLayoutManager.addTextContainer(container)
        measuringStorage.addLayoutManager(measuringLayoutManager)
        return container
    }()
    private static var heightCache: [String: CGFloat] = [:]

    /// Height the paragraph needs at the given width. Cached — called from
    /// SwiftUI body for every visible row on every layout pass.
    static func preferredHeight(text: String, fontName: String, fontSize: CGFloat,
                                tracking: CGFloat, lineSpacing: CGFloat,
                                alignment: NSTextAlignment, width: CGFloat) -> CGFloat {
        guard width > 0, !text.isEmpty else { return 0 }
        let key = "\(text.count)|\(text.hashValue)|\(fontName)|\(fontSize)|\(tracking)|\(lineSpacing)|\(alignment.rawValue)|\(width)"
        if let cached = heightCache[key] { return cached }

        measuringStorage.setAttributedString(attributedString(
            text: text,
            font: resolveFont(name: fontName, size: fontSize),
            textColor: .black,
            tracking: tracking,
            lineSpacing: lineSpacing,
            alignment: alignment
        ))
        measuringContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        measuringLayoutManager.ensureLayout(for: measuringContainer)
        let height = ceil(measuringLayoutManager.usedRect(for: measuringContainer).height)

        if heightCache.count > 20000 { heightCache.removeAll() }
        heightCache[key] = height
        return height
    }

    static func attributedString(text: String, font: UIFont, textColor: UIColor,
                                 tracking: CGFloat, lineSpacing: CGFloat,
                                 alignment: NSTextAlignment) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = alignment
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor,
            .kern: tracking,
            .paragraphStyle: paragraphStyle
        ])
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var onWordTapped: ((Int) -> Void)?
        var onWordLongPressed: ((Int) -> Void)?

        init(onWordTapped: ((Int) -> Void)?, onWordLongPressed: ((Int) -> Void)?) {
            self.onWordTapped = onWordTapped
            self.onWordLongPressed = onWordLongPressed
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? TextKitParagraphUIView else { return }
            guard let index = view.tokenIndex(at: gesture.location(in: view)) else { return }
            onWordTapped?(index)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let view = gesture.view as? TextKitParagraphUIView else { return }
            guard let index = view.tokenIndex(at: gesture.location(in: view)) else { return }
            onWordLongPressed?(index)
        }
    }
}

// MARK: - Backing UIView

final class TextKitParagraphUIView: UIView {
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer: NSTextContainer = {
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        return container
    }()

    /// Local token index -> UTF-16 range in the displayed text.
    private var tokenNSRanges: [NSRange] = []
    private var configuredKey: String = ""

    // Translucent highlight over the word — reads as a text highlighter.
    // A CALayer so appearance/disappearance fades without redrawing glyphs.
    private let highlightLayer = CAShapeLayer()
    private var highlightedTokenIndex: Int? = nil

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        highlightLayer.opacity = 0
        layer.addSublayer(highlightLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(text: String, font: UIFont, textColor: UIColor, tracking: CGFloat,
                   lineSpacing: CGFloat, alignment: NSTextAlignment, width: CGFloat,
                   isTokenJoined: Bool) {
        let key = "\(text.count)|\(text.hashValue)|\(font.fontName)|\(font.pointSize)|\(tracking)|\(lineSpacing)|\(alignment.rawValue)|\(width)|\(textColor.hash)"
        guard key != configuredKey else { return }
        configuredKey = key

        textStorage.setAttributedString(ParagraphTextKitView.attributedString(
            text: text, font: font, textColor: textColor,
            tracking: tracking, lineSpacing: lineSpacing, alignment: alignment
        ))
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        // Token-joined text (chunks): ranges = space split, exact 1:1 with the
        // global words slice. Original paragraph text: same tokenizer pass that
        // produced the global words, so counts match by construction.
        if isTokenJoined {
            tokenNSRanges = Self.spaceSeparatedRanges(in: text)
        } else {
            tokenNSRanges = TextTokenizer.tokenizeWithRanges(text).map { NSRange($0.range, in: text) }
        }
        setNeedsDisplay()
    }

    private static func spaceSeparatedRanges(in text: String) -> [NSRange] {
        var result: [NSRange] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == " " {
                i = text.index(after: i)
                continue
            }
            var j = i
            while j < text.endIndex && text[j] != " " {
                j = text.index(after: j)
            }
            result.append(NSRange(i..<j, in: text))
            i = j
        }
        return result
    }

    override func draw(_ rect: CGRect) {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    // MARK: - Hit Testing

    /// Nearest token to a point — taps inside the paragraph always resolve.
    func tokenIndex(at point: CGPoint) -> Int? {
        guard !tokenNSRanges.isEmpty else { return nil }
        let charIndex = layoutManager.characterIndex(
            for: point,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        if let exact = tokenNSRanges.firstIndex(where: { NSLocationInRange(charIndex, $0) }) {
            return exact
        }
        // Between tokens (separator character) — take the nearest by distance.
        var best = 0
        var bestDistance = Int.max
        for (i, range) in tokenNSRanges.enumerated() {
            let distance = charIndex < range.location
                ? range.location - charIndex
                : charIndex - (range.location + max(range.length, 1) - 1)
            if distance < bestDistance {
                bestDistance = distance
                best = i
            }
        }
        return best
    }

    /// Bounding rect (view coordinates) of a token, from the live layout.
    func rect(forTokenIndex index: Int) -> CGRect? {
        guard index >= 0, index < tokenNSRanges.count else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: tokenNSRanges[index], actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return rect.isEmpty ? nil : rect
    }

    // MARK: - Highlight

    func setHighlight(tokenIndex: Int?, color: UIColor) {
        guard tokenIndex != highlightedTokenIndex else { return }
        highlightedTokenIndex = tokenIndex

        if let index = tokenIndex, let wordRect = rect(forTokenIndex: index) {
            let path = UIBezierPath(
                roundedRect: wordRect.insetBy(dx: -4, dy: -2),
                cornerRadius: 5
            )
            highlightLayer.path = path.cgPath
            highlightLayer.fillColor = color.cgColor
            animateHighlight(to: 1, duration: 0.15)
        } else {
            animateHighlight(to: 0, duration: 0.3)
        }
    }

    private func animateHighlight(to opacity: Float, duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = highlightLayer.presentation()?.opacity ?? highlightLayer.opacity
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        highlightLayer.opacity = opacity
        highlightLayer.add(animation, forKey: "opacity")
    }
}

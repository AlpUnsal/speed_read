import SwiftUI
import UIKit

struct ParagraphView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings = SettingsManager.shared
    var onTap: () -> Void
    var onWordTap: ((Int) -> Void)?
    var onScroll: (() -> Void)?
    var onSpeedScrub: ((CGFloat) -> Void)?
    var onSpeedScrubEnded: (() -> Void)?
    
    var body: some View {
        ParagraphTextView(
            text: viewModel.originalText,
            wordRanges: viewModel.wordRanges,
            currentIndex: viewModel.currentIndex,
            fontName: settings.fontName,
            fontSizeMultiplier: settings.fontSizeMultiplier,
            theme: settings.theme,
            textColor: settings.textColor,
            onTap: onTap,
            onWordTap: onWordTap,
            onScroll: onScroll,
            onSpeedScrub: onSpeedScrub,
            onSpeedScrubEnded: onSpeedScrubEnded
        )
        // Make text view background transparent so it sits on app background
        .background(Color.clear)
    }
}

struct ParagraphTextView: UIViewRepresentable {
    var text: String
    var wordRanges: [Range<String.Index>]
    var currentIndex: Int
    var fontName: String
    var fontSizeMultiplier: Double
    var theme: AppTheme
    var textColor: Color // Add binding
    var onTap: () -> Void
    var onWordTap: ((Int) -> Void)?
    var onScroll: (() -> Void)?
    var onSpeedScrub: ((CGFloat) -> Void)?
    var onSpeedScrubEnded: (() -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 80, right: 20)
        textView.showsVerticalScrollIndicator = true
        textView.delegate = context.coordinator
        
        // Tap gesture for jumping
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false // Allow touches to pass through
        tapGesture.delegate = context.coordinator
        textView.addGestureRecognizer(tapGesture)
        
        // Pan gesture for speed control (right side)
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        // This ensures vertical drags in the zone are captured by us, not the scroll view
        textView.addGestureRecognizer(panGesture)
        // Note: We'll rely on delegate 'shouldBegin' to limit this to the right side
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        // Update parent reference so coordinator has latest wordRanges
        coordinator.parent = self
        
        let font = UIFont(name: fontName, size: 24 * CGFloat(fontSizeMultiplier)) ?? UIFont.systemFont(ofSize: 24 * CGFloat(fontSizeMultiplier))
        let uiTextColor = UIColor(textColor)
        
        if coordinator.needsFullReload(text: text, fontName: fontName, fontSizeMultiplier: fontSizeMultiplier, theme: theme, textColor: uiTextColor) {
            
            coordinator.lastFontSizeMultiplier = fontSizeMultiplier
            coordinator.lastTheme = theme
            coordinator.lastTextColor = uiTextColor
            
            // Create paragraph style for spacing
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.5
            paragraphStyle.alignment = .left
            
            let fullAttribs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: uiTextColor.withAlphaComponent(0.4), // Increased visibility for dimmed text
                .paragraphStyle: paragraphStyle
            ]
            let attributedString = NSMutableAttributedString(string: text, attributes: fullAttribs)
            
            uiView.attributedText = attributedString
            
            // Re-highlight current
            coordinator.highlight(index: currentIndex, in: uiView, ranges: wordRanges, textColor: uiTextColor)
            
        } else if coordinator.lastIndex != currentIndex {
            // Just update highlight
            coordinator.updateHighlight(
                from: coordinator.lastIndex,
                to: currentIndex,
                in: uiView,
                ranges: wordRanges,
                textColor: uiTextColor
            )
        }
        
        coordinator.lastIndex = currentIndex
        
        // Auto-scroll logic - only auto-scroll if user is not manually scrolling
        // When user is scrolling or has scrolled, don't fight their scroll position
        if !coordinator.isUserScrolling && !wordRanges.isEmpty && currentIndex < wordRanges.count {
            if let range = rangeToNSRange(wordRanges[currentIndex], in: text) {
                let glyphRange = uiView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = uiView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: uiView.textContainer)
                
                let targetCenterY = rect.midY + uiView.textContainerInset.top
                let visibleHeight = uiView.bounds.height
                let desiredOffsetY = targetCenterY - (visibleHeight / 2)
                
                let maxOffsetY = max(0, uiView.contentSize.height - visibleHeight)
                let finalOffsetY = min(max(0, desiredOffsetY), maxOffsetY)
                
                uiView.setContentOffset(CGPoint(x: 0, y: finalOffsetY), animated: true)
            }
        }
    }
    
    // Helper to convert Range<String.Index> to NSRange
    private func rangeToNSRange(_ range: Range<String.Index>, in text: String) -> NSRange? {
        return NSRange(range, in: text)
    }
    
    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ParagraphTextView
        weak var textView: UITextView?
        
        var lastText: String = ""
        var lastFontName: String = ""
        var lastFontSizeMultiplier: Double = 1.0
        var lastTheme: AppTheme = .black
        var lastTextColor: UIColor = .white
        var lastIndex: Int = -1
        var isUserScrolling: Bool = false
        
        init(_ parent: ParagraphTextView) {
            self.parent = parent
        }
        
        func needsFullReload(text: String, fontName: String, fontSizeMultiplier: Double, theme: AppTheme, textColor: UIColor) -> Bool {
            return text != lastText || fontName != lastFontName || fontSizeMultiplier != lastFontSizeMultiplier || theme != lastTheme || textColor != lastTextColor
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else {
                parent.onTap()
                return
            }
            
            let location = gesture.location(in: textView)
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            
            // Adjust for text container inset only
            var adjustedLocation = location
            adjustedLocation.x -= textView.textContainerInset.left
            adjustedLocation.y -= textView.textContainerInset.top
            
            // Get character index at tap location
            let characterIndex = layoutManager.characterIndex(for: adjustedLocation, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            
            // Find which word this character belongs to
            let text = textView.text ?? ""
            for (wordIndex, range) in parent.wordRanges.enumerated() {
                if let nsRange = parent.rangeToNSRange(range, in: text) {
                    if characterIndex >= nsRange.location && characterIndex < nsRange.location + nsRange.length {
                        // Found the tapped word
                        parent.onWordTap?(wordIndex)
                        return
                    }
                }
            }
            
            // Tapped outside any word
            parent.onTap()
        }
        
        private func word(at index: Int, in text: String) -> String {
            guard index >= 0 && index < parent.wordRanges.count else { return "" }
            let range = parent.wordRanges[index]
            return String(text[range])
        }
        
        // MARK: - UITextViewDelegate
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserScrolling = true
            parent.onScroll?()
        }
        
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserScrolling = false
            }
        }
        
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserScrolling = false
        }
        
        func highlight(index: Int, in textView: UITextView, ranges: [Range<String.Index>], textColor: UIColor) {
            guard index >= 0 && index < ranges.count,
                  let range = parent.rangeToNSRange(ranges[index], in: textView.text) else { return }
            
            // We need mutable attributed text
            guard let storage = textView.textStorage as NSTextStorage? else { return }
            
            // Apply highlight attributes
            let highlightAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: UIFont(name: parent.fontName, size: 24 * CGFloat(parent.fontSizeMultiplier))?.bold() ?? UIFont.systemFont(ofSize: 24 * CGFloat(parent.fontSizeMultiplier), weight: .bold)
            ]
            
            storage.addAttributes(highlightAttributes, range: range)
        }

        // MARK: - Speed Control Pan Gesture
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            
            switch gesture.state {
            case .changed:
                let velocity = gesture.velocity(in: textView)
                // Invert Y because dragging up (negative) usually means "increase" in this context (slider up)
                // But velocity.y < 0 means moving up.
                // We pass the translation or velocity to the parent.
                // Using translation for smoother scrubbing might be better, or velocity for momentum.
                // The previous implementation used translation.height on Changed.
                let translation = gesture.translation(in: textView)
                
                // We use translation.y. Dragging UP (negative y) should INCREASE speed.
                // Dragging DOWN (positive y) should DECREASE speed.
                // Passing raw Y translation.
                parent.onSpeedScrub?(translation.y)
                
                // Reset translation to avoid accumulating large values if we want relative deltas,
                // BUT the previous view logic expected cumulative translation from start of drag
                // or checked translation delta. The previous logic was:
                // let delta = -value.translation.height * sensitivity / 100
                // So let's pass the translation and let callbacks handle it? 
                // Actually the closure expects a delta. Let's send the *delta* since last change.
                gesture.setTranslation(.zero, in: textView)
                
            case .ended, .cancelled:
                parent.onSpeedScrubEnded?()
            default:
                break
            }
        }
        
        // MARK: - UIGestureRecognizerDelegate
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView else { return true }
            
            if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                let location = panGesture.location(in: textView)
                let bounds = textView.bounds
                
                // Define speed control zone: Right 35%, Bottom 60%
                // (Matches RSVPView: width 0.35, height 0.6, pos x 0.85 (right edge), y 0.65 (bottomish))
                let zoneWidth = bounds.width * 0.35
                let zoneHeight = bounds.height * 0.6
                // RSVPView zone was roughly centered vertically at 0.65, so it goes from 0.35 to 0.95 height?
                // Let's simplest approximation: Right 35%, Bottom 60% of visible area.
                // CAREFUL: TextView bounds.height might be huge (content size). We want VISIBLE area.
                
                // We need the visible rect, which is effectively bounds.size (since bounds origin shifts with scroll)
                // Wait, bounds.origin shifts with scroll? Yes. 
                // frame is in superview coords. bounds is in self coords.
                // location is in bounds coords.
                // To check "screen" position, we need to compare location relative to bounds.origin.
                
                let visibleRect = textView.convert(textView.bounds, to: nil)
                // This converts to window coords. But more simply:
                // Relative X position within the *visible* frame:
                let relativeX = location.x - textView.contentOffset.x
                let relativeY = location.y - textView.contentOffset.y
                
                // Check if touch is in right 35% of width
                let isRightSide = relativeX > (textView.frame.width * (1.0 - 0.35))
                
                // Check if touch is in bottom 60% of height
                let isBottomSide = relativeY > (textView.frame.height * (1.0 - 0.6))
                
                if isRightSide && isBottomSide {
                    return true // This is our custom pan gesture, we want to start
                } else {
                    return false // Not in zone, let validation fail so scroll view can take over
                }
            }
            
            return true
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow tap gesture to recognize alongside others (like selection clearing if any)
            if gestureRecognizer is UITapGestureRecognizer {
                return true
            }
            return false
        }


        func updateHighlight(from oldIndex: Int, to newIndex: Int, in textView: UITextView, ranges: [Range<String.Index>], textColor: UIColor) {
            guard let storage = textView.textStorage as NSTextStorage? else { return }
            
            // Re-resolve font for consistency
            let pointSize = 24 * CGFloat(parent.fontSizeMultiplier)
            let baseFont = UIFont(name: parent.fontName, size: pointSize) ?? UIFont.systemFont(ofSize: pointSize)
            let boldFont = baseFont.bold()
            
            if oldIndex >= 0 && oldIndex < ranges.count {
                if let oldRange = parent.rangeToNSRange(ranges[oldIndex], in: textView.text) {
                    // Reset to dimmed and normal weight
                    let dimmedAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: textColor.withAlphaComponent(0.3),
                        .font: baseFont
                    ]
                    storage.setAttributes(dimmedAttrs, range: oldRange)
                }
            }
            
            if newIndex >= 0 && newIndex < ranges.count {
                if let newRange = parent.rangeToNSRange(ranges[newIndex], in: textView.text) {
                    // Set to highlight and bold
                    let highlightAttrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: textColor,
                        .font: boldFont
                    ]
                    storage.addAttributes(highlightAttrs, range: newRange)
                }
            }
        }
    }
}

// Helper to get bold version of custom font
extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = self.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0) // 0 keeps original size
    }
}

import SwiftUI
import UIKit

struct ParagraphView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings = SettingsManager.shared
    var onTap: () -> Void
    
    var body: some View {
        ParagraphTextView(
            text: viewModel.originalText,
            wordRanges: viewModel.wordRanges,
            currentIndex: viewModel.currentIndex,
            fontName: settings.fontName,
            fontSizeMultiplier: settings.fontSizeMultiplier,
            theme: settings.theme,
            onTap: onTap
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
    var onTap: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = false // Prevent selection for smoother reading
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 80, right: 20) // Bottom padding for controls
        textView.showsVerticalScrollIndicator = true
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        textView.addGestureRecognizer(tapGesture)
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        let coordinator = context.coordinator
        
        // Check if we need to full reload (font, theme, or text changed)
        // We use a simplified check: if text length differs or theme/font changed
        let font = UIFont(name: fontName, size: 24 * CGFloat(fontSizeMultiplier)) ?? UIFont.systemFont(ofSize: 24 * CGFloat(fontSizeMultiplier))
        let textColor = UIColor(SettingsManager.shared.textColor)
        
        if coordinator.needsFullReload(text: text, fontName: fontName, fontSizeMultiplier: fontSizeMultiplier, theme: theme) {
            
            let fullAttribs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor.withAlphaComponent(0.3) // Dimmed by default
            ]
            let attributedString = NSMutableAttributedString(string: text, attributes: fullAttribs)
            
            uiView.attributedText = attributedString
            coordinator.lastText = text
            coordinator.lastFontName = fontName
            coordinator.lastFontSizeMultiplier = fontSizeMultiplier
            coordinator.lastTheme = theme
            
            // Re-highlight current
            coordinator.highlight(index: currentIndex, in: uiView, ranges: wordRanges, textColor: textColor)
            
        } else if coordinator.lastIndex != currentIndex {
            // Just update highlight
            coordinator.updateHighlight(
                from: coordinator.lastIndex,
                to: currentIndex,
                in: uiView,
                ranges: wordRanges,
                textColor: textColor
            )
        }
        
        coordinator.lastIndex = currentIndex
        
        // Auto-scroll logic
        // Only auto-scroll if playing? Or always?
        // Let's safe-scroll to always keep the current line in view
        if !wordRanges.isEmpty && currentIndex < wordRanges.count {
            if let range = rangeToNSRange(wordRanges[currentIndex], in: text) {
                // Ensure layout is up to date before scrolling
                // uiView.layoutManager.ensureLayout(for: uiView.textContainer)
                
                // We want the highlighted word to be somewhat centered vertically if possible, or usually just visible
                // 'scrollRangeToVisible' does minimal scrolling.
                // To keep it centered is better for reading.
                let glyphRange = uiView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = uiView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: uiView.textContainer)
                
                // Calculate centered offset
                // Target Y = rect.center.y
                // View Center Y = view.height / 2
                // Offset = Target Y - View Center Y
                // Also account for content insets if any
                
                let targetCenterY = rect.midY + uiView.textContainerInset.top
                let visibleHeight = uiView.bounds.height
                let desiredOffsetY = targetCenterY - (visibleHeight / 2)
                
                // Clamp offset
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
    
    class Coordinator: NSObject {
        var parent: ParagraphTextView
        
        var lastText: String = ""
        var lastFontName: String = ""
        var lastFontSizeMultiplier: Double = 1.0
        var lastTheme: AppTheme = .dark
        var lastIndex: Int = -1
        
        init(_ parent: ParagraphTextView) {
            self.parent = parent
        }
        
        func needsFullReload(text: String, fontName: String, fontSizeMultiplier: Double, theme: AppTheme) -> Bool {
            return text != lastText || fontName != lastFontName || fontSizeMultiplier != lastFontSizeMultiplier || theme != lastTheme
        }
        
        @objc func handleTap() {
            parent.onTap()
        }
        
        func highlight(index: Int, in textView: UITextView, ranges: [Range<String.Index>], textColor: UIColor) {
            guard index >= 0 && index < ranges.count,
                  let range = parent.rangeToNSRange(ranges[index], in: textView.text) else { return }
            
            // We need mutable attributed text
            guard let storage = textView.textStorage as NSTextStorage? else { return }
            
            // Apply highlight attributes
            // Apply highlight attributes
            let highlightAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor(SettingsManager.shared.textColor),
                .font: UIFont(name: parent.fontName, size: 24 * CGFloat(parent.fontSizeMultiplier))?.bold() ?? UIFont.systemFont(ofSize: 24 * CGFloat(parent.fontSizeMultiplier), weight: .bold)
                // Use custom bold function or fallback
            ]
            
            storage.addAttributes(highlightAttributes, range: range)
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

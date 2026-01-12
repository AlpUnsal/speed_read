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
                
                // Convert to content offset
                let centeredY = rect.origin.y + rect.height/2 - uiView.bounds.height/2
                
                // Only animate if the distance is significant to avoid jitter, or just uses setContentOffset with animation
                // But we want smooth scrolling. Text View scrollRangeToVisible is standard.
                uiView.scrollRangeToVisible(range)
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
            let highlightAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor(SettingsManager.shared.textColor), // Full Opacity
                // We could add a background color if desired, but request was just "opaque"
                // .backgroundColor: UIColor.yellow.withAlphaComponent(0.3)
            ]
            
            storage.addAttributes(highlightAttributes, range: range)
            
            // Optional: Accent color for the specific word? user said "one word is highlighted".
            // Implementation Plan said "Full opacity + Accent Color".
            // Let's use Accent Color for even better visibility?
            // "where one word is highlighted while the rest are lightly greyed out and less opaque" -> implies logic is opacity diff.
            // But let's add bold or accent for clarity. The "Current Word" in RSVP is usually accented (red center).
            // Let's just make it full opacity normal color for now to be strictly "paragraph form".
            // Update: User request said "one word is highlighted". Standard highligher is yellow background or bold.
            // Let's stick to Opacity 1.0 vs 0.3.
        }
        
        func updateHighlight(from oldIndex: Int, to newIndex: Int, in textView: UITextView, ranges: [Range<String.Index>], textColor: UIColor) {
            guard let storage = textView.textStorage as NSTextStorage? else { return }
            
            if oldIndex >= 0 && oldIndex < ranges.count {
                if let oldRange = parent.rangeToNSRange(ranges[oldIndex], in: textView.text) {
                    // Reset to dimmed
                    storage.addAttribute(.foregroundColor, value: textColor.withAlphaComponent(0.3), range: oldRange)
                }
            }
            
            if newIndex >= 0 && newIndex < ranges.count {
                if let newRange = parent.rangeToNSRange(ranges[newIndex], in: textView.text) {
                    // Set to highlight
                    storage.addAttribute(.foregroundColor, value: textColor, range: newRange)
                }
            }
        }
    }
}

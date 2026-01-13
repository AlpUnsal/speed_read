import SwiftUI

struct WordDisplayView: View {
    let word: String
    let fontSize: CGFloat
    var fontName: String = "EBGaramond-Regular" // Default
    var theme: AppTheme = .black // Default
    
    // Colors
    private var textColor: Color {
        switch theme {
        case .light: return Color(hex: "1A1A1A")
        default: return Color(hex: "E5E5E5")
        }
    }
    private let highlightColor = Color(hex: "E63946")
    
    // Animation state
    @State private var isVisible = false
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                    Text(String(character))
                        .font(.custom(fontName, size: fontSize))
                        .foregroundColor(index == 1 ? highlightColor : textColor)
                }
            }
            .position(x: calculateXPosition(in: geometry), y: geometry.size.height / 2)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.9)
        }
        .onChange(of: word) { _ in
            // Reset and trigger animation
            isVisible = false
            withAnimation(.easeOut(duration: 0.08)) {
                isVisible = true
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.1)) {
                isVisible = true
            }
        }
    }
    
    /// Calculate X position so that the second letter (ORP) is slightly left of center
    /// This makes average-length words appear more visually centered
    private func calculateXPosition(in geometry: GeometryProxy) -> CGFloat {
        // Anchor point is offset left of center for better visual balance
        let anchorX = geometry.size.width * 0.38
        
        guard word.count > 1 else {
            // Single letter word - just center it
            return anchorX
        }
        
        // Calculate width of first character to offset the word
        let firstChar = String(word.prefix(1))
        let firstCharWidth = firstChar.size(withFont: UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)).width
        
        // Calculate width of second character (the ORP)
        let secondChar = String(word.dropFirst().prefix(1))
        let secondCharWidth = secondChar.size(withFont: UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)).width
        
        // Calculate total word width
        let wordWidth = word.size(withFont: UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)).width
        
        // Position so the center of the second character is at anchor point
        let offsetX = firstCharWidth + (secondCharWidth / 2)
        
        return anchorX - offsetX + (wordWidth / 2)
    }
    
    /// Dynamic font size based on word length
    static func fontSize(for word: String) -> CGFloat {
        let length = word.count
        switch length {
        case 0...12: return 48
        case 13...18: return 36
        case 19...24: return 28
        default: return 22
        }
    }
}

// MARK: - String Extension for measuring text width
extension String {
    func size(withFont font: UIFont) -> CGSize {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes)
    }
}

#Preview {
    ZStack {
        Color(hex: "1A1A1A")
        WordDisplayView(word: "Reading", fontSize: 48)
    }
}

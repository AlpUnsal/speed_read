import SwiftUI

struct WordDisplayView: View {
    let word: String
    let fontSize: CGFloat
    var fontName: String = "EBGaramond-Regular" // Default
    var theme: AppTheme = .black // Default
    var animate: Bool = true
    var useAbsolutePositioning: Bool = true
    
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
        if useAbsolutePositioning {
            GeometryReader { geometry in
                wordContent
                    .position(x: calculateXPosition(in: geometry), y: geometry.size.height / 2)
            }
        } else {
            wordContent
        }
    }
    
    private var wordContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                Text(String(character))
                    .font(.custom(fontName, size: fontSize))
                    .foregroundColor((index == 1 || (word.count == 1 && index == 0)) ? highlightColor : textColor)
            }
        }
        .opacity((animate && !isVisible) ? 0 : 1)
        .scaleEffect((animate && !isVisible) ? 0.9 : 1)
        .onChange(of: word) { _ in
            if animate {
                // Reset and trigger animation
                isVisible = false
                withAnimation(.easeOut(duration: 0.08)) {
                    isVisible = true
                }
            }
        }
        .onAppear {
            if animate {
                withAnimation(.easeOut(duration: 0.1)) {
                    isVisible = true
                }
            } else {
                isVisible = true
            }
        }
    }
    
    /// Calculate X position so that the second letter (ORP) is slightly left of center
    private func calculateXPosition(in geometry: GeometryProxy) -> CGFloat {
        // Anchor point is offset left of center for better visual balance
        let anchorX = geometry.size.width * 0.38
        
        guard word.count > 1 else {
            return anchorX
        }
        
        let offset = calculateORPOffset()
        let wordWidth = word.size(withFont: UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)).width
        
        return anchorX - offset + (wordWidth / 2)
    }
    
    /// Calculates distance from start of word to center of ORP (2nd char)
    func calculateORPOffset() -> CGFloat {
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        
        if word.count <= 1 {
            return word.size(withFont: font).width / 2
        }
        
        // Width of first char
        let firstChar = String(word.prefix(1))
        let firstCharWidth = firstChar.size(withFont: font).width
        
        // Width of second char
        let secondChar = String(word.dropFirst().prefix(1))
        let secondCharWidth = secondChar.size(withFont: font).width
        
        return firstCharWidth + (secondCharWidth / 2)
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

// Note: String.size(withFont:) extension is now in FontMetricsCache.swift


#Preview {
    ZStack {
        Color(hex: "1A1A1A")
        WordDisplayView(word: "Reading", fontSize: 48)
    }
}

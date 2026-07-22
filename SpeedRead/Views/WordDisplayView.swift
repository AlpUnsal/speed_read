import SwiftUI

struct WordDisplayView: View {
    let word: String
    let fontSize: CGFloat
    var fontName: String = "EBGaramond-Regular" // Default
    var theme: AppTheme = .black // Default
    var animate: Bool = true
    var useAbsolutePositioning: Bool = true
    
    @ObservedObject var settings = SettingsManager.shared
    
    // Colors
    private var textColor: Color {
        switch theme {
        case .black, .grey: return Color(hex: "E5E5E5")
        case .sage: return Color(hex: "758B7D")
        case .iceBlue: return Color(hex: "6A8294")
        case .cherry: return Color(hex: "9E747A")
        case .lilac: return Color(hex: "816B99")
        default: return Color(hex: "1A1A1A")
        }
    }
    
    private var highlightColor: Color {
        switch theme {
        case .sage: return Color(hex: "1A4D2E")
        case .iceBlue: return Color(hex: "134B6E")
        case .cherry: return Color(hex: "8A2533")
        case .lilac: return Color(hex: "4E1D7B")
        default: return Color(hex: "E63946")
        }
    }
    
    // Animation state
    @State private var isVisible = false
    
    var body: some View {
        if useAbsolutePositioning {
            GeometryReader { geometry in
                ZStack {
                    wordContent
                        .position(x: calculateXPosition(in: geometry), y: geometry.size.height / 2)
                    
                    if settings.showORPEmphasisLines {
                        let anchorX = geometry.size.width * 0.325
                        let centerY = geometry.size.height / 2
                        
                        // Use constants based on 48.0 max font size for stability
                        // Scaled to match landscape mode and user font scaling settings
                        let scaleFactor = fontSize / WordDisplayView.fontSize(for: word)
                        let baseFontSize: CGFloat = 48.0 * scaleFactor
                        let lineLength = baseFontSize * 0.25
                        
                        // Asymmetric spacing:
                        // Top line closer to accommodate x-height (lowercase & ascenders)
                        let topOffset = baseFontSize * 0.75
                        
                        // Bottom line pushed further down to safely clear descenders
                        let bottomOffset = baseFontSize * 0.95
                        
                        ZStack {
                            Rectangle()
                                .fill(textColor.opacity(0.3))
                                .frame(width: 1.5, height: lineLength)
                                .position(x: anchorX, y: centerY - topOffset)
                                
                            Rectangle()
                                .fill(textColor.opacity(0.3))
                                .frame(width: 1.5, height: lineLength)
                                .position(x: anchorX, y: centerY + bottomOffset)
                        }
                    }
                }
            }
        } else {
            wordContent
        }
    }
    
    private var wordContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                let isORP = (index == FontMetricsCache.orpIndex(for: word))
                Text(String(character))
                    .font(.custom(fontName, size: fontSize))
                    .foregroundColor(isORP ? highlightColor : textColor)
            }
        }
        .opacity((animate && !isVisible) ? 0 : 1)
        .scaleEffect((animate && !isVisible) ? 0.9 : 1)
        .onChange(of: word) { _, _ in
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
        let anchorX = geometry.size.width * 0.325

        guard word.count > 1 else {
            return anchorX
        }
        
        let offset = calculateORPOffset()
        let wordWidth = word.size(withFont: UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)).width
        
        return anchorX - offset + (wordWidth / 2)
    }
    
    /// Calculates distance from start of word to center of ORP character
    func calculateORPOffset() -> CGFloat {
        return FontMetricsCache.shared.orpOffset(for: word, fontName: fontName, fontSize: fontSize)
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

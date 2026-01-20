import SwiftUI

@available(iOS 17.0, *)
struct ParagraphView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings = SettingsManager.shared
    
    // Callbacks (kept for compatibility with parent view, though some might be unused in new design)
    var onTap: () -> Void
    var onWordTap: ((Int) -> Void)?
    var onScroll: (() -> Void)?
    var onSpeedScrub: ((CGFloat) -> Void)?
    var onSpeedScrubEnded: (() -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 15) {
                        ForEach(Array(viewModel.words.enumerated()), id: \.offset) { index, word in
                            WordRow(
                                word: word,
                                index: index,
                                currentIndex: viewModel.currentIndex,
                                settings: settings,
                                geometry: geometry
                            )
                            .id(index)
                            .onTapGesture {
                                withAnimation {
                                    viewModel.goToIndex(index)
                                }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: Binding(
                    get: { viewModel.currentIndex },
                    set: { newValue in
                        if let index = newValue {
                            viewModel.goToIndex(index)
                        }
                    }
                ))
                .safeAreaPadding(.top, geometry.size.height / 2 - 24) // Center first item (approx half height)
                .safeAreaPadding(.bottom, geometry.size.height / 2 - 24) // Center last item
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.clear)
    }
}

struct WordRow: View {
    let word: String
    let index: Int
    let currentIndex: Int
    let settings: SettingsManager
    let geometry: GeometryProxy
    
    var body: some View {
        let isCurrent = index == currentIndex
        
        // Calculate font size logic similar to WordDisplayView but maybe uniform or scaled?
        // User requested: "Active Word: 100% opacity, standard size... Context Words: Faded... potentially slightly smaller"
        // Let's stick to standard size for alignment consistency, or slight scale.
        
        let standardFontSize = WordDisplayView.fontSize(for: word) * settings.fontSizeMultiplier
        let fontSize = isCurrent ? standardFontSize : standardFontSize * 0.85
        
        // Alignment Guide Logic:
        // We want the ORP (Red Letter) to be at a specific screen X percent.
        // Screen Anchors: 
        // RSVP View uses: anchorX = geometry.size.width * 0.38
        // So we need to shift THIS view so that its ORP is at 0.38 * width.
        
        // We will use a ZStack with an offset.
        // Or better: Use 'frame(width: geometry.size.width)' and offset the content.
        
        ZStack(alignment: .leading) {
            WordDisplayView(
                word: word,
                fontSize: fontSize,
                fontName: settings.fontName,
                theme: settings.theme,
                animate: false,
                useAbsolutePositioning: false
            )
            .opacity(isCurrent ? 1.0 : 0.3)
            .saturation(isCurrent ? 1.0 : 0.0) // Monochrome for context words
            // Calculate Offset to align ORP to anchor
            .modifier(ORPAlignmentModifier(
                word: word,
                fontSize: fontSize,
                fontName: settings.fontName,
                screenWidth: geometry.size.width
            ))
        }
        .frame(height: 50) // Fixed height for row stability?
        .frame(width: geometry.size.width, alignment: .leading)
    }
}

struct ORPAlignmentModifier: ViewModifier {
    let word: String
    let fontSize: CGFloat
    let fontName: String
    let screenWidth: CGFloat
    
    func body(content: Content) -> some View {
        content.offset(x: calculateOffset())
    }
    
    private func calculateOffset() -> CGFloat {
        // Target Screen X for ORP
        let targetX = screenWidth * 0.18
        
        // Calculate ORP location relative to start of word
        let orpOffset = calculateORPInternalOffset()
        
        // We want (WordStart + orpOffset) = targetX
        // WordStart = targetX - orpOffset
        // Since the ZStack is aligned .leading (at 0), we just offset by this amount.
        return targetX - orpOffset
    }
    
    private func calculateORPInternalOffset() -> CGFloat {
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        
        if word.count <= 1 {
            return word.size(withFont: font).width / 2
        }
        
        let firstChar = String(word.prefix(1))
        let firstCharWidth = firstChar.size(withFont: font).width
        
        let secondChar = String(word.dropFirst().prefix(1))
        let secondCharWidth = secondChar.size(withFont: font).width
        
        return firstCharWidth + (secondCharWidth / 2)
    }
    
    // Helper duplicate from WordDisplayView - ideally shared but convenient here
}



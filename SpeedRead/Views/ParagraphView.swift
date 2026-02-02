import SwiftUI

@available(iOS 17.0, *)
struct ParagraphView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings = SettingsManager.shared
    
    // Callbacks (kept for compatibility with parent view)
    var onTap: () -> Void
    var onWordTap: ((Int) -> Void)?
    var onScroll: (() -> Void)?
    var onSpeedScrub: ((CGFloat) -> Void)?
    var onSpeedScrubEnded: (() -> Void)?
    
    var body: some View {
        GeometryReader { geometry in
            let centerY = geometry.size.height / 2
            
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 15) {
                        ForEach(viewModel.wordLayoutData.indices, id: \.self) { index in
                            OptimizedWordRow(
                                layoutData: viewModel.wordLayoutData[index],
                                index: index,
                                currentIndex: viewModel.currentIndex,
                                settings: settings,
                                screenWidth: geometry.size.width
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
                    .drawingGroup() // Rasterize to Metal for smoother scrolling
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
                // Position the current word in the lower portion of the screen
                .safeAreaPadding(.top, geometry.size.height * 0.6) // Push content down
                .safeAreaPadding(.bottom, geometry.size.height * 0.15)
                .scrollIndicators(.hidden)
            }
            // Apply gradient mask to fade words at top and bottom
            .mask(
                VStack(spacing: 0) {
                    // Top fade: transparent -> opaque (larger area above the word)
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.5)
                    
                    // Middle: fully visible (where the current word sits)
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: geometry.size.height * 0.15)
                    
                    // Bottom fade: opaque -> transparent (smaller area below)
                    LinearGradient(
                        gradient: Gradient(colors: [.black, .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.35)
                }
            )
        }
        .background(Color.clear)
    }
}

// MARK: - Optimized Word Row (Equatable for performance)

struct OptimizedWordRow: View, Equatable {
    let layoutData: RSVPViewModel.WordLayoutData
    let index: Int
    let currentIndex: Int
    let settings: SettingsManager
    let screenWidth: CGFloat
    
    // Equatable conformance - only re-render when these change
    static func == (lhs: OptimizedWordRow, rhs: OptimizedWordRow) -> Bool {
        lhs.index == rhs.index &&
        lhs.currentIndex == rhs.currentIndex &&
        lhs.layoutData == rhs.layoutData &&
        lhs.screenWidth == rhs.screenWidth
    }
    
    var body: some View {
        let isCurrent = index == currentIndex
        
        // Use precomputed font size, scale down for non-current
        let fontSize = isCurrent ? layoutData.fontSize : layoutData.fontSize * 0.85
        
        ZStack(alignment: .leading) {
            if isCurrent {
                // Full WordDisplayView with ORP highlighting for current word
                WordDisplayView(
                    word: layoutData.word,
                    fontSize: fontSize,
                    fontName: settings.fontName,
                    theme: settings.theme,
                    animate: false,
                    useAbsolutePositioning: false
                )
            } else {
                // Simplified text rendering for context words (much faster)
                SimpleWordText(
                    word: layoutData.word,
                    fontSize: fontSize,
                    fontName: settings.fontName,
                    textColor: settings.textColor.opacity(0.3)
                )
            }
        }
        .frame(height: 50)
        .frame(width: screenWidth, alignment: .leading)
        .offset(x: calculateOffset(fontSize: fontSize))
    }
    
    /// Calculate X offset to align ORP at target position
    private func calculateOffset(fontSize: CGFloat) -> CGFloat {
        let targetX = screenWidth * 0.18
        
        // Scale the precomputed ORP offset if font size changed
        let isCurrent = index == currentIndex
        let scaleFactor: CGFloat = isCurrent ? 1.0 : 0.85
        let orpOffset = layoutData.orpOffset * scaleFactor
        
        return targetX - orpOffset
    }
}

// MARK: - Simple Word Text (fast rendering for context words)

struct SimpleWordText: View {
    let word: String
    let fontSize: CGFloat
    let fontName: String
    let textColor: Color
    
    var body: some View {
        Text(word)
            .font(.custom(fontName, size: fontSize))
            .foregroundColor(textColor)
    }
}

import SwiftUI

// MARK: - Scroll Offset Preference Key (kept for fallback)

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@available(iOS 17.0, *)
struct ParagraphView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings = SettingsManager.shared
    
    // Callbacks
    var onTap: () -> Void
    var onWordTap: ((Int) -> Void)?
    var onScroll: (() -> Void)?
    var onSpeedScrub: ((CGFloat) -> Void)?
    var onSpeedScrubEnded: (() -> Void)?
    
    // Scroll position tracking using iOS 17 API
    @State private var scrollPosition: Int?
    @State private var isUserScrolling = false
    
    private let rowHeight: CGFloat = 65  // 50 height + 15 spacing
    
    var body: some View {
        GeometryReader { geometry in
            let fontName = settings.fontName
            let theme = settings.theme
            let windowStart = viewModel.windowStartIndex
            let focalPointY = geometry.size.height * 0.65
            
            // The highlighted word is the scroll position (during scroll) or viewModel.currentIndex
            let highlightedIndex = scrollPosition ?? viewModel.currentIndex
            
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 15) {
                        ForEach(Array(viewModel.visibleLayoutData.enumerated()), id: \.offset) { displayIndex, layoutData in
                            let actualIndex = windowStart + displayIndex
                            let isCurrent = actualIndex == highlightedIndex
                            
                            WordRowView(
                                word: layoutData.word,
                                fontSize: isCurrent ? layoutData.fontSize : layoutData.fontSize * 0.85,
                                orpOffset: layoutData.orpOffset * (isCurrent ? 1.0 : 0.85),
                                isCurrent: isCurrent,
                                fontName: fontName,
                                theme: theme,
                                screenWidth: geometry.size.width
                            )
                            .id(actualIndex)
                            .onTapGesture {
                                viewModel.goToIndex(actualIndex)
                                scrollPosition = actualIndex
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.top, focalPointY)
                    .padding(.bottom, geometry.size.height * 0.35)
                }
                .scrollPosition(id: $scrollPosition, anchor: UnitPoint(x: 0.5, y: 0.65))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            if !isUserScrolling {
                                isUserScrolling = true
                                onScroll?()
                            }
                        }
                        .onEnded { _ in
                            // Sync to viewModel when scroll ends
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isUserScrolling = false
                                if let pos = scrollPosition {
                                    viewModel.goToIndex(pos)
                                }
                            }
                        }
                )
                .onChange(of: viewModel.currentIndex) { _, newIndex in
                    // When viewModel changes (playback), update scroll position
                    if !isUserScrolling {
                        scrollPosition = newIndex
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0.5, y: 0.65))
                        }
                    }
                }
                .onAppear {
                    scrollPosition = viewModel.currentIndex
                    proxy.scrollTo(viewModel.currentIndex, anchor: UnitPoint(x: 0.5, y: 0.65))
                }
            }
            // Gradient mask
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.55)
                    
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: geometry.size.height * 0.15)
                    
                    LinearGradient(
                        gradient: Gradient(colors: [.black, .clear]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.30)
                }
            )
        }
        .background(Color.clear)
    }
}

// MARK: - Word Row View

struct WordRowView: View, Equatable {
    let word: String
    let fontSize: CGFloat
    let orpOffset: CGFloat
    let isCurrent: Bool
    let fontName: String
    let theme: AppTheme
    let screenWidth: CGFloat
    
    static func == (lhs: WordRowView, rhs: WordRowView) -> Bool {
        lhs.word == rhs.word &&
        lhs.fontSize == rhs.fontSize &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.fontName == rhs.fontName &&
        lhs.theme == rhs.theme &&
        lhs.screenWidth == rhs.screenWidth
    }
    
    private var textColor: Color {
        switch theme {
        case .light: return Color(hex: "1A1A1A")
        default: return Color(hex: "E5E5E5")
        }
    }
    
    private var contextColor: Color {
        switch theme {
        case .light: return Color(hex: "1A1A1A").opacity(0.3)
        default: return Color(hex: "E5E5E5").opacity(0.3)
        }
    }
    
    private let highlightColor = Color(hex: "E63946")
    
    var body: some View {
        HStack(spacing: 0) {
            if isCurrent {
                ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                    Text(String(character))
                        .font(.custom(fontName, size: fontSize))
                        .foregroundColor(orpIndex(for: word) == index ? highlightColor : textColor)
                }
            } else {
                Text(word)
                    .font(.custom(fontName, size: fontSize))
                    .foregroundColor(contextColor)
            }
        }
        .frame(height: 50)
        .frame(width: screenWidth, alignment: .leading)
        .offset(x: screenWidth * 0.18 - orpOffset)
    }
    
    private func orpIndex(for word: String) -> Int {
        word.count <= 1 ? 0 : 1
    }
}

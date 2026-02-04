import SwiftUI

// MARK: - Scroll Offset Preference Key (kept for fallback)

// MARK: - Item Position Preference Key
private struct ItemMinYPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
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
    @StateObject private var scrollManager = ScrollManager()
    @State private var lastScrollTime: Date = .distantPast
    
    private let rowHeight: CGFloat = 65  // 50 height + 15 spacing
    
    var body: some View {
        GeometryReader { geometry in
            let fontName = settings.fontName
            let theme = settings.theme
            let windowStart = viewModel.windowStartIndex
            let focalPointY = geometry.size.height * 0.85
            
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
                                    fontSize: layoutData.fontSize,
                                    orpOffset: layoutData.orpOffset,
                                    isCurrent: isCurrent,
                                    fontName: fontName,
                                    theme: theme,
                                    screenWidth: geometry.size.width
                                )
                            .id(actualIndex)
                            .onTapGesture {
                                // Ignore taps within 200ms of scrolling to prevent
                                // accidental taps when stopping a swipe
                                guard Date().timeIntervalSince(lastScrollTime) > 0.2 else { return }
                                viewModel.goToIndex(actualIndex)
                                scrollPosition = actualIndex
                            }
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(
                                            key: ItemMinYPreferenceKey.self,
                                            value: [actualIndex: geo.frame(in: .named("scroll")).midY]
                                        )
                                }
                            )
                        }
                    }
                    // No scrollTargetLayout - allows free momentum scrolling
                    .padding(.top, focalPointY)
                    .padding(.bottom, geometry.size.height * 0.60) // Massive padding to ensure last item can reach focal point
                    .background(ScrollViewConfigurator()) // Inject configurator to find parent ScrollView
                }
                .id(viewModel.scrollResetID) // Force full recreation on reset
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ItemMinYPreferenceKey.self) { itemPositions in
                    // Rate Limit: Prevent multiple updates per frame (max 60fps)
                    let now = Date().timeIntervalSince1970
                    guard now - scrollManager.lastUpdateTime > 0.015 else { return }
                    scrollManager.lastUpdateTime = now
                    
                    // 1. Momentum / Idle detection: Keep isUserScrolling true while updates are arriving
                    if scrollManager.isUserScrolling {
                        scrollManager.registerScrollActivity {
                            if let pos = scrollPosition {
                                viewModel.goToIndex(pos)
                            }
                        }
                    }
                    
                    // Calculate which word is at the focal point based on item geometry
                    // Update whenever manual mode is active (paused), covering both dragging AND momentum
                    // AND ensure we aren't in the middle of a programmatic scroll (like reset)
                    if !viewModel.isPlaying && !scrollManager.isProgrammaticScroll {
                        // Current distance
                        let currentDist = abs((itemPositions[scrollPosition ?? -1] ?? 10000) - focalPointY)
                        
                        // Find the item whose midY is closest to the focalPointY
                        // Use Hystersis: prefer current item unless another is SIGNIFICANTLY closer
                        let closest = itemPositions.min(by: { 
                            abs($0.value - focalPointY) < abs($1.value - focalPointY)
                        })
                        
                        if let match = closest {
                            let newDist = abs(match.value - focalPointY)
                            
                            // HYSTERESIS: Only switch if new item is >10pts closer, or current is wildly off (>100pts)
                            if newDist < currentDist - 10 || currentDist > 100 {
                                let closestIndex = match.key
                                let clampedIndex = max(0, min(closestIndex, viewModel.totalWords - 1))
                                
                                if scrollPosition != clampedIndex {
                                    DispatchQueue.main.async {
                                        scrollPosition = clampedIndex
                                        
                                        // Sync viewModel index without triggering scroll (since we are scrolling)
                                        if viewModel.currentIndex != clampedIndex {
                                            scrollManager.isSyncingIndex = true
                                            // LIGHTWEIGHT UPDATE: Only change the highlight, don't rebuild the window
                                            viewModel.updateIndexOnly(clampedIndex)
                                            
                                            Task { @MainActor in
                                                // Small delay to ensure onChange fires before we reset flag
                                                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                                                scrollManager.isSyncingIndex = false
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in
                            // Cancel idle timer on direct interaction
                            scrollManager.startScrolling()
                            onScroll?()
                        }
                        .onEnded { _ in
                            // Record scroll end time for tap guard
                            lastScrollTime = Date()
                            // Momentum tracking in onPreferenceChange handles the reset now
                            scrollManager.registerScrollActivity {
                                if let pos = scrollPosition {
                                    viewModel.goToIndex(pos)
                                }
                            }
                        }
                )
                .onChange(of: viewModel.currentIndex) { _, newIndex in
                    // When viewModel changes (playback), update scroll position
                    // Only scroll if we aren't manually syncing from the scroll itself
                    if !scrollManager.isUserScrolling && !scrollManager.isSyncingIndex {
                        scrollManager.isProgrammaticScroll = true
                        scrollPosition = newIndex
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(newIndex, anchor: UnitPoint(x: 0.5, y: 0.85))
                        }
                        
                        // Re-enable tracking after scroll settles
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scrollManager.isProgrammaticScroll = false
                        }
                    }
                }
                .onAppear {
                    scrollPosition = viewModel.currentIndex
                    proxy.scrollTo(viewModel.currentIndex, anchor: UnitPoint(x: 0.5, y: 0.85))
                }
            }
            // Gradient mask - fade only above, solid at bottom
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.70)
                    
                    Rectangle()
                        .fill(Color.black)
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

// MARK: - ScrollView Configurator
// Accesses the underlying UIScrollView to set deceleration rate
struct ScrollViewConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Run on next runloop to ensure view hierarchy is built
        DispatchQueue.main.async {
            var current: UIView? = uiView
            while let view = current {
                if let scrollView = view as? UIScrollView {
                    // Set to normal (higher friction than fast)
                    scrollView.decelerationRate = .normal
                    return
                }
                current = view.superview
            }
        }
    }
}

// MARK: - Scroll Manager
@MainActor
class ScrollManager: ObservableObject {
    @Published var isUserScrolling = false
    
    // Logic flags - not published to prevent view updates on logic changes
    var isSyncingIndex = false
    var isProgrammaticScroll = false
    var lastUpdateTime: TimeInterval = 0
    
    private var idleTask: Task<Void, Never>?
    
    func registerScrollActivity(onStop: @escaping () -> Void) {
        // Cancel previous task - this mutation does NOT trigger UI update
        idleTask?.cancel()
        
        // Start new task
        idleTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            if !Task.isCancelled {
                self.isUserScrolling = false
                onStop()
            }
        }
    }
    
    func startScrolling() {
        idleTask?.cancel()
        if !isUserScrolling {
            isUserScrolling = true
        }
    }
}

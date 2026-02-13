import SwiftUI

@available(iOS 17.0, *)
struct ParagraphView: View {
    @ObservedObject var viewModel: RSVPViewModel
    @ObservedObject var settings = SettingsManager.shared
    
    // Callbacks - mostly kept for signature compatibility, though logic is now internal
    var onTap: () -> Void
    var onWordTap: ((Int) -> Void)?
    var onScroll: (() -> Void)?
    var onSpeedScrub: ((CGFloat) -> Void)?
    var onSpeedScrubEnded: (() -> Void)?
    
    // Internal State for Drag Gesture
    @State private var dragOffset: CGFloat = 0
    @State private var baseIndex: Int = 0
    @State private var baseWeight: CGFloat = 0
    
    // Cumulative weights for variable scroll speed
    @State private var cumulativeWeights: [CGFloat] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background - specific to theme
                settings.backgroundColor
                    .ignoresSafeArea()
                    .onTapGesture {
                        onTap()
                    }
                
                // Wheel Visualization
                VStack(spacing: 12) {
                    // Show a range of words around the current index
                    // -7 to +8 covers most screen heights comfortably
                    ForEach(-7..<8, id: \.self) { offset in
                        let wordIndex = viewModel.currentIndex + offset
                        if wordIndex >= 0 && wordIndex < viewModel.totalWords {
                            HStack(spacing: 40) {
                                // Horizontal line for current position (left side)
                                if offset == 0 {
                                    Rectangle()
                                        .fill(settings.textColor.opacity(0.3))
                                        .frame(width: 40, height: 1)
                                } else {
                                    Spacer().frame(width: 40)
                                }
                                
                                // Build word with ORP highlighting
                                HStack(spacing: 0) {
                                    ForEach(Array(viewModel.word(at: wordIndex).enumerated()), id: \.offset) { charIndex, character in
                                        let orpIndex = orpIndexFor(word: viewModel.word(at: wordIndex))
                                        Text(String(character))
                                            .font(.custom(settings.fontName, size: (offset == 0 ? 40 : 20) * settings.fontSizeMultiplier))
                                            .foregroundColor(
                                                offset == 0 && charIndex == orpIndex
                                                    ? Color(hex: "E63946") // Red for ORP letter
                                                    : (offset == 0 
                                                        ? settings.textColor 
                                                        : settings.textColor.opacity(0.4 - Double(abs(offset)) * 0.04))
                                            )
                                            .fontWeight(offset == 0 ? .medium : .regular)
                                    }
                                }
                                .offset(x: offset == 0 ? orpHorizontalOffset(for: viewModel.word(at: wordIndex), in: geometry) : 0)
                                .multilineTextAlignment(.center)
                                
                                // Horizontal line for current position (right side)
                                if offset == 0 {
                                    Rectangle()
                                        .fill(settings.textColor.opacity(0.3))
                                        .frame(width: 40, height: 1)
                                } else {
                                    Spacer().frame(width: 40)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                // Tap to jump to this word
                                viewModel.goToIndex(wordIndex)
                            }
                        } else {
                            // Spacer for out of bounds to keep center aligned
                            Spacer().frame(height: offset == 0 ? 40 : 25)
                        }
                    }
                }
                .offset(y: dragOffset * 0.3) // Parallax/Dampening effect for smoothness
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle()) // Hit test entire area
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Initialize base weight on first drag
                        if dragOffset == 0 {
                            // Build weights if not done yet
                            // IMPORTANT: Must do this BEFORE calculating baseWeight
                            if cumulativeWeights.isEmpty {
                                buildCumulativeWeights()
                            }
                            
                            baseIndex = viewModel.currentIndex
                            baseWeight = weightAt(index: baseIndex)
                        }
                        
                        // Calculate target weight based on drag distance
                        // Sensitivity: 30 points per weight unit
                        let sensitivity: CGFloat = 30.0
                        let weightOffset = -value.translation.height / sensitivity
                        let targetWeight = baseWeight + weightOffset
                        
                        // Find index corresponding to target weight
                        let newIndex = indexForWeight(targetWeight)
                        
                        // Update ViewModel live - use goToIndex to ensure progress saving
                        let clampedIndex = max(0, min(newIndex, viewModel.totalWords - 1))
                        if viewModel.currentIndex != clampedIndex {
                            viewModel.goToIndex(clampedIndex)
                        }
                        
                        // Update drag offset for visual feedback
                        dragOffset = value.translation.height.truncatingRemainder(dividingBy: sensitivity)
                        
                        // Callback for "scroll started" if needed
                        onScroll?()
                    }
                    .onEnded { _ in
                        // Commit final position
                        baseIndex = viewModel.currentIndex
                        baseWeight = weightAt(index: baseIndex)
                        dragOffset = 0
                        
                        // Callback for "scroll ended" if needed
                        // Note: RSVPViewModel updates binding automatically
                    }
            )
        }
    .onAppear {
        // Pre-calculate weights when view appears to avoid jank on first scroll
        if cumulativeWeights.isEmpty {
            buildCumulativeWeights()
        }
    }
    }
    
    // MARK: - Helper Functions
    
    /// Returns the middle letter index for a word
    /// For odd-length words: exact middle (e.g., "hello" = index 2)
    /// For even-length words: left of middle (e.g., "test" = index 1)
    private func orpIndexFor(word: String) -> Int {
        guard word.count > 0 else { return 0 }
        return (word.count - 1) / 2
    }
    
    /// Calculate horizontal offset to center the middle letter on screen
    private func orpHorizontalOffset(for word: String, in geometry: GeometryProxy) -> CGFloat {
        guard word.count > 1 else { return 0 }
        
        let font = FontMetricsCache.shared.font(name: settings.fontName, size: 40 * settings.fontSizeMultiplier)
        let middleIndex = orpIndexFor(word: word)
        
        // Calculate width up to and including the middle character
        var offsetToMiddle: CGFloat = 0
        for (index, char) in word.enumerated() {
            let charWidth = String(char).size(withFont: font).width
            if index < middleIndex {
                offsetToMiddle += charWidth
            } else if index == middleIndex {
                offsetToMiddle += charWidth / 2
                break
            }
        }
        
        let wordWidth = word.size(withFont: font).width
        
        // Calculate offset to position middle letter at center
        return (wordWidth / 2) - offsetToMiddle
    }
    
    // MARK: - Weight-Based Scrolling
    
    /// Calculate scroll weight for a word based on its length
    /// Longer words get higher weights, making them "stick" longer
    private func scrollWeight(for word: String) -> CGFloat {
        switch word.count {
        case 0...6: return 1.0      // Short words: normal speed
        case 7...10: return 1.3     // Medium words: 30% slower
        case 11...15: return 1.6    // Long words: 60% slower
        default: return 2.0         // Very long words: 100% slower
        }
    }
    
    /// Build cumulative weights array for all words
    private func buildCumulativeWeights() {
        var cumulative: CGFloat = 0
        cumulativeWeights = viewModel.words.map { word in
            cumulative += scrollWeight(for: word)
            return cumulative
        }
    }
    
    /// Get cumulative weight at a specific index
    private func weightAt(index: Int) -> CGFloat {
        guard index >= 0 && index < cumulativeWeights.count else { return 0 }
        return cumulativeWeights[index]
    }
    
    /// Find word index for a given cumulative weight using binary search
    private func indexForWeight(_ targetWeight: CGFloat) -> Int {
        guard !cumulativeWeights.isEmpty else { return 0 }
        
        // Clamp to valid weight range
        let clampedWeight = max(0, min(targetWeight, cumulativeWeights.last ?? 0))
        
        // Binary search for the index
        var left = 0
        var right = cumulativeWeights.count - 1
        
        while left < right {
            let mid = (left + right) / 2
            if cumulativeWeights[mid] < clampedWeight {
                left = mid + 1
            } else {
                right = mid
            }
        }
        
        return left
    }
}

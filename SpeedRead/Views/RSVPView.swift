import SwiftUI

struct RSVPView: View {
    let text: String
    let documentId: UUID?
    let startIndex: Int
    let initialWPM: Double
    let onExit: () -> Void
    
    @StateObject private var viewModel = RSVPViewModel()
    @ObservedObject private var settings = SettingsManager.shared
    
    @State private var showControls = true
    @AppStorage("hasShownSpeedHint") private var hasShownSpeedHint = false
    @State private var showSpeedHint: Bool
    
    init(text: String, documentId: UUID?, startIndex: Int, initialWPM: Double, onExit: @escaping () -> Void) {
        self.text = text
        self.documentId = documentId
        self.startIndex = startIndex
        self.initialWPM = initialWPM
        self.onExit = onExit
        // Initialize showSpeedHint based on UserDefaults
        _showSpeedHint = State(initialValue: !UserDefaults.standard.bool(forKey: "hasShownSpeedHint"))
    }
    
    @State private var currentWPMDisplay: Double? = nil
    @State private var hideWPMTimer: Timer? = nil
    
    // Context Peek state
    @State private var showContextPeek = false
    @State private var peekIndex: Int = 0
    @State private var peekBaseIndex: Int = 0
    @State private var originalPeekIndex: Int = 0
    @State private var peekDragOffset: CGFloat = 0
    @State private var wasPlayingBeforePeek = false
    
    var body: some View {
        ZStack {
            // Background - only tap-to-play in speed reader mode (not paragraph)
            settings.backgroundColor
                .ignoresSafeArea()
                .onTapGesture {
                    if settings.readerMode != .paragraph {
                        viewModel.togglePlayPause()
                    }
                }
            
            // Reader Content
            if settings.readerMode == .paragraph {
                ParagraphView(
                    viewModel: viewModel,
                    onTap: {
                        // Do nothing - only play button controls playback in paragraph mode
                    },
                    onWordTap: { wordIndex in
                        // Jump to tapped word and stay paused
                        viewModel.goToIndex(wordIndex)
                    },
                    onScroll: {
                        // Pause when user scrolls
                        if viewModel.isPlaying {
                            viewModel.togglePlayPause()
                        }
                    },
                    onSpeedScrub: { deltaY in
                        // Swipe up (neg Y) = faster, swipe down (pos Y) = slower
                        // Sensitivity adjustment
                        let sensitivity: Double = 0.5
                        let wpmDelta = -deltaY * sensitivity
                        
                        let newWPM = viewModel.wordsPerMinute + wpmDelta
                        viewModel.wordsPerMinute = min(max(newWPM, viewModel.minWPM), viewModel.maxWPM)
                        
                        // Show WPM feedback
                        currentWPMDisplay = viewModel.wordsPerMinute
                        hideWPMTimer?.invalidate()
                        
                        // Hide hint if needed
                        if showSpeedHint {
                            hasShownSpeedHint = true
                            withAnimation(.easeOut(duration: 0.3)) {
                                showSpeedHint = false
                            }
                        }
                    },
                    onSpeedScrubEnded: {
                        // Hide WPM feedback after delay
                        hideWPMTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                            withAnimation {
                                currentWPMDisplay = nil
                            }
                        }
                    }
                )
                .padding(.top, 60)
                .padding(.bottom, 140) // Increased padding to clear bottom buttons
            } else {
                // Word Display (centered with ORP anchor)
                WordDisplayView(
                    word: viewModel.currentWord,
                    fontSize: WordDisplayView.fontSize(for: viewModel.currentWord) * settings.fontSizeMultiplier,
                    fontName: settings.fontName,
                    theme: settings.theme
                )
            }
            
            // UI Overlay
            VStack {
                // Top bar with exit button, restart, and progress
                HStack {
                    Button(action: { saveProgressAndExit() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                            .padding(12)
                    }
                    
                    Spacer()
                    
                    // Progress indicator
                    Text("\(viewModel.currentIndex + 1) / \(viewModel.totalWords)")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(Color(hex: "555555"))
                    
                    Spacer()
                    
                    // Restart button
                    Button(action: { viewModel.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                            .padding(12)
                    }
                }
                .padding(.top, 8)
                
                Spacer()
                
                // Bottom controls - skip backward, play/pause, skip forward
                HStack(spacing: 48) {
                    // Skip backward 15 words
                    Button(action: { viewModel.skipBackward(by: 15) }) {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                            .frame(width: 44, height: 44) // Larger touch target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    // Play/Pause
                    Button(action: {
                        if showContextPeek {
                            hideContextPeek()
                        }
                        viewModel.togglePlayPause()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause" : "play.fill")
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(Color(hex: "777777"))
                            .frame(width: 60, height: 60) // Large touch target for main action
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    // Skip forward 15 words
                    Button(action: { viewModel.skipForward(by: 15) }) {
                        Image(systemName: "goforward.15")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "555555"))
                            .frame(width: 44, height: 44) // Larger touch target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.bottom, 50)
            }
            .zIndex(10) // Ensure buttons are above ParagraphView
            
            // Speed control zone & Feedback Overlay
            GeometryReader { geo in
                // Swipe zone covers right third of screen, bottom half (Speed Reader Mode only)
                if settings.readerMode != .paragraph {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.35, height: geo.size.height * 0.6)
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.65)
                        .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onChanged { value in
                                // Swipe up = faster, swipe down = slower
                                let sensitivity: Double = 1.5
                                let delta = -value.translation.height * sensitivity / 100
                                let newWPM = viewModel.wordsPerMinute + delta
                                viewModel.wordsPerMinute = min(max(newWPM, viewModel.minWPM), viewModel.maxWPM)
                                
                                // Show WPM feedback
                                currentWPMDisplay = viewModel.wordsPerMinute
                                hideWPMTimer?.invalidate()
                                
                                // Hide the initial hint after first use
                                if showSpeedHint {
                                    hasShownSpeedHint = true
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        showSpeedHint = false
                                    }
                                }
                            }
                            .onEnded { _ in
                                // Hide WPM display after a delay
                                hideWPMTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        currentWPMDisplay = nil
                                    }
                                }
                            }
                    )
                } // End if not paragraph mode (gesture zone)
                
                // WPM feedback display (shows during/after swipe)
                if let wpm = currentWPMDisplay {
                    Text("\(Int(wpm)) WPM")
                        .font(.custom("EBGaramond-Regular", size: 18))
                        .foregroundColor(Color(hex: "888888"))
                        .position(x: geo.size.width * 0.85, y: geo.size.height * 0.45)
                        .transition(.opacity)
                }
                
                // Initial hint (fades away after first swipe)
                if showSpeedHint {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 24))
                        Text("Swipe to\nadjust speed")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .multilineTextAlignment(.center)
                    }
                    .foregroundColor(Color(hex: "555555"))
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.55)
                    .transition(.opacity)
                }
            } // End GeometryReader
            
            // Context Peek zone - only in speed reader mode (not paragraph mode)
            if settings.readerMode != .paragraph {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.35, height: geo.size.height * 0.7)
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.5)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Show context peek on first drag
                                    if !showContextPeek {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            showContextPeek = true
                                        }
                                        peekIndex = viewModel.currentIndex
                                        peekBaseIndex = viewModel.currentIndex
                                        originalPeekIndex = viewModel.currentIndex
                                        // Pause if playing
                                        if viewModel.isPlaying {
                                            wasPlayingBeforePeek = true
                                            viewModel.togglePlayPause()
                                        }
                                    }
                                    
                                    // Calculate word offset based on drag from base
                                    let sensitivity: CGFloat = 30.0 // pixels per word
                                    let wordOffset = Int(-value.translation.height / sensitivity)
                                    let newPeekIndex = peekBaseIndex + wordOffset
                                    peekIndex = max(0, min(newPeekIndex, viewModel.totalWords - 1))
                                    peekDragOffset = value.translation.height.truncatingRemainder(dividingBy: sensitivity)
                                }
                                .onEnded { _ in
                                    // Update base index to current peek position for continuous scrolling
                                    peekBaseIndex = peekIndex
                                    peekDragOffset = 0
                                }
                        )
                }
            }
            
            // Context Peek Overlay
            if showContextPeek {
                ZStack {
                    // Semi-transparent background
                    settings.backgroundColor
                        .opacity(0.95)
                        .ignoresSafeArea()
                    
                    // Word list centered on peekIndex - tap word to jump
                    VStack(spacing: 12) {
                        ForEach(-7..<8, id: \.self) { offset in
                            let wordIndex = peekIndex + offset
                            if wordIndex >= 0 && wordIndex < viewModel.totalWords {
                                HStack(spacing: 8) {
                                    // Marker for original position
                                    if wordIndex == originalPeekIndex {
                                        Circle()
                                            .fill(Color(hex: "E63946"))
                                            .frame(width: 6, height: 6)
                                    } else {
                                        Spacer().frame(width: 6)
                                    }
                                    
                                    Text(viewModel.word(at: wordIndex))
                                        .font(.custom(settings.fontName, size: offset == 0 ? 28 : 20))
                                        .foregroundColor(
                                            offset == 0 
                                                ? settings.textColor 
                                                : settings.textColor.opacity(0.4 - Double(abs(offset)) * 0.04)
                                        )
                                        .fontWeight(offset == 0 ? .medium : .regular)
                                }
                                .onTapGesture {
                                    jumpToWordAndDismiss(wordIndex)
                                }
                            }
                        }
                    }
                    .offset(y: peekDragOffset * 0.3)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let sensitivity: CGFloat = 30.0
                            let wordOffset = Int(-value.translation.height / sensitivity)
                            let newPeekIndex = peekBaseIndex + wordOffset
                            peekIndex = max(0, min(newPeekIndex, viewModel.totalWords - 1))
                            peekDragOffset = value.translation.height.truncatingRemainder(dividingBy: sensitivity)
                        }
                        .onEnded { _ in
                            peekBaseIndex = peekIndex
                            peekDragOffset = 0
                        }
                )
                .onTapGesture {
                    hideContextPeek()
                }
                .transition(.opacity)
            }
            
            // Progress bar at bottom
            VStack {
                Spacer()
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(hex: "2A2A2A"))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(Color(hex: "E63946"))
                            .frame(width: geometry.size.width * viewModel.progress, height: 2)
                    }
                }
                .frame(height: 2)
            }
        }
        .onAppear {
            viewModel.loadText(text, startingAt: startIndex)
            viewModel.wordsPerMinute = initialWPM
        }
        .onDisappear {
            saveProgress()
        }
        .statusBarHidden(true)
    }
    
    private func saveProgress() {
        if let docId = documentId {
            LibraryManager.shared.updateProgress(
                for: docId,
                wordIndex: viewModel.currentIndex,
                wpm: viewModel.wordsPerMinute
            )
        }
    }
    
    private func saveProgressAndExit() {
        saveProgress()
        onExit()
    }
    
    private func hideContextPeek() {
        withAnimation(.easeOut(duration: 0.3)) {
            showContextPeek = false
        }
        peekDragOffset = 0
        peekBaseIndex = 0
        wasPlayingBeforePeek = false
    }
    
    private func jumpToWordAndDismiss(_ index: Int) {
        // Jump to the selected word
        viewModel.skipForward(by: index - viewModel.currentIndex)
        
        // Hide the peek overlay
        withAnimation(.easeOut(duration: 0.3)) {
            showContextPeek = false
        }
        peekDragOffset = 0
        peekBaseIndex = 0
        wasPlayingBeforePeek = false
        
        // Stay paused - user will click play when ready
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    RSVPView(
        text: "This is a sample text for testing the RSVP speed reading functionality.",
        documentId: nil,
        startIndex: 0,
        initialWPM: 300,
        onExit: {}
    )
}

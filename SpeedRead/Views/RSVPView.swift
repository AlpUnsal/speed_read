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
    @State private var showUI = true
    @State private var uiHideTimer: Timer? = nil
    @AppStorage("hasShownSpeedHint") private var hasShownSpeedHint = false
    @State private var showSpeedHint: Bool
    
    @AppStorage("hasShownContextPeekHint") private var hasShownContextPeekHint = false
    @State private var showContextPeekHint: Bool
    
    init(text: String, documentId: UUID?, startIndex: Int, initialWPM: Double, onExit: @escaping () -> Void) {
        self.text = text
        self.documentId = documentId
        self.startIndex = startIndex
        self.initialWPM = initialWPM
        self.onExit = onExit
        // Initialize showSpeedHint based on UserDefaults
        _showSpeedHint = State(initialValue: !UserDefaults.standard.bool(forKey: "hasShownSpeedHint"))
        _showContextPeekHint = State(initialValue: !UserDefaults.standard.bool(forKey: "hasShownContextPeekHint"))
    }
    
    @State private var currentWPMDisplay: Double? = nil
    @State private var hideWPMTimer: Timer? = nil
    @State private var lastDragY: CGFloat? = nil
    
    // Context Peek state
    @State private var showContextPeek = false
    @State private var peekIndex: Int = 0
    @State private var peekBaseIndex: Int = 0
    @State private var originalPeekIndex: Int = 0
    @State private var peekDragOffset: CGFloat = 0
    @State private var wasPlayingBeforePeek = false
    
    // Navigation & Search state
    @State private var showSearch = false
    @State private var showChapterList = false
    @State private var showSettings = false
    
    // Scrubbing state
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var scrubIndex: Int = 0
    @State private var wasPlayingBeforeScrub = false
    @State private var preScrubIndex: Int? = nil
    @State private var showReturnPrompt = false
    
    var body: some View {
        GeometryReader { mainGeo in
            let isLandscape = mainGeo.size.width > mainGeo.size.height
            let landscapeScale = isLandscape ? 1.5 : 1.0
            
            ZStack {
                // Background - only tap-to-play in speed reader mode (not paragraph)
                settings.backgroundColor
                    .ignoresSafeArea()
                    .onTapGesture {
                        if settings.readerMode == .paragraph {
                            toggleParagraphUI()
                        } else {
                            handlePlayPause()
                        }
                    }
                
                // Reader Content
                    if settings.readerMode == .paragraph {
                        if #available(iOS 17.0, *) {
                            ParagraphView(
                                viewModel: viewModel,
                                onTap: { toggleParagraphUI() },
                                onWordTap: { wordIndex in
                                    viewModel.goToIndex(wordIndex)
                                },
                                onScroll: {
                                    if viewModel.isPlaying {
                                        viewModel.togglePlayPause()
                                    }
                                },
                                onSpeedScrub: { deltaY in
                                    let sensitivity: Double = 0.5
                                    let wpmDelta = -deltaY * sensitivity
                                    let newWPM = viewModel.wordsPerMinute + wpmDelta
                                    viewModel.wordsPerMinute = min(max(newWPM, viewModel.minWPM), viewModel.maxWPM)
                                    currentWPMDisplay = viewModel.wordsPerMinute
                                    hideWPMTimer?.invalidate()
                                    if showSpeedHint {
                                        hasShownSpeedHint = true
                                        withAnimation(.easeOut(duration: 0.3)) { showSpeedHint = false }
                                    }
                                },
                                onSpeedScrubEnded: {
                                    hideWPMTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                                        withAnimation { currentWPMDisplay = nil }
                                    }
                                }
                            )
                            .padding(.top, 60)
                        } else {
                            Text("Paragraph View requires iOS 17 or later")
                                .foregroundColor(settings.textColor)
                                .padding()
                        }
                    } else {
                    // Word Display (centered with ORP anchor)
                    WordDisplayView(
                        word: viewModel.currentWord,
                        fontSize: WordDisplayView.fontSize(for: viewModel.currentWord) * settings.fontSizeMultiplier * landscapeScale,
                        fontName: settings.fontName,
                        theme: settings.theme
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handlePlayPause()
                    }
                }
                
                // UI Overlay
                VStack {
                    // Top bar with exit button, restart, and progress
                    // In paragraph mode: always visible
                    // In RSVP mode: fades when playing
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
                        
                        // Settings button
                        Button(action: {
                            viewModel.pause()
                            uiHideTimer?.invalidate()
                            withAnimation { showUI = true }
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(Color(hex: "555555"))
                                .padding(12)
                        }

                        // Restart button
                        Button(action: { viewModel.reset() }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(Color(hex: "555555"))
                                .padding(12)
                        }
                    }
                    .padding(.top, 8)
                    .opacity(showUI ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.5), value: showUI)
                    .allowsHitTesting(showUI)
                    
                    Spacer()
                    
                    // Bottom controls - [Sections] [◀10] [Play/Pause] [10▶] [Search]
                    // Only show in RSVP mode (not paragraph mode)
                    if settings.readerMode != .paragraph {
                        HStack(spacing: 24) {
                            // Sections button (opens chapter/heading list)
                            Button(action: {
                                viewModel.pause()
                                uiHideTimer?.invalidate()
                                withAnimation { showUI = true }
                                showChapterList = true
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Skip backward 10 seconds
                            Button(action: {
                                let skipCount = Int((viewModel.wordsPerMinute / 60.0) * 10.0)
                                viewModel.skipBackward(by: max(1, skipCount))
                            }) {
                                Image(systemName: "gobackward.10")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(Color(hex: "555555"))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Play/Pause
                            Button(action: {
                                if showContextPeek {
                                    hideContextPeek()
                                }
                                handlePlayPause()
                            }) {
                                Image(systemName: viewModel.isPlaying ? "pause" : "play.fill")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundColor(Color(hex: "777777"))
                                    .frame(width: 60, height: 60)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Skip forward 10 seconds
                            Button(action: {
                                let skipCount = Int((viewModel.wordsPerMinute / 60.0) * 10.0)
                                viewModel.skipForward(by: max(1, skipCount))
                            }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Search button
                            Button(action: {
                                viewModel.pause()
                                uiHideTimer?.invalidate()
                                withAnimation { showUI = true }
                                showSearch = true
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.bottom, 20)
                        .opacity(showUI ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5), value: showUI)
                        .allowsHitTesting(showUI)
                    } else {
                        // Controls for paragraph mode - [Sections] [Search]
                        HStack(spacing: 40) {
                            // Sections button
                            Button(action: {
                                viewModel.pause()
                                uiHideTimer?.invalidate()
                                withAnimation { showUI = true }
                                showChapterList = true
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .frame(width: 50, height: 50)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Search button
                            Button(action: {
                                viewModel.pause()
                                uiHideTimer?.invalidate()
                                withAnimation { showUI = true }
                                showSearch = true
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .frame(width: 50, height: 50)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }
                        .padding(.bottom, 24)
                        .opacity(showUI ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5), value: showUI)
                        .allowsHitTesting(showUI)
                    }
                }
                .zIndex(10) // Ensure buttons are above ParagraphView
                
                // Speed control zone & Feedback Overlay
                GeometryReader { geo in
                    // Swipe zone covers right third of screen, full height (Speed Reader Mode only)
                    if settings.readerMode != .paragraph {
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width * 0.33, height: geo.size.height)
                            .position(x: geo.size.width * 0.835, y: geo.size.height * 0.5)
                            .gesture(
                            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                                .onChanged { value in
                                    // Track incremental Y movement for accurate direction detection
                                    if lastDragY == nil {
                                        lastDragY = value.location.y
                                    }
                                    let deltaY = value.location.y - (lastDragY ?? value.location.y)
                                    lastDragY = value.location.y
                                    
                                    // Swipe up (negative deltaY) = faster, swipe down = slower
                                    let sensitivity: Double = 1.5
                                    let wpmDelta = -deltaY * sensitivity
                                    let newWPM = viewModel.wordsPerMinute + wpmDelta
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
                                    lastDragY = nil
                                    // Hide WPM display after a delay
                                    hideWPMTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            currentWPMDisplay = nil
                                        }
                                    }
                                }
                        )
                        .onTapGesture {
                            handlePlayPause()
                        }
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
                    
                    // Context Peek Hint (Left side)
                    if showContextPeekHint {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 24))
                            Text("Swipe to\nscroll")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .multilineTextAlignment(.center)
                        }
                        .foregroundColor(Color(hex: "555555"))
                        .position(x: geo.size.width * 0.15, y: geo.size.height * 0.55)
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
                                            // Dismiss hint if visible
                                            if showContextPeekHint {
                                                hasShownContextPeekHint = true
                                                withAnimation(.easeOut(duration: 0.3)) {
                                                    showContextPeekHint = false
                                                }
                                            }

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
                            .onTapGesture {
                                handlePlayPause()
                            }
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
                            let halfCount = isLandscape ? 3 : 7
                            ForEach(-halfCount...halfCount, id: \.self) { offset in
                                let wordIndex = peekIndex + offset
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
                                        GeometryReader { geo in
                                            HStack(spacing: 0) {
                                                ForEach(Array(viewModel.word(at: wordIndex).enumerated()), id: \.offset) { charIndex, character in
                                                    let word = viewModel.word(at: wordIndex)
                                                    let orpIndex = word.count <= 1 ? 0 : 1
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
                                            .fixedSize(horizontal: true, vertical: false)
                                            .offset(x: offset == 0 ? calculateORPOffset(for: viewModel.word(at: wordIndex), in: geo) : 0)
                                            .multilineTextAlignment(.center)
                                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                        }
                                        .frame(height: 40)
                                        
                                        // Horizontal line for current position (right side)
                                        if offset == 0 {
                                            Rectangle()
                                                .fill(settings.textColor.opacity(0.3))
                                                .frame(width: 40, height: 1)
                                        } else {
                                            Spacer().frame(width: 40)
                                        }
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
                
                // Scrubbing Preview Bubble
                if isScrubbing {
                    VStack(spacing: 4) {
                        Text(viewModel.word(at: scrubIndex))
                            .font(.custom(settings.fontName, size: 28))
                            .fontWeight(.medium)
                            .foregroundColor(settings.textColor)
                        
                        Text("\(scrubIndex + 1) / \(viewModel.totalWords)")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(settings.secondaryTextColor)
                        
                        if let section = viewModel.currentSectionLabel(at: scrubIndex) {
                            Text(section)
                                .font(.custom("EBGaramond-Regular", size: 12))
                                .foregroundColor(settings.mutedTextColor)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(settings.backgroundColor)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settings.cardBorderColor, lineWidth: 0.5)
                    )
                    .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height - 120)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(100)
                }

                // Progress bar at bottom
                VStack(spacing: 0) {
                    Spacer()
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            // Visual Bar (remains thin and sleek)
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color(hex: "2A2A2A"))
                                    .frame(height: 3)
                                
                                Rectangle()
                                    .fill(Color(hex: "E63946"))
                                    // Use scrubProgress if scrubbing, otherwise viewModel.progress
                                    .frame(width: geometry.size.width * (isScrubbing ? scrubProgress : viewModel.progress), height: 3)
                            }
                            .frame(height: 3)
                            
                            // Interaction Zone (Invisible, larger touch target)
                            Color.clear
                                .frame(height: 50) // Generous hit target
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if !isScrubbing {
                                                // Deadzone: Wait for intentional movement
                                                // This prevents micro-jitters from triggering or failing the lock too early
                                                if abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                                                    return
                                                }
                                                
                                                // Directional Lock: Check if movement is primarily vertical (Home Swipe)
                                                // Only enforce this if vertical movement is significant
                                                if abs(value.translation.height) > abs(value.translation.width) * 1.2 {
                                                    return // Likely a home swipe, ignore
                                                }
                                                
                                                // 2. Start scrubbing
                                                isScrubbing = true
                                                wasPlayingBeforeScrub = viewModel.isPlaying
                                                preScrubIndex = viewModel.currentIndex
                                                viewModel.pause()
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                            }
                                            
                                            // Calculate progress
                                            let progress = min(max(value.location.x / geometry.size.width, 0), 1)
                                            scrubProgress = progress
                                            
                                            // Convert to index
                                            let newIndex = Int(progress * Double(viewModel.totalWords - 1))
                                            scrubIndex = newIndex
                                            
                                            // Live update (fluid scrubbing)
                                            viewModel.updateIndexOnly(newIndex)
                                        }
                                        .onEnded { _ in
                                            // Only commit if we actually started scrubbing
                                            if isScrubbing {
                                                isScrubbing = false
                                                viewModel.goToIndex(scrubIndex)
                                                
                                                if let prevIndex = preScrubIndex, abs(scrubIndex - prevIndex) > 100 {
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                        showReturnPrompt = true
                                                    }
                                                } else {
                                                    showReturnPrompt = false
                                                }
                                                
                                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                                generator.impactOccurred()
                                            }
                                        }
                                )
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(height: 50) // Container height
                    .padding(.bottom, 0)
                }
                .padding(.bottom, 8) // Reduced from 24 to 8 for a lower profile (closer to bottom)
                .ignoresSafeArea(.all, edges: [.horizontal])
                .opacity(showUI ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.5), value: showUI)
                .allowsHitTesting(showUI)
                
                // Return Prompt Overlay
                if showReturnPrompt {
                    VStack {
                        Spacer()
                        Button(action: {
                            if let idx = preScrubIndex {
                                viewModel.goToIndex(idx)
                                preScrubIndex = nil
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showReturnPrompt = false
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Return to position")
                                    .font(.custom("EBGaramond-Medium", size: 16))
                            }
                            .foregroundColor(settings.textColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(settings.backgroundColor)
                                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(settings.cardBorderColor, lineWidth: 0.5)
                            )
                        }
                        .padding(.bottom, 80) // Position above the progress bar and buttons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(100)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                viewModel.pause()
                uiHideTimer?.invalidate()
                withAnimation { showUI = true }
                
                // Force an immediate synchronous save when backgrounding
                saveProgress()
                LibraryManager.shared.forceSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Redundancy: force save again if needed
                saveProgress()
                LibraryManager.shared.forceSave()
            }
            .onAppear {
                // Unlock orientation for RSVP view
                OrientationManager.orientationLock = .allButUpsideDown
                
                // Start auto-hide timer for Paragraph Mode
                if settings.readerMode == .paragraph {
                    toggleParagraphUI()
                }
                
                // Use async loading for large documents to avoid blocking UI
                viewModel.loadTextAsync(
                    text,
                    startingAt: startIndex,
                    fontName: settings.fontName,
                    fontSizeMultiplier: settings.fontSizeMultiplier
                ) {
                    // Setup navigation points after loading
                    if let docId = documentId,
                       let doc = LibraryManager.shared.documents.first(where: { $0.id == docId }) {
                        viewModel.setNavigationPoints(doc.navigationPoints)
                    } else {
                        // Generate page-based navigation for documents without stored nav points
                        let pages = PageChunker.createPages(from: viewModel.words)
                        viewModel.setNavigationPoints(pages)
                    }
                }
                viewModel.wordsPerMinute = initialWPM
                
                // Bind the periodic progress updates from the view model
                viewModel.onProgressUpdate = { index, wpm in
                    if let docId = documentId {
                        LibraryManager.shared.updateProgress(
                            for: docId,
                            wordIndex: index,
                            wpm: wpm
                        )
                    }
                }
            }
            .onDisappear {
                // Re-lock to portrait when leaving
                OrientationManager.orientationLock = .portrait
                saveProgress()
            }
            .statusBarHidden(true)
            .sheet(isPresented: $showChapterList) {
                ChapterListView(viewModel: viewModel, isPresented: $showChapterList)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showSearch) {
                WordSearchView(viewModel: viewModel, isPresented: $showSearch)
            }
        }
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
    
    private func toggleParagraphUI() {
        // Show UI and start auto-hide timer
        withAnimation {
            showUI = true
        }
        
        // Cancel any existing timer
        uiHideTimer?.invalidate()
        
        // Auto-hide after 3 seconds
        uiHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                showUI = false
            }
        }
    }
    
    private func handlePlayPause() {
        viewModel.togglePlayPause()
        
        // Hide return prompt when playing
        if viewModel.isPlaying && showReturnPrompt {
            withAnimation(.easeOut(duration: 0.3)) {
                showReturnPrompt = false
            }
            preScrubIndex = nil
        }
        
        // Cancel any existing timer
        uiHideTimer?.invalidate()
        
        // If now playing, start timer to hide UI after 2 seconds
        if viewModel.isPlaying {
            uiHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                withAnimation {
                    showUI = false
                }
            }
        } else {
            // If paused, show UI immediately
            withAnimation {
                showUI = true
            }
        }
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
    
    /// Calculate horizontal offset to center the ORP letter for context peek
    private func calculateORPOffset(for word: String, in geometry: GeometryProxy) -> CGFloat {
        guard word.count > 1 else { return 0 }
        
        let font = FontMetricsCache.shared.font(name: settings.fontName, size: 40 * settings.fontSizeMultiplier)
        let orpOffset = FontMetricsCache.shared.orpOffset(for: word, fontName: settings.fontName, fontSize: 40 * settings.fontSizeMultiplier)
        let wordWidth = word.size(withFont: font).width
        
        // Calculate offset to position ORP at center
        return (wordWidth / 2) - orpOffset
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

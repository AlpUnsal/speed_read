import SwiftUI

struct RSVPView: View {
    let text: String
    let documentId: UUID?
    let startIndex: Int
    let initialWPM: Double
    let isSampleText: Bool
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

    // Session reader mode: the document's override, falling back to the global
    // default. Tutorial docs are always RSVP (its gestures are RSVP-only).
    @State private var currentMode: ReaderMode

    // Word picker — the reading -> RSVP handoff state
    @State private var isWordPickerActive = false
    @State private var pickerSelectedWordIndex: Int? = nil

    init(text: String, documentId: UUID?, startIndex: Int, initialWPM: Double, isSampleText: Bool = false, onExit: @escaping () -> Void) {
        self.text = text
        self.documentId = documentId
        self.startIndex = startIndex
        self.initialWPM = initialWPM
        self.isSampleText = isSampleText
        self.onExit = onExit
        // For sample text: hints start hidden and are triggered by specific words
        // For regular books: show hints immediately if not yet shown
        _showSpeedHint = State(initialValue: isSampleText ? false : !UserDefaults.standard.bool(forKey: "hasShownSpeedHint"))
        _showContextPeekHint = State(initialValue: isSampleText ? false : !UserDefaults.standard.bool(forKey: "hasShownContextPeekHint"))

        let documentMode = documentId.flatMap { id in
            LibraryManager.shared.documents.first(where: { $0.id == id })?.readerMode
        }
        _currentMode = State(initialValue: isSampleText ? .rsvp : (documentMode ?? SettingsManager.shared.readerMode))
    }
    
    @State private var currentWPMDisplay: Double? = nil
    @State private var hideWPMTimer: Timer? = nil
    @State private var lastDragY: CGFloat? = nil

    // Gated first-run tutorial (inert unless attached in onAppear)
    @StateObject private var tutorial = TutorialController()
    @AppStorage("hasCompletedTutorial") private var hasCompletedTutorial = false

    // Context Peek state
    @State private var showContextPeek = false
    @State private var peekIndex: Int = 0
    @State private var peekBaseIndex: Int = 0
    @State private var originalPeekIndex: Int = 0
    @State private var peekDragOffset: CGFloat = 0
    // Whether peek was already open when the current peek-zone drag began —
    // the left-edge exit swipe must not fire mid-scroll-session
    @State private var peekZoneDragActive = false
    @State private var peekOpenAtDragStart = false
    @State private var wasPlayingBeforePeek = false

    // Double-tap tracking (manual, to avoid SwiftUI's single-tap delay)
    @State private var lastRightTapTime: Date = .distantPast
    @State private var lastLeftTapTime: Date = .distantPast

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
    @State private var pillJumpDestinationIndex: Int? = nil
    
    // View lifecycle guard — prevents late-firing async callbacks from
    // overwriting progress after the user has already exited the reader
    @State private var isViewActive = false
    
    // Figure viewer state
    @State private var showFigureViewer = false
    @State private var showFigureExpanded = false
    @State private var figureImage: UIImage? = nil
    @State private var figureZoomScale: CGFloat = 1.0
    @State private var figureLastZoomScale: CGFloat = 1.0
    @State private var figurePanOffset: CGSize = .zero
    @State private var figureLastPanOffset: CGSize = .zero
    
    // Dictionary State
    @State private var wordToDefine: DefinedWord? = nil
    
    var body: some View {
        GeometryReader { mainGeo in
            let isLandscape = mainGeo.size.width > mainGeo.size.height
            let landscapeScale = isLandscape ? 1.5 : 1.0
            
            ZStack {
                // Background
                settings.backgroundColor
                    .ignoresSafeArea()
                    .onTapGesture {
                        if currentMode == .reading {
                            toggleReadingUI()
                        } else {
                            handlePlayPause()
                        }
                    }

                // Reader Content
                    if currentMode == .reading {
                        NormalReadingView(
                            viewModel: viewModel,
                            settings: settings,
                            onTap: { toggleReadingUI() },
                            onWordLongPress: { word in
                                viewModel.pause()
                                let cleanWord = word.cleanForDictionary()
                                if !cleanWord.isEmpty {
                                    wordToDefine = DefinedWord(term: cleanWord)
                                }
                            },
                            isWordPickerActive: isWordPickerActive,
                            pickerSelectedWordIndex: pickerSelectedWordIndex,
                            onWordPicked: { globalIndex in
                                handleWordPicked(globalIndex)
                            }
                        )
                        .ignoresSafeArea()
                    } else {
                    // Word Display (centered with ORP anchor)
                    WordDisplayView(
                        word: viewModel.currentWord,
                        fontSize: WordDisplayView.fontSize(for: viewModel.currentWord) * settings.fontSizeMultiplier * landscapeScale,
                        fontName: settings.fontName,
                        theme: settings.theme
                    )
                    .contentShape(Rectangle())
                    .offset(y: (showFigureViewer && !showFigureExpanded) ? mainGeo.size.height * 0.15 : 0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFigureViewer)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFigureExpanded)
                    .onLongPressGesture(minimumDuration: 0.25) {
                        viewModel.pause()
                        tutorial.reportLongPressStarted()
                        let cleanWord = viewModel.currentWord.cleanForDictionary()
                        if !cleanWord.isEmpty {
                            wordToDefine = DefinedWord(term: cleanWord)
                        }
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                    }
                    .onTapGesture {
                        handlePlayPause()
                    }

                    // Dialogue indicator bar (right side)
                    if settings.showDialogueIndicator {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(settings.accentColor.opacity(viewModel.isInsideDialogue ? 0.35 : 0))
                            .frame(width: 2.5, height: 30)
                            .position(x: mainGeo.size.width * 0.85, y: mainGeo.size.height / 2)
                            .offset(y: (showFigureViewer && !showFigureExpanded) ? mainGeo.size.height * 0.15 : 0)
                            .animation(.easeInOut(duration: 0.15), value: viewModel.isInsideDialogue)
                            .allowsHitTesting(false)
                    }
                }
                
                // UI Overlay
                VStack {
                    // Top bar with exit button, restart, and progress
                    // In paragraph mode: always visible
                    // In RSVP mode: fades when playing
                    ZStack {
                        // Progress indicator (Centered absolutely)
                        // During the tutorial, chapter/book progress is replaced by the step count
                        if tutorial.isActive && tutorial.currentStep != .finished {
                            Text("\(tutorial.currentStepNumber) of \(TutorialController.totalSteps)")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(Color(hex: "555555"))
                        } else {
                            Text("Chapter \(viewModel.chapterProgressPercentage)% · Book \(viewModel.bookProgressPercentage)%")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(Color(hex: "555555"))
                        }

                        HStack {
                            Button(action: { saveProgressAndExit() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .padding(12)
                            }

                            Spacer()

                            HStack(spacing: 0) {
                                // Quiet tutorial escape hatch — the doc stays in the library
                                if tutorial.isActive {
                                    Button(action: {
                                        hasCompletedTutorial = true
                                        tutorial.deactivate()
                                        saveProgressAndExit()
                                    }) {
                                        Text("Skip")
                                            .font(.custom("EBGaramond-Regular", size: 15))
                                            .foregroundColor(Color(hex: "555555"))
                                            .padding(12)
                                    }
                                }

                                // Reader mode toggle (hidden for the tutorial — its
                                // gesture teaching is RSVP-only)
                                if !isSampleText {
                                    Button(action: { toggleMode() }) {
                                        Image(systemName: currentMode == .reading ? "text.word.spacing" : "text.alignleft")
                                            .font(.system(size: 20, weight: .light))
                                            .foregroundColor(Color(hex: "555555"))
                                            .padding(12)
                                    }
                                }

                                // Settings button
                                Button(action: {
                                    viewModel.pause()
                                    uiHideTimer?.invalidate()
                                    withAnimation { showUI = true }
                                    showSettings = true
                                }) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundColor(Color(hex: "555555"))
                                        .padding(12)
                                }

                                // Restart button
                                Button(action: {
                                    let currentIndex = viewModel.currentIndex
                                    viewModel.reset()
                                    if currentIndex > 100 {
                                        preScrubIndex = currentIndex
                                        pillJumpDestinationIndex = viewModel.currentIndex
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            showReturnPrompt = true
                                        }
                                    }
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundColor(Color(hex: "555555"))
                                        .padding(12)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity)
                    .background(currentMode == .reading ? settings.backgroundColor : Color.clear)
                    .opacity(showUI ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.5), value: showUI)
                    .allowsHitTesting(showUI)
                    
                    Spacer()
                    
                    // Bottom controls - [Sections] [◀10] [Play/Pause] [10▶] [Search]
                    // Only show in RSVP mode (not reading mode)
                    if currentMode != .reading {
                        HStack(spacing: 24) {
                            // Sections button (opens chapter/heading list)
                            Button(action: {
                                viewModel.pause()
                                uiHideTimer?.invalidate()
                                withAnimation { showUI = true }
                                showChapterList = true
                            }) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(Color(hex: "555555"))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Skip backward 10 seconds
                            Button(action: {
                                let skipCount = Int((viewModel.wordsPerMinute / 60.0) * 10.0)
                                if showContextPeek {
                                    jumpToWordAndDismiss(max(0, peekIndex - max(1, skipCount)))
                                } else {
                                    viewModel.skipBackward(by: max(1, skipCount))
                                }
                            }) {
                                Image(systemName: "gobackward.10")
                                .font(.system(size: 20, weight: .light))
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
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundColor(Color(hex: "777777"))
                                    .frame(width: 60, height: 60)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ScaleButtonStyle())
                            
                            // Skip forward 10 seconds
                            Button(action: {
                                let skipCount = Int((viewModel.wordsPerMinute / 60.0) * 10.0)
                                if showContextPeek {
                                    jumpToWordAndDismiss(min(viewModel.totalWords - 1, peekIndex + max(1, skipCount)))
                                } else {
                                    viewModel.skipForward(by: max(1, skipCount))
                                }
                            }) {
                                Image(systemName: "goforward.10")
                                    .font(.system(size: 20, weight: .light))
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
                                    .font(.system(size: 20, weight: .light))
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
                        // Controls for reading mode - [Sections] [Search]
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
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                        .padding(.top, 8)
                        .background(settings.backgroundColor)
                        .opacity(showUI ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.5), value: showUI)
                        .allowsHitTesting(showUI)
                    }
                }
                .zIndex(10) // Ensure buttons are above reader content
                
                // Speed control zone & Feedback Overlay
                GeometryReader { geo in
                    // Swipe zone covers right third of screen, full height (Speed Reader Mode only)
                    if currentMode != .reading {
                        let isFigureVisible = showFigureViewer && !showFigureExpanded
                        let zoneHeight = isFigureVisible ? geo.size.height * 0.5 : geo.size.height
                        let zoneY = isFigureVisible ? geo.size.height * 0.75 : geo.size.height * 0.5
                        
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width * 0.33, height: zoneHeight)
                            .position(x: geo.size.width * 0.835, y: zoneY)
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

                                    tutorial.reportSpeedGestureActive()

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
                            let now = Date()
                            let elapsed = now.timeIntervalSince(lastRightTapTime)
                            lastRightTapTime = now

                            if elapsed < 0.3 {
                                // Double-tap: undo the play/pause from first tap, then skip
                                handlePlayPause()
                                let wasPlaying = viewModel.isPlaying
                                viewModel.skipForward(seconds: 10)
                                if wasPlaying { viewModel.play() }
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                lastRightTapTime = .distantPast
                            } else {
                                // Single tap: immediate play/pause
                                handlePlayPause()
                            }
                        }
                    } // End if not paragraph mode (gesture zone)
                    
                    // WPM feedback display (shows during/after swipe)
                    if let wpm = currentWPMDisplay {
                        let isFigureVisible = showFigureViewer && !showFigureExpanded
                        Text("\(Int(wpm)) WPM")
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(Color(hex: "888888"))
                            .position(x: geo.size.width * 0.85, y: isFigureVisible ? geo.size.height * 0.60 : geo.size.height * 0.45)
                            .transition(.opacity)
                    }
                    
                    // Initial hint (fades away after first swipe)
                    if showSpeedHint {
                        let isFigureVisible = showFigureViewer && !showFigureExpanded
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 24))
                            Text("Swipe to\nadjust speed")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .multilineTextAlignment(.center)
                        }
                        .foregroundColor(Color(hex: "555555"))
                        .position(x: geo.size.width * 0.85, y: isFigureVisible ? geo.size.height * 0.70 : geo.size.height * 0.55)
                        .transition(.opacity)
                    }
                    
                    // Context Peek Hint (Left side)
                    if showContextPeekHint {
                        let isFigureVisible = showFigureViewer && !showFigureExpanded
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 24))
                            Text("Swipe to\nscroll")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .multilineTextAlignment(.center)
                        }
                        .foregroundColor(Color(hex: "555555"))
                        .position(x: geo.size.width * 0.15, y: isFigureVisible ? geo.size.height * 0.70 : geo.size.height * 0.55)
                        .transition(.opacity)
                    }

                    // Tutorial checkpoint hint — stays until the gesture is performed
                    if let hint = tutorial.activeHint {
                        TutorialHintOverlay(icon: hint.hintIcon, text: hint.hintText)
                            .position(tutorialHintPoint(for: hint.hintPosition, in: geo))
                    }

                    // Grace-period beat before the stream restarts
                    if tutorial.isGracePeriod {
                        Text("Resuming…")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(settings.mutedTextColor)
                            .position(x: geo.size.width * 0.5, y: geo.size.height * 0.62)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                } // End GeometryReader
                
                // Context Peek zone - only in speed reader mode
                if currentMode != .reading {
                    GeometryReader { geo in
                        let isFigureVisible = showFigureViewer && !showFigureExpanded
                        let peekZoneHeight = isFigureVisible ? geo.size.height * 0.5 : geo.size.height * 0.7
                        let peekZoneY = isFigureVisible ? geo.size.height * 0.75 : geo.size.height * 0.5
                        
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .frame(width: geo.size.width * 0.35, height: peekZoneHeight)
                            .position(x: geo.size.width * 0.15, y: peekZoneY)
                            .gesture(
                                DragGesture(coordinateSpace: .global)
                                    .onChanged { value in
                                        if !peekZoneDragActive {
                                            peekZoneDragActive = true
                                            peekOpenAtDragStart = showContextPeek
                                        }

                                        // Left-edge swipe-to-exit: horizontal right swipe from left
                                        // edge — but never mid-peek-session, where a scroll drag
                                        // drifting right must not exit the reader
                                        if !peekOpenAtDragStart &&
                                            value.startLocation.x < 40 &&
                                            value.translation.width > 50 &&
                                            abs(value.translation.height) < 40 {
                                            saveProgressAndExit()
                                            return
                                        }

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
                                        peekZoneDragActive = false
                                        // Update base index to current peek position for continuous scrolling
                                        peekBaseIndex = peekIndex
                                        peekDragOffset = 0
                                    }
                            )
                            .onTapGesture {
                                let now = Date()
                                let elapsed = now.timeIntervalSince(lastLeftTapTime)
                                lastLeftTapTime = now

                                if elapsed < 0.3 {
                                    // Double-tap: undo the play/pause from first tap, then skip
                                    handlePlayPause()
                                    let wasPlaying = viewModel.isPlaying
                                    viewModel.skipBackward(seconds: 10)
                                    if wasPlaying { viewModel.play() }
                                    let impact = UIImpactFeedbackGenerator(style: .medium)
                                    impact.impactOccurred()
                                    lastLeftTapTime = .distantPast
                                } else {
                                    // Single tap: immediate play/pause
                                    handlePlayPause()
                                }
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
                                        // Build word row with geometry for fixed lines
                                        GeometryReader { geo in
                                            ZStack {
                                                // The word itself
                                                HStack(spacing: 0) {
                                                    ForEach(Array(viewModel.word(at: wordIndex).enumerated()), id: \.offset) { charIndex, character in
                                                        let word = viewModel.word(at: wordIndex)
                                                        let orpIndex = FontMetricsCache.orpIndex(for: word)
                                                        let isORP = (offset == 0 && charIndex == orpIndex)
                                                        let fontSize = (offset == 0 ? 40 : 20) * settings.fontSizeMultiplier
                                                        
                                                        Text(String(character))
                                                            .font(.custom(settings.fontName, size: fontSize))
                                                            .foregroundColor(
                                                                isORP
                                                                    ? settings.accentColor // Red for ORP letter
                                                                    : (offset == 0 
                                                                        ? settings.textColor 
                                                                        : settings.textColor.opacity(0.4 - Double(abs(offset)) * 0.04))
                                                            )
                                                            .fontWeight(.regular)
                                                    }
                                                }
                                                .fixedSize(horizontal: true, vertical: false)
                                                .offset(x: offset == 0 ? calculateORPOffset(for: viewModel.word(at: wordIndex), in: geo) : 0)
                                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                                

                                            }
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
                        .offset(y: peekDragOffset * 0.3 + ((showFigureViewer && !showFigureExpanded) ? UIScreen.main.bounds.height * 0.15 : 0))
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
                                    .fill(settings.progressBarBackgroundColor)
                                    .frame(height: 3)

                                Rectangle()
                                    .fill(settings.accentColor)
                                    .frame(width: geometry.size.width * (isScrubbing ? scrubProgress : viewModel.progress), height: 3)
                            }
                            .frame(height: 3)

                            // Interaction Zone (Invisible, larger touch target)
                            // 20pt keeps the zone below the bottom control buttons
                            Color.clear
                                .frame(height: 20)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if !isScrubbing {
                                                if abs(value.translation.width) < 10 && abs(value.translation.height) < 10 {
                                                    return
                                                }
                                                if abs(value.translation.height) > abs(value.translation.width) * 1.2 {
                                                    return
                                                }
                                                isScrubbing = true
                                                wasPlayingBeforeScrub = viewModel.isPlaying
                                                preScrubIndex = viewModel.currentIndex
                                                // The drag mutates currentIndex via updateIndexOnly,
                                                // so hand goToIndex the true departure point now
                                                viewModel.markDepartureForNextJump(viewModel.currentIndex)
                                                viewModel.pause()
                                                let generator = UIImpactFeedbackGenerator(style: .light)
                                                generator.impactOccurred()
                                            }

                                            let progress = min(max(value.location.x / geometry.size.width, 0), 1)
                                            scrubProgress = progress
                                            let newIndex = Int(progress * Double(viewModel.totalWords - 1))
                                            scrubIndex = newIndex
                                            viewModel.updateIndexOnly(newIndex)
                                        }
                                        .onEnded { _ in
                                            if isScrubbing {
                                                isScrubbing = false
                                                viewModel.goToIndex(scrubIndex)

                                                if let prevIndex = preScrubIndex, abs(scrubIndex - prevIndex) > 100 {
                                                    pillJumpDestinationIndex = scrubIndex
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
                    .frame(height: 20)
                    .padding(.bottom, 0)
                }
                .padding(.bottom, 8)
                .ignoresSafeArea(.all, edges: [.horizontal])
                .zIndex(10)
                .opacity(showUI ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.5), value: showUI)
                .allowsHitTesting(showUI)

                // Return Prompt Overlay
                if showReturnPrompt {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Button(action: {
                                if let idx = preScrubIndex {
                                    viewModel.goToIndex(idx)
                                    preScrubIndex = nil
                                    pillJumpDestinationIndex = nil
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showReturnPrompt = false
                                    }
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 14, weight: .light))
                                    Text("Return to position")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                }
                                .foregroundColor(settings.textColor)
                            }

                            Button(action: {
                                preScrubIndex = nil
                                pillJumpDestinationIndex = nil
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showReturnPrompt = false
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(settings.textColor.opacity(0.5))
                            }
                        }
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
                        .padding(.bottom, 80) // Position above the progress bar and buttons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(100)
                }

                // Word Picker Banner (reading -> RSVP handoff)
                if isWordPickerActive {
                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Text("Tap a word to start there")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(settings.textColor)

                            Button(action: { confirmWordPickerSelection() }) {
                                HStack(spacing: 6) {
                                    Text("Start here")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10, weight: .light))
                                }
                                .foregroundColor(settings.accentColor)
                            }

                            Button(action: { cancelWordPicker() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .light))
                                    .foregroundColor(settings.textColor.opacity(0.5))
                            }
                        }
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
                        .padding(.bottom, 80)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .zIndex(100)
                }
            // --- FIGURE OVERLAYS (extracted to fix type-check timeout) ---
            figureHalfScreenOverlay(geo: mainGeo)
            figureExpandedOverlay()

            // Tutorial finale — "you just read at N WPM" payoff card
            if tutorial.showStatCard {
                TutorialStatCardView(wpm: tutorial.finalWPMAchieved) {
                    hasCompletedTutorial = true
                    // The tutorial already taught both gestures — skip the
                    // first-book coach marks for speed and peek
                    hasShownSpeedHint = true
                    hasShownContextPeekHint = true
                    tutorial.deactivate()
                    saveProgressAndExit()
                }
                .zIndex(300)
            }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .global)
                    .onChanged { value in
                        guard !showFigureViewer,
                              !showFigureExpanded,
                              !isScrubbing,
                              !showContextPeek,
                              value.startLocation.y < mainGeo.size.height - 80,
                              value.translation.width > 100,
                              value.translation.width > abs(value.translation.height) * 2.0 else {
                            return
                        }
                        saveProgressAndExit()
                    }
            )
            .sheet(item: $wordToDefine, onDismiss: {
                tutorial.reportDictionarySheetDismissed()
            }) { definedWord in
                DictionaryView(term: definedWord.term)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                viewModel.pause()
                uiHideTimer?.invalidate()
                withAnimation { showUI = true }
                
                // Force an immediate synchronous save when backgrounding
                saveProgress()
                LibraryManager.shared.forceSave()
            }
            .onChange(of: viewModel.figureToShow) { _, figure in
                guard let figure = figure else { return }
                // Already paused by ViewModel — just load image and show overlay
                if isSampleText {
                    figureImage = UIImage(named: figure.imageFileName)
                } else if let docId = documentId {
                    figureImage = LibraryManager.shared.loadFigureImage(for: docId, fileName: figure.imageFileName)
                }
                uiHideTimer?.invalidate()
                withAnimation { showUI = true }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showFigureViewer = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Redundancy: force save again if needed
                saveProgress()
                LibraryManager.shared.forceSave()
            }
            .onAppear {
                // Mark the view as active — any post-load callbacks will check this
                // flag before doing work, so late-firing completions after exit are no-ops.
                isViewActive = true
                
                // Unlock orientation for RSVP view
                OrientationManager.orientationLock = .allButUpsideDown
                
                // An unfinished tutorial always restarts from the beginning so the
                // checkpoint/gate sequence runs a clean, complete pass
                let effectiveStartIndex = (isSampleText && !hasCompletedTutorial) ? 0 : startIndex

                // Set initial progress immediately so early exits don't overwrite saved index
                viewModel.currentIndex = effectiveStartIndex
                
                // Start auto-hide timer for Reading Mode
                if currentMode == .reading {
                    toggleReadingUI()
                }
                
                // Use async loading for large documents to avoid blocking UI
                viewModel.loadTextAsync(
                    text,
                    startingAt: effectiveStartIndex,
                    fontName: settings.fontName,
                    fontSizeMultiplier: settings.fontSizeMultiplier
                ) {
                    // Guard: if the user exited before loading finished, skip post-load
                    // setup — the correct index was already saved from onDisappear.
                    guard isViewActive else { return }

                    // Setup navigation points after loading
                    if let docId = documentId,
                       let doc = LibraryManager.shared.documents.first(where: { $0.id == docId }) {
                        viewModel.setNavigationPoints(doc.navigationPoints)
                        viewModel.setPositionHistory(doc.positionHistory)
                        // Restore smart-pacing familiarity (faded by time away).
                        // doc.lastReadDate still holds the previous session's
                        // date here — progress updates only start after load.
                        viewModel.seedRarityFamiliarity(doc.rarityFamiliarity ?? [:], lastReadDate: doc.lastReadDate)
                        // If it's sample text, inject the tutorial figure programmatically,
                        // anchored to the end of "...no copy-pasting needed."
                        if isSampleText {
                            if let neededIndex = viewModel.words.firstIndex(where: { $0.hasPrefix("needed") }) {
                                let extensionScreenFigure = FigureAnnotation(
                                    id: UUID(),
                                    wordIndex: neededIndex + 1,
                                    caption: nil,
                                    imageFileName: "tutorial_extension_screen"
                                )
                                viewModel.setFigureAnnotations([extensionScreenFigure])
                            }
                            // Arm the gated tutorial on the first pass only —
                            // once completed/skipped, the doc plays like any other
                            if !hasCompletedTutorial {
                                tutorial.requestResume = {
                                    guard !showContextPeek, wordToDefine == nil,
                                          !viewModel.isPlaying else { return }
                                    viewModel.play()
                                }
                                tutorial.attach(viewModel: viewModel)
                                viewModel.shouldAdvance = { [weak tutorial] index in
                                    tutorial?.shouldAdvance(pastIndex: index) ?? true
                                }
                            }
                        } else {
                            viewModel.setFigureAnnotations(doc.figureAnnotations)
                        }
                    } else {
                        // Generate page-based navigation for documents without stored nav points
                        let pages = PageChunker.createPages(from: viewModel.words)
                        viewModel.setNavigationPoints(pages)
                    }
                }
                viewModel.wordsPerMinute = initialWPM
                
                // Bind the periodic progress updates from the view model
                viewModel.onProgressUpdate = { [weak viewModel] index, wpm in
                    if let docId = documentId {
                        LibraryManager.shared.updateProgress(
                            for: docId,
                            wordIndex: index,
                            wpm: wpm
                        )
                        if let viewModel {
                            LibraryManager.shared.updateRarityFamiliarity(
                                for: docId,
                                counts: viewModel.rarityFamiliaritySnapshot
                            )
                        }
                    }
                }

                // Persist position snapshots (sample text keeps in-memory history only)
                viewModel.onSnapshotRecorded = { snapshot in
                    if let docId = documentId {
                        LibraryManager.shared.recordPositionSnapshot(for: docId, snapshot)
                    }
                }
            }
            .onDisappear {
                // Mark the view as inactive so any still-running async work
                // (e.g. late-completing loadTextAsync) doesn't clobber saved state.
                isViewActive = false
                
                // Re-lock to portrait when leaving
                OrientationManager.orientationLock = .portrait
                saveProgress()
                
                // Force an immediate synchronous disk write so progress is never
                // lost to the debounce window, regardless of how the user exits.
                LibraryManager.shared.forceSave()
                
                // Safely access UIApplication.shared for extensions
                if let sharedApp = UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication {
                    sharedApp.isIdleTimerDisabled = false
                }
            }
            .onChange(of: viewModel.isPlaying) { _, isPlaying in
                if let sharedApp = UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication {
                    sharedApp.isIdleTimerDisabled = isPlaying
                }
            }
            .onChange(of: viewModel.currentIndex) { _, newIndex in
                if newIndex >= viewModel.totalWords - 1 && viewModel.totalWords > 0 {
                    // Document reached the end, show UI automatically
                    withAnimation { showUI = true }
                }
                if isSampleText {
                    tutorial.applyRampIfNeeded(currentIndex: newIndex)
                    // The playback loop increments one past the last word when
                    // the final word's display time elapses
                    if newIndex >= viewModel.totalWords && viewModel.totalWords > 0 {
                        tutorial.documentDidFinish()
                    }
                }

                // Auto-dismiss the "Return to position" pill once the user has
                // read ~100 words past the spot they jumped to
                if showReturnPrompt, !isScrubbing, let dest = pillJumpDestinationIndex,
                   newIndex - dest > 100 {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showReturnPrompt = false
                    }
                    preScrubIndex = nil
                    pillJumpDestinationIndex = nil
                }

                // While picking a start word, the default follows the user's
                // scrolling (currentIndex only moves on user scrolls) so
                // "Start here" always means the visible highlight.
                if isWordPickerActive, pickerSelectedWordIndex != newIndex {
                    pickerSelectedWordIndex = newIndex
                }
            }
            .statusBarHidden(!showUI)
            .sheet(isPresented: $showChapterList) {
                ChapterListView(viewModel: viewModel, isPresented: $showChapterList)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(settings.backgroundColor)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(sessionMode: currentMode)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(settings.backgroundColor)
            }
            .fullScreenCover(isPresented: $showSearch) {
                wordSearchCover()
            }
        }
    }
    
    private func saveProgress() {
        if let docId = documentId {
            // If the text hasn't finished loading yet (words is empty), fall back
            // to startIndex so an early exit never overwrites the saved position with 0.
            let indexToSave = viewModel.words.isEmpty ? startIndex : viewModel.currentIndex
            LibraryManager.shared.updateProgress(
                for: docId,
                wordIndex: indexToSave,
                wpm: viewModel.wordsPerMinute
            )
            LibraryManager.shared.updateRarityFamiliarity(
                for: docId,
                counts: viewModel.rarityFamiliaritySnapshot
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
        tutorial.reportPeekDismissed()
    }
    
    // MARK: - Reader Mode Switching

    private func toggleMode() {
        if currentMode == .rsvp {
            // RSVP -> Reading: the current word's paragraph anchors to the top
            // and NormalReadingView highlights the exact word on appear.
            viewModel.pause()
            currentMode = .reading
            persistCurrentMode()
            uiHideTimer?.invalidate()
            withAnimation { showUI = true }
        } else if isWordPickerActive {
            // Toggling while picking = cancel; stay in reading mode untouched.
            cancelWordPicker()
        } else {
            enterWordPickerState()
        }
    }

    private func persistCurrentMode() {
        if let docId = documentId {
            LibraryManager.shared.setReaderMode(currentMode, for: docId)
        }
    }

    private func enterWordPickerState() {
        viewModel.pause()
        uiHideTimer?.invalidate()
        withAnimation { showUI = true }
        // Default = the current position (first word of the top-visible
        // paragraph if the user has scrolled, the exact word otherwise).
        pickerSelectedWordIndex = viewModel.currentIndex
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isWordPickerActive = true
        }
    }

    private func handleWordPicked(_ globalIndex: Int) {
        pickerSelectedWordIndex = globalIndex
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        // Let the highlight flash on the chosen word before switching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            confirmWordPickerSelection()
        }
    }

    private func confirmWordPickerSelection() {
        guard isWordPickerActive, let index = pickerSelectedWordIndex else { return }
        // goToIndex BEFORE flipping the mode: the departure snapshot uses the
        // reading position, and NormalReadingView's onDisappear then
        // force-saves the picked index.
        viewModel.goToIndex(index)
        withAnimation(.easeOut(duration: 0.2)) {
            isWordPickerActive = false
        }
        pickerSelectedWordIndex = nil
        currentMode = .rsvp
        persistCurrentMode()
    }

    private func cancelWordPicker() {
        withAnimation(.easeOut(duration: 0.2)) {
            isWordPickerActive = false
        }
        pickerSelectedWordIndex = nil
    }

    private func toggleReadingUI() {
        // The picker banner lives in the UI chrome — don't hide it mid-pick.
        guard !isWordPickerActive else { return }
        if showUI {
            uiHideTimer?.invalidate()
            uiHideTimer = nil
            withAnimation { showUI = false }
        } else {
            withAnimation { showUI = true }
            uiHideTimer?.invalidate()
            uiHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                withAnimation { showUI = false }
            }
        }
    }
    
    private func handlePlayPause() {
        if isScrubbing || showContextPeek {
            return
        }

        tutorial.reportCenterTap()
        // While a checkpoint waits for its gesture, tapping must not push past the gate
        if tutorial.blocksPlayback {
            return
        }

        viewModel.togglePlayPause()

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
        tutorial.reportPeekDismissed()

        // Stay paused - user will click play when ready
    }
    
    /// Screen position for a tutorial checkpoint hint. Side hints match the
    /// placement of the first-launch speed/peek hints; center hints sit below
    /// the displayed word.
    private func tutorialHintPoint(for position: TutorialController.HintPosition, in geo: GeometryProxy) -> CGPoint {
        switch position {
        case .center:
            return CGPoint(x: geo.size.width * 0.5, y: geo.size.height * 0.66)
        case .rightEdge:
            return CGPoint(x: geo.size.width * 0.85, y: geo.size.height * 0.55)
        case .leftEdge:
            return CGPoint(x: geo.size.width * 0.15, y: geo.size.height * 0.55)
        }
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
    
    // MARK: - Figure Overlay Views (extracted from body to reduce type-check complexity)
    
    @ViewBuilder
    private func wordSearchCover() -> some View {
        WordSearchView(
            viewModel: viewModel,
            isPresented: $showSearch
        )
        .presentationBackground(settings.backgroundColor)
    }
    
    @ViewBuilder
    private func figureHalfScreenOverlay(geo: GeometryProxy) -> some View {
        if showFigureViewer, !showFigureExpanded {
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    settings.backgroundColor.opacity(0.92)
                    
                    VStack(spacing: 12) {
                        Spacer().frame(height: 50)
                        
                        if let image = figureImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: geo.size.height * 0.35)
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                                .onTapGesture {
                                    viewModel.pause()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showFigureExpanded = true
                                    }
                                }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo")
                                    .font(.system(size: 40))
                                    .foregroundColor(settings.mutedTextColor)
                                Text("Loading figure...")
                                    .font(.custom("EBGaramond-Regular", size: 14))
                                    .foregroundColor(settings.mutedTextColor)
                            }
                            .frame(height: geo.size.height * 0.25)
                        }
                        
                        if let caption = viewModel.figureToShow?.caption {
                            Text(caption)
                                .font(.custom("EBGaramond-Italic", size: 15))
                                .foregroundColor(settings.secondaryTextColor)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .lineLimit(3)
                        }
                        
                        Text("Tap image to expand")
                            .font(.custom("EBGaramond-Regular", size: 12))
                            .foregroundColor(settings.mutedTextColor)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    
                    Button(action: { closeFigureViewer() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(settings.textColor)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(settings.backgroundColor.opacity(0.8)).overlay(Circle().stroke(settings.textColor.opacity(0.2), lineWidth: 1)))
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                }
                .frame(height: geo.size.height * 0.5)
                .gesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            if abs(value.translation.width) + abs(value.translation.height) > 80 { closeFigureViewer() }
                        }
                )
                
                Color.clear
                    .frame(height: geo.size.height * 0.5)
                    .allowsHitTesting(false)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(50)
        }
    }
    
    @ViewBuilder
    private func figureExpandedOverlay() -> some View {
        if showFigureExpanded {
            ZStack {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()
                    .onTapGesture { dismissExpandedFigure() }
                
                if let image = figureImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(figureZoomScale)
                        .offset(figurePanOffset)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    figureZoomScale = figureLastZoomScale * value.magnification
                                }
                                .onEnded { _ in
                                    figureLastZoomScale = max(1.0, figureZoomScale)
                                    figureZoomScale = figureLastZoomScale
                                    if figureZoomScale <= 1.0 {
                                        withAnimation(.spring(response: 0.3)) {
                                            figurePanOffset = .zero
                                            figureLastPanOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if figureZoomScale > 1.0 {
                                        figurePanOffset = CGSize(
                                            width: figureLastPanOffset.width + value.translation.width,
                                            height: figureLastPanOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { value in
                                    if figureZoomScale > 1.0 {
                                        figureLastPanOffset = figurePanOffset
                                    } else if abs(value.translation.width) + abs(value.translation.height) > 100 {
                                        dismissExpandedFigure()
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if figureZoomScale > 1.0 {
                                    figureZoomScale = 1.0
                                    figureLastZoomScale = 1.0
                                    figurePanOffset = .zero
                                    figureLastPanOffset = .zero
                                } else {
                                    figureZoomScale = 2.5
                                    figureLastZoomScale = 2.5
                                }
                            }
                        }
                }
                
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { dismissExpandedFigure() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                    
                    if let caption = viewModel.figureToShow?.caption {
                        Text(caption)
                            .font(.custom("EBGaramond-Italic", size: 16))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 40)
                    }
                }
            }
            .transition(.opacity)
            .zIndex(200)
        }
    }
    
    // MARK: - Figure Viewer Methods
    
    private func openFigureViewer() {
        guard let figure = viewModel.figureToShow ?? viewModel.figureAnnotations.first,
              let docId = documentId else { return }
        
        // Pause reading
        viewModel.pause()
        uiHideTimer?.invalidate()
        withAnimation { showUI = true }
        
        // Load figure image from disk
        figureImage = LibraryManager.shared.loadFigureImage(for: docId, fileName: figure.imageFileName)
        
        // Show the overlay
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            showFigureViewer = true
        }
    }
    
    private func closeFigureViewer() {
        viewModel.dismissCurrentFigure()
        withAnimation(.easeOut(duration: 0.25)) {
            showFigureViewer = false
            showFigureExpanded = false
        }
        figureImage = nil
        resetFigureZoom()
    }
    
    private func dismissExpandedFigure() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showFigureExpanded = false
        }
        resetFigureZoom()
    }
    
    private func resetFigureZoom() {
        figureZoomScale = 1.0
        figureLastZoomScale = 1.0
        figurePanOffset = .zero
        figureLastPanOffset = .zero
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

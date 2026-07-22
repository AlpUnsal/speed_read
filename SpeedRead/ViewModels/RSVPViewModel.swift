import Foundation
import Combine
import UIKit

class RSVPViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentWord: String = ""
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var wordsPerMinute: Double = 300
    @Published var progress: Double = 0
    @Published var isLoading: Bool = false
    @Published var isInsideDialogue: Bool = false
    @Published var scrollResetID = UUID()
    @Published var externalNavigationID = UUID()

    // Callback to persist progress externally (e.g. to LibraryManager)
    var onProgressUpdate: ((Int, Double) -> Void)?

    // Callback to persist a position snapshot externally (e.g. to LibraryManager)
    var onSnapshotRecorded: ((PositionSnapshot) -> Void)?

    // MARK: - Position History
    // Live in-memory history for the current document, seeded from the loaded
    // document so ChapterListView can render it. Persistence is one-way
    // (view model -> LibraryManager via onSnapshotRecorded).
    @Published var positionHistory: [PositionSnapshot] = []

    // Departure index override for the next goToIndex call — set by callers
    // (like scrub-start) where currentIndex gets mutated by lightweight
    // updates before goToIndex actually runs.
    private var pendingDepartureIndex: Int? = nil

    // Sustained-reading tracking (reading-checkpoint snapshots)
    private var wordsReadSinceLastCheckpoint = 0
    private var lastSequentialIndex: Int? = nil

    // Internal (not private): NormalReadingView uses the same threshold for
    // reading-mode scroll jumps so the two modes never disagree on "big jump".
    let jumpSnapshotThreshold = 100
    // Keep in sync with ReadingDocument.recordPositionSnapshot
    private let historyDedupeWindow = 50
    private let historyCap = 10
    
    // MARK: - Navigation Properties
    @Published var navigationPoints: [NavigationPoint] = []
    @Published var currentNavigationPoint: NavigationPoint?
    
    // MARK: - Search Properties
    @Published var searchResults: [SearchResult] = []
    @Published var currentSearchIndex: Int?
    private var searchQuery: String = ""
    
    // MARK: - Word Layout Data
    struct WordLayoutData: Equatable {
        let word: String
        let fontSize: CGFloat
        let orpOffset: CGFloat
    }
    
    // MARK: - Sliding Window Virtualization
    // For very large documents (1M+ words), we only keep a window of words in memory
    private let windowRadius = 2500  // 2500 words before + 2500 words after = 5000 total (Aggressive Preloading)
    @Published var windowStartIndex: Int = 0
    @Published var visibleLayoutData: [WordLayoutData] = []
    
    // Font settings for lazy computation
    private var fontName: String = "EBGaramond-Regular"
    private var fontSizeMultiplier: CGFloat = 1.0
    
    // MARK: - Raw Word Storage (strings only, minimal memory)
    @Published var words: [String] = []
    @Published var originalText: String = ""
    @Published var wordRanges: [Range<String.Index>] = []

    // Paragraph boundaries over `words` — single source of truth for reading
    // mode. Produced by the same tokenization pass as `words`, so paragraph
    // word indices can never drift from RSVP's indices.
    @Published var paragraphs: [ParagraphTokenization] = []
    
    private var timer: Timer?
    private var lastReadingSaveTime: Date = .distantPast

    // MARK: - Constants
    let minWPM: Double = 100
    let maxWPM: Double = 1000
    
    // MARK: - Computed Properties
    var totalWords: Int {
        words.count
    }
    
    var intervalMs: Double {
        return 60000.0 / wordsPerMinute
    }
    
    // Window info for gesture-based scrolling
    var windowEndIndex: Int {
        min(windowStartIndex + visibleLayoutData.count, words.count)
    }
    
    // Navigation computed properties
    var currentSectionLabel: String {
        currentSectionLabel(at: currentIndex) ?? ""
    }
    
    func currentSectionLabel(at index: Int) -> String? {
        guard !navigationPoints.isEmpty else {
            let pageNum = PageChunker.pageNumber(for: index)
            let totalPages = PageChunker.pageCount(for: words.count)
            return "Page \(pageNum) of \(totalPages)"
        }
        
        let point = navigationPoints.first { $0.contains(wordIndex: index) }
        
        if let current = point {
            if current.type == .chapter {
                return current.title
            } else if let idx = navigationPoints.firstIndex(where: { $0.id == current.id }) {
                return "Page \(idx + 1) of \(navigationPoints.count)"
            }
        }
        return nil
    }
    
    var isFirstSection: Bool {
        guard let current = currentNavigationPoint,
              let index = navigationPoints.firstIndex(where: { $0.id == current.id }) else {
            return currentIndex == 0
        }
        return index == 0
    }
    
    var isLastSection: Bool {
        guard let current = currentNavigationPoint,
              let index = navigationPoints.firstIndex(where: { $0.id == current.id }) else {
            return currentIndex >= words.count - 1
        }
        return index == navigationPoints.count - 1
    }
    
    // Percentage formatting
    var bookProgressPercentage: Int {
        if totalWords == 0 { return 0 }
        return Int((Double(currentIndex + 1) / Double(totalWords)) * 100)
    }
    
    var chapterProgressPercentage: Int {
        let defaultPercent = bookProgressPercentage
        
        guard !navigationPoints.isEmpty, let current = currentNavigationPoint else {
            return defaultPercent // Fallback if no true chapters
        }
        
        // Find the index of the current navigation point
        if let currentIdx = navigationPoints.firstIndex(where: { $0.id == current.id }) {
            let chapterStart = current.wordStartIndex
            var chapterEnd = totalWords
            
            // If there's a next point, the chapter ends right before it
            if currentIdx < navigationPoints.count - 1 {
                chapterEnd = navigationPoints[currentIdx + 1].wordStartIndex
            }
            
            let chapterLength = chapterEnd - chapterStart
            if chapterLength <= 0 { return 100 } // Safety
            
            let wordsReadInChapter = (currentIndex + 1) - chapterStart
            
            // Calculate percentage and clamp between 0 and 100
            let percentage = Int((Double(wordsReadInChapter) / Double(chapterLength)) * 100)
            return max(0, min(100, percentage))
        }
        
        return defaultPercent
    }
    
    // MARK: - Debug
    let id = UUID()
    
    // MARK: - Initialization
    init() {}
    
    // MARK: - Public Methods
    
    /// Load text with sliding window virtualization (best for large documents)
    func loadText(_ text: String, startingAt index: Int = 0,
                  fontName: String = "EBGaramond-Regular",
                  fontSizeMultiplier: CGFloat = 1.0) {
        self.fontName = fontName
        self.fontSizeMultiplier = fontSizeMultiplier
        self.originalText = text
        self.raritySeenCounts = [:]
        self.pacingSpentEMA = 0
        updateDocumentLanguage(for: text)

        // Tokenize (this is relatively fast even for large docs)
        let tokenized = TextTokenizer.tokenizeParagraphs(text)
        self.words = tokenized.words
        self.paragraphs = tokenized.paragraphs
        
        // Skip range calculation for very large documents (saves memory)
        // Ranges are only needed for paragraph highlighting which we're not using in windowed mode
        if words.count < 100000 {
            var ranges: [Range<String.Index>] = []
            var searchStartIndex = text.startIndex
            for word in words {
                if let range = text.range(of: word, options: .literal, range: searchStartIndex..<text.endIndex) {
                    ranges.append(range)
                    searchStartIndex = range.upperBound
                }
            }
            self.wordRanges = ranges
        } else {
            self.wordRanges = []
        }
        
        // Set initial state
        currentIndex = min(index, max(0, words.count - 1))
        currentWord = words.isEmpty ? "" : words[currentIndex]
        isInsideDialogue = TextTokenizer.dialogueState(at: currentIndex, in: words)
        updateProgress()
        
        // Initialize the visible window around the starting position
        updateWindow(around: currentIndex)
    }
    
    /// Async version for UI responsiveness during initial load
    func loadTextAsync(_ text: String, startingAt index: Int = 0,
                       fontName: String = "EBGaramond-Regular",
                       fontSizeMultiplier: CGFloat = 1.0,
                       onComplete: (() -> Void)? = nil) {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tokenized = TextTokenizer.tokenizeParagraphs(text)

            DispatchQueue.main.async {
                guard let self = self else { return }
                self.fontName = fontName
                self.fontSizeMultiplier = fontSizeMultiplier
                self.originalText = text
                self.raritySeenCounts = [:]
                self.pacingSpentEMA = 0
                self.updateDocumentLanguage(for: text)
                self.words = tokenized.words
                self.paragraphs = tokenized.paragraphs
                self.wordRanges = [] // Skip ranges for async load (large docs)
                
                self.currentIndex = min(index, max(0, self.words.count - 1))
                self.currentWord = self.words.isEmpty ? "" : self.words[self.currentIndex]
                self.isInsideDialogue = TextTokenizer.dialogueState(at: self.currentIndex, in: self.words)
                self.updateProgress()
                self.updateWindow(around: self.currentIndex)
                
                self.isLoading = false
                onComplete?()
            }
        }
    }
    
    /// Update the visible window of layout data around a center index
    func updateWindow(around centerIndex: Int) {
        let start = max(0, centerIndex - windowRadius)
        let end = min(words.count, centerIndex + windowRadius)
        
        // Only recompute if window actually moved significantly
        let currentCenter = windowStartIndex + visibleLayoutData.count / 2
        let moved = abs(centerIndex - currentCenter)
        
        // Threshold: only update if we moved more than 50 words from center
        // This prevents constant recomputation during small scrolls
        if !visibleLayoutData.isEmpty && moved < 50 && start >= windowStartIndex && end <= windowEndIndex {
            return
        }
        
        windowStartIndex = start
        
        // Compute layout data only for the visible window
        let cache = FontMetricsCache.shared
        visibleLayoutData = (start..<end).map { i in
            let word = words[i]
            let baseFontSize = WordDisplayView.fontSize(for: word)
            let fontSize = baseFontSize * fontSizeMultiplier
            let orpOffset = cache.orpOffset(for: word, fontName: fontName, fontSize: fontSize)
            return WordLayoutData(word: word, fontSize: fontSize, orpOffset: orpOffset)
        }
    }
    
    /// Get layout data for a specific word index (computes on-demand if needed)
    func layoutData(at index: Int) -> WordLayoutData? {
        guard index >= 0 && index < words.count else { return nil }
        
        // Check if it's in the current window
        let windowIndex = index - windowStartIndex
        if windowIndex >= 0 && windowIndex < visibleLayoutData.count {
            return visibleLayoutData[windowIndex]
        }
        
        // Not in window - compute on-demand
        let word = words[index]
        let baseFontSize = WordDisplayView.fontSize(for: word)
        let fontSize = baseFontSize * fontSizeMultiplier
        let orpOffset = FontMetricsCache.shared.orpOffset(for: word, fontName: fontName, fontSize: fontSize)
        return WordLayoutData(word: word, fontSize: fontSize, orpOffset: orpOffset)
    }
    
    /// Check if an index is the current word
    func isCurrent(_ index: Int) -> Bool {
        index == currentIndex
    }
    
    // MARK: - Playback Controls
    
    func play() {
        guard !words.isEmpty else { return }
        isPlaying = true
        scheduleNextWord()
    }
    
    func pause() {
        let wasPlaying = isPlaying
        isPlaying = false
        timer?.invalidate()
        timer = nil
        // A pause ends a "reading run" — resuming starts a fresh 200-word count
        resetSustainedReadingTracking()

        // Trigger save when paused
        if wasPlaying {
            onProgressUpdate?(currentIndex, wordsPerMinute)
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func reset() {
        let departureIndex = pendingDepartureIndex ?? currentIndex
        pendingDepartureIndex = nil
        pause()
        if departureIndex > jumpSnapshotThreshold {
            recordSnapshot(at: departureIndex, kind: .jumpDeparture)
        }
        resetSustainedReadingTracking()
        currentIndex = 0
        currentWord = words.first ?? ""
        scrollResetID = UUID() // Force ScrollView reconstruction
        updateProgress()
        updateWindow(around: 0)
        onProgressUpdate?(currentIndex, wordsPerMinute)
    }
    
    func skipForward(by count: Int = 10) {
        let newIndex = min(currentIndex + count, words.count - 1)
        goToIndex(newIndex)
    }
    
    func skipForward(seconds: Double) {
        let wordsPerSecond = wordsPerMinute / 60.0
        let wordsToSkip = max(1, Int(wordsPerSecond * seconds))
        skipForward(by: wordsToSkip)
    }
    
    func skipBackward(by count: Int = 10) {
        let newIndex = max(currentIndex - count, 0)
        goToIndex(newIndex)
    }
    
    func skipBackward(seconds: Double) {
        let wordsPerSecond = wordsPerMinute / 60.0
        let wordsToSkip = max(1, Int(wordsPerSecond * seconds))
        skipBackward(by: wordsToSkip)
    }
    
    func word(at index: Int) -> String {
        guard index >= 0 && index < words.count else { return "" }
        return words[index]
    }
    
    func goToIndex(_ index: Int) {
        let wasPlaying = isPlaying
        if wasPlaying {
            pause()
        }
        let target = max(0, min(index, words.count - 1))
        let departureIndex = pendingDepartureIndex ?? currentIndex
        pendingDepartureIndex = nil
        if abs(target - departureIndex) > jumpSnapshotThreshold {
            recordSnapshot(at: departureIndex, kind: .jumpDeparture)
        }
        resetSustainedReadingTracking()

        currentIndex = target
        if currentIndex < words.count {
            currentWord = words[currentIndex]
            // Checking just the landing word leaves the toggle stale when it
            // carries no quote — reconstruct from position instead.
            isInsideDialogue = TextTokenizer.dialogueState(at: currentIndex, in: words)
        }
        updateProgress()
        updateWindow(around: currentIndex)
        checkAndTriggerFigure(at: currentIndex)
        externalNavigationID = UUID()
    }

    /// Lightweight update that doesn't trigger window re-computation
    /// Used during scrolling to keep the index in sync without lag
    func updateIndexOnly(_ index: Int) {
        currentIndex = max(0, min(index, words.count - 1))
        if currentIndex < words.count {
            currentWord = words[currentIndex]
        }
        updateProgress()
    }

    /// Lightweight update for reading mode scroll tracking.
    /// Updates currentIndex, progress, and currentNavigationPoint (efficiently).
    /// Debounced save ensures position persists without disk thrash.
    func updateIndexForReading(_ index: Int, forceSave: Bool = false) {
        let clamped = max(0, min(index, words.count - 1))

        let indexChanged = clamped != currentIndex
        if indexChanged {
            currentIndex = clamped
            if words.isEmpty {
                progress = 0
            } else {
                progress = Double(currentIndex) / Double(words.count)
            }

            // Efficient navigation point update: check current first, then neighbors, then full scan
            if let current = currentNavigationPoint, current.contains(wordIndex: clamped) {
                // Still in same section — no update needed
            } else if let current = currentNavigationPoint,
                      let idx = navigationPoints.firstIndex(where: { $0.id == current.id }) {
                if idx + 1 < navigationPoints.count && navigationPoints[idx + 1].contains(wordIndex: clamped) {
                    currentNavigationPoint = navigationPoints[idx + 1]
                } else if idx - 1 >= 0 && navigationPoints[idx - 1].contains(wordIndex: clamped) {
                    currentNavigationPoint = navigationPoints[idx - 1]
                } else {
                    currentNavigationPoint = navigationPoints.first { $0.contains(wordIndex: clamped) }
                }
            } else {
                currentNavigationPoint = navigationPoints.first { $0.contains(wordIndex: clamped) }
            }
        }

        // Save logic: forceSave always triggers (even if index unchanged),
        // otherwise debounce to every 0.5 seconds during active scrolling
        if forceSave {
            lastReadingSaveTime = Date()
            onProgressUpdate?(currentIndex, wordsPerMinute)
        } else if indexChanged {
            let now = Date()
            if now.timeIntervalSince(lastReadingSaveTime) >= 0.5 {
                lastReadingSaveTime = now
                onProgressUpdate?(currentIndex, wordsPerMinute)
            }
        }
    }
    
    // MARK: - Private Methods

    /// How many times each rare word has been displayed in this document.
    /// Feeds the smart-pacing familiarity decay: a rare word earns a full
    /// pause on first sight, none by its sixth. Persisted per document via
    /// seedRarityFamiliarity/rarityFamiliaritySnapshot; counts are capped
    /// so long books don't accumulate meaninglessly large values.
    private var raritySeenCounts: [String: Int] = [:]
    private static let raritySeenCap = 12

    /// Current counts, for persisting into ReadingDocument.
    var rarityFamiliaritySnapshot: [String: Int] { raritySeenCounts }

    /// Restore familiarity from a document's persisted counts, gently faded
    /// by time away — like real memory: after a week, a learned word drops
    /// to a ~35% pause; it never fades below a count of 2 (60% pause), and
    /// words seen only once keep their full pause. Call after loadText,
    /// which resets the counts.
    func seedRarityFamiliarity(_ counts: [String: Int], lastReadDate: Date?) {
        guard !counts.isEmpty else { return }
        var faded = counts
        if let last = lastReadDate {
            let days = Date().timeIntervalSince(last) / 86_400
            if days >= 7 {
                let halvings = days >= 30 ? 2 : 1
                faded = counts.mapValues { max(min($0, 2), $0 >> halvings) }
            }
        }
        raritySeenCounts = faded
    }

    /// Detected document language ("en", "tr", ...) and the matching device
    /// spell-check dictionary ("en_US", ...). When no dictionary matches,
    /// rarity pauses are disabled for the document rather than checked
    /// against the wrong language; length pauses still apply.
    private var documentLanguageCode: String?
    private var spellCheckLanguage: String?

    private func updateDocumentLanguage(for text: String) {
        documentLanguageCode = TextTokenizer.detectLanguage(of: text)
        spellCheckLanguage = TextTokenizer.spellCheckLanguage(matching: documentLanguageCode)
        if documentLanguageCode?.hasPrefix("en") == true {
            TextTokenizer.prepareZipfTable()
        }
    }

    /// Smoothed smart-pacing *demand* in ms per word (EMA over roughly the
    /// last 25 words), measured before the budget scale so the guard
    /// converges applied spend to the budget rather than overshooting.
    private var pacingSpentEMA: Double = 0

    /// Extra ms for rare and long words (smart pacing). Counts the rare-word
    /// sighting as a side effect, so call it exactly once per displayed word.
    ///
    /// Budget guard: in jargon-dense text (technical PDFs) most words are
    /// "rare" and the extras would compound into a lower effective WPM. Once
    /// the rolling spend exceeds ~7% of the base interval, new extras scale
    /// down proportionally — with a floor so first-sight rare words never
    /// vanish entirely. Plain stretches let the budget recover.
    private func smartPacingDelayMs(for word: String) -> Double {
        guard SettingsManager.shared.smartPacing else { return 0 }
        var extra = TextTokenizer.lengthDelay(for: word, wpm: wordsPerMinute)
        if let language = spellCheckLanguage,
           let key = TextTokenizer.rarityKey(for: word, languageCode: documentLanguageCode) {
            // English documents get graded weights from the Zipf table;
            // other languages (and English before the table loads) keep the
            // binary dictionary signal.
            let weight: Double
            if documentLanguageCode?.hasPrefix("en") == true,
               let graded = TextTokenizer.gradedRarityWeight(key, language: language) {
                weight = graded
            } else {
                weight = TextTokenizer.isRareWord(key, language: language) ? 1.0 : 0.0
            }
            if weight >= 0.05 {
                let count = raritySeenCounts[key, default: 0]
                raritySeenCounts[key] = min(count + 1, Self.raritySeenCap)
                extra += TextTokenizer.rarityDelay(wpm: wordsPerMinute, seenCount: count) * weight
            }
        }
        extra *= SettingsManager.shared.smartPacingIntensity.multiplier

        let budgetPerWord = (60000.0 / wordsPerMinute) * 0.07
        let scale = pacingSpentEMA <= budgetPerWord
            ? 1.0
            : max(0.25, budgetPerWord / pacingSpentEMA)
        pacingSpentEMA += 0.04 * (extra - pacingSpentEMA)
        return extra * scale
    }

    private func scheduleNextWord() {
        guard isPlaying, currentIndex < words.count else {
            if currentIndex >= words.count {
                pause()
            }
            return
        }
        
        let word = words[currentIndex]
        currentWord = word
        updateDialogueState(for: word)

        let nextWord = currentIndex + 1 < words.count ? words[currentIndex + 1] : nil
        let pauseMs = TextTokenizer.pauseDelay(for: word, wpm: wordsPerMinute)
        let dialogueMs = TextTokenizer.dialogueTransitionDelay(currentWord: word, nextWord: nextWord, wpm: wordsPerMinute)
        let pacingMs = smartPacingDelayMs(for: word)
        let delay = (pauseMs + dialogueMs + pacingMs) / 1000.0
        
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentIndex += 1
            self.trackSequentialReading(newIndex: self.currentIndex)
            self.updateProgress()
            
            // Check if a figure should be shown at this index (auto-popup + auto-pause)
            let newlyTriggered = self.checkAndTriggerFigure(at: self.currentIndex)
            if newlyTriggered {
                self.pause()
                return  // Stop advancing — user will resume manually
            }

            // Tutorial checkpoint gate — pauses with the previous word still
            // displayed. Unlike figures, gates are one-shot and never re-arm.
            if let gate = self.shouldAdvance, !gate(self.currentIndex) {
                self.pause()
                return
            }

            // Checkpoint every 50 words
            if self.currentIndex % 50 == 0 {
                self.onProgressUpdate?(self.currentIndex, self.wordsPerMinute)
            }
            
            // Update window periodically during playback
            if self.currentIndex % 50 == 0 {
                self.updateWindow(around: self.currentIndex)
            }
            
            self.scheduleNextWord()
        }
    }
    
    /// Track whether the reader is currently inside dialogue (between opening and closing quotes)
    private func updateDialogueState(for word: String) {
        if TextTokenizer.containsClosingQuote(word) {
            isInsideDialogue = false
        } else if TextTokenizer.containsOpeningQuote(word) {
            isInsideDialogue = true
        }
    }

    private func updateProgress() {
        if words.isEmpty {
            progress = 0
        } else {
            progress = Double(currentIndex) / Double(words.count)
        }
        // Update current navigation point
        currentNavigationPoint = navigationPoints.first { $0.contains(wordIndex: currentIndex) }
    }
    
    // MARK: - Navigation Methods
    
    /// Set navigation points for the document
    func setNavigationPoints(_ points: [NavigationPoint]) {
        self.navigationPoints = points
        currentNavigationPoint = navigationPoints.first { $0.contains(wordIndex: currentIndex) }
    }

    // MARK: - Position History Methods

    /// Seed the live history from the loaded document
    func setPositionHistory(_ history: [PositionSnapshot]) {
        positionHistory = history
    }

    /// Records a `.jumpDeparture` snapshot for a reading-mode scroll session
    /// that ended far from where it started. The caller (NormalReadingView)
    /// compares the session delta against `jumpSnapshotThreshold`.
    func recordReadingJumpSnapshot(departureIndex: Int) {
        recordSnapshot(at: departureIndex, kind: .jumpDeparture)
    }

    /// Explicitly mark `index` as the departure point for the next jump.
    /// Used by callers (like scrub-start) where currentIndex will be mutated
    /// by intermediate lightweight updates before goToIndex is called.
    func markDepartureForNextJump(_ index: Int) {
        pendingDepartureIndex = index
    }

    /// ~8-word snippet starting at `index`, for display in history rows
    private func snippet(at index: Int) -> String {
        guard index >= 0, index < words.count else { return "" }
        let end = min(index + 8, words.count)
        return words[index..<end].joined(separator: " ")
    }

    /// Record a snapshot into the live history (same dedupe/cap as
    /// ReadingDocument.recordPositionSnapshot) and forward it for persistence.
    private func recordSnapshot(at index: Int, kind: PositionSnapshot.Kind) {
        guard index >= 0, index < words.count else { return }
        let snap = PositionSnapshot(
            wordIndex: index,
            kind: kind,
            sectionLabel: currentSectionLabel(at: index),
            snippet: snippet(at: index)
        )
        positionHistory.removeAll { abs($0.wordIndex - snap.wordIndex) < historyDedupeWindow }
        positionHistory.insert(snap, at: 0)
        if positionHistory.count > historyCap {
            positionHistory = Array(positionHistory.prefix(historyCap))
        }
        onSnapshotRecorded?(snap)
    }

    /// Called on every forward playback tick. Records a reading-checkpoint
    /// snapshot after ~200 words of continuous forward reading, so genuine
    /// reading progress survives even if the user later reads from a wrong spot.
    private func trackSequentialReading(newIndex: Int) {
        if let last = lastSequentialIndex, newIndex == last + 1 {
            wordsReadSinceLastCheckpoint += 1
        } else {
            wordsReadSinceLastCheckpoint = 1
        }
        lastSequentialIndex = newIndex

        if wordsReadSinceLastCheckpoint >= 200 {
            // Snapshot the START of the run — that's where a lost user wants to return
            recordSnapshot(at: max(0, newIndex - wordsReadSinceLastCheckpoint), kind: .readingCheckpoint)
            wordsReadSinceLastCheckpoint = 0  // re-arm; dedupe window prevents spam
        }
    }

    private func resetSustainedReadingTracking() {
        wordsReadSinceLastCheckpoint = 0
        lastSequentialIndex = nil
    }
    
    // MARK: - Playback Gate

    /// Optional external gate — the playback loop asks this closure before
    /// advancing past a given index; returning false pauses instead. Nil (the
    /// default) means always advance, so normal documents are unaffected.
    /// Used by TutorialController for the gated first-run tutorial.
    var shouldAdvance: ((Int) -> Bool)? = nil

    // MARK: - Figure Annotations

    @Published var figureAnnotations: [FigureAnnotation] = []
    
    /// Set when reading crosses a figure's word index for the first time (auto-popup trigger)
    @Published var figureToShow: FigureAnnotation? = nil
    
    /// IDs of figures the user has explicitly dismissed — won't auto-show again
    /// unless the reader navigates back before the figure's word index
    private var dismissedFigureIds: Set<UUID> = []
    
    /// Last index at which we checked for a new figure (avoids re-triggering)
    private var lastFigureTriggerIndex: Int = -1
    
    func setFigureAnnotations(_ figures: [FigureAnnotation]) {
        self.figureAnnotations = figures
        dismissedFigureIds = []
        lastFigureTriggerIndex = -1
        figureToShow = nil
    }
    
    /// Trigger a specific figure to show manually (e.g. from a menu).
    func showKnownFigure(_ figure: FigureAnnotation) {
        pause()
        figureToShow = figure
    }
    
    /// Call this when the user explicitly dismisses the figure overlay
    func dismissCurrentFigure() {
        if let f = figureToShow {
            dismissedFigureIds.insert(f.id)
        }
        figureToShow = nil
    }
    
    /// Check if a new figure should be shown at the current word index.
    /// Called from the timer loop so figures pop up the moment reading reaches them.
    /// Returns `true` if it newly triggered a figure to pull up (so the reader should pause).
    @discardableResult
    private func checkAndTriggerFigure(at index: Int) -> Bool {
        guard !figureAnnotations.isEmpty else { return false }
        // Don't re-check the same index
        guard index != lastFigureTriggerIndex else { return false }
        lastFigureTriggerIndex = index
        
        var newlyTriggered = false
        
        // Find a figure whose wordIndex we just crossed (within a small look-behind window)
        let lookBehind = 5
        for figure in figureAnnotations {
            let wi = figure.wordIndex
            guard wi > 0 else { continue }
            // Trigger when we first arrive at or just past the figure's word index
            if index >= wi && index <= wi + lookBehind {
                if !dismissedFigureIds.contains(figure.id) {
                    if figureToShow?.id != figure.id {
                        figureToShow = figure
                        newlyTriggered = true
                    }
                }
            }
            // If we navigated back before a dismissed figure, un-dismiss it
            if index < wi {
                dismissedFigureIds.remove(figure.id)
            }
        }
        
        return newlyTriggered
    }
    
    /// Jump to the next section (chapter/page)
    @discardableResult
    func jumpToNextSection() -> Bool {
        guard !navigationPoints.isEmpty else { return false }
        
        if let current = currentNavigationPoint,
           let currentIdx = navigationPoints.firstIndex(where: { $0.id == current.id }),
           currentIdx < navigationPoints.count - 1 {
            let next = navigationPoints[currentIdx + 1]
            goToIndex(next.wordStartIndex)
            return true
        }
        return false
    }
    
    /// Jump to the previous section (chapter/page)
    @discardableResult
    func jumpToPreviousSection() -> Bool {
        guard !navigationPoints.isEmpty else { return false }
        
        if let current = currentNavigationPoint,
           let currentIdx = navigationPoints.firstIndex(where: { $0.id == current.id }) {
            // If we're past the start of current chapter, go to its start
            if currentIndex > current.wordStartIndex + 10 {
                goToIndex(current.wordStartIndex)
                return true
            }
            // Otherwise go to previous chapter
            if currentIdx > 0 {
                let prev = navigationPoints[currentIdx - 1]
                goToIndex(prev.wordStartIndex)
                return true
            }
        }
        return false
    }
    
    /// Jump to a specific navigation point
    func jumpToNavigationPoint(_ point: NavigationPoint) {
        goToIndex(point.wordStartIndex)
    }
    
    // MARK: - Search Methods
    
    /// Search for a query in the document
    func search(query: String) {
        searchQuery = query
        if query.isEmpty {
            searchResults = []
            currentSearchIndex = nil
            return
        }
        
        searchResults = WordSearcher.search(query: query, in: words, caseSensitive: false)
        
        // Find nearest result to current position
        if !searchResults.isEmpty {
            currentSearchIndex = searchResults.enumerated().min(by: { 
                abs($0.element.wordIndex - currentIndex) < abs($1.element.wordIndex - currentIndex) 
            })?.offset ?? 0
        } else {
            currentSearchIndex = nil
        }
    }
    
    /// Jump to the next search result
    func jumpToNextSearchResult() {
        guard !searchResults.isEmpty else { return }
        
        if let current = currentSearchIndex {
            currentSearchIndex = (current + 1) % searchResults.count
        } else {
            currentSearchIndex = 0
        }
        
        if let index = currentSearchIndex {
            goToIndex(searchResults[index].wordIndex)
        }
    }
    
    /// Jump to the previous search result
    func jumpToPreviousSearchResult() {
        guard !searchResults.isEmpty else { return }
        
        if let current = currentSearchIndex {
            currentSearchIndex = current > 0 ? current - 1 : searchResults.count - 1
        } else {
            currentSearchIndex = searchResults.count - 1
        }
        
        if let index = currentSearchIndex {
            goToIndex(searchResults[index].wordIndex)
        }
    }
    
    /// Jump to a specific search result
    func jumpToSearchResult(at index: Int) {
        guard index >= 0 && index < searchResults.count else { return }
        currentSearchIndex = index
        goToIndex(searchResults[index].wordIndex)
    }
    
    /// Clear search state
    func clearSearch() {
        searchQuery = ""
        searchResults = []
        currentSearchIndex = nil
    }
}

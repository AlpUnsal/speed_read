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
    @Published var scrollResetID = UUID()
    
    // Callback to persist progress externally (e.g. to LibraryManager)
    var onProgressUpdate: ((Int, Double) -> Void)?
    
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
    
    private var timer: Timer?
    
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
        
        // Tokenize (this is relatively fast even for large docs)
        self.words = TextTokenizer.tokenize(text)
        
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
            let words = TextTokenizer.tokenize(text)
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.fontName = fontName
                self.fontSizeMultiplier = fontSizeMultiplier
                self.originalText = text
                self.words = words
                self.wordRanges = [] // Skip ranges for async load (large docs)
                
                self.currentIndex = min(index, max(0, words.count - 1))
                self.currentWord = words.isEmpty ? "" : words[self.currentIndex]
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
        pause()
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
    
    func skipBackward(by count: Int = 10) {
        let newIndex = max(currentIndex - count, 0)
        goToIndex(newIndex)
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
        currentIndex = max(0, min(index, words.count - 1))
        if currentIndex < words.count {
            currentWord = words[currentIndex]
        }
        updateProgress()
        updateWindow(around: currentIndex)
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
    
    // MARK: - Private Methods
    
    private func scheduleNextWord() {
        guard isPlaying, currentIndex < words.count else {
            if currentIndex >= words.count {
                pause()
            }
            return
        }
        
        let word = words[currentIndex]
        currentWord = word
        
        let pauseMultiplier = TextTokenizer.pauseMultiplier(for: word, wpm: wordsPerMinute)
        let delay = intervalMs * pauseMultiplier / 1000.0
        
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentIndex += 1
            self.updateProgress()
            
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

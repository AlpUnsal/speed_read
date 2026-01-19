import Foundation
import Combine

class RSVPViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentWord: String = ""
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var wordsPerMinute: Double = 300
    @Published var progress: Double = 0
    
    // MARK: - Private Properties
    @Published var words: [String] = [] // Made public for Paragraph View
    @Published var originalText: String = "" // For Paragraph View
    @Published var wordRanges: [Range<String.Index>] = [] // For Paragraph View highlighting
    
    private var timer: Timer?
    
    // MARK: - Constants
    let minWPM: Double = 100
    let maxWPM: Double = 1000
    
    // MARK: - Computed Properties
    var totalWords: Int {
        words.count
    }
    
    var intervalMs: Double {
        // Convert WPM to milliseconds per word
        // WPM = words / minute, so ms/word = 60000 / WPM
        return 60000.0 / wordsPerMinute
    }
    
    // MARK: - Debug
    let id = UUID()
    
    // MARK: - Initialization
    init() {
    }
    
    // MARK: - Public Methods
    func loadText(_ text: String, startingAt index: Int = 0) {
        self.originalText = text
        self.words = TextTokenizer.tokenize(text)
        
        // Calculate ranges
        var ranges: [Range<String.Index>] = []
        var searchStartIndex = text.startIndex
        
        for word in words {
            if let range = text.range(of: word, options: .literal, range: searchStartIndex..<text.endIndex) {
                ranges.append(range)
                searchStartIndex = range.upperBound
            }
        }
        self.wordRanges = ranges
        
        currentIndex = min(index, max(0, words.count - 1))
        currentWord = words.isEmpty ? "" : words[currentIndex]
        updateProgress()
    }
    
    func play() {
        guard !words.isEmpty else { return }
        isPlaying = true
        scheduleNextWord()
    }
    
    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
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
        updateProgress()
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
        // Don't auto-resume - let user press play
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
        
        // Calculate delay with punctuation pause
        let pauseMultiplier = TextTokenizer.pauseMultiplier(for: word)
        let delay = intervalMs * pauseMultiplier / 1000.0
        
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.currentIndex += 1
            self.updateProgress()
            self.scheduleNextWord()
        }
    }
    
    private func updateProgress() {
        if words.isEmpty {
            progress = 0
        } else {
            progress = Double(currentIndex) / Double(words.count)
        }
    }
}

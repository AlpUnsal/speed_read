import Foundation

/// Represents a navigation point within a document (chapter or page)
struct NavigationPoint: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let wordStartIndex: Int
    let wordEndIndex: Int
    let type: NavigationType
    
    init(id: UUID = UUID(), title: String, wordStartIndex: Int, wordEndIndex: Int, type: NavigationType) {
        self.id = id
        self.title = title
        self.wordStartIndex = wordStartIndex
        self.wordEndIndex = wordEndIndex
        self.type = type
    }
    
    /// Word count for this navigation point
    var wordCount: Int {
        wordEndIndex - wordStartIndex
    }
    
    /// Calculate progress within this section (0.0 to 1.0)
    func progress(at currentIndex: Int) -> Double {
        guard wordCount > 0 else { return 0 }
        let adjustedIndex = max(0, min(currentIndex - wordStartIndex, wordCount))
        return Double(adjustedIndex) / Double(wordCount)
    }
    
    /// Check if a word index falls within this navigation point
    func contains(wordIndex: Int) -> Bool {
        wordIndex >= wordStartIndex && wordIndex < wordEndIndex
    }
}

/// Type of navigation point
enum NavigationType: String, Codable {
    case chapter  // For EPUB/PDF chapters
    case page     // For word-count-based pages
}

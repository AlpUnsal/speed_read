import Foundation

/// Search result representing a word match with context
struct SearchResult: Identifiable, Equatable {
    let id: UUID
    let wordIndex: Int
    let contextSnippet: String
    
    init(wordIndex: Int, contextSnippet: String) {
        self.id = UUID()
        self.wordIndex = wordIndex
        self.contextSnippet = contextSnippet
    }
}

/// Utility for searching words within a document
struct WordSearcher {
    
    /// Search for a query in the words array
    /// - Parameters:
    ///   - query: Search term
    ///   - words: Array of words to search
    ///   - caseSensitive: Whether search is case-sensitive
    /// - Returns: Array of search results with context
    static func search(query: String, in words: [String], caseSensitive: Bool = false) -> [SearchResult] {
        guard !query.isEmpty, !words.isEmpty else { return [] }
        
        let searchQuery = caseSensitive ? query : query.lowercased()
        var results: [SearchResult] = []
        
        for (index, word) in words.enumerated() {
            let wordToMatch = caseSensitive ? word : word.lowercased()
            
            // Match if word contains the query (allows partial matches)
            if wordToMatch.contains(searchQuery) {
                let context = createContextSnippet(words: words, at: index, highlightQuery: query)
                results.append(SearchResult(wordIndex: index, contextSnippet: context))
            }
        }
        
        return results
    }
    
    /// Find the next match from the current position
    /// - Parameters:
    ///   - currentIndex: Current word index
    ///   - query: Search term
    ///   - words: Array of words
    ///   - caseSensitive: Whether search is case-sensitive
    /// - Returns: Index of next match, or nil if not found
    static func findNext(from currentIndex: Int, query: String, in words: [String], caseSensitive: Bool = false) -> Int? {
        guard !query.isEmpty, !words.isEmpty else { return nil }
        
        let searchQuery = caseSensitive ? query : query.lowercased()
        
        // Search from current position to end
        for i in (currentIndex + 1)..<words.count {
            let word = caseSensitive ? words[i] : words[i].lowercased()
            if word.contains(searchQuery) {
                return i
            }
        }
        
        // Wrap around: search from beginning to current position
        for i in 0...currentIndex {
            let word = caseSensitive ? words[i] : words[i].lowercased()
            if word.contains(searchQuery) {
                return i
            }
        }
        
        return nil
    }
    
    /// Find the previous match from the current position
    /// - Parameters:
    ///   - currentIndex: Current word index
    ///   - query: Search term
    ///   - words: Array of words
    ///   - caseSensitive: Whether search is case-sensitive
    /// - Returns: Index of previous match, or nil if not found
    static func findPrevious(from currentIndex: Int, query: String, in words: [String], caseSensitive: Bool = false) -> Int? {
        guard !query.isEmpty, !words.isEmpty else { return nil }
        
        let searchQuery = caseSensitive ? query : query.lowercased()
        
        // Search from current position backwards
        for i in stride(from: currentIndex - 1, through: 0, by: -1) {
            let word = caseSensitive ? words[i] : words[i].lowercased()
            if word.contains(searchQuery) {
                return i
            }
        }
        
        // Wrap around: search from end to current position
        for i in stride(from: words.count - 1, through: currentIndex, by: -1) {
            let word = caseSensitive ? words[i] : words[i].lowercased()
            if word.contains(searchQuery) {
                return i
            }
        }
        
        return nil
    }
    
    /// Create a context snippet around the matched word
    private static func createContextSnippet(words: [String], at index: Int, highlightQuery: String) -> String {
        let contextRadius = 4 // Words before and after
        let startIndex = max(0, index - contextRadius)
        let endIndex = min(words.count - 1, index + contextRadius)
        
        var snippet = ""
        
        // Add ellipsis if not at start
        if startIndex > 0 {
            snippet += "..."
        }
        
        // Build context
        for i in startIndex...endIndex {
            if i > startIndex {
                snippet += " "
            }
            snippet += words[i]
        }
        
        // Add ellipsis if not at end
        if endIndex < words.count - 1 {
            snippet += "..."
        }
        
        return snippet
    }
}

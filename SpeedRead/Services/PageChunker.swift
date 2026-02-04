import Foundation

/// Utility for creating page-based navigation from unstructured documents
struct PageChunker {
    
    /// Default words per page (roughly equivalent to a book page)
    static let defaultWordsPerPage = 250
    
    /// Create page-based navigation points from a word array
    /// - Parameters:
    ///   - words: Array of words from the document
    ///   - wordsPerPage: Number of words per page
    /// - Returns: Array of NavigationPoints representing pages
    static func createPages(from words: [String], wordsPerPage: Int = defaultWordsPerPage) -> [NavigationPoint] {
        guard !words.isEmpty, wordsPerPage > 0 else { return [] }
        
        var pages: [NavigationPoint] = []
        var currentIndex = 0
        var pageNumber = 1
        
        while currentIndex < words.count {
            let startIndex = currentIndex
            let endIndex = min(currentIndex + wordsPerPage, words.count)
            
            let page = NavigationPoint(
                title: "Page \(pageNumber)",
                wordStartIndex: startIndex,
                wordEndIndex: endIndex,
                type: .page
            )
            
            pages.append(page)
            currentIndex = endIndex
            pageNumber += 1
        }
        
        return pages
    }
    
    /// Create page-based navigation points from text
    /// - Parameters:
    ///   - text: Raw text content
    ///   - wordsPerPage: Number of words per page
    /// - Returns: Array of NavigationPoints representing pages
    static func createPages(from text: String, wordsPerPage: Int = defaultWordsPerPage) -> [NavigationPoint] {
        let words = TextTokenizer.tokenize(text)
        return createPages(from: words, wordsPerPage: wordsPerPage)
    }
    
    /// Calculate total number of pages for a given word count
    static func pageCount(for totalWords: Int, wordsPerPage: Int = defaultWordsPerPage) -> Int {
        guard totalWords > 0, wordsPerPage > 0 else { return 0 }
        return Int(ceil(Double(totalWords) / Double(wordsPerPage)))
    }
    
    /// Find the page containing a specific word index
    static func pageNumber(for wordIndex: Int, wordsPerPage: Int = defaultWordsPerPage) -> Int {
        guard wordIndex >= 0, wordsPerPage > 0 else { return 1 }
        return (wordIndex / wordsPerPage) + 1
    }
}

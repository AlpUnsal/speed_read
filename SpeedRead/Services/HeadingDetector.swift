import Foundation

/// Detects headings in plain text files (Markdown style, ALL CAPS, numbered sections)
struct HeadingDetector {
    
    /// Detected heading with its position in the text
    struct DetectedHeading {
        let title: String
        let level: Int
        let lineIndex: Int
    }
    
    /// Detect headings in text content
    /// - Parameter text: Raw text content
    /// - Returns: Array of detected headings with their line indices
    static func detectHeadings(in text: String) -> [DetectedHeading] {
        let lines = text.components(separatedBy: .newlines)
        var headings: [DetectedHeading] = []
        
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Check for Markdown headings (# Heading)
            if let markdownHeading = detectMarkdownHeading(trimmed) {
                headings.append(DetectedHeading(
                    title: markdownHeading.title,
                    level: markdownHeading.level,
                    lineIndex: index
                ))
                continue
            }
            
            // Check for ALL CAPS headings (at least 3 words, max 60 chars)
            if isAllCapsHeading(trimmed) {
                headings.append(DetectedHeading(
                    title: trimmed.capitalized,
                    level: 1,
                    lineIndex: index
                ))
                continue
            }
            
            // Check for numbered sections (1. Section, 1.1 Subsection, Chapter 1:)
            if let numberedHeading = detectNumberedHeading(trimmed) {
                headings.append(DetectedHeading(
                    title: numberedHeading.title,
                    level: numberedHeading.level,
                    lineIndex: index
                ))
            }
        }
        
        return headings
    }
    
    /// Convert detected headings to NavigationPoints using word indices
    static func createNavigationPoints(from text: String) -> [NavigationPoint] {
        let lines = text.components(separatedBy: .newlines)
        let headings = detectHeadings(in: text)
        
        guard !headings.isEmpty else { return [] }
        
        var navigationPoints: [NavigationPoint] = []
        let words = TextTokenizer.tokenize(text)
        let totalWords = words.count
        
        // Create a map of line index to word index
        var lineToWordIndex: [Int] = []
        var currentWordIndex = 0
        
        for line in lines {
            lineToWordIndex.append(currentWordIndex)
            let lineWords = TextTokenizer.tokenize(line)
            currentWordIndex += lineWords.count
        }
        
        // Create navigation points
        for (i, heading) in headings.enumerated() {
            let startIndex = lineToWordIndex[heading.lineIndex]
            let endIndex: Int
            
            if i + 1 < headings.count {
                endIndex = lineToWordIndex[headings[i + 1].lineIndex]
            } else {
                endIndex = totalWords
            }
            
            guard endIndex > startIndex else { continue }
            
            let point = NavigationPoint(
                title: heading.title,
                wordStartIndex: startIndex,
                wordEndIndex: endIndex,
                type: .heading,
                level: heading.level
            )
            navigationPoints.append(point)
        }
        
        return navigationPoints
    }
    
    // MARK: - Private Helpers
    
    private static func detectMarkdownHeading(_ line: String) -> (title: String, level: Int)? {
        // Match # at start of line
        guard line.hasPrefix("#") else { return nil }
        
        var level = 0
        for char in line {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        
        guard level >= 1 && level <= 6 else { return nil }
        
        let title = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        
        return (title, level)
    }
    
    private static func isAllCapsHeading(_ line: String) -> Bool {
        // Must be short (headings are typically brief)
        guard line.count >= 3 && line.count <= 60 else { return false }
        
        // Must have at least some letters
        let letters = line.filter { $0.isLetter }
        guard letters.count >= 3 else { return false }
        
        // All letters must be uppercase
        guard letters.allSatisfy({ $0.isUppercase }) else { return false }
        
        // Should have multiple words (to avoid acronyms)
        let wordCount = line.split(separator: " ").count
        guard wordCount >= 2 else { return false }
        
        return true
    }
    
    private static func detectNumberedHeading(_ line: String) -> (title: String, level: Int)? {
        // Pattern: "Chapter X:", "1. Title", "1.1 Title", "Part I:"
        let patterns: [(pattern: String, level: Int)] = [
            (#"^Chapter\s+\d+[:\s]"#, 1),
            (#"^Part\s+[IVX\d]+[:\s]"#, 1),
            (#"^\d+\.\s+"#, 1),
            (#"^\d+\.\d+\s+"#, 2),
            (#"^\d+\.\d+\.\d+\s+"#, 3),
            (#"^[IVX]+\.\s+"#, 1)
        ]
        
        for (pattern, level) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    return (line, level)
                }
            }
        }
        
        return nil
    }
}

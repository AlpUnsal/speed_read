import Foundation
import PDFKit
import Vision
import UIKit
import OSLog

/// Service for parsing PDF documents using native PDFKit
/// Optimized for research papers: extracts main body text, removes headers/footers/citations
/// Uses native text extraction (attributedString) with Anchor-Based Section Detection
struct PDFParsingService {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "PDFParsingService")
    
    /// Extract clean list of words and navigation points from a PDF URL
    /// - Parameter url: URL of the PDF file
    /// - Returns: Tuple containing array of words and navigation points
    /// Extract clean list of words and navigation points from a PDF URL
    /// - Parameter url: URL of the PDF file
    /// - Returns: Tuple containing full text and navigation points
    static func parsePDF(url: URL) -> (text: String, navigationPoints: [NavigationPoint]) {
        guard let document = PDFDocument(url: url) else {
            logger.error("Failed to load PDF document")
            return ("", [])
        }
        
        var fullText = ""
        var totalWordCount = 0
        var detectedSections: [InternalSection] = []
        
        // 1. Try to get sections from PDF Outline (Table of Contents)
        var isUsingOutline = false
        if let outlineRoot = document.outlineRoot {
            detectedSections = extractSectionsFromOutline(root: outlineRoot, document: document)
            isUsingOutline = !detectedSections.isEmpty
        }
        
        var currentWordCount = 0
        var pageWordCounts: [Int] = []
        
        // --- ANCHOR DETECTION STATE ---
        // Known anchors to look for in the first few pages
        let anchorKeywords = ["abstract", "introduction", "background", "related work", "method", "methods", "results", "discussion", "conclusion", "references"]
        var learnedHeadingFontSize: CGFloat? = nil
        // ------------------------------
        
        // Process each page
        for i in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: i) else { 
                    pageWordCounts.append(currentWordCount)
                    return 
                }
                
                // Mark start of page words
                pageWordCounts.append(currentWordCount)
                
                guard let attributedString = page.attributedString else { return }
                let pageText = attributedString.string
                let fullRange = NSRange(location: 0, length: attributedString.length)
                
                var pageHeadings: [InternalSection] = []
                var localWords: [String] = []
                
                (pageText as NSString).enumerateSubstrings(in: fullRange, options: .byLines) { line, substringRange, _, _ in
                    guard let line = line else { return }
                    let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanLine.isEmpty { return }
                    
                    // 2. Section Detection (Native)
                    if !isUsingOutline {
                        if let font = attributedString.attribute(.font, at: substringRange.location, effectiveRange: nil) as? UIFont {
                             let fontSize = font.pointSize
                             
                             // A) LEARN STYLE (if not yet learned)
                             if learnedHeadingFontSize == nil {
                                 let lowerLine = cleanLine.lowercased()
                                 for anchor in anchorKeywords {
                                     if lowerLine.contains(anchor) {
                                         let textOnly = lowerLine.replacingOccurrences(of: "^[0-9ivx]+\\.?\\s*", with: "", options: .regularExpression)
                                         
                                         if textOnly == anchor || textOnly.hasPrefix(anchor + " ") || textOnly.hasPrefix(anchor + ":") {
                                             let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                                             if wordCount <= 10 {
                                                 learnedHeadingFontSize = fontSize
                                                 logger.error("🎯 LEARNED HEADING STYLE: Size \(fontSize) from '\(cleanLine)'")
                                             }
                                         }
                                     }
                                 }
                             }
                             
                             // B) DETECT USING LEARNED STYLE
                             var isHeading = false
                             if let targetSize = learnedHeadingFontSize {
                                 let sizeDiff = abs(fontSize - targetSize)
                                 let isSizeMatch = sizeDiff < 0.5
                                 
                                 if isSizeMatch {
                                     let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                                     let endsWithPeriod = cleanLine.hasSuffix(".")
                                     let isTitleCase = cleanLine.range(of: "^[0-9A-Z]", options: .regularExpression) != nil
                                     
                                     if wordCount <= 15 && !endsWithPeriod && isTitleCase {
                                         isHeading = true
                                     }
                                 }
                             } else {
                                 if fontSize > 14 { 
                                      let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                                      if wordCount <= 20 {
                                         isHeading = true
                                      }
                                 }
                             }
                             
                             if isHeading {
                                 logger.info("✅ FOUND SECTION: '\(cleanLine)' (Size: \(fontSize))")
                                 pageHeadings.append(InternalSection(
                                    title: cleanLine,
                                    pageIndex: i,
                                    wordOffsetOnPage: localWords.count,
                                    isFromOutline: false
                                 ))
                             }
                        }
                    }
                    
                    // 3. Process Words for RSVP
                    let cleanedLine = removeCitations(from: line)
                    let words = cleanedLine.components(separatedBy: .whitespacesAndNewlines)
                    
                    for word in words {
                        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                        if !trimmed.isEmpty && word.rangeOfCharacter(from: .decimalDigits) == nil {
                            localWords.append(word)
                        }
                    }
                }
                
                detectedSections.append(contentsOf: pageHeadings)
                
                // OPTIMIZATION: Build string directly to avoid huge array overhead
                if !localWords.isEmpty {
                    fullText += localWords.joined(separator: " ") + " "
                }
                
                totalWordCount += localWords.count
                currentWordCount += localWords.count
                
                // 4. Refine Outline Sections (Fix 0-offset bug with STRICT matching)
                if isUsingOutline {
                    // Find sections that belong to this page
                    for idx in detectedSections.indices {
                        if detectedSections[idx].pageIndex == i {
                            let title = detectedSections[idx].title
                            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            
                            if detectedSections[idx].wordOffsetOnPage == 0 {
                                // STRICT SEARCH: Look for a LINE that starts with the title
                                // This prevents matching "In this section we discuss Model Architecture" as the header
                                var foundOffset: Int? = nil
                                var currentLocalOffset = 0
                                
                                (pageText as NSString).enumerateSubstrings(in: fullRange, options: .byLines) { line, _, _, stop in
                                    guard let line = line else { return }
                                    let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let lowerLine = cleanLine.lowercased()
                                    
                                    // Check if line STARTS with title (e.g. "3. Model Architecture")
                                    // Or is exactly the title ("Model Architecture")
                                    if lowerLine.hasPrefix(cleanTitle) || 
                                       lowerLine.contains(" " + cleanTitle) { // Handles "1. Title"
                                        
                                        // HEURISTIC: Header typically short (<= 10 words)
                                        let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                                        if wordCount <= 12 {
                                            foundOffset = currentLocalOffset
                                            stop.pointee = true
                                        }
                                    }
                                    
                                    // Advance offset
                                    let lineWords = cleanLine.components(separatedBy: .whitespacesAndNewlines)
                                               .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .decimalDigits) == nil }
                                    currentLocalOffset += lineWords.count
                                }
                                
                                if let offset = foundOffset {
                                     detectedSections[idx] = InternalSection(
                                        title: title,
                                        pageIndex: i,
                                        wordOffsetOnPage: offset,
                                        isFromOutline: true
                                    )
                                    // logger.info("Refined STRICT '\(title)' -> Offset \(offset)")
                                } else {
                                    // logger.info("Strict Match Failed for '\(title)' on page \(i)")
                                }
                            }
                        }
                    }
                }
                
                // 5. Explicit Abstract Detection (Force insert if missing)
                // Only check first 2 pages
                if i < 2 {
                    let pageString = localWords.joined(separator: " ").lowercased()
                    if pageString.contains("abstract") {
                         // Find strict line for Abstract
                         var abstractOffset: Int? = nil
                         var currentLocalOffset = 0
                         
                         (pageText as NSString).enumerateSubstrings(in: fullRange, options: .byLines) { line, _, _, stop in
                            guard let line = line else { return }
                            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if cleanLine.lowercased() == "abstract" || cleanLine.lowercased().hasPrefix("abstract.") {
                                abstractOffset = currentLocalOffset
                                stop.pointee = true
                            }
                            let lineWords = cleanLine.components(separatedBy: .whitespacesAndNewlines)
                                           .filter { !$0.isEmpty && $0.rangeOfCharacter(from: .decimalDigits) == nil }
                            currentLocalOffset += lineWords.count
                         }
                         
                         if let offset = abstractOffset {
                             // Check if we already have it
                             if !detectedSections.contains(where: { $0.title.lowercased() == "abstract" }) {
                                 detectedSections.insert(InternalSection(
                                    title: "Abstract",
                                    pageIndex: i,
                                    wordOffsetOnPage: offset,
                                    isFromOutline: true // Treat as refined
                                 ), at: 0)
                                 // logger.info("Detected IMPLICIT Abstract -> Offset \(offset)")
                             }
                         }
                    }
                }
            }
        }
        
        // logger.info("PDF Loop Finished. Total Words: \(totalWordCount) | Sections: \(detectedSections.count)")
        
        // Map sections to NavigationPoints
        var finalNavigationPoints: [NavigationPoint] = []
        
        let sortedSections = detectedSections.sorted {
            if $0.pageIndex != $1.pageIndex {
                return $0.pageIndex < $1.pageIndex
            }
            return $0.wordOffsetOnPage < $1.wordOffsetOnPage
        }
        
        // logger.info("Processing Sections...")
        
        for (index, section) in sortedSections.enumerated() {
            var trueWordIndex = 0
            
            if section.isFromOutline {
                if section.pageIndex < pageWordCounts.count {
                    trueWordIndex = pageWordCounts[section.pageIndex]
                }
            } else {
                 if section.pageIndex < pageWordCounts.count {
                    trueWordIndex = pageWordCounts[section.pageIndex] + section.wordOffsetOnPage
                } else {
                    trueWordIndex = section.wordOffsetOnPage
                }
            }
            
            // Override with refined offset if available (Wait, we updated detectedSections but logic above uses 0 if fromOutline??)
            // BUG FOUND: The logic above `if section.isFromOutline` used `pageWordCounts[section.pageIndex]` DIRECTLY, ignoring `wordOffsetOnPage`!
            // FIX: Always use wordOffsetOnPage for Outline sections too now that we refine it.
            
            if section.isFromOutline && section.wordOffsetOnPage > 0 {
                 if section.pageIndex < pageWordCounts.count {
                    trueWordIndex = pageWordCounts[section.pageIndex] + section.wordOffsetOnPage
                }
            }
            
            let endIndex: Int
            if index + 1 < sortedSections.count {
                let nextSection = sortedSections[index + 1]
                let nextOffset = nextSection.wordOffsetOnPage
                
                // Calculate next true index
                 if nextSection.pageIndex < pageWordCounts.count {
                    endIndex = pageWordCounts[nextSection.pageIndex] + nextOffset
                 } else {
                     endIndex = totalWordCount
                 }
            } else {
                endIndex = totalWordCount
            }
            
            if trueWordIndex < endIndex {
                 finalNavigationPoints.append(NavigationPoint(
                    title: section.title,
                    wordStartIndex: trueWordIndex,
                    wordEndIndex: endIndex,
                    type: .section
                ))
                // logger.info("Added Section: \(section.title) [\(trueWordIndex)-\(endIndex)]")
            } else {
                // logger.warning("Dropping Section '\(section.title)': Start (\(trueWordIndex)) >= End (\(endIndex)). (Page \(section.pageIndex), Offset \(section.wordOffsetOnPage))")
            }
        }
        
        // logger.info("Returning Result with \(finalNavigationPoints.count) Nav Points and Text Length: \(fullText.count)")
        return (fullText, finalNavigationPoints)
    }

    // Internal struct
    private struct InternalSection {
        let title: String
        let pageIndex: Int
        let wordOffsetOnPage: Int
        let isFromOutline: Bool
    }
    
    // MARK: - Helper Methods
    
    private static func removeCitations(from text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "\\[[0-9, -]+\\]", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }
    
    private static func extractSectionsFromOutline(root: PDFOutline, document: PDFDocument) -> [InternalSection] {
        logger.error("Extracting Outline...")
        var sections: [InternalSection] = []
        
        func traverse(_ outline: PDFOutline) {
            if let label = outline.label, let dest = outline.destination, let page = dest.page {
                let pageIndex = document.index(for: page)
                sections.append(InternalSection(title: label, pageIndex: pageIndex, wordOffsetOnPage: 0, isFromOutline: true))
            }
            for i in 0..<outline.numberOfChildren {
                if let child = outline.child(at: i) {
                    traverse(child)
                }
            }
        }
        
        for i in 0..<root.numberOfChildren {
             if let child = root.child(at: i) {
                 traverse(child)
             }
        }
        return sections
    }
}

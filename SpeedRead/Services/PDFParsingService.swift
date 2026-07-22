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
    /// - Returns: Tuple containing full text, navigation points, and optional title
    static func parsePDF(url: URL) -> (text: String, navigationPoints: [NavigationPoint], title: String?, figures: [FigureAnnotation], figureImages: [String: UIImage]) {
        guard let document = PDFDocument(url: url) else {
            logger.error("Failed to load PDF document")
            return ("", [], nil, [], [String: UIImage]())
        }
        
        var pdfTitle: String? = nil
        if let rawTitle = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pdfTitle = trimmed
            }
        }
        
        var fullText = ""
        // Per-page text collected during the loop; pages are joined afterwards
        // so a paragraph spilling across a page boundary isn't force-split.
        var pageTextEntries: [(pageIndex: Int, text: String, endsParagraph: Bool)] = []
        var totalWordCount = 0
        var detectedSections: [InternalSection] = []
        
        // Figure detection state
        var figures: [FigureAnnotation] = []
        var figureImages: [String: UIImage] = [:]
        let figurePattern = try? NSRegularExpression(pattern: "(?:Figure|Fig\\.|Exhibit)\\s+(\\d+[a-zA-Z]?)(?:[:\\.]\\s*(.{0,120}))?", options: [.caseInsensitive])
        
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
                
                var pageHeadings: [InternalSection] = []
                var localWords: [String] = []
                // Paragraph-aware text assembly
                var localTextSegments: [String] = []  // Each segment is a line's words; "\n" entries mark paragraph breaks
                var localWordCount: Int = 0
                var previousLineMinY: CGFloat? = nil  // Previous line's bottom (PDF coords: Y up)
                var lineHeightSum: CGFloat = 0
                var lineHeightSamples: Int = 0
                
                guard let attributedString = page.attributedString else { return }
                let pageText = attributedString.string
                let fullRange = NSRange(location: 0, length: attributedString.length)
                
                var boundsForLine: [CGRect] = []
                var lineStrings: [String] = []

                (pageText as NSString).enumerateSubstrings(in: fullRange, options: .byLines) { line, substringRange, _, _ in
                    guard let line = line else { return }
                    lineStrings.append(line)
                    
                    // We need the bounding box to check for headers/footers
                    guard let selections = page.selection(for: substringRange) else {
                        boundsForLine.append(.zero)
                        return
                    }
                    boundsForLine.append(selections.bounds(for: page))
                }

                // 2. Identify "Body" characteristics (Median Font Size)
                var fontSizes: [CGFloat] = []
                for i in 0..<lineStrings.count {
                    let range = (pageText as NSString).range(of: lineStrings[i])
                    if range.location != NSNotFound, range.length > 0 {
                        if let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont {
                            fontSizes.append(font.pointSize)
                        }
                    }
                }
                
                let bodyFontSize: CGFloat
                if fontSizes.isEmpty {
                    bodyFontSize = 12.0 // Fallback
                } else {
                    let sortedFonts = fontSizes.sorted()
                    bodyFontSize = sortedFonts[sortedFonts.count / 2] // Median is usually body text
                }

                // Page dimensions for relative margin calculation
                let pageBounds = page.bounds(for: .cropBox)
                let pageHeight = pageBounds.height
                let topMarginThreshold = pageBounds.maxY - (pageHeight * 0.12) // Top 12%
                let bottomMarginThreshold = pageBounds.minY + (pageHeight * 0.12) // Bottom 12%

                // --- HEURISTIC TITLE EXTRACTION (First Page Only) ---
                if i == 0 && pdfTitle == nil {
                    var maxFontSize: CGFloat = 0.0
                    
                    // First pass: find max font size
                    for (idx, line) in lineStrings.enumerated() {
                        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if cleanLine.isEmpty || cleanLine.components(separatedBy: .whitespaces).count == 1 { continue }
                        
                        let bounds = boundsForLine[idx]
                        
                        // Ignore extreme margins where watermarks and page numbers live
                        let isAtTopMargin = bounds.minY > (pageBounds.maxY - pageHeight * 0.05)
                        let isAtBottomMargin = bounds.maxY < (pageBounds.minY + pageHeight * 0.05)
                        let isAtLeftMargin = bounds.minX < (pageBounds.minX + pageBounds.width * 0.15)
                        let isAtRightMargin = bounds.maxX > (pageBounds.maxX - pageBounds.width * 0.15)
                        
                        // The true title will usually be somewhere in the upper half, and not crammed into a margin
                        let isInUpperHalf = bounds.minY > (pageBounds.minY + pageHeight * 0.4)
                        
                        if isAtTopMargin || isAtBottomMargin || isAtLeftMargin || isAtRightMargin || !isInUpperHalf {
                            continue
                        }
                        
                        let range = (pageText as NSString).range(of: line)
                        if range.location != NSNotFound, range.length > 0 {
                            if let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont {
                                if font.pointSize > maxFontSize {
                                    maxFontSize = font.pointSize
                                }
                            }
                        }
                    }
                    
                    // Second pass: extract lines matching max font size, if it's significantly larger than body
                    if maxFontSize > (bodyFontSize * 1.25) {
                        var titleLines: [String] = []
                        for (idx, line) in lineStrings.enumerated() {
                            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if cleanLine.isEmpty { continue }
                            
                            let bounds = boundsForLine[idx]
                            // Title lines must be in the upper 70% of the page
                            let isInUpperArea = bounds.minY > (pageBounds.minY + pageHeight * 0.3)
                            if !isInUpperArea { continue }
                            
                            let range = (pageText as NSString).range(of: line)
                            if range.location != NSNotFound, range.length > 0 {
                                if let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont {
                                    if abs(font.pointSize - maxFontSize) < 1.0 { // slightly more lenient epsilon
                                        titleLines.append(cleanLine)
                                    }
                                }
                            }
                        }
                        
                        let extractedTitle = titleLines.joined(separator: " ")
                        if !extractedTitle.isEmpty && extractedTitle.count < 300 {
                            pdfTitle = extractedTitle
                            logger.info("Heuristically extracted title: '\(extractedTitle)' (Size: \(maxFontSize))")
                        }
                    }
                }
                // ----------------------------------------------------

                // Process lines, applying header/footer exclusion
                for (index, line) in lineStrings.enumerated() {
                    let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanLine.isEmpty { continue }

                    let bounds = boundsForLine[index]
                    let isAtTop = bounds.minY > topMarginThreshold 
                    let isAtBottom = bounds.maxY < bottomMarginThreshold
                    
                    // Retrieve font size for this line
                    var lineFontSize = bodyFontSize // Default
                    let range = (pageText as NSString).range(of: line)
                    if range.location != NSNotFound, range.length > 0 {
                        if let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont {
                            lineFontSize = font.pointSize
                        }
                    }

                    // --- HYBRID EXCLUSION RULES ---
                    if bounds != .zero {
                        // 1. If it's in the extreme margins and NOT the body font size, it is a header/footer
                        if (isAtTop || isAtBottom) {
                             if abs(lineFontSize - bodyFontSize) > 0.5 {
                                 // logger.info("Excluding Header/Footer (Font Mismatch): '\(cleanLine)'")
                                 continue
                             }
                             
                             // 2. If it's in the extreme margins and is extremely short (e.g. just a page number)
                             let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                             if wordCount <= 3 && cleanLine.rangeOfCharacter(from: CharacterSet.letters) == nil {
                                 // logger.info("Excluding Page Number: '\(cleanLine)'")
                                 continue
                             }
                        }
                    }
                    
                    // 3. Section Detection (Native)
                    if !isUsingOutline {
                         // A) LEARN STYLE (if not yet learned)
                         if learnedHeadingFontSize == nil {
                             let lowerLine = cleanLine.lowercased()
                             for anchor in anchorKeywords {
                                 if lowerLine.contains(anchor) {
                                     let textOnly = lowerLine.replacingOccurrences(of: "^[0-9ivx]+\\.?\\s*", with: "", options: .regularExpression)
                                     
                                     if textOnly == anchor || textOnly.hasPrefix(anchor + " ") || textOnly.hasPrefix(anchor + ":") {
                                         let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                                         if wordCount <= 10 {
                                             learnedHeadingFontSize = lineFontSize
                                             logger.error("🎯 LEARNED HEADING STYLE: Size \(lineFontSize) from '\(cleanLine)'")
                                         }
                                     }
                                 }
                             }
                         }
                         
                         // B) DETECT USING LEARNED STYLE
                         var isHeading = false
                         if let targetSize = learnedHeadingFontSize {
                             let sizeDiff = abs(lineFontSize - targetSize)
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
                             if lineFontSize > 14 { 
                                  let wordCount = cleanLine.components(separatedBy: .whitespaces).count
                                  if wordCount <= 20 {
                                     isHeading = true
                                  }
                             }
                         }
                         
                         if isHeading {
                             logger.info("✅ FOUND SECTION: '\(cleanLine)' (Size: \(lineFontSize))")
                             pageHeadings.append(InternalSection(
                                title: cleanLine,
                                pageIndex: i,
                                wordOffsetOnPage: localWordCount,
                                isFromOutline: false
                             ))
                         }
                    }

                    // 4. Process Words for RSVP
                    let cleanedLine = PDFParsingService.removeCitations(from: line)
                    let words = cleanedLine.components(separatedBy: .whitespacesAndNewlines)

                    var lineWords: [String] = []
                    for word in words {
                        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                        if !trimmed.isEmpty {
                            localWords.append(word)
                            lineWords.append(word)
                        }
                    }

                    // Track paragraph breaks via vertical gaps between lines
                    // (reuses `bounds` already declared for this line above)
                    if bounds != .zero {
                        let lineHeight = bounds.height
                        if lineHeight > 0 {
                            lineHeightSum += lineHeight
                            lineHeightSamples += 1
                        }

                        if let prevMinY = previousLineMinY {
                            let avgLineHeight = lineHeightSamples > 0 ? lineHeightSum / CGFloat(lineHeightSamples) : lineHeight
                            // PDF coords: Y increases upward. Gap between lines = previous bottom - current top
                            let gap = prevMinY - bounds.maxY
                            let threshold = max(avgLineHeight * 0.8, 6.0)
                            if gap > threshold && !localTextSegments.isEmpty {
                                localTextSegments.append("\n\n")
                            }
                        }
                        previousLineMinY = bounds.minY
                    }

                    if !lineWords.isEmpty {
                        localTextSegments.append(lineWords.joined(separator: " "))
                        localWordCount += lineWords.count
                    }
                }

                detectedSections.append(contentsOf: pageHeadings)

                // Build text preserving paragraph breaks
                if localWordCount > 0 {
                    var pageText2 = localTextSegments.joined(separator: " ")
                    // Clean up spaces around paragraph break markers
                    pageText2 = pageText2.replacingOccurrences(of: " \n\n ", with: "\n\n")
                    pageText2 = pageText2.replacingOccurrences(of: " \n\n", with: "\n\n")
                    pageText2 = pageText2.replacingOccurrences(of: "\n\n ", with: "\n\n")
                    // The page ends a paragraph when its last word closes a
                    // sentence or a paragraph gap was already detected there.
                    let lastWord = pageText2
                        .components(separatedBy: .whitespacesAndNewlines)
                        .last(where: { !$0.isEmpty }) ?? ""
                    pageTextEntries.append((
                        pageIndex: i,
                        text: pageText2,
                        endsParagraph: TextTokenizer.endsSentence(lastWord)
                            || pageText2.hasSuffix("\n\n")
                    ))
                }
                
                // --- FIGURE DETECTION ---
                // Check if this page contains figure references ("Figure N", "Fig. N", "Exhibit N")
                if let figurePattern = figurePattern {
                    let pageTextForFigures = lineStrings.joined(separator: " ")
                    let figureRange = NSRange(pageTextForFigures.startIndex..., in: pageTextForFigures)
                    let matches = figurePattern.matches(in: pageTextForFigures, options: [], range: figureRange)
                    
                    for match in matches {
                        // Extract figure number and optional caption
                        let figureNumRange = match.range(at: 1)
                        
                        if let swiftNumRange = Range(figureNumRange, in: pageTextForFigures) {
                            let figureNum = String(pageTextForFigures[swiftNumRange])
                            
                            // Build the full caption
                            let fullMatchRange = match.range(at: 0)
                            var fullCaption: String? = nil
                            if let swiftFullRange = Range(fullMatchRange, in: pageTextForFigures) {
                                fullCaption = String(pageTextForFigures[swiftFullRange])
                            }
                            
                            // Check if we already have this figure (avoid duplicates)
                            let figureKey = "figure_\(figureNum)"
                            if !figures.contains(where: { $0.imageFileName == "\(figureKey).png" }) {
                                let imageFileName = "\(figureKey).png"
                                // Render just the figure region (above the caption), not the whole page
                                if let figureImage = renderFigureRegion(
                                    page: page,
                                    captionText: fullCaption ?? figureNum,
                                    lineStrings: lineStrings,
                                    boundsForLine: boundsForLine,
                                    maxWidth: 900
                                ) {
                                    figureImages[imageFileName] = figureImage
                                    let figure = FigureAnnotation(
                                        wordIndex: currentWordCount,
                                        caption: fullCaption,
                                        imageFileName: imageFileName
                                    )
                                    figures.append(figure)
                                    logger.info("Extracted figure: \(fullCaption ?? figureKey) at word index \(currentWordCount)")
                                }
                            }
                        }
                    }
                }
                // --- END FIGURE DETECTION ---
                
                totalWordCount += localWordCount
                currentWordCount += localWordCount
                
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
                                    
                                    // Advance offset (must count words the same
                                    // way the main text emission does)
                                    let lineWords = cleanLine.components(separatedBy: .whitespacesAndNewlines)
                                               .filter { !$0.isEmpty }
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
                    let pageString = localTextSegments.joined(separator: " ").lowercased()
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
                                           .filter { !$0.isEmpty }
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

        // Join page texts: break between pages only when the earlier page
        // ended a paragraph or the next page opens with a heading — otherwise
        // the paragraph flows across the page boundary instead of being
        // force-split mid-sentence.
        for (k, entry) in pageTextEntries.enumerated() {
            fullText += entry.text
            if k < pageTextEntries.count - 1 {
                let nextPage = pageTextEntries[k + 1].pageIndex
                // Sections still at offset 0 include unrefined outline entries;
                // treating those as page-top headings keeps the old (break)
                // behavior for them — conservative.
                let nextStartsWithHeading = detectedSections.contains {
                    $0.pageIndex == nextPage && $0.wordOffsetOnPage == 0
                }
                fullText += (entry.endsParagraph || nextStartsWithHeading) ? "\n\n" : " "
            } else {
                fullText += "\n\n"
            }
        }

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
        return (fullText, finalNavigationPoints, pdfTitle, figures, figureImages)
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
    
    /// Render just the figure region from a page by locating the caption line and cropping
    /// the area immediately above it (where the figure image lives), then trimming whitespace.
    private static func renderFigureRegion(
        page: PDFPage,
        captionText: String,
        lineStrings: [String],
        boundsForLine: [CGRect],
        maxWidth: CGFloat
    ) -> UIImage? {
        let pageBounds = page.bounds(for: .cropBox)
        let scale = min(maxWidth / pageBounds.width, 2.0)
        let fullSize = CGSize(width: pageBounds.width * scale, height: pageBounds.height * scale)
        
        // ------------------------------------------------------------------
        // 1. Find caption Y position in PDF coords (bottom-up)
        // ------------------------------------------------------------------
        var captionPDFY: CGFloat? = nil
        // First try: match via the lineStrings+boundsForLine we already have
        let captionLower = captionText.lowercased()
        for (idx, line) in lineStrings.enumerated() {
            if line.lowercased().contains(captionLower.prefix(20)) && boundsForLine[idx] != .zero {
                captionPDFY    = boundsForLine[idx].minY   // bottom of caption line
                break
            }
        }
        
        // Fallback: try PDFKit text search
        if captionPDFY == nil {
            let pageText = page.attributedString?.string ?? ""
            let searchStr = String(captionText.prefix(30))
            if let range = pageText.range(of: searchStr, options: .caseInsensitive) {
                let nsRange = NSRange(range, in: pageText)
                if let sel = page.selection(for: nsRange) {
                    let b = sel.bounds(for: page)
                    captionPDFY    = b.minY
                }
            }
        }
        
        // ------------------------------------------------------------------
        // 2. Render the full page
        // ------------------------------------------------------------------
        // Force scale=1.0 so CGImage pixels match our point-based crop coordinates
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: fullSize, format: format)
        let fullImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: fullSize))
            ctx.cgContext.translateBy(x: 0, y: fullSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .cropBox, to: ctx.cgContext)
        }
        
        // ------------------------------------------------------------------
        // 3. Convert caption Y to image coordinates and crop the figure strip
        // ------------------------------------------------------------------
        //  PDF coords:  Y=0 at bottom, Y=pageHeight at top
        //  Image coords: Y=0 at top,   Y=fullSize.height at bottom
        //  Conversion: imageY = (pageHeight - pdfY) * scale
        var stripEndY: CGFloat = fullSize.height  // how far down in image to crop (default: full page)
        
        if let pdfY = captionPDFY {
            // We want everything ABOVE the caption — i.e., in image coords, rows 0 ..< stripEndY
            // The bottom of the caption line in PDF coords = pdfY
            // In image coords that is at row: (pageHeight - pdfY) * scale
            stripEndY = (pageBounds.height - pdfY) * scale
            // Add a small margin (keep the caption label visible for context)
            stripEndY = min(stripEndY + 24 * scale, fullSize.height)
        }
        
        // Safety: never crop to nothing
        if stripEndY < 40 { return fullImage }
        
        let stripRect = CGRect(x: 0, y: 0, width: fullSize.width, height: stripEndY)
        
        // ------------------------------------------------------------------
        // 4. Pixel-scan the strip to trim leading/trailing whitespace rows
        //    Works for any PDF: scanned, vector, embedded bitmap, etc.
        // ------------------------------------------------------------------
        return cropToContentBounds(image: fullImage, within: stripRect)
    }
    
    /// Crops an image to its non-white content bounding box within a given region.
    /// Scans rows and columns and trims whitespace (pixels brighter than threshold).
    private static func cropToContentBounds(image: UIImage, within region: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return image }
        let imgWidth  = cgImage.width
        let imgHeight = cgImage.height
        
        // Clamp region to actual image
        let clamp = region.intersection(CGRect(x: 0, y: 0, width: imgWidth, height: imgHeight))
        guard !clamp.isNull, clamp.width > 0, clamp.height > 0 else { return nil }
        guard let cropped = cgImage.cropping(to: clamp) else { return nil }
        
        let w = Int(clamp.width)
        let h = Int(clamp.height)
        
        // Create an RGBA context so we have a predictable pixel layout
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return UIImage(cgImage: cropped) }
        
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: w, height: h))
        
        guard let data = ctx.data else { return UIImage(cgImage: cropped) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        
        let whiteThr: UInt8 = 242  // pixel must be brighter than this to count as "white"
        
        func isWhiteRow(_ row: Int) -> Bool {
            for col in 0..<w {
                let off = (row * w + col) * 4
                if ptr[off] < whiteThr || ptr[off+1] < whiteThr || ptr[off+2] < whiteThr { return false }
            }
            return true
        }
        func isWhiteCol(_ col: Int) -> Bool {
            for row in 0..<h {
                let off = (row * w + col) * 4
                if ptr[off] < whiteThr || ptr[off+1] < whiteThr || ptr[off+2] < whiteThr { return false }
            }
            return true
        }
        
        var top    = 0
        var bottom = h - 1
        var left   = 0
        var right  = w - 1
        
        while top    <= bottom && isWhiteRow(top)    { top    += 1 }
        while bottom >= top    && isWhiteRow(bottom) { bottom -= 1 }
        while left   <= right  && isWhiteCol(left)   { left   += 1 }
        while right  >= left   && isWhiteCol(right)  { right  -= 1 }
        
        guard top < bottom, left < right else { return UIImage(cgImage: cropped) }
        
        // Add small padding
        let pad = 8
        top    = max(0, top - pad)
        bottom = min(h - 1, bottom + pad)
        left   = max(0, left - pad)
        right  = min(w - 1, right + pad)
        
        let finalRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        guard let finalCG = cropped.cropping(to: finalRect) else { return UIImage(cgImage: cropped) }
        return UIImage(cgImage: finalCG)
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

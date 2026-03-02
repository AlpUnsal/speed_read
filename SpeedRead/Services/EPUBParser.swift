import Foundation
import ZIPFoundation
import OSLog

class EPUBParser {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "EPUBParser")
    
    /// Parse result containing text and chapter navigation
    struct ParseResult {
        let text: String
        let chapters: [NavigationPoint]
        let title: String?
    }
    
    /// Parse EPUB and return text only (backward compatible)
    static func parse(url: URL) -> String? {
        return parseWithChapters(url: url)?.text
    }
    
    /// Parse EPUB and return both text and chapter navigation points
    static func parseWithChapters(url: URL) -> ParseResult? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            // Unzip the EPUB file
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: url, to: tempDir)
            
            // 1. Find the OPF file path from META-INF/container.xml
            let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
            guard let containerData = try? Data(contentsOf: containerURL) else {
                logger.error("Could not find container.xml")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            let containerParser = ContainerXMLParser(data: containerData)
            guard let opfPath = containerParser.parse(), !opfPath.isEmpty else {
                logger.error("Could not find OPF path in container.xml")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            // 2. Parse the OPF file to get manifest and spine
            let opfURL = tempDir.appendingPathComponent(opfPath)
            let opfBasePath = opfURL.deletingLastPathComponent()
            
            guard let opfData = try? Data(contentsOf: opfURL) else {
                logger.error("Could not read OPF file at \(opfURL.path)")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            let opfParser = OPFParser(data: opfData)
            let (manifest, spine, parsedTitle) = opfParser.parse()
            
            // 3. Try to parse NCX for chapter titles
            var chapterTitles: [String: String] = [:] // href -> title
            if let ncxHref = findNCXPath(in: manifest, opfBasePath: opfBasePath) {
                let ncxURL = opfBasePath.appendingPathComponent(ncxHref)
                if let ncxData = try? Data(contentsOf: ncxURL) {
                    let ncxParser = NCXParser(data: ncxData)
                    chapterTitles = ncxParser.parse()
                }
            }
            
            // 4. Extract text from each chapter in spine order, tracking word indices
            var fullText = ""
            var chapters: [NavigationPoint] = []
            var currentWordIndex = 0
            
            for itemRef in spine {
                if let href = manifest[itemRef] {
                    let chapterURL = opfBasePath.appendingPathComponent(href)
                    
                    if let chapterData = try? Data(contentsOf: chapterURL),
                       let chapterContent = String(data: chapterData, encoding: .utf8) {
                        
                        // Look for sub-chapters within this HTML file (fragments)
                        let subChapterHrefs = chapterTitles.keys.filter { $0.hasPrefix(href + "#") }.sorted()
                        
                        var processedHTML = chapterContent
                        
                        var indicesToHrefs: [Int: String] = [:]
                        
                        // Inject markers into HTML for sub-chapters so they survive attributed string conversion
                        for (idx, subHref) in subChapterHrefs.enumerated() {
                            let fragment = subHref.components(separatedBy: "#").last ?? ""
                            if !fragment.isEmpty {
                                let marker = "axilomarker\(idx)axilo"
                                indicesToHrefs[idx] = subHref
                                
                                // Attempt to insert marker right before the element with this ID or Name
                                // We matching `<... id="fragment"` or `<... name="fragment"`
                                // Added spaces around marker to prevent text fusion
                                let pattern1 = "(<[^>]*id=\"\(fragment)\"[^>]*>)"
                                let pattern2 = "(<[^>]*name=\"\(fragment)\"[^>]*>)"
                                
                                processedHTML = processedHTML.replacingOccurrences(
                                    of: pattern1,
                                    with: " \(marker) $1",
                                    options: .regularExpression
                                )
                                processedHTML = processedHTML.replacingOccurrences(
                                    of: pattern2,
                                    with: " \(marker) $1",
                                    options: .regularExpression
                                )
                            }
                        }
                        
                        let text = DocumentParser.extractTextFromHTML(processedHTML)
                        let rawWords = TextTokenizer.tokenize(text)
                        
                        if !rawWords.isEmpty {
                            // Find where our markers ended up and clean the text
                            var cleanWords: [String] = []
                            var subChapterStarts: [(href: String, index: Int)] = []
                            
                            // If the whole file itself is a chapter without fragments
                            if chapterTitles[href] != nil {
                                subChapterStarts.append((href, currentWordIndex))
                            }
                            
                            for word in rawWords {
                                let lowerWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                                if lowerWord.hasPrefix("axilomarker") && lowerWord.hasSuffix("axilo") {
                                    let idxString = String(lowerWord.dropFirst(11).dropLast(5))
                                    if let idx = Int(idxString), let fullHref = indicesToHrefs[idx] {
                                        if chapterTitles[fullHref] != nil {
                                            subChapterStarts.append((fullHref, currentWordIndex + cleanWords.count))
                                        }
                                    }
                                } else {
                                    cleanWords.append(word)
                                }
                            }
                            
                            // Build full clean text
                            let chapterCleanText = cleanWords.joined(separator: " ")
                            fullText += chapterCleanText + "\n\n"
                            
                            // IF NO CHAPTERS WERE IDENTIFIED (no explicit title, no fragments)
                            // Fallback to making the whole file one section
                            if subChapterStarts.isEmpty {
                                subChapterStarts.append((href, currentWordIndex))
                            }
                            
                            // Create Navigation Points
                            for (i, startNode) in subChapterStarts.enumerated() {
                                let chapterTitle = chapterTitles[startNode.href] ?? "Chapter \(chapters.count + 1)"
                                
                                let nWordStart = startNode.index
                                let nWordEnd: Int
                                
                                if i + 1 < subChapterStarts.count {
                                    nWordEnd = subChapterStarts[i + 1].index
                                } else {
                                    nWordEnd = currentWordIndex + cleanWords.count
                                }
                                
                                // Only add if it actually has content
                                if nWordEnd > nWordStart {
                                    let chapter = NavigationPoint(
                                        title: chapterTitle,
                                        wordStartIndex: nWordStart,
                                        wordEndIndex: nWordEnd,
                                        type: .chapter
                                    )
                                    chapters.append(chapter)
                                }
                            }
                            
                            currentWordIndex += cleanWords.count
                        }
                    } else {
                        logger.warning("Could not read chapter: \(href)")
                    }
                }
            }
            
            // Adjust final end indices to be purely contiguous
            for i in 0..<chapters.count {
               if i + 1 < chapters.count {
                   chapters[i] = NavigationPoint(
                       title: chapters[i].title,
                       wordStartIndex: chapters[i].wordStartIndex,
                       wordEndIndex: chapters[i + 1].wordStartIndex,
                       type: chapters[i].type,
                       level: chapters[i].level
                   )
               }
            }
            
            // Cleanup
            try? fileManager.removeItem(at: tempDir)
            
            let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If no chapters were extracted, fall back to heading detection first, then pages
            if chapters.isEmpty && !trimmedText.isEmpty {
                let headings = HeadingDetector.createNavigationPoints(from: trimmedText)
                if !headings.isEmpty {
                    return ParseResult(text: trimmedText, chapters: headings, title: parsedTitle)
                } else {
                    let pages = PageChunker.createPages(from: trimmedText)
                    return ParseResult(text: trimmedText, chapters: pages, title: parsedTitle)
                }
            }
            
            // If we have very few chapters (e.g. 1 massive chapter) and the book is huge, 
            // Heading Detector might be better
            if chapters.count <= 2 && trimmedText.count > 50000 {
                let headings = HeadingDetector.createNavigationPoints(from: trimmedText)
                if headings.count > chapters.count {
                    return ParseResult(text: trimmedText, chapters: headings, title: parsedTitle)
                }
            }
            
            return ParseResult(text: trimmedText, chapters: chapters, title: parsedTitle)
            
        } catch {
            logger.error("EPUB parsing failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }
    
    /// Find NCX file path from manifest
    private static func findNCXPath(in manifest: [String: String], opfBasePath: URL) -> String? {
        // Look for .ncx file in manifest
        for (_, href) in manifest {
            if href.lowercased().hasSuffix(".ncx") {
                return href
            }
        }
        // Try common locations
        let commonPaths = ["toc.ncx", "content.ncx"]
        for path in commonPaths {
            let fullPath = opfBasePath.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fullPath.path) {
                return path
            }
        }
        return nil
    }
}

// MARK: - XML Parsers

private class ContainerXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var opfPath: String?
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return opfPath
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "rootfile", let fullPath = attributeDict["full-path"] {
            self.opfPath = fullPath
        }
    }
}

private class OPFParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var manifest: [String: String] = [:] // id -> href
    private var spine: [String] = [] // list of idrefs
    
    private var title: String?
    private var inTitle = false
    private var currentTitleText = ""
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> ([String: String], [String], String?) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (manifest, spine, (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil)
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = elementName.lowercased()
        
        if name == "item" || name == "opf:item" {
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            }
        }
        
        if name == "itemref" || name == "opf:itemref" {
            if let idref = attributeDict["idref"] {
                spine.append(idref)
            }
        }
        
        if name == "dc:title" || name == "title" {
            inTitle = true
            currentTitleText = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle {
            currentTitleText += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "dc:title" || name == "title" {
            inTitle = false
            if title == nil {
                title = currentTitleText
            }
        }
    }
}

/// Parser for NCX table of contents (EPUB 2)
private class NCXParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var chapterTitles: [String: String] = [:] // href -> title
    
    // State for parsing
    private var currentNavPointSrc: String?
    private var currentText: String = ""
    private var isInText = false
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> [String: String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return chapterTitles
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // Handle both with and without namespace prefix
        let name = elementName.lowercased()
        
        if name == "text" || name.hasSuffix(":text") {
            isInText = true
            currentText = ""
        }
        
        if name == "content" || name.hasSuffix(":content") {
            if let src = attributeDict["src"] {
                // Keep the fragment identifier so we can map sub-chapters!
                currentNavPointSrc = src
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInText {
            currentText += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        
        if name == "text" || name.hasSuffix(":text") {
            isInText = false
        }
        
        if name == "navpoint" || name.hasSuffix(":navpoint") {
            // Save the chapter title if we have both src and text
            if let src = currentNavPointSrc, !currentText.isEmpty {
                let trimmedTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedTitle.isEmpty {
                    chapterTitles[src] = trimmedTitle
                }
            }
            currentNavPointSrc = nil
            currentText = ""
        }
    }
}

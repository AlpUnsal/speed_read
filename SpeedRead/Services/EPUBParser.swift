import Foundation
import ZIPFoundation
import OSLog

class EPUBParser {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "EPUBParser")
    
    /// Parse result containing text and chapter navigation
    struct ParseResult {
        let text: String
        let chapters: [NavigationPoint]
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
            let (manifest, spine) = opfParser.parse()
            
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
                        
                        let text = DocumentParser.extractTextFromHTML(chapterContent)
                        let words = TextTokenizer.tokenize(text)
                        
                        if !words.isEmpty {
                            // Create chapter navigation point
                            let chapterTitle = chapterTitles[href] ?? "Chapter \(chapters.count + 1)"
                            let chapter = NavigationPoint(
                                title: chapterTitle,
                                wordStartIndex: currentWordIndex,
                                wordEndIndex: currentWordIndex + words.count,
                                type: .chapter
                            )
                            chapters.append(chapter)
                            
                            fullText += text + "\n\n"
                            currentWordIndex += words.count
                        }
                    } else {
                        logger.warning("Could not read chapter: \(href)")
                    }
                }
            }
            
            // Cleanup
            try? fileManager.removeItem(at: tempDir)
            
            let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If no chapters were extracted, fall back to page-based navigation
            if chapters.isEmpty && !trimmedText.isEmpty {
                let pages = PageChunker.createPages(from: trimmedText)
                return ParseResult(text: trimmedText, chapters: pages)
            }
            
            return ParseResult(text: trimmedText, chapters: chapters)
            
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
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> ([String: String], [String]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return (manifest, spine)
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "item" || elementName == "opf:item" { // handle optional namespaces roughly
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            }
        }
        
        if elementName == "itemref" || elementName == "opf:itemref" {
            if let idref = attributeDict["idref"] {
                spine.append(idref)
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
                // Remove fragment identifier (e.g., "chapter1.xhtml#section1" -> "chapter1.xhtml")
                currentNavPointSrc = src.components(separatedBy: "#").first
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

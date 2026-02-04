import Foundation
import ZIPFoundation
import OSLog

class DOCXParser {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "DOCXParser")
    
    /// Parse result containing text and navigation points
    struct ParseResult {
        let text: String
        let navigationPoints: [NavigationPoint]
    }
    
    /// Parse DOCX and return text only (backward compatible)
    static func parse(url: URL) -> String? {
        return parseWithHeadings(url: url)?.text
    }
    
    /// Parse DOCX and return both text and heading navigation points
    static func parseWithHeadings(url: URL) -> ParseResult? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            // Unzip the DOCX file
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: url, to: tempDir)
            
            // Locate word/document.xml
            let documentXMLURL = tempDir.appendingPathComponent("word/document.xml")
            
            guard let xmlData = try? Data(contentsOf: documentXMLURL) else {
                logger.error("Could not find word/document.xml")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            let parser = DOCXContentParser(data: xmlData)
            let (text, headings) = parser.parse()
            
            // Cleanup
            try? fileManager.removeItem(at: tempDir)
            
            guard let extractedText = text else { return nil }
            
            // Convert headings to NavigationPoints
            let words = TextTokenizer.tokenize(extractedText)
            var navigationPoints: [NavigationPoint] = []
            
            for (i, heading) in headings.enumerated() {
                let startIndex = heading.wordIndex
                let endIndex: Int
                
                if i + 1 < headings.count {
                    endIndex = headings[i + 1].wordIndex
                } else {
                    endIndex = words.count
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
            
            return ParseResult(text: extractedText, navigationPoints: navigationPoints)
            
        } catch {
            logger.error("DOCX parsing failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }
}

// MARK: - XML Parser

/// Internal heading representation
private struct DOCXHeading {
    let title: String
    let level: Int
    let wordIndex: Int
}

private class DOCXContentParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var extractedText = ""
    private var currentText = ""
    private var inTextElement = false
    
    // Heading detection
    private var headings: [DOCXHeading] = []
    private var currentParagraphStyle: String?
    private var currentParagraphText = ""
    private var currentWordIndex = 0
    private var paragraphStartWordIndex = 0
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> (String?, [DOCXHeading]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return (extractedText.isEmpty ? nil : extractedText, headings)
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        // Start of paragraph - track position
        if elementName == "w:p" || elementName.hasSuffix(":p") {
            paragraphStartWordIndex = currentWordIndex
            currentParagraphText = ""
            currentParagraphStyle = nil
        }
        
        // Detect paragraph style (Heading1, Heading2, Title, etc.)
        if elementName == "w:pStyle" || elementName.hasSuffix(":pStyle") {
            currentParagraphStyle = attributeDict["w:val"]
        }
        
        // w:t identifies a text run
        if elementName == "w:t" || elementName.hasSuffix(":t") {
            inTextElement = true
            currentText = ""
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTextElement {
            currentText += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "w:t" || elementName.hasSuffix(":t") {
            extractedText += currentText
            currentParagraphText += currentText
            
            // Count words as we go
            let words = TextTokenizer.tokenize(currentText)
            currentWordIndex += words.count
            
            inTextElement = false
        }
        
        // End of paragraph
        if elementName == "w:p" || elementName.hasSuffix(":p") {
            extractedText += "\n"
            
            // Check if this paragraph is a heading
            if let style = currentParagraphStyle, !currentParagraphText.isEmpty {
                let level = headingLevel(from: style)
                if level > 0 {
                    let heading = DOCXHeading(
                        title: currentParagraphText.trimmingCharacters(in: .whitespacesAndNewlines),
                        level: level,
                        wordIndex: paragraphStartWordIndex
                    )
                    headings.append(heading)
                }
            }
        }
    }
    
    /// Convert Word style to heading level
    private func headingLevel(from style: String) -> Int {
        let lowercased = style.lowercased()
        
        // Title is level 1
        if lowercased == "title" { return 1 }
        
        // Heading1, Heading2, etc.
        if lowercased.hasPrefix("heading") {
            let number = lowercased.dropFirst("heading".count)
            if let level = Int(number), level >= 1 && level <= 6 {
                return level
            }
        }
        
        // h1, h2, etc.
        if lowercased.hasPrefix("h") && lowercased.count == 2 {
            let number = lowercased.dropFirst(1)
            if let level = Int(number), level >= 1 && level <= 6 {
                return level
            }
        }
        
        return 0
    }
}


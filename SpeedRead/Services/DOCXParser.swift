import Foundation
import ZIPFoundation
import OSLog

class DOCXParser {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "DOCXParser")
    
    static func parse(url: URL) -> String? {
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
            let text = parser.parse()
            
            // Cleanup
            try? fileManager.removeItem(at: tempDir)
            
            return text
            
        } catch {
            logger.error("DOCX parsing failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }
}

// MARK: - XML Parser

private class DOCXContentParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var extractedText = ""
    private var currentText = ""
    private var inTextElement = false
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return extractedText.isEmpty ? nil : extractedText
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
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
            inTextElement = false
        }
        
        // Add a newline/space after paragraphs
        if elementName == "w:p" || elementName.hasSuffix(":p") {
            extractedText += "\n"
        }
        
        // Add space after line breaks if needed (w:br)? Usually handled by p.
    }
}

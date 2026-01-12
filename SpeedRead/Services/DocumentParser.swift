import Foundation
import PDFKit
import UniformTypeIdentifiers

struct DocumentParser {
    
    /// Parse document at URL and return extracted text
    static func parse(url: URL) -> String? {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "txt":
            return parseTXT(url: url)
        case "pdf":
            return parsePDF(url: url)
        case "docx":
            return parseDOCX(url: url)
        case "rtf":
            return parseRTF(url: url)
        case "epub":
            return parseEPUB(url: url)
        default:
            return nil
        }
    }
    
    // MARK: - TXT Parser
    private static func parseTXT(url: URL) -> String? {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Try other encodings
            if let data = try? Data(contentsOf: url) {
                return String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1)
            }
            return nil
        }
    }
    
    // MARK: - PDF Parser
    private static func parsePDF(url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        
        var fullText = ""
        for i in 0..<document.pageCount {
            if let page = document.page(at: i),
               let pageText = page.string {
                fullText += pageText + " "
            }
        }
        return fullText.isEmpty ? nil : fullText
    }
    
    // MARK: - DOCX Parser
    // Note: Full DOCX support requires ZIPFoundation or similar library for iOS
    // For now, we return nil - recommend using TXT, PDF, or RTF formats
    private static func parseDOCX(url: URL) -> String? {
        // DOCX parsing requires unzipping which needs a third-party library on iOS
        // NSAttributedString.DocumentType.officeOpenXML is not available on iOS
        // For production, add ZIPFoundation via SPM and implement proper extraction
        print("DOCX parsing not fully supported on iOS without ZIPFoundation. Use PDF, TXT, or RTF instead.")
        return nil
    }
    
    private static func extractTextFromDOCXML(data: Data) -> String? {
        let parser = DOCXMLParser(data: data)
        return parser.parse()
    }
    
    // MARK: - RTF Parser
    private static func parseRTF(url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url)
            let attributedString = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attributedString.string
        } catch {
            print("RTF parsing error: \(error)")
            return nil
        }
    }
    
    // MARK: - EPUB Parser
    // Note: Full EPUB support requires ZIPFoundation or similar library for iOS
    // For now, we return nil - recommend using TXT, PDF, or DOCX formats
    private static func parseEPUB(url: URL) -> String? {
        // EPUB parsing requires unzipping which needs a third-party library on iOS
        // For production, add ZIPFoundation via SPM and implement proper extraction
        print("EPUB parsing not fully supported on iOS without ZIPFoundation. Use PDF, TXT, or DOCX instead.")
        return nil
    }
    
    private static func extractTextFromHTML(_ html: String) -> String {
        // Simple HTML tag stripping
        var text = html
        // Remove script and style tags with content
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        // Remove all HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - DOCX XML Parser
class DOCXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var extractedText = ""
    private var currentText = ""
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return extractedText.isEmpty ? nil : extractedText
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // w:t elements contain text in DOCX
        if elementName == "w:t" || elementName.hasSuffix(":t") {
            extractedText += currentText
        }
        // Add space after paragraphs
        if elementName == "w:p" || elementName.hasSuffix(":p") {
            extractedText += " "
        }
        currentText = ""
    }
}

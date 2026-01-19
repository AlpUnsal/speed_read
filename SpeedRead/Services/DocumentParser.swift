import Foundation
import PDFKit
import UniformTypeIdentifiers
import OSLog

struct DocumentParser {
    
    // Create a logger for this subsystem
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "DocumentParser")
    
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
    private static func parseDOCX(url: URL) -> String? {
        return DOCXParser.parse(url: url)
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
            logger.error("RTF parsing error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - EPUB Parser
    private static func parseEPUB(url: URL) -> String? {
        return EPUBParser.parse(url: url)
    }
    
    // MARK: - HTML Extraction Helper
    // Made internal so EPUBParser can use it
    static func extractTextFromHTML(_ html: String) -> String {
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

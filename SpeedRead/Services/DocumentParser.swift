import Foundation
import PDFKit
import Vision
import UIKit
import UniformTypeIdentifiers
import OSLog

struct DocumentParser {
    
    // Create a logger for this subsystem
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "DocumentParser")
    
    /// Parse document at URL and return extracted text
    static func parse(url: URL) -> String? {
        return parseWithNavigation(url: url)?.text
    }
    
    /// Parse result containing text and navigation points
    struct ParseResult {
        let text: String
        let navigationPoints: [NavigationPoint]
    }
    
    /// Parse document at URL and return text with navigation points
    /// Parse document at URL and return text with navigation points
    static func parseWithNavigation(url: URL) -> ParseResult? {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "txt":
            if let text = parseTXT(url: url) {
                let headings = HeadingDetector.createNavigationPoints(from: text)
                let points = !headings.isEmpty ? headings : PageChunker.createPages(from: text)
                return ParseResult(text: text, navigationPoints: points)
            }
            return nil
        case "pdf":
            return parsePDF(url: url)
        case "docx":
            if let result = DOCXParser.parseWithHeadings(url: url) {
                let points = !result.navigationPoints.isEmpty ? result.navigationPoints : PageChunker.createPages(from: result.text)
                return ParseResult(text: result.text, navigationPoints: points)
            }
            return nil
        case "rtf":
            if let text = parseRTF(url: url) {
                let headings = HeadingDetector.createNavigationPoints(from: text)
                let points = !headings.isEmpty ? headings : PageChunker.createPages(from: text)
                return ParseResult(text: text, navigationPoints: points)
            }
            return nil
        case "epub":
            if let result = EPUBParser.parseWithChapters(url: url) {
                return ParseResult(text: result.text, navigationPoints: result.chapters)
            }
            return nil
        default:
            return nil
        }
    }
    
    /// Parse and Save directly to Inbox (Crash Prevention Strategy)
    /// Returns the UUID of the saved document
    static func parseAndSave(url: URL) -> UUID? {
        // logger.debug("DocumentParser: Starting parseAndSave...")
        
        var savedID: UUID?
        
        autoreleasepool {
            // 1. Parse (using existing method)
            if let result = parseWithNavigation(url: url) {
                let title = url.deletingPathExtension().lastPathComponent
                // logger.debug("DocumentParser: Parsing complete. Text: \(result.text.count)")
                
                // 2. Create Document
                let newDoc = ReadingDocument(
                    name: title,
                    content: result.text,
                    navigationPoints: result.navigationPoints
                )
                
                // 3. Save to Inbox
                // logger.debug("DocumentParser: Saving to Inbox...")
                LibraryManager.saveToInbox(newDoc)
                
                // logger.debug("DocumentParser: Saved UUID: \(newDoc.id)")
            } else {
                // logger.error("DocumentParser: Parsing returned nil")
            }
        }
        
        return savedID
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
    // MARK: - PDF Parser
    // MARK: - PDF Parser
    // MARK: - PDF Parser
    private static func parsePDF(url: URL) -> ParseResult? {
        // Use the dedicated PDFParsingService
        // Now returns (text: String, navigationPoints: [NavigationPoint])
        var finalResult: ParseResult?
        
        // Wrap in autoreleasepool to ensure PDFKit memory is released BEFORE we return
        autoreleasepool {
            // logger.debug("DocumentParser: Calling PDFParsingService...")
            let (text, navigationPoints) = PDFParsingService.parsePDF(url: url)
            // logger.debug("DocumentParser: PDF Service returned text length: \(text.count)")
            
            if !text.isEmpty {
                // If we found specific navigation points (Sections), use them.
                // Otherwise, fallback to generic PageChunker
                if !navigationPoints.isEmpty {
                     // logger.debug("DocumentParser: Creating result with sections")
                     finalResult = ParseResult(text: text, navigationPoints: navigationPoints)
                } else {
                     // logger.debug("DocumentParser: Fallback to pages")
                     let pages = PageChunker.createPages(from: text)
                     finalResult = ParseResult(text: text, navigationPoints: pages)
                }
            } else {
                logger.error("DocumentParser: Empty text!")
            }
        }
        
        if finalResult != nil {
            // logger.debug("DocumentParser: Returning result (Autoreleasepool drained)")
        }
        
        return finalResult
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
    static func extractTextFromHTML(_ html: String) -> String {
        return HTMLHelper.extractTextFromHTML(html)
    }
}

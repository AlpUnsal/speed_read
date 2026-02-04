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
    static func parseWithNavigation(url: URL) -> ParseResult? {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "txt":
            if let text = parseTXT(url: url) {
                // Try to detect headings first, fallback to pages
                let headings = HeadingDetector.createNavigationPoints(from: text)
                if !headings.isEmpty {
                    return ParseResult(text: text, navigationPoints: headings)
                }
                let pages = PageChunker.createPages(from: text)
                return ParseResult(text: text, navigationPoints: pages)
            }
            return nil
        case "pdf":
            if let text = parsePDF(url: url) {
                // TODO: Add PDF outline extraction
                let pages = PageChunker.createPages(from: text)
                return ParseResult(text: text, navigationPoints: pages)
            }
            return nil
        case "docx":
            // Use new DOCX parser with heading extraction
            if let result = DOCXParser.parseWithHeadings(url: url) {
                if !result.navigationPoints.isEmpty {
                    return ParseResult(text: result.text, navigationPoints: result.navigationPoints)
                }
                // Fallback to pages
                let pages = PageChunker.createPages(from: result.text)
                return ParseResult(text: result.text, navigationPoints: pages)
            }
            return nil
        case "rtf":
            if let text = parseRTF(url: url) {
                // Try heading detection for RTF (similar to plain text)
                let headings = HeadingDetector.createNavigationPoints(from: text)
                if !headings.isEmpty {
                    return ParseResult(text: text, navigationPoints: headings)
                }
                let pages = PageChunker.createPages(from: text)
                return ParseResult(text: text, navigationPoints: pages)
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
    private static func parsePDF(url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        
        // Attempt to parse using Vision (OCR) first for better accuracy
        if let visionText = parsePDFWithVision(document: document) {
            return visionText
        }
        
        // Fallback to standard PDFKit extraction
        return parsePDFLegacy(document: document)
    }
    
    private static func parsePDFWithVision(document: PDFDocument) -> String? {
        var mainText: [String] = []
        
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            
            // Render page to image for Vision request
            guard let cgImage = createCGImage(from: page) else { continue }
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    logger.error("Vision text request error: \(error.localizedDescription)")
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                
                // Sort by Y position (top to bottom)
                // Vision origin is bottom-left, so higher Y is higher up
                let sortedObservations = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                
                let pageText = sortedObservations.compactMap { observation in
                    return observation.topCandidates(1).first?.string
                }
                
                mainText.append(contentsOf: pageText)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logger.error("Failed to perform Vision request: \(error.localizedDescription)")
            }
        }
        
        let fullText = mainText.joined(separator: "\n")
        return fullText.isEmpty ? nil : fullText
    }
    
    private static func createCGImage(from page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(pageRect)
            ctx.cgContext.translateBy(x: 0.0, y: pageRect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image.cgImage
    }

    private static func parsePDFLegacy(document: PDFDocument) -> String? {
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
    static func extractTextFromHTML(_ html: String) -> String {
        return HTMLHelper.extractTextFromHTML(html)
    }
}

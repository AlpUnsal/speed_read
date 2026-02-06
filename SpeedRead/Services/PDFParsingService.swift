import Foundation
import PDFKit
import Vision
import UIKit
import OSLog

/// Service for parsing PDF documents using Vision framework
/// Optimized for research papers: extracts main body text, removes headers/footers/citations
struct PDFParsingService {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "PDFParsingService")
    
    /// Extract clean list of words from a PDF URL suitable for RSVP reading
    /// - Parameter url: URL of the PDF file
    /// - Returns: Array of words (strings)
    static func parsePDFWords(url: URL) -> [String] {
        guard let document = PDFDocument(url: url) else {
            logger.error("Failed to load PDF document")
            return []
        }
        
        var allWords: [String] = []
        
        // Process each page
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            
            // Render page to image for Vision
            // Using a fixed width of 1000px as suggested for balance of speed/accuracy
            guard let cgImage = createCGImage(from: page, targetWidth: 1000) else { continue }
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    logger.error("Vision request failed: \(error.localizedDescription)")
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                
                // Filter and extract text
                let pageWords = processObservations(observations)
                allWords.append(contentsOf: pageWords)
            }
            
            // Configure request for accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Prevent common OCR issues with columns by treating it as document-aware if possible,
            // though standard text request handles blocks well.
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logger.error("Failed to perform Vision request on page \(i): \(error.localizedDescription)")
            }
        }
        
        return allWords
    }
    
    // MARK: - Helper Methods
    
    /// Process Vision observations to filter headers/footers and clean text
    private static func processObservations(_ observations: [VNRecognizedTextObservation]) -> [String] {
        var pageWords: [String] = []
        
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            
            // 1. Filter by Position (Header/Footer)
            // Vision coordinates: Origin (0,0) is bottom-left.
            // Header: Top 10% (y > 0.9)
            // Footer: Bottom 10% (y < 0.1)
            // We check the bounding box center to be safe, or the bottom edge for header / top edge for footer.
            
            let boundingBox = observation.boundingBox
            let isHeader = boundingBox.origin.y > 0.90
            let isFooter = (boundingBox.origin.y + boundingBox.height) < 0.10
            
            if isHeader || isFooter {
                continue
            }
            
            let text = candidate.string
            
            // 2. Filter citations and noise
            // Remove citation brackets like [1], [12-14]
            let cleanedText = removeCitations(from: text)
            
            // Split into words
            let componentWords = cleanedText.components(separatedBy: .whitespacesAndNewlines)
            
            for word in componentWords {
                let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                
                if trimmed.isEmpty { continue }
                
                // 3. Filter words with digits (references, years, figures)
                // As requested: exclude words containing any decimal digits
                if word.rangeOfCharacter(from: .decimalDigits) != nil {
                   continue
                }
                
                pageWords.append(word)
            }
        }
        
        return pageWords
    }
    
    private static func removeCitations(from text: String) -> String {
        // Regex to remove patterns like [1], [12], [1, 2]
        // Simple patterns first
        var result = text
        
        // Remove [123] type citations
        if let regex = try? NSRegularExpression(pattern: "\\[[0-9, -]+\\]", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        
        return result
    }
    
    private static func createCGImage(from page: PDFPage, targetWidth: CGFloat) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        
        // Calculate scale to hit target width (e.g. 1000px)
        // If detection is poor, we might want higher resolution, but 1000 is a good start.
        let scale = targetWidth / pageRect.width
        let size = CGSize(width: targetWidth, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: size))
            
            // Flip context for PDF coordinate system
            ctx.cgContext.translateBy(x: 0.0, y: size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Scale the PDF page to fit the new size
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        
        return image.cgImage
    }
}

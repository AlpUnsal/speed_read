import UIKit

struct HTMLHelper {
    /// Extracts readable text from HTML string by attempting to isolate the main content
    /// and then using NSAttributedString for proper parsing.
    static func extractTextFromHTML(_ html: String) -> String {
        // 1. Pre-process: Try to isolate the article body to avoid header/footer noise
        // Substack often uses "available-content" or "post-content"
        var contentHtml = html
        
        // Simple regex to find the start of the content div
        // We look for class="available-content" which is common in specific layouts
        // Substack uses "available-content" or "post-content" or "body markup"
        let selectors = [
            "class=\"[^\"]*available-content[^\"]*\"",
            "class=\"[^\"]*post-content[^\"]*\"",
            "class=\"[^\"]*markup[^\"]*\"", // Substack
            "class=\"[^\"]*body[^\"]*\""
        ]
        
        var foundRange: Range<String.Index>? = nil
        
        for selector in selectors {
            if let range = contentHtml.range(of: "<div[^>]*\(selector)[^>]*>", options: .regularExpression) {
                foundRange = range
                break
            }
        }
        
        if let range = foundRange {
            contentHtml = String(contentHtml[range.lowerBound...])
        } else if let range = contentHtml.range(of: "<article[^>]*>", options: .regularExpression) {
             contentHtml = String(contentHtml[range.lowerBound...])
        }
        
        // 2. Convert to Data
        guard let data = contentHtml.data(using: .utf8) else { return "" }
        
        // 3. Use NSAttributedString to parse HTML (handles entities, blocking, etc.)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        // Note: transforming HTML to string should ideally be done on a background thread
        // if the document is very large, but here we are likely already in a background context.
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            // Trim whitespace
            let text = attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Post-process: Remove excessive newlines (more than 3)
            return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        }
        
        return ""
    }
    
    /// Extracts the title from HTML string using meta tags or title tag
    static func extractTitle(from html: String) -> String? {
        // Try og:title first
        if let range = html.range(of: "<meta[^>]*property=\"og:title\"[^>]*content=\"([^\"]*)\"", options: .regularExpression) {
            let match = String(html[range])
            if let contentRange = match.range(of: "content=\"([^\"]*)\"", options: .regularExpression) {
                let content = String(match[contentRange])
                return content.replacingOccurrences(of: "content=\"", with: "").replacingOccurrences(of: "\"", with: "")
            }
        }
        
        // Try <title> tag
        if let range = html.range(of: "<title>([^<]*)</title>", options: .regularExpression) {
            let match = String(html[range])
                .replacingOccurrences(of: "<title>", with: "")
                .replacingOccurrences(of: "</title>", with: "")
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
}

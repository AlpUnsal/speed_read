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
    
    // MARK: - Structured HTML Extraction (for EPUB reading mode)

    /// Block-level HTML elements that represent paragraph boundaries
    private static let blockElements: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "blockquote", "li", "ol", "ul", "table", "tr",
        "section", "article", "header", "footer", "pre",
        "figure", "figcaption", "hr", "nav", "aside",
        "address", "details", "summary"
    ]

    /// Extracts text from HTML preserving only real paragraph boundaries.
    /// Uses XMLParser so only block-level element boundaries produce `\n\n`.
    /// Inline elements (`<span>`, `<em>`, `<a>`, etc.) do NOT create line breaks.
    static func extractTextFromHTMLStructured(_ html: String) -> String {
        // Pre-process: replace HTML entities that aren't valid in XML
        // XMLParser only understands &amp; &lt; &gt; &quot; &apos;
        var xmlSafe = html
        // Replace &nbsp; and other named HTML entities with their Unicode equivalents
        xmlSafe = xmlSafe.replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&mdash;", with: "\u{2014}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&ndash;", with: "\u{2013}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&lsquo;", with: "\u{2018}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&rsquo;", with: "\u{2019}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&ldquo;", with: "\u{201C}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&rdquo;", with: "\u{201D}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&hellip;", with: "\u{2026}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&trade;", with: "\u{2122}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&copy;", with: "\u{00A9}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&reg;", with: "\u{00AE}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&deg;", with: "\u{00B0}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&frac12;", with: "\u{00BD}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&frac14;", with: "\u{00BC}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&frac34;", with: "\u{00BE}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&times;", with: "\u{00D7}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&divide;", with: "\u{00F7}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&iexcl;", with: "\u{00A1}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&cent;", with: "\u{00A2}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&pound;", with: "\u{00A3}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&sect;", with: "\u{00A7}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&laquo;", with: "\u{00AB}")
        xmlSafe = xmlSafe.replacingOccurrences(of: "&raquo;", with: "\u{00BB}")
        // Catch any remaining named entities we missed — replace with space to avoid XML parse failure
        xmlSafe = xmlSafe.replacingOccurrences(
            of: "&(?!amp;|lt;|gt;|quot;|apos;|#)[a-zA-Z]+;",
            with: " ",
            options: .regularExpression
        )

        // EPUB content is valid XHTML — try XMLParser
        if let data = xmlSafe.data(using: .utf8) {
            let delegate = StructuredHTMLParserDelegate(blockElements: blockElements)
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.shouldProcessNamespaces = true
            if parser.parse() {
                return delegate.postProcessedResult()
            }
        }

        // Fallback: regex-based tag stripping for malformed HTML
        return extractTextFromHTMLFallback(html)
    }

    /// Regex fallback for malformed HTML that XMLParser can't handle
    private static func extractTextFromHTMLFallback(_ html: String) -> String {
        var text = html

        // Use a unique placeholder for intentional breaks so source newlines can be collapsed
        let paraBreak = "\u{FFFE}\u{FFFE}"  // Paragraph boundary placeholder
        let lineBreak = "\u{FFFE}"           // Line break placeholder

        // Replace <br> with line break placeholder
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: lineBreak, options: .regularExpression)

        // Replace closing block tags with paragraph boundary placeholder
        let blockClosingPattern = "</(?:p|div|h[1-6]|blockquote|li|ol|ul|table|tr|section|article|header|footer|pre|figure|figcaption)>"
        text = text.replacingOccurrences(of: blockClosingPattern, with: paraBreak, options: .regularExpression)

        // Strip all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#8217;", with: "\u{2019}")
        text = text.replacingOccurrences(of: "&#8216;", with: "\u{2018}")
        text = text.replacingOccurrences(of: "&#8220;", with: "\u{201C}")
        text = text.replacingOccurrences(of: "&#8221;", with: "\u{201D}")
        text = text.replacingOccurrences(of: "&#8212;", with: "\u{2014}")
        text = text.replacingOccurrences(of: "&#8211;", with: "\u{2013}")

        // Decode numeric entities (&#NNN;)
        if let numericPattern = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsText = text as NSString
            let matches = numericPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let codeStr = nsText.substring(with: match.range(at: 1))
                if let code = UInt32(codeStr), let scalar = Unicode.Scalar(code) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }

        // Decode hex entities (&#xNNN;)
        if let hexPattern = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let nsText = text as NSString
            let matches = hexPattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let hexStr = nsText.substring(with: match.range(at: 1))
                if let code = UInt32(hexStr, radix: 16), let scalar = Unicode.Scalar(code) {
                    text = (text as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
        }

        // Collapse ALL whitespace (including source newlines) to single spaces.
        // In HTML, newlines in source are just whitespace.
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Restore our intentional breaks from placeholders
        text = text.replacingOccurrences(of: " ?\(paraBreak) ?", with: "\n\n")
        text = text.replacingOccurrences(of: " ?\(lineBreak) ?", with: "\n")

        // Collapse 3+ newlines to double
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Title Extraction

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

// MARK: - XMLParser Delegate for Structured HTML Extraction

private class StructuredHTMLParserDelegate: NSObject, XMLParserDelegate {
    private let blockElements: Set<String>
    private var textBuffer = ""
    private var skipContent = false
    private var afterBlock = false  // True after a block element closed — skip inter-tag whitespace
    /// Elements whose text content should be discarded
    private let skipElements: Set<String> = ["style", "script", "head"]

    init(blockElements: Set<String>) {
        self.blockElements = blockElements
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()

        if skipElements.contains(name) {
            skipContent = true
            return
        }

        // Opening a block element also means we're at a boundary — skip preceding whitespace
        if blockElements.contains(name) {
            afterBlock = true
        }

        // <br> inserts a single newline
        if name == "br" {
            textBuffer.append("\n")
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()

        if skipElements.contains(name) {
            skipContent = false
            return
        }

        // Block-level element end → paragraph boundary
        // Only add if buffer doesn't already end with a newline (prevents nested block duplication)
        if blockElements.contains(name) {
            if textBuffer.hasSuffix("\n\n") {
                // Already at a paragraph boundary
            } else if textBuffer.hasSuffix("\n") {
                textBuffer.append("\n")
            } else {
                textBuffer.append("\n\n")
            }
            afterBlock = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !skipContent else { return }

        // Skip whitespace-only text nodes between block elements (HTML indentation)
        if afterBlock {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }
            afterBlock = false
        }

        // In HTML, newlines within text content are treated as spaces.
        // Replace them here so only our intentional \n (from <br>) and \n\n (from block boundaries) survive.
        let normalized = string.replacingOccurrences(of: "\n", with: " ")
        textBuffer.append(normalized)
    }

    /// Post-process the raw buffer into clean paragraph-separated text
    func postProcessedResult() -> String {
        var text = textBuffer
        // Collapse runs of horizontal whitespace (tabs, spaces) but keep newlines
        text = text.replacingOccurrences(of: "[^\\S\\n]+", with: " ", options: .regularExpression)
        // Collapse 3+ newlines to double
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        // Clean up space-newline combinations
        text = text.replacingOccurrences(of: " *\\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n ", with: "\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

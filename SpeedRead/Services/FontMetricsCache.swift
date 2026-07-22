import UIKit

/// A cache for font objects and character width measurements to avoid
/// expensive CoreText calls during scroll events.
class FontMetricsCache {
    static let shared = FontMetricsCache()
    
    private init() {}
    
    // MARK: - Font Cache
    
    /// Cache key: "fontName-fontSize"
    private var fontCache: [String: UIFont] = [:]
    private let fontCacheLock = NSLock()
    
    /// Get or create a cached UIFont instance
    func font(name: String, size: CGFloat) -> UIFont {
        let key = "\(name)-\(size)"
        
        fontCacheLock.lock()
        defer { fontCacheLock.unlock() }
        
        if let cached = fontCache[key] {
            return cached
        }
        
        let font = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
        fontCache[key] = font
        return font
    }
    
    // MARK: - Character Width Cache
    
    /// Cache key: "char-fontName-fontSize"
    private var charWidthCache: [String: CGFloat] = [:]
    private let charWidthCacheLock = NSLock()
    
    /// Get or compute the width of a character with a given font
    func charWidth(_ char: String, fontName: String, fontSize: CGFloat) -> CGFloat {
        let key = "\(char)-\(fontName)-\(fontSize)"
        
        charWidthCacheLock.lock()
        defer { charWidthCacheLock.unlock() }
        
        if let cached = charWidthCache[key] {
            return cached
        }
        
        let font = self.font(name: fontName, size: fontSize)
        let width = char.size(withFont: font).width
        charWidthCache[key] = width
        return width
    }
    
    // MARK: - Leading Punctuation Detection

    /// Characters that should be skipped when determining the ORP index.
    private static let leadingPunctuationSet: Set<Character> = [
        "\"", "'",          // ASCII straight quotes
        "\u{201C}",         // " LEFT DOUBLE QUOTATION MARK
        "\u{2018}",         // ' LEFT SINGLE QUOTATION MARK
        "\u{201E}",         // „ DOUBLE LOW-9 QUOTATION MARK
        "\u{201A}",         // ‚ SINGLE LOW-9 QUOTATION MARK
        "\u{00AB}",         // « LEFT-POINTING DOUBLE ANGLE QUOTATION MARK
        "\u{2039}",         // ‹ SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    ]

    /// Returns the character index that should be highlighted as the ORP.
    /// Normally index 1 (2nd character). When the word starts with a
    /// quotation mark, returns index 2 (3rd character) so the highlight
    /// falls on the first real letter of the word.
    static func orpIndex(for word: String) -> Int {
        guard word.count > 1 else { return 0 }
        if let first = word.first, leadingPunctuationSet.contains(first) {
            return min(2, word.count - 1)
        }
        return 1
    }

    // MARK: - ORP Offset Calculation

    /// Calculate the ORP (Optimal Recognition Point) offset for a word.
    /// Returns the distance from the start of the word to the center of the ORP character.
    func orpOffset(for word: String, fontName: String, fontSize: CGFloat) -> CGFloat {
        guard word.count > 1 else {
            let font = self.font(name: fontName, size: fontSize)
            return word.size(withFont: font).width / 2
        }

        let targetIndex = FontMetricsCache.orpIndex(for: word)
        var offset: CGFloat = 0
        for (i, char) in word.enumerated() {
            let w = charWidth(String(char), fontName: fontName, fontSize: fontSize)
            if i < targetIndex {
                offset += w
            } else {
                offset += w / 2
                break
            }
        }
        return offset
    }
    
    // MARK: - Batch Operations (for performance with large documents)
    
    /// Compute ORP offsets for multiple words in a single batch.
    /// More efficient than calling orpOffset() repeatedly due to reduced lock contention.
    func orpOffsets(for words: [String], fontName: String, fontSize: CGFloat) -> [CGFloat] {
        let font = self.font(name: fontName, size: fontSize)

        return words.map { word in
            guard word.count > 1 else {
                return word.size(withFont: font).width / 2
            }

            let targetIndex = FontMetricsCache.orpIndex(for: word)
            var offset: CGFloat = 0
            for (i, char) in word.enumerated() {
                let w = charWidth(String(char), fontName: fontName, fontSize: fontSize)
                if i < targetIndex {
                    offset += w
                } else {
                    offset += w / 2
                    break
                }
            }
            return offset
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear all caches (call when font settings change)
    func clearCache() {
        fontCacheLock.lock()
        fontCache.removeAll()
        fontCacheLock.unlock()
        
        charWidthCacheLock.lock()
        charWidthCache.removeAll()
        charWidthCacheLock.unlock()
    }
}

// MARK: - String Extension (moved from WordDisplayView for shared access)
extension String {
    func size(withFont font: UIFont) -> CGSize {
        let attributes = [NSAttributedString.Key.font: font]
        return (self as NSString).size(withAttributes: attributes)
    }
}

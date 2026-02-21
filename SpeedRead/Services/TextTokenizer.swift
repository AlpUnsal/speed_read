import Foundation
import UIKit

struct TextTokenizer {
    
    // Shared text checker instance for performance (thread-safe according to Apple docs)
    private static let spellChecker = UITextChecker()
    
    /// Tokenize text into words for RSVP display
    static func tokenize(_ text: String) -> [String] {
        // Split by whitespace and newlines first
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        
        var words: [String] = []
        var skipNext = false
        
        for i in 0..<components.count {
            if skipNext {
                skipNext = false
                continue
            }
            
            let component = components[i]
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Check for line-break hyphenation (e.g. from PDFs or copy-pasted text)
            if trimmed.hasSuffix("-") && i + 1 < components.count {
                let nextComponent = components[i+1].trimmingCharacters(in: .whitespaces)
                if !nextComponent.isEmpty {
                    let firstPart = String(trimmed.dropLast())
                    
                    // Extract just the letters to form a clean word for dictionary checking
                    let firstLetters = firstPart.components(separatedBy: CharacterSet.letters.inverted).joined()
                    let secondLetters = nextComponent.components(separatedBy: CharacterSet.letters.inverted).joined()
                    let combinedWord = firstLetters + secondLetters
                    
                    if !combinedWord.isEmpty {
                        let range = NSRange(location: 0, length: combinedWord.utf16.count)
                        let misspelledRange = spellChecker.rangeOfMisspelledWord(in: combinedWord, range: range, startingAt: 0, wrap: false, language: "en_US")
                        
                        // If it's a valid dictionary word without hyphens, merge the two components
                        if misspelledRange.location == NSNotFound {
                            let merged = firstPart + nextComponent
                            let parts = splitOnPunctuation(merged)
                            words.append(contentsOf: parts)
                            skipNext = true
                            continue
                        }
                    }
                }
            }
            
            // Normal tokenization (either no hyphen or not a valid merged word)
            // Split on em dashes, en dashes, and slashes (but NOT hyphens)
            // This keeps genuine compound words like "well-known" separate
            let parts = splitOnPunctuation(trimmed)
            words.append(contentsOf: parts)
        }
        
        return words
    }
    
    /// Split a word on specific separators (em dash, en dash, double hyphen, ellipses)
    /// Attaches the separator to the PRECEDING word.
    /// Keeps slashes combined (does not split).
    private static func splitOnPunctuation(_ text: String) -> [String] {
        // If text is short, quick check to avoid processing
        if text.count < 2 { return [text] }
        
        var result: [String] = []
        var currentToken = ""
        
        // We'll advance through the string character by character (or lookahead)
        let chars = Array(text)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            // Check for multi-char separators first
            
            // 1. Double Hyphen "--"
            if char == "-" && i + 1 < chars.count && chars[i+1] == "-" {
                // Found "--"
                // Append "--" to current token
                currentToken.append("-")
                currentToken.append("-")
                
                // Push current token and reset
                result.append(currentToken)
                currentToken = ""
                
                i += 2
                continue
            }
            
            // 2. Ellipsis "..." (3 dots)
            if char == "." && i + 2 < chars.count && chars[i+1] == "." && chars[i+2] == "." {
                // Found "..."
                currentToken.append(".")
                currentToken.append(".")
                currentToken.append(".")
                
                // Push current token and reset
                result.append(currentToken)
                currentToken = ""
                
                i += 3
                continue
            }
            
            // 3. Single-char separators: Em dash (—), En dash (–), Ellipsis char (…)
            if char == "\u{2014}" || char == "\u{2013}" || char == "\u{2026}" { // \u{2026} is …
                // Attach to current token
                currentToken.append(char)
                
                // Push and reset
                result.append(currentToken)
                currentToken = ""
                
                i += 1
                continue
            }
            
            // Regular character (including /)
            currentToken.append(char)
            i += 1
        }
        
        // Append any remaining text
        if !currentToken.isEmpty {
            result.append(currentToken)
        }
        
        // Filter out empty strings just in case logic produced them
        return result.filter { !$0.isEmpty }
    }
    
    /// Calculate recommended pause multiplier based on punctuation and speed
    /// The pause is speed-relative: faster reading = shorter pauses, slower = slightly longer
    /// Returns a multiplier for the display time (1.0 = normal, slightly higher = subtle pause)
    static func pauseMultiplier(for word: String, wpm: Double = 300) -> Double {
        // Characters that might mask the actual punctuation at the end of a word
        let closingPunctuation = CharacterSet(charactersIn: "\"\u{201D}\u{2019}'\u{0027})]}\u{201C}\u{2018}")
        
        // Find the last "meaningful" character (skipping quotes, brackets, etc.)
        var meaningfulChar: Character? = nil
        
        for char in word.reversed() {
            if let scalar = char.unicodeScalars.first, !closingPunctuation.contains(scalar) {
                meaningfulChar = char
                break
            }
        }
        
        // Calculate a speed factor: higher WPM = smaller additional pause
        // At 300 WPM (baseline), factor is 1.0
        // At 600 WPM, factor is 0.5 (half the pause)
        // At 150 WPM, factor is 1.5 (slightly longer pause)
        // Clamped to keep pauses reasonable
        let speedFactor = min(1.5, max(0.3, 300 / wpm))
        
        // Pause additions: noticeable pauses that mirror natural speech rhythm
        // At 60fps, 1 frame ≈ 16.7ms
        if let char = meaningfulChar {
            switch char {
            case ".", "!", "?":
                // Sentence end: ~1.65x at 300 WPM
                return 1.0 + (0.65 * speedFactor)
            case ",", ";", ":":
                // Comma pause: ~1.50x at 300 WPM (Slower than before, but faster than period)
                return 1.0 + (0.50 * speedFactor)
            case "—", "–":
                // Em/en dash: ~1.55x at 300 WPM
                return 1.0 + (0.55 * speedFactor)
            default:
                // If it contains a slash (either/or), treat like a comma
                if word.contains("/") {
                    return 1.0 + (0.50 * speedFactor)
                }
                return 1.0
            }
        }
        
        // Fallback check for slash if no meaningful char was found (unlikely but safe)
        if word.contains("/") {
            return 1.0 + (0.50 * speedFactor)
        }
        
        return 1.0
    }
}

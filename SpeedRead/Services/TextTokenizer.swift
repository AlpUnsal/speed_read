import Foundation

struct TextTokenizer {
    
    /// Tokenize text into words for RSVP display
    static func tokenize(_ text: String) -> [String] {
        // Split by whitespace and newlines first
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        
        var words: [String] = []
        
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Split on em dashes, en dashes, and slashes (but NOT hyphens)
            // This keeps compound words like "well-known" together
            let parts = splitOnPunctuation(trimmed)
            words.append(contentsOf: parts)
        }
        
        return words
    }
    
    /// Split a word on specific punctuation (em dash, en dash, slash)
    /// Returns array of tokens, including the punctuation as separate tokens
    private static func splitOnPunctuation(_ text: String) -> [String] {
        var result: [String] = []
        var currentWord = ""
        
        for char in text {
            // Em dash (—), en dash (–), or slash (/)
            if char == "\u{2014}" || char == "\u{2013}" || char == "/" {
                // Add the word before the punctuation
                if !currentWord.isEmpty {
                    result.append(currentWord)
                    currentWord = ""
                }
                // Add the punctuation as its own token
                result.append(String(char))
            } else {
                currentWord.append(char)
            }
        }
        
        // Add any remaining word
        if !currentWord.isEmpty {
            result.append(currentWord)
        }
        
        return result
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
                return 1.0
            }
        }
        return 1.0
    }
}

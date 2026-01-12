import Foundation

struct TextTokenizer {
    
    /// Tokenize text into words for RSVP display
    static func tokenize(_ text: String) -> [String] {
        // Split by whitespace and newlines
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        
        // Filter empty strings and clean up
        let words = components
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return words
    }
    
    /// Calculate recommended pause multiplier based on punctuation
    /// Returns a multiplier for the display time (1.0 = normal, 1.5 = longer pause)
    static func pauseMultiplier(for word: String) -> Double {
        let lastChar = word.last
        
        // Longer pauses for sentence-ending punctuation
        if let char = lastChar {
            switch char {
            case ".", "!", "?":
                return 1.5
            case ",", ";", ":":
                return 1.25
            case "—", "–":
                return 1.3
            default:
                return 1.0
            }
        }
        return 1.0
    }
}

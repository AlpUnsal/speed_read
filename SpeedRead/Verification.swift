
import Foundation

// Copy of the logic from TextTokenizer.swift for verification
class TextTokenizerVerifier {
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
        
        let speedFactor = min(1.5, max(0.3, 300 / wpm))
        
        if let char = meaningfulChar {
            switch char {
            case ".", "!", "?":
                return 1.0 + (0.65 * speedFactor)
            case ",", ";", ":":
                return 1.0 + (0.50 * speedFactor)
            case "—", "–":
                return 1.0 + (0.55 * speedFactor)
            default:
                return 1.0
            }
        }
        return 1.0
    }
}

// Test Cases
let testCases: [(String, String)] = [
    ("Hello.", "Period"),
    ("Hello!", "Exclamation"),
    ("Hello?", "Question"),
    ("\"Hello,\"", "Comma inside quote"),
    ("\"Hello.\"", "Period inside quote"),
    ("Hello.\"", "Period followed by quote"),
    ("(Hello.)", "Period inside parens"),
    ("Hello", "None")
]

print("Running verification...")
for (word, type) in testCases {
    let multiplier = TextTokenizerVerifier.pauseMultiplier(for: word)
    let isPaused = multiplier > 1.0
    print("'\(word)' (\(type)): \(isPaused ? "PAUSED" : "no pause") (multiplier: \(multiplier))")
    
    if type != "None" && !isPaused {
        print("❌ FAILED: Should have paused")
        exit(1)
    } else if type == "None" && isPaused {
        print("❌ FAILED: Should NOT have paused")
        exit(1)
    }
}
print("✅ All checks passed!")

import Foundation
import UIKit
import NaturalLanguage

// MARK: - Paragraph-Aware Tokenization Types

/// One paragraph's slice of the global word array, plus its display text.
struct ParagraphTokenization: Equatable {
    let paragraphText: String   // trimmed, single \n collapsed to spaces (display text)
    let wordStartIndex: Int     // offset into TokenizedDocument.words
    let wordCount: Int
    let isEmpty: Bool
}

/// Result of tokenizing a document paragraph-by-paragraph: the flat word array
/// (what RSVP plays) and the paragraph boundaries over it (what reading mode
/// renders). The words array is the concatenation of each paragraph's tokens,
/// so both views agree on word indices by construction.
struct TokenizedDocument {
    let words: [String]
    let paragraphs: [ParagraphTokenization]
}

struct TextTokenizer {

    // Shared text checker instance for performance (thread-safe according to Apple docs)
    private static let spellChecker = UITextChecker()

    /// Tokenize text into words for RSVP display
    static func tokenize(_ text: String) -> [String] {
        tokenizeWithRanges(text).map(\.word)
    }

    /// Tokenizes a document paragraph-by-paragraph (split on "\n\n").
    /// Note: unlike whole-text tokenization, a hyphenated word split across a
    /// paragraph boundary is never merged — such splits were already blocked
    /// by empty components in the old whole-text path, so behavior matches.
    static func tokenizeParagraphs(_ text: String) -> TokenizedDocument {
        let rawParagraphs = text.components(separatedBy: "\n\n")
        var words: [String] = []
        var paragraphs: [ParagraphTokenization] = []
        paragraphs.reserveCapacity(rawParagraphs.count)

        for para in rawParagraphs {
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                paragraphs.append(ParagraphTokenization(
                    paragraphText: "",
                    wordStartIndex: words.count,
                    wordCount: 0,
                    isEmpty: true
                ))
                continue
            }

            // Single \n inside a paragraph is source formatting (e.g. <br/>),
            // not a paragraph break — collapse for display, then tokenize the
            // display text itself so tokens and rendered text always align.
            let displayText = trimmed.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
            let tokens = tokenize(displayText)
            paragraphs.append(ParagraphTokenization(
                paragraphText: displayText,
                wordStartIndex: words.count,
                wordCount: tokens.count,
                isEmpty: false
            ))
            words.append(contentsOf: tokens)
        }

        return TokenizedDocument(words: words, paragraphs: paragraphs)
    }

    /// Same tokenization as `tokenize(_:)`, but each token carries its source
    /// range within `text` — used for word hit-testing in reading mode.
    /// Tokens from a hyphenation merge span both source fragments.
    static func tokenizeWithRanges(_ text: String) -> [(word: String, range: Range<String.Index>)] {
        // Scan whitespace-separated components with their source ranges.
        // `adjacentToNext` marks pairs separated by exactly one whitespace
        // character — the only case where the hyphenation merge may fire
        // (wider gaps produced empty components that blocked the merge in the
        // historical components(separatedBy:)-based implementation).
        var components: [(text: String, range: Range<String.Index>, adjacentToNext: Bool)] = []
        var i = text.startIndex
        while i < text.endIndex {
            if isWhitespace(text[i]) {
                i = text.index(after: i)
                continue
            }
            var j = i
            while j < text.endIndex && !isWhitespace(text[j]) {
                j = text.index(after: j)
            }
            var k = j
            var separatorCount = 0
            while k < text.endIndex && isWhitespace(text[k]) {
                separatorCount += 1
                k = text.index(after: k)
            }
            components.append((String(text[i..<j]), i..<j, separatorCount == 1))
            i = k
        }

        var result: [(word: String, range: Range<String.Index>)] = []
        var idx = 0

        while idx < components.count {
            let component = components[idx]

            // Check for line-break hyphenation (e.g. from PDFs or copy-pasted text)
            if component.text.hasSuffix("-"), component.adjacentToNext, idx + 1 < components.count {
                let next = components[idx + 1]
                let firstPart = String(component.text.dropLast())

                // Extract just the letters to form a clean word for dictionary checking
                let firstLetters = firstPart.components(separatedBy: CharacterSet.letters.inverted).joined()
                let secondLetters = next.text.components(separatedBy: CharacterSet.letters.inverted).joined()
                let combinedWord = firstLetters + secondLetters

                if !combinedWord.isEmpty {
                    let range = NSRange(location: 0, length: combinedWord.utf16.count)
                    let misspelledRange = spellChecker.rangeOfMisspelledWord(in: combinedWord, range: range, startingAt: 0, wrap: false, language: "en_US")

                    // If it's a valid dictionary word without hyphens, merge the two components
                    if misspelledRange.location == NSNotFound {
                        let merged = firstPart + next.text
                        // Offsets inside a synthesized merged string can't map back
                        // to the source — every part gets the full union range.
                        let unionRange = component.range.lowerBound..<next.range.upperBound
                        for (part, _) in splitOnPunctuationWithOffsets(merged) {
                            result.append((part, unionRange))
                        }
                        idx += 2
                        continue
                    }
                }
            }

            // Normal tokenization (either no hyphen or not a valid merged word)
            // Split on em dashes, en dashes, and slashes (but NOT hyphens)
            // This keeps genuine compound words like "well-known" separate
            for (part, charRange) in splitOnPunctuationWithOffsets(component.text) {
                let lower = text.index(component.range.lowerBound, offsetBy: charRange.lowerBound)
                let upper = text.index(component.range.lowerBound, offsetBy: charRange.upperBound)
                result.append((part, lower..<upper))
            }
            idx += 1
        }

        return result
    }

    /// A Character counts as whitespace when all its scalars are in
    /// .whitespacesAndNewlines — mirrors components(separatedBy:) for real text.
    private static func isWhitespace(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    /// Split a word on specific separators (em dash, en dash, double hyphen, ellipses)
    /// Attaches the separator to the PRECEDING word.
    /// Keeps slashes combined (does not split).
    /// Each part carries its character-offset range within `text`.
    private static func splitOnPunctuationWithOffsets(_ text: String) -> [(String, Range<Int>)] {
        // If text is short, quick check to avoid processing
        if text.count < 2 {
            return text.isEmpty ? [] : [(text, 0..<text.count)]
        }

        var result: [(String, Range<Int>)] = []
        var currentToken = ""
        var tokenStart = 0

        // We'll advance through the string character by character (or lookahead)
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            // Check for multi-char separators first

            // 1. Double Hyphen "--"
            if char == "-" && i + 1 < chars.count && chars[i+1] == "-" {
                currentToken.append("--")
                result.append((currentToken, tokenStart..<(i + 2)))
                currentToken = ""
                tokenStart = i + 2
                i += 2
                continue
            }

            // 2. Ellipsis "..." (3 dots)
            if char == "." && i + 2 < chars.count && chars[i+1] == "." && chars[i+2] == "." {
                currentToken.append("...")
                result.append((currentToken, tokenStart..<(i + 3)))
                currentToken = ""
                tokenStart = i + 3
                i += 3
                continue
            }

            // 3. Single-char separators: Em dash (—), En dash (–), Ellipsis char (…)
            if char == "\u{2014}" || char == "\u{2013}" || char == "\u{2026}" { // \u{2026} is …
                currentToken.append(char)
                result.append((currentToken, tokenStart..<(i + 1)))
                currentToken = ""
                tokenStart = i + 1
                i += 1
                continue
            }

            // Regular character (including /)
            currentToken.append(char)
            i += 1
        }

        // Append any remaining text
        if !currentToken.isEmpty {
            result.append((currentToken, tokenStart..<chars.count))
        }

        // Filter out empty strings just in case logic produced them
        return result.filter { !$0.0.isEmpty }
    }
    
    /// Calculate total display time in milliseconds for a word, including punctuation pauses.
    /// Uses absolute minimum floors so pauses remain perceptible even at high WPM.
    /// At 300 WPM the feel is identical to the old multiplier approach.
    /// At 600-800+ WPM the floors kick in, guaranteeing a noticeable pause.
    static func pauseDelay(for word: String, wpm: Double = 300) -> Double {
        let base = 60000.0 / wpm

        let meaningfulChar = lastMeaningfulCharacter(of: word)

        // Extra ms to add, with a guaranteed minimum floor
        var extraMs: Double = 0

        if let char = meaningfulChar {
            switch char {
            case ".", "!", "?":
                // Sentence end: at least 170ms extra
                extraMs = max(170, base * 0.65)
            case ",", ";", ":":
                // Comma pause: at least 110ms extra
                extraMs = max(110, base * 0.50)
            case "—", "–":
                // Em/en dash: at least 135ms extra
                extraMs = max(135, base * 0.55)
            default:
                if word.contains("/") {
                    extraMs = max(110, base * 0.50)
                }
            }
        } else if word.contains("/") {
            extraMs = max(80, base * 0.50)
        }

        return base + extraMs
    }

    // Characters that might mask the actual punctuation at the end of a word
    private static let wordClosingPunctuation = CharacterSet(charactersIn: "\"\u{201D}\u{2019}'\u{0027})]}\u{201C}\u{2018}")

    /// Last character of `word` that isn't a closing quote/bracket.
    private static func lastMeaningfulCharacter(of word: String) -> Character? {
        for char in word.reversed() {
            if let scalar = char.unicodeScalars.first, !wordClosingPunctuation.contains(scalar) {
                return char
            }
        }
        return nil
    }

    /// True when the word ends a sentence — ., ! or ?, possibly wrapped in
    /// closing quotes/brackets (e.g. `dog."` or `there!)`).
    static func endsSentence(_ word: String) -> Bool {
        switch lastMeaningfulCharacter(of: word) {
        case ".", "!", "?": return true
        default: return false
        }
    }

    // MARK: - Dialogue Detection

    private static let openingQuotes: Set<Character> = ["\u{201C}", "\u{2018}", "\"", "\u{00AB}"]  // " ' " «
    private static let closingQuotes: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "\u{00BB}"]  // " ' " »

    /// Returns true if the word starts with an opening quote character
    static func startsWithOpeningQuote(_ word: String) -> Bool {
        guard let first = word.first else { return false }
        return openingQuotes.contains(first)
    }

    /// Returns true if the word contains a closing quote (possibly followed by punctuation like ." or ,"")
    static func containsClosingQuote(_ word: String) -> Bool {
        let trailingPunctuation: Set<Character> = [".", ",", "?", "!", ";", ":"]

        // Check characters from the end, skipping trailing punctuation
        for char in word.reversed() {
            if trailingPunctuation.contains(char) {
                continue
            }
            return closingQuotes.contains(char)
        }
        return false
    }

    /// Returns true if the word contains an opening quote character anywhere
    static func containsOpeningQuote(_ word: String) -> Bool {
        return word.contains(where: { openingQuotes.contains($0) })
    }

    /// Reconstructs dialogue state at an arbitrary position — the live state
    /// is a running toggle, so loads and jumps must derive it by scanning
    /// back to the most recent quote-bearing word. Per-word precedence
    /// (closing wins) mirrors updateDialogueState exactly, so ambiguous
    /// straight quotes resolve the same way playback would have.
    static func dialogueState(at index: Int, in words: [String]) -> Bool {
        guard !words.isEmpty else { return false }
        let clamped = max(0, min(index, words.count - 1))
        // Dialogue spans are short; a capped lookback keeps quote-free books
        // from scanning to the start on every jump. Default: not in dialogue.
        let lookbackFloor = max(0, clamped - 3000)
        var i = clamped
        while i >= lookbackFloor {
            let word = words[i]
            if containsClosingQuote(word) { return false }
            if containsOpeningQuote(word) { return true }
            i -= 1
        }
        return false
    }

    /// Calculate extra pause in milliseconds for dialogue transitions.
    /// Returns additional ms to add when the current word closes a quote
    /// and the next word opens a new one (speaker change).
    static func dialogueTransitionDelay(currentWord: String, nextWord: String?, wpm: Double) -> Double {
        guard let next = nextWord else { return 0 }

        let currentClosesQuote = containsClosingQuote(currentWord)
        let nextOpensQuote = startsWithOpeningQuote(next)

        if currentClosesQuote && nextOpensQuote {
            let base = 60000.0 / wpm
            return max(220, base * 0.8)
        }

        return 0
    }

    // MARK: - Smart Pacing (rarity + length pauses)

    /// Dictionary verdicts keyed by normalized word, valid for one spell-check
    /// language at a time (cleared on switch — one document plays at once).
    /// Main-thread only: rarity checks happen exclusively from playback
    /// scheduling.
    private static var rarityCache: [String: Bool] = [:]
    private static var rarityCacheLanguage: String = ""

    /// Dominant language of a document (BCP-47 code like "en", "tr"),
    /// detected from a prefix sample. Nil when detection fails.
    static func detectLanguage(of text: String) -> String? {
        let sample = String(text.prefix(2000))
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage?.rawValue
    }

    /// The device spell-check dictionary matching a detected language code
    /// ("tr" → "tr_TR"), or nil when the device has none — callers should
    /// disable rarity pauses rather than check against the wrong dictionary.
    static func spellCheckLanguage(matching code: String?) -> String? {
        guard let code = code else { return nil }
        let available = UITextChecker.availableLanguages
        if available.contains(code) { return code }
        return available.first { $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
    }

    /// Reduces a display token to a lookup key for rarity checks. Nil for
    /// tokens that should never earn a rarity pause: numbers, single
    /// letters, pure punctuation. Locale-aware lowercasing matters for
    /// languages like Turkish (dotted/dotless i).
    static func rarityKey(for word: String, languageCode: String?) -> String? {
        let code = languageCode ?? "en"
        var w = word.lowercased(with: Locale(identifier: code))
        while let first = w.first, !first.isLetter { w.removeFirst() }
        while let last = w.last, !last.isLetter { w.removeLast() }
        if code.hasPrefix("en"),
           w.hasSuffix("'s") || w.hasSuffix("\u{2019}s") { w = String(w.dropLast(2)) }
        guard w.count >= 2, !w.contains(where: { $0.isNumber }) else { return nil }
        return w
    }

    /// Bundled English word-frequency table: lowercase word → Zipf score
    /// quantized as round(zipf * 20). Loaded once, off-main; nil until then.
    /// Read/written on the main thread only (like rarityCache).
    private static var zipfTable: [String: UInt8]?
    private static var zipfTableLoadStarted = false

    /// Kicks off the one-time background load of the Zipf table. Playback
    /// falls back to the binary dictionary signal until it lands, so there
    /// is no cold-start gap — just Phase-1 behavior for the first moments.
    static func prepareZipfTable() {
        guard !zipfTableLoadStarted else { return }
        zipfTableLoadStarted = true
        DispatchQueue.global(qos: .utility).async {
            guard let url = Bundle.main.url(forResource: "en_zipf", withExtension: "txt"),
                  let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
            var table = [String: UInt8](minimumCapacity: 60_000)
            for line in raw.split(separator: "\n") {
                guard let tab = line.firstIndex(of: "\t"),
                      let score = UInt8(line[line.index(after: tab)...]) else { continue }
                table[String(line[..<tab])] = score
            }
            DispatchQueue.main.async { zipfTable = table }
        }
    }

    /// Graded difficulty weight 0–1 for English words. Zipf ≥ 4.0 (roughly
    /// the top 7k words) never earns a rarity pause; 4.0→2.5 ramps linearly
    /// to full weight. Words below the table's floor fall back to the
    /// system dictionary: present → 0.85 (rare-but-valid, "tenebrous"),
    /// absent → 1.0 (invented names, "Raskolnikov"). Nil until the table
    /// has loaded — callers should use the binary signal meanwhile.
    static func gradedRarityWeight(_ key: String, language: String) -> Double? {
        guard let table = zipfTable else { return nil }
        if let score = table[key] {
            let zipf = Double(score) / 20.0
            if zipf >= 4.0 { return 0 }
            if zipf <= 2.5 { return 1.0 }
            return (4.0 - zipf) / 1.5
        }
        return isRareWord(key, language: language) ? 1.0 : 0.85
    }

    /// True when the word is absent from the system dictionary — a cheap
    /// proxy for rare/unfamiliar (invented names, jargon, foreign words).
    /// The capitalized form is checked too because the dictionary stores
    /// proper nouns capitalized ("July", "Gatsby" pass; "Raskolnikov" fails).
    static func isRareWord(_ key: String, language: String) -> Bool {
        if language != rarityCacheLanguage {
            rarityCache = [:]
            rarityCacheLanguage = language
        }
        if let cached = rarityCache[key] { return cached }
        func inDictionary(_ s: String) -> Bool {
            let range = NSRange(location: 0, length: s.utf16.count)
            return spellChecker.rangeOfMisspelledWord(
                in: s, range: range, startingAt: 0, wrap: false, language: language
            ).location == NSNotFound
        }
        let capitalized = key.capitalized(with: Locale(identifier: language))
        let rare = !inDictionary(key) && !inDictionary(capitalized)
        rarityCache[key] = rare
        return rare
    }

    /// Extra display time for long words — fixation time grows with word
    /// length, and fixed-interval RSVP feels most rushed exactly there.
    /// Language-agnostic. Zero below 8 letters, full weight at 13+.
    static func lengthDelay(for word: String, wpm: Double) -> Double {
        let letters = word.filter(\.isLetter).count
        guard letters >= 8 else { return 0 }
        let weight = min(1.0, Double(letters - 7) / 6.0)
        let base = 60000.0 / wpm
        return min(60, max(30, base * 0.25)) * weight
    }

    /// Extra display time for a rare word, fading as the reader keeps
    /// encountering it in the current document. Capped below the comma
    /// pause so pacing stays subtle rather than stuttery.
    static func rarityDelay(wpm: Double, seenCount: Int) -> Double {
        let familiarity: Double
        switch seenCount {
        case 0...1: familiarity = 1.0
        case 2:     familiarity = 0.6
        case 3:     familiarity = 0.35
        case 4...5: familiarity = 0.15
        default:    return 0
        }
        let base = 60000.0 / wpm
        return min(140, max(60, base * 0.5)) * familiarity
    }
}

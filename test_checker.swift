import AppKit
let checker = NSSpellChecker.shared
func isValidWord(_ word: String) -> Bool {
    let range = NSRange(location: 0, length: word.utf16.count)
    let misspelledRange = checker.checkSpelling(of: word, startingAt: 0, language: "en_US", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
    return misspelledRange.location == NSNotFound
}
let testCases = ["Algorithm", "UNDERSTANDING", "wellknown", "algo-\nrithm"]
for w in testCases {
    print("\(w): \(isValidWord(w))")
}

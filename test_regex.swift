import Foundation

let tag = "science fiction"
let targetGenre = "science fiction"
let pattern = "\\b\(NSRegularExpression.escapedPattern(for: targetGenre))\\b"

print("Pattern: \(pattern)")
let contains = tag.range(of: pattern, options: .regularExpression) != nil
print("Contains: \(contains)")

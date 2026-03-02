import Foundation

let targetGenre = "fantasy"
let isSciFi = false

let allTags = [
    "dracula, count (fictitious character) -- fiction",
    "epistolary fiction",
    "gothic fiction",
    "horror tales",
    "transylvania (romania) -- fiction",
    "vampires -- fiction",
    "whitby (england) -- fiction",
    "category: british literature",
    "category: classics of literature",
    "category: crime, thrillers and mystery",
    "category: novels",
    "category: science-fiction & fantasy",
    "gothic fiction",
    "horror",
    "movie books",
    "mystery fiction"
]

let v = allTags.contains { tag in
    let lowerTag = tag.lowercased()
    
    if lowerTag.contains("category: science-fiction & fantasy") {
        return false
    }
    
    let pattern = "\\b\(NSRegularExpression.escapedPattern(for: targetGenre))\\b"
    let containsTarget = lowerTag.range(of: pattern, options: .regularExpression) != nil
    
    if isSciFi {
        let alternativePattern = "\\bsci-fi\\b"
        return containsTarget || lowerTag.range(of: alternativePattern, options: .regularExpression) != nil
    }
    
    return containsTarget
}

print("Fantasy in Dracula: \(v)")

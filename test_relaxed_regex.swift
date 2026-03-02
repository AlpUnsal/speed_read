import Foundation

let tags = ["american science fiction", "science-fiction", "science fiction", "category: science-fiction & fantasy", "sci fi"]

let targetGenre = "science fiction"
let isSciFi = true

for tag in tags {
    let lowerTag = tag.lowercased()
    
    // Ignore overarching grouping
    if lowerTag.contains("category: science-fiction & fantasy") {
        print("\(tag) -> REJECT (Category)")
        continue
    }
    
    // Relaxed match (substring contains) instead of strict word bounds
    let containsTarget = lowerTag.contains(targetGenre)
    var isMatch = containsTarget
    
    if isSciFi {
        isMatch = isMatch || lowerTag.contains("sci-fi") || lowerTag.contains("sci fi")
    }
    
    print("\(tag) -> \(isMatch ? "MATCH" : "NO MATCH")")
}


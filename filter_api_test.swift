import Foundation

let topic = "Sci-Fi"
let url = URL(string: "https://gutendex.com/books/?languages=en&topic=science%20fiction")!

struct GutenbergBook: Codable {
    let title: String
    let subjects: [String]?
    let bookshelves: [String]?
}
struct Res: Codable { let results: [GutenbergBook] }

let group = DispatchGroup()
group.enter()

URLSession.shared.dataTask(with: url) { data, response, error in
    defer { group.leave() }
    guard let data = data else { print("No data"); return }
    let res = try! JSONDecoder().decode(Res.self, from: data)
    
    print("Fetched \(res.results.count) books")
    
    let isSciFi = topic.lowercased() == "sci-fi"
    let targetGenre = isSciFi ? "science fiction" : topic.lowercased()
    
    let exclusions: [String: [String]] = [
        "sci-fi": ["horror", "fantasy", "gothic", "vampire", "magic", "monster"],
        "science fiction": ["horror", "fantasy", "gothic", "vampire", "magic", "monster"]
    ]
    
    let currentExclusions = exclusions[topic.lowercased()] ?? []
    let currentExclusionsPattern = currentExclusions.map { "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b" }
    
    var finalResults = [GutenbergBook]()
    for book in res.results {
        let allTags = (book.subjects ?? []) + (book.bookshelves ?? [])
        
        let hasExclusion = allTags.contains { tag in
            let lowerTag = tag.lowercased()
            return currentExclusionsPattern.contains { pattern in
                lowerTag.range(of: pattern, options: .regularExpression) != nil
            }
        }
        if hasExclusion { continue }
        
        let hasTarget = allTags.contains { tag in
            let lowerTag = tag.lowercased()
            if lowerTag.contains("category: science-fiction & fantasy") { return false }
            
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: targetGenre))\\b"
            let containsTarget = lowerTag.range(of: pattern, options: .regularExpression) != nil
            
            if isSciFi {
                return containsTarget || lowerTag.range(of: "\\bsci-fi\\b", options: .regularExpression) != nil
            }
            return containsTarget
        }
        
        if hasTarget {
            finalResults.append(book)
        }
    }
    
    print("Final filtered count: \(finalResults.count)")
}.resume()

group.wait()

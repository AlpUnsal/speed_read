import Foundation

struct GutenbergBook: Codable {
    let title: String
    let subjects: [String]?
    let bookshelves: [String]?
}

let booksRaw = """
[
  {
    "title": "Frankenstein",
    "subjects": [
      "Frankenstein's monster (Fictitious character) -- Fiction",
      "Gothic fiction",
      "Horror tales",
      "Science fiction"
    ],
    "bookshelves": [
      "Horror",
      "Precursors of Science Fiction"
    ]
  },
  {
    "title": "The Time Machine",
    "subjects": [
        "Science fiction",
        "Time travel -- Fiction"
    ],
    "bookshelves": [
        "Science Fiction"
    ]
  }
]
"""

let books = try! JSONDecoder().decode([GutenbergBook].self, from: booksRaw.data(using: .utf8)!)

func filterBooks(topic: String, query: String, results: [GutenbergBook]) -> [GutenbergBook] {
    var filteredResults = results
    if !topic.isEmpty, query.isEmpty {
        let isSciFi = topic.lowercased() == "sci-fi"
        let targetGenre = isSciFi ? "science fiction" : topic.lowercased()
        
        let exclusions: [String: [String]] = [
            "sci-fi": ["horror", "fantasy", "gothic", "vampire", "magic", "monster"],
            "science fiction": ["horror", "fantasy", "gothic", "vampire", "magic", "monster"],
            "fantasy": ["horror", "science fiction", "sci-fi", "gothic", "vampire", "space", "alien"],
            "mystery": ["horror", "fantasy", "science fiction", "sci-fi", "romance"],
            "romance": ["horror", "science fiction", "sci-fi"],
            "horror": ["romance"],
            "philosophy": ["fantasy", "science fiction", "sci-fi", "horror", "romance"],
            "history": ["fantasy", "science fiction", "sci-fi", "horror", "romance"]
        ]
        let currentExclusions = exclusions[topic.lowercased()] ?? []
        let currentExclusionsPattern = currentExclusions.map { "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b" }
        
        filteredResults = results.filter { book in
            let allTags = (book.subjects ?? []) + (book.bookshelves ?? [])
            
            // 1. Check exclusions
            let hasExclusion = allTags.contains { tag in
                let lowerTag = tag.lowercased()
                 return currentExclusionsPattern.contains { pattern in
                     lowerTag.range(of: pattern, options: .regularExpression) != nil
                 }
            }
            if hasExclusion { return false }
            
            // 2. We require a STRICT whole-word match on at least one subject/bookshelf
            return allTags.contains { tag in
                let lowerTag = tag.lowercased()
                
                // Ignore Gutendex's overarching, inaccurate groupings
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
        }
    }
    return filteredResults
}

let scifiBooks = filterBooks(topic: "Sci-Fi", query: "", results: books)
print("Sci-Fi books:")
for b in scifiBooks { print("- \(b.title)") }

print("\nHorror books:")
let horrorBooks = filterBooks(topic: "Horror", query: "", results: books)
for b in horrorBooks { print("- \(b.title)") }

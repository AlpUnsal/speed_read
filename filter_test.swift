import Foundation

let jsonStr = """
{
  "count": 100,
  "next": null,
  "previous": null,
  "results": [
    {
      "id": 84,
      "title": "Frankenstein",
      "authors": [],
      "formats": {},
      "download_count": 100,
      "subjects": ["Science fiction", "Horror", "Gothic literature"],
      "bookshelves": []
    },
    {
      "id": 12,
      "title": "A Space Odyssey",
      "authors": [],
      "formats": {},
      "download_count": 100,
      "subjects": ["Science fiction", "Space adventure"],
      "bookshelves": []
    }
  ]
}
"""

struct GutenbergBook: Codable {
    let title: String
    let subjects: [String]?
    let bookshelves: [String]?
}

struct Res: Codable { let results: [GutenbergBook] }

let data = jsonStr.data(using: .utf8)!
let result = try! JSONDecoder().decode(Res.self, from: data)

let topic = "Sci-Fi"
let isSciFi = topic.lowercased() == "sci-fi"
let targetGenre = isSciFi ? "science fiction" : topic.lowercased()

let exclusions: [String: [String]] = [
    "sci-fi": ["horror", "fantasy", "gothic", "vampire", "magic", "monster"],
    "science fiction": ["horror", "fantasy", "gothic", "vampire", "magic", "monster"]
]

let currentExclusions = exclusions[topic.lowercased()] ?? []
let currentExclusionsPattern = currentExclusions.map { "\\b\($0)\\b" }

let start = Date()
var passCount = 0

for book in result.results {
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
        let pattern = "\\b\(targetGenre)\\b"
        let containsTarget = lowerTag.range(of: pattern, options: .regularExpression) != nil
        if isSciFi {
            return containsTarget || lowerTag.range(of: "\\bsci-fi\\b", options: .regularExpression) != nil
        }
        return containsTarget
    }
    
    if hasTarget {
        passCount += 1
        print("Passed: \(book.title)")
    }
}
print("Checked \(result.results.count) books, passed \(passCount) in \(Date().timeIntervalSince(start))s")


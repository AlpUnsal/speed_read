import Foundation

func fetch() async {
    let url = URL(string: "https://gutendex.com/books/?search=frankenstein")!
    let data = try! await URLSession.shared.data(from: url).0
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let results = json["results"] as? [[String: Any]] {
        for book in results.prefix(3) {
            let title = book["title"] as? String ?? ""
            let subjects = book["subjects"] as? [String] ?? []
            let bookshelves = book["bookshelves"] as? [String] ?? []
            print("Title: \(title)")
            print("Tags: \((subjects + bookshelves).joined(separator: ", "))\n")
        }
    }
}
await fetch()

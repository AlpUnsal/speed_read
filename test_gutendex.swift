import Foundation

let semaphore = DispatchSemaphore(value: 0)

Task {
    do {
        let url = URL(string: "https://gutendex.com/books/?languages=en&topic=fantasy")!
        let (data, _) = try await URLSession.shared.data(from: url)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let results = json["results"] as? [[String: Any]] {
            for book in results {
                let title = book["title"] as? String ?? ""
                let subjects = book["subjects"] as? [String] ?? []
                let bookshelves = book["bookshelves"] as? [String] ?? []
                let tags = subjects + bookshelves
                print("Title: \(title)")
                print("Tags: \(tags.joined(separator: ", "))\n")
            }
        }
    } catch {
        print("Error: \(error)")
    }
    semaphore.signal()
}

semaphore.wait()

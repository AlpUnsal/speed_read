import Foundation

struct GutenbergAuthor: Codable {
    let name: String
    let birthYear: Int?
    let deathYear: Int?
    enum CodingKeys: String, CodingKey {
        case name
        case birthYear = "birth_year"
        case deathYear = "death_year"
    }
}

struct GutenbergBook: Codable {
    let id: Int
    let title: String
    let authors: [GutenbergAuthor]
    let formats: [String: String]
    let downloadCount: Int
    let subjects: [String]?
    let bookshelves: [String]?
    enum CodingKeys: String, CodingKey {
        case id, title, authors, formats, subjects, bookshelves
        case downloadCount = "download_count"
    }
}

let path = "/Users/alp/Library/Developer/CoreSimulator/Devices/9D360F7B-5ADC-45B5-88BF-A78C7B0ED134/data/Containers/Data/Application/40C11D5E-0B65-4EAD-9E23-AD056C29FFE8/Documents/genre_cache_fantasy.json"

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    print("Data loaded, bytes: \(data.count)")
    let books = try JSONDecoder().decode([GutenbergBook].self, from: data)
    print("Successfully decoded \(books.count) books")
} catch {
    print("Decoding error: \(error)")
}

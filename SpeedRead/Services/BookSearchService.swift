import Foundation

struct GutendexResponse: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [GutenbergBook]
}

struct GutenbergBook: Codable, Identifiable {
    let id: Int
    let title: String
    let authors: [GutenbergAuthor]
    let formats: [String: String]
    let downloadCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, title, authors, formats
        case downloadCount = "download_count"
    }
    
    private func sanitize(urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        var secureString = trimmed.replacingOccurrences(of: "http://", with: "https://")
        
        if secureString.hasPrefix("//") {
            secureString = "https:" + secureString
        } else if secureString.hasPrefix("/") {
            secureString = "https://www.gutenberg.org" + secureString
        } else if !secureString.hasPrefix("https://") {
            secureString = "https://" + secureString
        }
        
        if let url = URL(string: secureString) {
            return url
        }
        if let encoded = secureString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: encoded)
        }
        return nil
    }

    var epubURL: URL? {
        if let urlString = formats["application/epub+zip"] {
            return sanitize(urlString: urlString)
        }
        return nil
    }
    
    var txtURL: URL? {
        if let urlString = formats["text/plain; charset=us-ascii"] ?? formats["text/plain"] ?? formats["text/plain; charset=utf-8"] {
            return sanitize(urlString: urlString)
        }
        return nil
    }
    
    var bestDownloadURL: URL? {
        epubURL ?? txtURL
    }
    
    var coverURL: URL? {
        if let urlString = formats["image/jpeg"] {
            return sanitize(urlString: urlString)
        }
        return nil
    }
    
    var primaryAuthorName: String {
        guard let author = authors.first else { return "Unknown Author" }
        // Gutenberg authors are often "Last, First" -> Reverse it to "First Last"
        let parts = author.name.components(separatedBy: ", ")
        if parts.count == 2 {
            return "\(parts[1]) \(parts[0])"
        }
        return author.name
    }
}

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

class BookSearchService: ObservableObject {
    @Published var searchResults: [GutenbergBook] = []
    @Published var isSearching = false
    @Published var errorMessage: String? = nil
    
    private let cacheFileName = "gutendex_cache.json"
    private var currentSearchTask: Task<Void, Never>?
    
    private var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(cacheFileName)
    }
    
    init() {
        loadCachedBooks()
    }
    
    private func loadCachedBooks() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        if let cachedResult = try? JSONDecoder().decode(GutendexResponse.self, from: data) {
            self.searchResults = cachedResult.results
        }
    }
    
    private func saveToCache(data: Data) {
        try? data.write(to: cacheURL)
    }
    
    // Default fetch lists popular books
    func fetchPopularBooks() {
        search(query: "")
    }
    
    // Instantly restores the cached popular books, then updates in the background
    func clearSearch() {
        currentSearchTask?.cancel()
        DispatchQueue.main.async {
            self.loadCachedBooks()
            self.isSearching = false
            self.errorMessage = nil
        }
        fetchPopularBooks()
    }
    
    func search(query: String) {
        currentSearchTask?.cancel()
        
        currentSearchTask = Task {
            let isPopularSearch = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            await MainActor.run {
                // Only show the searching spinner if we have no cached results 
                // OR if it's an active custom search that we don't have results for yet.
                if self.searchResults.isEmpty || !isPopularSearch {
                    self.isSearching = true
                }
                self.errorMessage = nil
            }
        
        var components = URLComponents(string: "https://gutendex.com/books/")!
        var queryItems = [URLQueryItem(name: "languages", value: "en")]
        
        if isPopularSearch {
            queryItems.append(URLQueryItem(name: "sort", value: "popular"))
        } else {
            queryItems.append(URLQueryItem(name: "search", value: query))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else {
            if !Task.isCancelled {
                await MainActor.run {
                    self.errorMessage = "Invalid Search Query"
                    self.isSearching = false
                }
            }
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if Task.isCancelled { return }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = "Failed to fetch from server."
                        self.isSearching = false
                    }
                }
                return
            }
            
            let result = try await Task.detached(priority: .userInitiated) {
                return try JSONDecoder().decode(GutendexResponse.self, from: data)
            }.value
            
            if Task.isCancelled { return }
            
            // If it's the popular search, update the persistent cache
            if isPopularSearch {
                self.saveToCache(data: data)
            }
            
            await MainActor.run {
                self.searchResults = result.results
                self.isSearching = false
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) {
                await MainActor.run {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.isSearching = false
                }
            }
        }
    }
}
}


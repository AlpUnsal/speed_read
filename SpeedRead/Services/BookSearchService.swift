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
    let subjects: [String]?
    let bookshelves: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, authors, formats, subjects, bookshelves
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
    
    var primaryGenre: String? {
        let allTags = (subjects ?? []) + (bookshelves ?? [])
        if allTags.isEmpty { return nil }
        
        let preferredGenres = ["Sci-Fi", "Science Fiction", "Fantasy", "Mystery", "Romance", "Philosophy", "History", "Horror", "Thriller", "Adventure", "Poetry", "Drama"]
        
        // 1. Check for strict whole-word matches in our preferred list
        for tag in allTags {
            for preferred in preferredGenres {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: preferred))\\b"
                if tag.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                    if preferred == "Science Fiction" { return "Sci-Fi" }
                    return preferred
                }
            }
        }
        
        // 2. If no preferred match, try to find a short, clean tag (e.g. "Science fiction")
        let cleanTags = allTags.compactMap { tag -> String? in
            // Remove Gutenberg specific classifications like "PS" or "PR"
            if tag.count <= 3 && tag.uppercased() == tag { return nil }
            
            // Exclude overly broad overarching categories
            if tag.lowercased().contains("category:") { return nil }
            
            // Extract before hyphens (e.g., "Science fiction -- History" -> "Science fiction")
            let baseTag = tag.components(separatedBy: " -- ").first ?? tag
            return baseTag.trimmingCharacters(in: .whitespaces)
        }
        
        return cleanTags.min(by: { $0.count < $1.count })
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
    
    // In-memory cache for genre switching so we don't hit the network every time
    private var genreCache: [String: [GutenbergBook]] = [:]
    
    private func cacheURL(for topic: String) -> URL {
        let topicSlug = topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filename = topicSlug.isEmpty ? cacheFileName : "genre_cache_\(topicSlug).json"
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(filename)
    }
    
    init() {
        loadCachedBooks()
    }
    
    // Instantly loads ALL cached genre lists from disk into memory on app launch
    // to guarantee 0.0s render times without hitting Gutendex.
    private func loadCachedBooks() {
        let genres = ["", "Fantasy", "Mystery", "Romance", "Philosophy", "History", "Horror"] // "" represents popular "All" tab
        
        for topic in genres {
            let url = cacheURL(for: topic)
            if let data = try? Data(contentsOf: url) {
                
                // Popular items are historically wrapped in GutendexResponse struct
                // Genre items are saved strictly as [GutenbergBook]
                if topic.isEmpty {
                    // Try to decode as [GutenbergBook] first
                    if let books = try? JSONDecoder().decode([GutenbergBook].self, from: data) {
                        self.searchResults = books
                        self.genreCache[""] = books
                    } else if let cachedResult = try? JSONDecoder().decode(GutendexResponse.self, from: data) {
                        // Fallback constraint if older cache
                        self.searchResults = cachedResult.results
                        self.genreCache[""] = cachedResult.results
                    }
                } else {
                    if let books = try? JSONDecoder().decode([GutenbergBook].self, from: data) {
                        self.genreCache[topic] = books
                    }
                }
            }
        }
    }
    
    private func saveToCache(data: Data, for topic: String? = nil) {
        let cacheKey = topic ?? ""
        let url = cacheURL(for: cacheKey)
        try? data.write(to: url)
        
        // Update user defaults refresh clock
        UserDefaults.standard.set(Date(), forKey: "last_fetch_date_\(cacheKey)")
    }
    
    // Default fetch lists popular books ("All" tab)
    func fetchPopularBooks() {
        search(query: "")
        
        // After starting the popular search, initiate silent preloading for all genres
        let genres = ["Fantasy", "Mystery", "Romance", "Philosophy", "History", "Horror"]
        preloadGenres(topics: genres)
    }
    
    private func preloadGenres(topics: [String]) {
        Task.detached(priority: .background) {
            for topic in topics {
                // If we don't have it in memory yet, it means it wasn't on disk either.
                // Or if it's explicitly older than 7 days, we need to refresh it anyway.
                let cacheKey = "last_fetch_date_\(topic)"
                let shouldFetch: Bool
                
                if self.genreCache[topic] == nil {
                    shouldFetch = true
                } else if let lastFetch = UserDefaults.standard.object(forKey: cacheKey) as? Date,
                          let days = Calendar.current.dateComponents([.day], from: lastFetch, to: Date()).day,
                          days >= 7 { // Expire cache after 7 days
                    shouldFetch = true
                } else {
                    shouldFetch = false
                }
                
                if shouldFetch {
                    // Wait 1.5 seconds before dispatching the next silent request
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run {
                        self.search(query: "", topic: topic, silent: true)
                    }
                }
            }
        }
    }
    
    func clearSearch() {
        currentSearchTask?.cancel()
        DispatchQueue.main.async {
            self.loadCachedBooks()
            self.isSearching = false
            self.errorMessage = nil
            
            // Re-trigger the background pre-fetch mechanic to ensure 7-day TTL expiration check is run natively
            let genres = ["Fantasy", "Mystery", "Romance", "Philosophy", "History", "Horror"]
            self.preloadGenres(topics: genres)
            
            // Also explicitly check expiration for the popular ("") tab in the background without blocking the UI
            Task.detached(priority: .background) {
                let cacheKey = "last_fetch_date_"
                var shouldFetch = false
                
                if let lastFetch = UserDefaults.standard.object(forKey: cacheKey) as? Date,
                   let days = Calendar.current.dateComponents([.day], from: lastFetch, to: Date()).day,
                   days >= 7 { // Expire cache after 7 days
                    shouldFetch = true
                }
                
                if shouldFetch {
                    await MainActor.run {
                        self.search(query: "", topic: nil, silent: true)
                    }
                }
            }
        }
    }
    
    func search(query: String, topic: String? = nil, silent: Bool = false) {
        if !silent {
            currentSearchTask?.cancel()
        }
        
        let isPopularSearch = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && topic == nil
        
        // 1. Check Cache first (if it's a pure topic or popular search)
        let cacheKey = topic ?? ""
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let cached = genreCache[cacheKey] {
                if !silent {
                    self.searchResults = cached
                    self.isSearching = false
                    self.errorMessage = nil
                }
                return
            }
        }
        
        let searchTask = Task {
            if !silent {
                await MainActor.run {
                    self.isSearching = true
                    self.errorMessage = nil
                }
            }
            
        
            do {
                var allResults: [GutenbergBook] = []
                let apiTopic = (topic?.lowercased() == "sci-fi") ? "science fiction" : topic
                let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                
                @Sendable func fetchBooks(from components: URLComponents) async throws -> GutendexResponse? {
                    guard let url = components.url else { return nil }
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if Task.isCancelled && !silent { return nil }
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    return try await Task.detached(priority: silent ? .background : .userInitiated) {
                        return try JSONDecoder().decode(GutendexResponse.self, from: data)
                    }.value
                }
                
                if isPopularSearch {
                    var components = URLComponents(string: "https://gutendex.com/books/")!
                    components.queryItems = [
                        URLQueryItem(name: "languages", value: "en"),
                        URLQueryItem(name: "sort", value: "popular")
                    ]
                    if let response = try await fetchBooks(from: components) {
                        allResults = response.results
                    }
                } else if cleanQuery.isEmpty {
                    var components = URLComponents(string: "https://gutendex.com/books/")!
                    components.queryItems = [
                        URLQueryItem(name: "languages", value: "en")
                    ]
                    if let filterTopic = apiTopic, !filterTopic.isEmpty {
                        components.queryItems?.append(URLQueryItem(name: "topic", value: filterTopic))
                    }
                    if let response = try await fetchBooks(from: components) {
                        allResults = response.results
                    }
                } else {
                    async let searchResponse: GutendexResponse? = {
                        var components = URLComponents(string: "https://gutendex.com/books/")!
                        components.queryItems = [
                            URLQueryItem(name: "languages", value: "en"),
                            URLQueryItem(name: "search", value: cleanQuery)
                        ]
                        return try? await fetchBooks(from: components)
                    }()
                    
                    async let topicResponse: GutendexResponse? = {
                        var components = URLComponents(string: "https://gutendex.com/books/")!
                        components.queryItems = [
                            URLQueryItem(name: "languages", value: "en"),
                            URLQueryItem(name: "topic", value: cleanQuery)
                        ]
                        return try? await fetchBooks(from: components)
                    }()
                    
                    let (sRes, tRes) = await (searchResponse, topicResponse)
                    if Task.isCancelled && !silent { return }
                    
                    var seenIds = Set<Int>()
                    if let s = sRes {
                        for book in s.results {
                            if seenIds.insert(book.id).inserted {
                                allResults.append(book)
                            }
                        }
                    }
                    if let t = tRes {
                        for book in t.results {
                            if seenIds.insert(book.id).inserted {
                                allResults.append(book)
                            }
                        }
                    }
                    
                    if sRes == nil && tRes == nil {
                        throw URLError(.badServerResponse)
                    }
                }
                
                if Task.isCancelled && !silent { return }
                
                // If it's pure topic/popular search with no text query, store it in memory & disk!
                let targetTopic = topic ?? ""
                
                // Filter results strictly for the topic since Gutenberg API can be overly broad
                let finalFilteredResults: [GutenbergBook]
                if let topic = topic, !topic.isEmpty, cleanQuery.isEmpty {
                let isSciFi = topic.lowercased() == "sci-fi"
                let targetGenre = isSciFi ? "science fiction" : topic.lowercased()
                
                // Define exclusions to prevent genre bleed (e.g., Horror showing up in Sci-Fi for Frankenstein)
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
                let exclusionRegexes = currentExclusions.compactMap {
                    try? NSRegularExpression(pattern: "\\b\($0)\\b", options: .caseInsensitive)
                }
                
                finalFilteredResults = allResults.filter { book in
                    let allTags = (book.subjects ?? []) + (book.bookshelves ?? [])
                    
                    // 1. Check if the book contains any excluded tags for this genre
                    let hasExclusion = allTags.contains { tag in
                        let nsTag = tag as NSString
                        let fullRange = NSRange(location: 0, length: nsTag.length)
                        return exclusionRegexes.contains { regex in
                            regex.firstMatch(in: tag, options: [], range: fullRange) != nil
                        }
                    }
                    if hasExclusion { return false }
                    
                    // 2. We use relaxed matching logic for finding the genre
                    return allTags.contains { tag in
                        let lowerTag = tag.lowercased()
                        
                        // Ignore Gutendex's overarching, inaccurate groupings
                        if lowerTag.contains("category: science-fiction & fantasy") {
                            return false
                        }
                        
                        let containsTarget = lowerTag.contains(targetGenre)
                        
                        if isSciFi {
                            return containsTarget || lowerTag.contains("sci-fi") || lowerTag.contains("sci fi")
                        }
                        
                        return containsTarget
                    }
                }
            } else {
                finalFilteredResults = allResults
            }
            
            await MainActor.run {
                // If it's pure topic/popular search with no text query, store it in memory and persistent disk
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.genreCache[cacheKey] = finalFilteredResults
                    if let finalData = try? JSONEncoder().encode(finalFilteredResults) {
                        self.saveToCache(data: finalData, for: targetTopic)
                    }
                }
                
                if !silent {
                    self.searchResults = finalFilteredResults
                    self.isSearching = false
                }
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && !silent {
                await MainActor.run {
                    self.errorMessage = "Error: \(error.localizedDescription)"
                    self.isSearching = false
                }
            }
        }
        }
        
        if !silent {
            currentSearchTask = searchTask
        }
    }
}

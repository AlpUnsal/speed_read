import Foundation

class MockService {
    var isSearching = false
    var genreCache: [String: [String]] = [:]
    
    func search(topic: String) {
        if let cached = genreCache[topic] {
            print("CACHE HIT! Found \(cached.count) items")
            isSearching = false
            return
        }
        print("CACHE MISS. Fetching from network...")
        isSearching = true
        
        // Simulating 0 results network fetch
        genreCache[topic] = []
        isSearching = false
    }
}

let svc = MockService()
svc.search(topic: "Sci-Fi") // Miss
svc.search(topic: "Sci-Fi") // Hit!

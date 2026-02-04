import Foundation

/// Represents a document in the user's reading library
struct ReadingDocument: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var currentWordIndex: Int
    var totalWords: Int
    var lastReadDate: Date
    var wordsPerMinute: Double
    var sourceBookmark: Data?  // Security-scoped bookmark for thumbnail generation
    var navigationPoints: [NavigationPoint]  // Chapter/page navigation points
    
    var progress: Double {
        guard totalWords > 0 else { return 0 }
        return Double(currentWordIndex) / Double(totalWords)
    }
    
    var isComplete: Bool {
        currentWordIndex >= totalWords - 1
    }
    
    /// Current navigation point based on word index
    var currentNavigationPoint: NavigationPoint? {
        navigationPoints.first { $0.contains(wordIndex: currentWordIndex) }
    }
    
    /// Label for current section (e.g., "Page 12 of 45" or "Ch. 3: Discovery")
    var currentSectionLabel: String {
        guard let current = currentNavigationPoint,
              let index = navigationPoints.firstIndex(where: { $0.id == current.id }) else {
            return "Page 1 of 1"
        }
        
        if current.type == .chapter {
            return current.title
        } else {
            return "Page \(index + 1) of \(navigationPoints.count)"
        }
    }
    
    init(name: String, content: String, sourceBookmark: Data? = nil, navigationPoints: [NavigationPoint]? = nil) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.currentWordIndex = 0
        self.totalWords = TextTokenizer.tokenize(content).count
        self.lastReadDate = Date()
        self.wordsPerMinute = 300
        self.sourceBookmark = sourceBookmark
        
        // Use provided navigation points, or generate page-based navigation
        if let navPoints = navigationPoints, !navPoints.isEmpty {
            self.navigationPoints = navPoints
        } else {
            self.navigationPoints = PageChunker.createPages(from: content)
        }
    }
    
    // Custom decoding to handle documents without navigationPoints (migration)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        content = try container.decode(String.self, forKey: .content)
        currentWordIndex = try container.decode(Int.self, forKey: .currentWordIndex)
        totalWords = try container.decode(Int.self, forKey: .totalWords)
        lastReadDate = try container.decode(Date.self, forKey: .lastReadDate)
        wordsPerMinute = try container.decode(Double.self, forKey: .wordsPerMinute)
        sourceBookmark = try container.decodeIfPresent(Data.self, forKey: .sourceBookmark)
        
        // Handle migration: generate pages if navigationPoints missing
        if let navPoints = try container.decodeIfPresent([NavigationPoint].self, forKey: .navigationPoints), !navPoints.isEmpty {
            navigationPoints = navPoints
        } else {
            navigationPoints = PageChunker.createPages(from: content)
        }
    }
}

/// Manages the user's document library with persistence
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    @Published var documents: [ReadingDocument] = []
    
    private let storageKey = "SpeedReadLibrary"
    private let appGroupIdentifier = "group.com.alpunsal.axilo"
    
    private init() {
        loadDocuments()
        
        // Observe changes from other processes (Share Extension)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeExternalUserDefaults), name: UserDefaults.didChangeNotification, object: nil)
    }
    
    @objc private func didChangeExternalUserDefaults() {
        loadDocuments()
    }
    
    // MARK: - Public Methods
    
    /// Add a new document to the library or update existing one with same name
    /// - Parameters:
    ///   - name: Document name
    ///   - content: Parsed text content
    ///   - sourceBookmark: Pre-created bookmark data for thumbnail generation
    func addDocument(name: String, content: String, sourceBookmark: Data? = nil) -> ReadingDocument {
        // Check if document with same name exists
        if let existingIndex = documents.firstIndex(where: { $0.name == name }) {
            // Update content but keep progress if content is the same
            if documents[existingIndex].content == content {
                documents[existingIndex].lastReadDate = Date()
                // Update bookmark if we have a new one
                if let bookmark = sourceBookmark {
                    documents[existingIndex].sourceBookmark = bookmark
                }
                saveDocuments()
                return documents[existingIndex]
            } else {
                // Content changed, reset progress
                let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark)
                documents[existingIndex] = newDoc
                saveDocuments()
                return newDoc
            }
        } else {
            // Add new document
            let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark)
            documents.insert(newDoc, at: 0)
            saveDocuments()
            return newDoc
        }
    }
    
    /// Update reading progress for a document
    func updateProgress(for documentId: UUID, wordIndex: Int, wpm: Double) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            documents[index].currentWordIndex = wordIndex
            documents[index].wordsPerMinute = wpm
            documents[index].lastReadDate = Date()
            saveDocuments()
        }
    }
    
    /// Reset progress for a document
    func resetProgress(for documentId: UUID) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            documents[index].currentWordIndex = 0
            documents[index].lastReadDate = Date()
            saveDocuments()
        }
    }
    
    /// Delete a document from the library
    func deleteDocument(_ document: ReadingDocument) {
        documents.removeAll { $0.id == document.id }
        saveDocuments()
    }
    
    /// Get a document by ID
    func getDocument(id: UUID) -> ReadingDocument? {
        return documents.first { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
    
    private func saveDocuments() {
        if let encoded = try? JSONEncoder().encode(documents) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadDocuments() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
            documents = decoded
        }
    }
}

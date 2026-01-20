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
    
    var progress: Double {
        guard totalWords > 0 else { return 0 }
        return Double(currentWordIndex) / Double(totalWords)
    }
    
    var isComplete: Bool {
        currentWordIndex >= totalWords - 1
    }
    
    init(name: String, content: String) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.currentWordIndex = 0
        self.totalWords = TextTokenizer.tokenize(content).count
        self.lastReadDate = Date()
        self.wordsPerMinute = 300
    }
}

/// Manages the user's document library with persistence
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    @Published var documents: [ReadingDocument] = []
    
    private let storageKey = "SpeedReadLibrary"
    private let appGroupIdentifier = "group.com.alpunsal.speedread"
    
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
    func addDocument(name: String, content: String) -> ReadingDocument {
        // Check if document with same name exists
        if let existingIndex = documents.firstIndex(where: { $0.name == name }) {
            // Update content but keep progress if content is the same
            if documents[existingIndex].content == content {
                documents[existingIndex].lastReadDate = Date()
                saveDocuments()
                return documents[existingIndex]
            } else {
                // Content changed, reset progress
                let newDoc = ReadingDocument(name: name, content: content)
                documents[existingIndex] = newDoc
                saveDocuments()
                return newDoc
            }
        } else {
            // Add new document
            let newDoc = ReadingDocument(name: name, content: content)
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

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
        refresh()
    }
    

    
    // MARK: - Public Methods
    
    /// Add a new document to the library or update existing one with same name
    /// - Parameters:
    ///   - name: Document name
    ///   - content: Parsed text content
    ///   - sourceBookmark: Pre-created bookmark data for thumbnail generation
    /// Add a new document to the library or update existing one with same name
    /// - Parameters:
    ///   - name: Document name
    ///   - content: Parsed text content
    ///   - sourceBookmark: Pre-created bookmark data for thumbnail generation
    ///   - navigationPoints: Optional list of navigation points (chapters/sections)
    func addDocument(name: String, content: String, sourceBookmark: Data? = nil, navigationPoints: [NavigationPoint]? = nil) -> ReadingDocument {
        // Check if document with same name exists
        if let existingIndex = documents.firstIndex(where: { $0.name == name }) {
            // Update content but keep progress if content is the same
            if documents[existingIndex].content == content {
                documents[existingIndex].lastReadDate = Date()
                // Update bookmark if we have a new one
                if let bookmark = sourceBookmark {
                    documents[existingIndex].sourceBookmark = bookmark
                }
                // Update navigation points if provided
                if let navPoints = navigationPoints {
                    documents[existingIndex].navigationPoints = navPoints
                }
                saveDocuments()
                return documents[existingIndex]
            } else {
                // Content changed, reset progress
                let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark, navigationPoints: navigationPoints)
                documents[existingIndex] = newDoc
                saveDocuments()
                return newDoc
            }
        } else {
            // Add new document
            let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark, navigationPoints: navigationPoints)
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
    
    private var libraryFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("library.json")
    }
    
    private var inboxURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Inbox")
    }
    
    private func saveDocuments() {
        guard let url = libraryFileURL else { return }
        do {
            let data = try JSONEncoder().encode(documents)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("Error saving library: \(error)")
        }
    }
    
    public func refresh() {
        guard let url = libraryFileURL else { return }
        
        // 1. Try loading from file
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
            documents = decoded
        } else {
            // 2. Migration: Check UserDefaults (Fallback)
            let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
            if let data = defaults.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
                print("Migrating from UserDefaults to File Storage...")
                documents = decoded
                saveDocuments()
            }
        }
        
        // 3. Process Inbox (Merge new items from Share Extension)
        processInbox()
    }
    
    // MARK: - Inbox Pattern (Share Extension Support)
    
    /// Save a document to the Inbox folder (for Share Extension)
    /// This avoids loading the entire library in memory-constrained extensions
    /// STATIC version to avoid initializing the full library
    static func saveToInbox(_ document: ReadingDocument) {
        let appGroupIdentifier = "group.com.alpunsal.axilo"
        guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?.appendingPathComponent("Inbox") else { return }
        
        do {
            // Ensure Inbox exists
            if !FileManager.default.fileExists(atPath: inbox.path) {
                try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            }
            
            let fileURL = inbox.appendingPathComponent("\(document.id.uuidString).json")
            let data = try JSONEncoder().encode(document)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            print("Saved to Inbox: \(fileURL.lastPathComponent)")
        } catch {
            print("Error saving to Inbox: \(error)")
        }
    }
    
    /// Save a document to the Inbox folder (Instance method wrapper)
    func saveToInbox(_ document: ReadingDocument) {
        Self.saveToInbox(document)
    }
    
    /// Merge files from Inbox into the main library
    func processInbox() {
        guard let inbox = inboxURL else { return }
        
        // Ensure Inbox exists
        if !FileManager.default.fileExists(atPath: inbox.path) {
            return
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
            var newDocs: [ReadingDocument] = []
            
            for url in fileURLs {
                if url.pathExtension == "json" {
                    do {
                        let data = try Data(contentsOf: url)
                        let doc = try JSONDecoder().decode(ReadingDocument.self, from: data)
                        newDocs.append(doc)
                        
                        // Delete processed file
                        try FileManager.default.removeItem(at: url)
                        print("Processed and deleted inbox item: \(doc.name)")
                    } catch {
                        print("Failed to process inbox item at \(url): \(error)")
                    }
                }
            }
            
            if !newDocs.isEmpty {
                // Merge into main documents
                // We add them to the top
                for doc in newDocs {
                    // Avoid duplicates by ID or Name
                    if !documents.contains(where: { $0.id == doc.id || ($0.name == doc.name && $0.content == doc.content) }) {
                        documents.insert(doc, at: 0)
                    }
                }
                saveDocuments()
            }
        } catch {
            print("Error processing Inbox: \(error)")
        }
    }
}

import Foundation

/// Represents a document in the user's reading library
struct ReadingDocument: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var originalName: String?
    var excerpt: String
    var currentWordIndex: Int
    var totalWords: Int
    var lastReadDate: Date
    var wordsPerMinute: Double
    var sourceBookmark: Data?  // Security-scoped bookmark for thumbnail generation
    var navigationPoints: [NavigationPoint]  // Chapter/page navigation points
    
    // Used ONLY during migration from old JSON format, ignored during encoding
    var migrationContent: String?
    
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
        self.originalName = name
        
        // Generate excerpt
        let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let excerptWords = Array(words.prefix(12))
        let text = excerptWords.joined(separator: " ")
        self.excerpt = text.count > 60 ? String(text.prefix(60)) + "..." : text
        
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
    
    enum CodingKeys: String, CodingKey {
        case id, name, originalName, excerpt, currentWordIndex, totalWords, lastReadDate, wordsPerMinute, sourceBookmark, navigationPoints
        // migrationContent is intentionally omitted so it doesn't get saved back to JSON
    }
    
    // Custom decoding to handle documents without navigationPoints (migration)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        originalName = try container.decodeIfPresent(String.self, forKey: .originalName)
        
        // Fallback for excerpt: check if it has the new property, or try to glean from old content
        if let decodedExcerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) {
            excerpt = decodedExcerpt
        } else {
            excerpt = "" // Will be populated during migration
        }
        
        currentWordIndex = try container.decode(Int.self, forKey: .currentWordIndex)
        totalWords = try container.decode(Int.self, forKey: .totalWords)
        lastReadDate = try container.decode(Date.self, forKey: .lastReadDate)
        wordsPerMinute = try container.decode(Double.self, forKey: .wordsPerMinute)
        sourceBookmark = try container.decodeIfPresent(Data.self, forKey: .sourceBookmark)
        
        // Handle migration: generate pages if navigationPoints missing
        if let navPoints = try container.decodeIfPresent([NavigationPoint].self, forKey: .navigationPoints), !navPoints.isEmpty {
            navigationPoints = navPoints
        } else {
            navigationPoints = [] // Will be populated during migration if empty
        }
        
        // Migration support: decode old 'content' key using a dynamic coding key
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
        if let oldContent = try dynamicContainer.decodeIfPresent(String.self, forKey: DynamicCodingKeys(stringValue: "content")!) {
            self.migrationContent = oldContent
            
            // If we didn't have an excerpt, generate it now from the old content
            if excerpt.isEmpty {
                let words = oldContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let excerptWords = Array(words.prefix(12))
                let text = excerptWords.joined(separator: " ")
                excerpt = text.count > 60 ? String(text.prefix(60)) + "..." : text
            }
            
            // If we didn't have navigation points, generate them now
            if navigationPoints.isEmpty {
                navigationPoints = PageChunker.createPages(from: oldContent)
            }
        }
    }
    
    struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// Manages the user's document library with persistence
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    @Published var documents: [ReadingDocument] = []
    
    private let storageKey = "SpeedReadLibrary"
    private let appGroupIdentifier = "group.com.alpunsal.axilo"
    
    // Background saving queue & debouncer
    private let saveQueue = DispatchQueue(label: "com.alpunsal.axilo.librarySaveQueue", qos: .background)
    private var saveWorkItem: DispatchWorkItem?
    
    private init() {
        refresh()
    }
    

    
    // MARK: - Public Methods
    
    /// Add a new document to the library or update existing one with same name
    /// - Parameters:
    ///   - name: Document name
    ///   - content: Parsed text content
    ///   - sourceBookmark: Pre-created bookmark data for thumbnail generation
    ///   - navigationPoints: Optional list of navigation points (chapters/sections)
    func addDocument(name: String, content: String, sourceBookmark: Data? = nil, navigationPoints: [NavigationPoint]? = nil) -> ReadingDocument {
        // Check if document with same name exists
        if let existingIndex = documents.firstIndex(where: { $0.name == name }) {
            // Check if content is the same (by comparing excerpt and total words for now)
            let isSameContent = documents[existingIndex].totalWords == TextTokenizer.tokenize(content).count
            if isSameContent {
                documents[existingIndex].lastReadDate = Date()
                // Update bookmark if we have a new one
                if let bookmark = sourceBookmark {
                    documents[existingIndex].sourceBookmark = bookmark
                }
                // Update navigation points if provided
                if let navPoints = navigationPoints {
                    documents[existingIndex].navigationPoints = navPoints
                }
                
                // Move updated document to the front
                let updatedDoc = documents.remove(at: existingIndex)
                documents.insert(updatedDoc, at: 0)
                
                saveDocuments()
                saveContent(content, for: documents[0].id)
                return documents[0]
            } else {
                // Content changed, reset progress
                let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark, navigationPoints: navigationPoints)
                let oldId = documents[existingIndex].id
                documents.remove(at: existingIndex)
                documents.insert(newDoc, at: 0)
                saveDocuments()
                saveContent(content, for: newDoc.id)
                deleteContent(for: oldId)
                return newDoc
            }
        } else {
            // Add new document
            let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark, navigationPoints: navigationPoints)
            documents.insert(newDoc, at: 0)
            saveDocuments()
            saveContent(content, for: newDoc.id)
            return newDoc
        }
    }
    
    /// Update reading progress for a document
    func updateProgress(for documentId: UUID, wordIndex: Int, wpm: Double) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            let hasChanged = documents[index].currentWordIndex != wordIndex || documents[index].wordsPerMinute != wpm
            
            // Always update last read date when progress is updated
            documents[index].lastReadDate = Date()
            
            if hasChanged {
                documents[index].currentWordIndex = wordIndex
                documents[index].wordsPerMinute = wpm
            }
            
            // Move updated document to the front
            if index != 0 {
                let updatedDoc = documents.remove(at: index)
                documents.insert(updatedDoc, at: 0)
                saveDocumentsAsync()
            } else if hasChanged {
                saveDocumentsAsync() // Use debounced async save
            }
        }
    }
    
    /// Reset progress for a document
    func resetProgress(for documentId: UUID) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            documents[index].currentWordIndex = 0
            documents[index].lastReadDate = Date()
            
            // Move updated document to the front
            if index != 0 {
                let updatedDoc = documents.remove(at: index)
                documents.insert(updatedDoc, at: 0)
            }
            
            saveDocuments()
        }
    }
    
    /// Delete a document from the library
    func deleteDocument(_ document: ReadingDocument) {
        documents.removeAll { $0.id == document.id }
        saveDocuments()
        deleteContent(for: document.id)
    }
    
    /// Rename a document
    func renameDocument(id: UUID, newName: String) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].name = newName
            saveDocumentsAsync()
        }
    }
    
    /// Get a document by ID
    func getDocument(id: UUID) -> ReadingDocument? {
        return documents.first { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private var libraryFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("library.json")
    }
    
    private var inboxURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Inbox")
    }
    
    private var contentDirectoryURL: URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        let url = groupURL.appendingPathComponent("Content")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    // MARK: - Content Management
    
    func saveContent(_ content: String, for documentId: UUID) {
        guard let dir = contentDirectoryURL else { return }
        let fileURL = dir.appendingPathComponent("\(documentId.uuidString).txt")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save content for \(documentId): \(error)")
        }
    }
    
    func loadContent(for documentId: UUID) -> String? {
        guard let dir = contentDirectoryURL else { return nil }
        let fileURL = dir.appendingPathComponent("\(documentId.uuidString).txt")
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            print("Failed to load content for \(documentId): \(error)")
            return nil
        }
    }
    
    private func deleteContent(for documentId: UUID) {
        guard let dir = contentDirectoryURL else { return }
        let fileURL = dir.appendingPathComponent("\(documentId.uuidString).txt")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Document Saving
    
    private func saveDocuments() {
        guard let url = libraryFileURL else { return }
        do {
            let data = try JSONEncoder().encode(documents)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("Library synchronously saved to disk.")
        } catch {
            print("Error saving library: \(error)")
        }
    }
    
    /// Debounced asynchronous save to prevent UI freezes
    func saveDocumentsAsync() {
        // Cancel previous pending save
        saveWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Create a discrete snapshot of the documents array to save
            let documentsSnapshot = self.documents
            
            guard let url = self.libraryFileURL else { return }
            do {
                let data = try JSONEncoder().encode(documentsSnapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                print("Library asynchronously saved to disk.")
            } catch {
                print("Error async saving library: \(error)")
            }
        }
        
        saveWorkItem = workItem
        // Debounce by 2 seconds
        saveQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    /// Force an immediate synchronous save (vital for app termination/backgrounding)
    func forceSave() {
        saveWorkItem?.cancel()
        saveDocuments()
    }
    
    public func refresh() {
        guard let url = libraryFileURL else { return }
        
        var needsMigrationSave = false
        
        // 1. Try loading from file
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
            documents = decoded.sorted(by: { $0.lastReadDate > $1.lastReadDate })
        } else {
            // 2. Migration: Check UserDefaults (Fallback)
            let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
            if let data = defaults.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
                print("Migrating from UserDefaults to File Storage...")
                documents = decoded.sorted(by: { $0.lastReadDate > $1.lastReadDate })
                needsMigrationSave = true
            }
        }
        
        // 2.5 Process Migration (extract legacy content out of JSON and into separate files)
        for i in 0..<documents.count {
            if let migrationContent = documents[i].migrationContent {
                print("Migrating rich content for \(documents[i].name) out of database...")
                saveContent(migrationContent, for: documents[i].id)
                documents[i].migrationContent = nil
                needsMigrationSave = true
            }
        }
        
        if needsMigrationSave {
            saveDocuments()
        }
        
        // 3. Process Inbox (Merge new items from Share Extension)
        processInbox()
    }
    
    // MARK: - Inbox Pattern (Share Extension Support)
    
    /// Save a document to the Inbox folder (for Share Extension)
    /// This avoids loading the entire library in memory-constrained extensions
    /// STATIC version to avoid initializing the full library
    static func saveToInbox(_ document: ReadingDocument, content: String) {
        let appGroupIdentifier = "group.com.alpunsal.axilo"
        guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?.appendingPathComponent("Inbox") else { return }
        
        do {
            // Ensure Inbox exists
            if !FileManager.default.fileExists(atPath: inbox.path) {
                try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            }
            
            let fileURL = inbox.appendingPathComponent("\(document.id.uuidString).json")
            let contentURL = inbox.appendingPathComponent("\(document.id.uuidString).txt")
            
            let data = try JSONEncoder().encode(document)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try content.write(to: contentURL, atomically: true, encoding: .utf8)
            print("Saved to Inbox: \(fileURL.lastPathComponent)")
        } catch {
            print("Error saving to Inbox: \(error)")
        }
    }
    
    /// Save a document to the Inbox folder (Instance method wrapper)
    func saveToInbox(_ document: ReadingDocument, content: String) {
        Self.saveToInbox(document, content: content)
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
            var newDocs: [(doc: ReadingDocument, content: String)] = []
            
            for url in fileURLs {
                if url.pathExtension == "json" {
                    let contentURL = url.deletingPathExtension().appendingPathExtension("txt")
                    do {
                        let data = try Data(contentsOf: url)
                        let doc = try JSONDecoder().decode(ReadingDocument.self, from: data)
                        if FileManager.default.fileExists(atPath: contentURL.path) {
                             let content = try String(contentsOf: contentURL, encoding: .utf8)
                             newDocs.append((doc, content))
                             try FileManager.default.removeItem(at: contentURL)
                        } else {
                             // Fallback if content file doesn't exist
                             newDocs.append((doc, doc.excerpt))
                        }
                        
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
                for item in newDocs {
                    let doc = item.doc
                    // Save content
                    saveContent(item.content, for: doc.id)
                    // Avoid duplicates by ID or Name
                    if let existingIndex = documents.firstIndex(where: { $0.id == doc.id || $0.name == doc.name }) {
                        var updatedDoc = documents[existingIndex]
                        updatedDoc.lastReadDate = Date()
                        documents.remove(at: existingIndex)
                        documents.insert(updatedDoc, at: 0)
                    } else {
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

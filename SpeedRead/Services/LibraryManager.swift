import Foundation
import UIKit

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
    var figureAnnotations: [FigureAnnotation]  // Extracted figure/exhibit annotations
    var folderId: UUID? // Optional folder reference
    var hasBeenOpened: Bool // Whether the user has opened the book at least once
    var hiddenFromRecents: Bool // Whether the user has dismissed this from the Recents section
    var positionHistory: [PositionSnapshot] // Recent jump departures / reading checkpoints
    var readerMode: ReaderMode? // Per-document override; nil = use SettingsManager default
    var rarityFamiliarity: [String: Int]? // Smart pacing: per-word sighting counts for rare words

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

    /// Insert a new snapshot, dropping entries within 50 words of it and
    /// keeping at most 10, newest first.
    /// Keep constants in sync with RSVPViewModel.historyDedupeWindow/historyCap.
    mutating func recordPositionSnapshot(_ snapshot: PositionSnapshot) {
        positionHistory.removeAll { abs($0.wordIndex - snapshot.wordIndex) < 50 }
        positionHistory.insert(snapshot, at: 0)
        if positionHistory.count > 10 {
            positionHistory = Array(positionHistory.prefix(10))
        }
    }

    init(name: String, content: String, sourceBookmark: Data? = nil, navigationPoints: [NavigationPoint]? = nil, figureAnnotations: [FigureAnnotation] = [], folderId: UUID? = nil) {
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
        self.figureAnnotations = figureAnnotations
        self.folderId = folderId
        self.hasBeenOpened = false
        self.hiddenFromRecents = false
        self.positionHistory = []
        self.readerMode = nil
        self.rarityFamiliarity = nil

        // Use provided navigation points, or generate page-based navigation
        if let navPoints = navigationPoints, !navPoints.isEmpty {
            self.navigationPoints = navPoints
        } else {
            self.navigationPoints = PageChunker.createPages(from: content)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, originalName, excerpt, currentWordIndex, totalWords, lastReadDate, wordsPerMinute, sourceBookmark, navigationPoints, figureAnnotations, folderId, hasBeenOpened, hiddenFromRecents, positionHistory, readerMode, rarityFamiliarity
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
        
        // Decode figure annotations (empty array for old documents)
        figureAnnotations = (try? container.decodeIfPresent([FigureAnnotation].self, forKey: .figureAnnotations)) ?? []
        
        // Decode folderId if present
        folderId = try? container.decodeIfPresent(UUID.self, forKey: .folderId)
        
        // Decode hasBeenOpened, default to true for existing library documents
        hasBeenOpened = (try? container.decodeIfPresent(Bool.self, forKey: .hasBeenOpened)) ?? true

        // Decode hiddenFromRecents, default to false
        hiddenFromRecents = (try? container.decodeIfPresent(Bool.self, forKey: .hiddenFromRecents)) ?? false

        // Decode position history (empty array for old documents)
        positionHistory = (try? container.decodeIfPresent([PositionSnapshot].self, forKey: .positionHistory)) ?? []

        // Decode per-document reader mode (nil = follow the global default)
        readerMode = try? container.decodeIfPresent(ReaderMode.self, forKey: .readerMode)

        // Decode smart-pacing familiarity (nil for old documents)
        rarityFamiliarity = try? container.decodeIfPresent([String: Int].self, forKey: .rarityFamiliarity)
        
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

/// Represents a folder in the user's reading library to organize documents
struct DocumentFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var dateCreated: Date
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, dateCreated: Date = Date(), sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.sortOrder = sortOrder
    }

    // Backward-compatible decoding for existing folders.json without sortOrder
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

/// Lightweight progress snapshot used as a redundant backup to guard against
/// lost progress when the app is killed during the 2-second async-save debounce.
/// Written synchronously on every updateProgress() call; merged on app launch.
struct ProgressCheckpoint: Codable {
    let id: UUID
    var wordIndex: Int
    var wpm: Double
    var lastReadDate: Date
}

/// A saved reading position the user can jump back to — either the spot they
/// jumped away from, or a checkpoint from a sustained reading run.
struct PositionSnapshot: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case jumpDeparture       // where the user was right before a big jump
        case readingCheckpoint   // start of a ~200-word continuous reading run
    }

    let id: UUID
    let wordIndex: Int
    let date: Date
    let kind: Kind
    let sectionLabel: String?   // "Chapter 3" / "Page 12 of 45"
    let snippet: String         // ~8 words starting at wordIndex

    init(id: UUID = UUID(), wordIndex: Int, date: Date = Date(), kind: Kind,
         sectionLabel: String?, snippet: String) {
        self.id = id
        self.wordIndex = wordIndex
        self.date = date
        self.kind = kind
        self.sectionLabel = sectionLabel
        self.snippet = snippet
    }
}

/// Manages the user's document library with persistence
class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    @Published var documents: [ReadingDocument] = []
    @Published var inboxDocuments: [ReadingDocument] = []
    @Published var folders: [DocumentFolder] = []
    
    /// Tracks if the user is currently dragging a document (used to disable tab-swiping)
    @Published var isDraggingDocument: Bool = false
    
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
    func addDocument(name: String, content: String, sourceBookmark: Data? = nil, navigationPoints: [NavigationPoint]? = nil, figureAnnotations: [FigureAnnotation] = [], figureImages: [String: UIImage] = [:]) -> ReadingDocument {
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
                // Content changed, reset progress — preserve folder assignment
                let existingFolderId = documents[existingIndex].folderId
                let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark, navigationPoints: navigationPoints, figureAnnotations: figureAnnotations, folderId: existingFolderId)
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
            let newDoc = ReadingDocument(name: name, content: content, sourceBookmark: sourceBookmark, navigationPoints: navigationPoints, figureAnnotations: figureAnnotations)
            documents.insert(newDoc, at: 0)
            saveDocuments()
            saveContent(content, for: newDoc.id)
            saveFigureImages(figureImages, for: newDoc.id)
            return newDoc
        }
    }
    
    /// Persist smart-pacing familiarity counts (rare-word sightings) for a
    /// document. Debounced via the async save; skips writes when unchanged.
    func updateRarityFamiliarity(for documentId: UUID, counts: [String: Int]) {
        guard !counts.isEmpty,
              let index = documents.firstIndex(where: { $0.id == documentId }),
              documents[index].rarityFamiliarity != counts else { return }
        documents[index].rarityFamiliarity = counts
        saveDocumentsAsync()
    }

    /// Update reading progress for a document
    func updateProgress(for documentId: UUID, wordIndex: Int, wpm: Double) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            let hasChanged = documents[index].currentWordIndex != wordIndex || documents[index].wordsPerMinute != wpm
            
            // Always update last read date when progress is updated
            documents[index].lastReadDate = Date()
            
            // Mark as opened and unhide from recents (user may have hidden it earlier)
            documents[index].hasBeenOpened = true
            documents[index].hiddenFromRecents = false
            
            if hasChanged {
                documents[index].currentWordIndex = wordIndex
                documents[index].wordsPerMinute = wpm
            }
            
            // Write a synchronous checkpoint so progress survives app kills
            // that happen in the debounce window before the async save fires.
            writeProgressCheckpoint(id: documentId, wordIndex: wordIndex, wpm: wpm)
            
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
    
    /// Record a position snapshot (jump departure or reading checkpoint) for a document.
    func recordPositionSnapshot(for documentId: UUID, _ snapshot: PositionSnapshot) {
        guard let index = documents.firstIndex(where: { $0.id == documentId }) else { return }
        documents[index].recordPositionSnapshot(snapshot)
        // Piggyback on the debounced async save; history is a UX nicety, not crash-critical.
        saveDocumentsAsync()
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
        deleteFigureImages(for: document.id)
        ThumbnailManager.shared.clearThumbnail(for: document.id)
    }
    
    /// Set (or clear, with nil) a document's reader-mode override.
    /// Documents without an override follow SettingsManager.readerMode.
    func setReaderMode(_ mode: ReaderMode?, for documentId: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentId }) else { return }
        guard documents[index].readerMode != mode else { return }
        documents[index].readerMode = mode
        saveDocuments() // Structural change — persist immediately, same as rename
    }

    /// Rename a document
    func renameDocument(id: UUID, newName: String) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].name = newName
            saveDocuments() // Ensures immediate persistence instead of risking data loss via async dropout
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
    
    private var inboxFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("inbox.json")
    }
    
    private var foldersFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("folders.json")
    }
    
    private var checkpointFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("library_checkpoint.json")
    }
    
    private var sharedInboxURL: URL? {
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
    
    // MARK: - Figure Storage
    
    private var figuresDirectoryURL: URL? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        let url = groupURL.appendingPathComponent("Figures")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    func saveFigureImages(_ images: [String: UIImage], for documentId: UUID) {
        guard !images.isEmpty, let figDir = figuresDirectoryURL else { return }
        let docFigDir = figDir.appendingPathComponent(documentId.uuidString)
        try? FileManager.default.createDirectory(at: docFigDir, withIntermediateDirectories: true)
        
        for (fileName, image) in images {
            let fileURL = docFigDir.appendingPathComponent(fileName)
            if let data = image.pngData() {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
    
    func loadFigureImage(for documentId: UUID, fileName: String) -> UIImage? {
        guard let figDir = figuresDirectoryURL else { return nil }
        let fileURL = figDir.appendingPathComponent(documentId.uuidString).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    private func deleteFigureImages(for documentId: UUID) {
        guard let figDir = figuresDirectoryURL else { return }
        let docFigDir = figDir.appendingPathComponent(documentId.uuidString)
        try? FileManager.default.removeItem(at: docFigDir)
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
    
    private func saveFolders() {
        guard let url = foldersFileURL else { return }
        do {
            let data = try JSONEncoder().encode(folders)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("Folders synchronously saved to disk.")
        } catch {
            print("Error saving folders: \(error)")
        }
    }
    
    private func saveInbox() {
        guard let url = inboxFileURL else { return }
        do {
            let data = try JSONEncoder().encode(inboxDocuments)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("Inbox synchronously saved to disk.")
        } catch {
            print("Error saving inbox: \(error)")
        }
    }
    
    /// Debounced asynchronous save to prevent UI freezes
    func saveDocumentsAsync() {
        // Cancel previous pending save
        saveWorkItem?.cancel()

        // Capture snapshot on main thread to avoid data race
        let documentsSnapshot = self.documents

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
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
        // Wait for any in-flight async write to finish before we overwrite
        saveQueue.sync {}
        saveDocuments()
        saveFolders()
        saveInbox()
    }
    
    // MARK: - Checkpoint (Redundant Progress Backup)
    
    /// Write a lightweight progress-only checkpoint for one document.
    /// This is called synchronously in updateProgress() to ensure that even
    /// if the app is killed before the debounced async save fires, we have
    /// an up-to-date record that can be merged back on next launch.
    private func writeProgressCheckpoint(id: UUID, wordIndex: Int, wpm: Double) {
        guard let url = checkpointFileURL else { return }
        
        // Load the current checkpoint array, upsert, then write back.
        var checkpoints: [ProgressCheckpoint]
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ProgressCheckpoint].self, from: data) {
            checkpoints = decoded
        } else {
            checkpoints = []
        }
        
        let newEntry = ProgressCheckpoint(id: id, wordIndex: wordIndex, wpm: wpm, lastReadDate: Date())
        if let i = checkpoints.firstIndex(where: { $0.id == id }) {
            checkpoints[i] = newEntry
        } else {
            checkpoints.append(newEntry)
        }
        
        if let data = try? JSONEncoder().encode(checkpoints) {
            try? data.write(to: url, options: [.atomic])
        }
    }
    
    /// Load all stored progress checkpoints from disk.
    private func loadProgressCheckpoints() -> [ProgressCheckpoint] {
        guard let url = checkpointFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ProgressCheckpoint].self, from: data)
        else { return [] }
        return decoded
    }
    
    public func refresh() {
        guard let url = libraryFileURL else { return }

        var needsMigrationSave = false

        // 1. Load documents from file
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
            documents = decoded.sorted(by: { $0.lastReadDate > $1.lastReadDate })
        } else {
            // 1b. Migration: Check UserDefaults (Fallback)
            let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard
            if let data = defaults.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
                print("Migrating from UserDefaults to File Storage...")
                documents = decoded.sorted(by: { $0.lastReadDate > $1.lastReadDate })
                needsMigrationSave = true
            }
        }

        // 2. Load folders (must happen before any save that could overwrite folders.json)
        if let foldersUrl = foldersFileURL,
           let data = try? Data(contentsOf: foldersUrl),
           let decoded = try? JSONDecoder().decode([DocumentFolder].self, from: data) {
            folders = decoded.sorted(by: { $0.sortOrder < $1.sortOrder })
        }

        // Ensure "Read Later" folder always exists
        if !folders.contains(where: { $0.name == "Read Later" }) {
            let readLater = DocumentFolder(name: "Read Later", sortOrder: 0)
            // Shift existing folders' sortOrder up by 1
            for i in folders.indices { folders[i].sortOrder += 1 }
            folders.insert(readLater, at: 0)
            saveFolders()
        }

        // 3. Load inbox
        if let inboxUrl = inboxFileURL,
           let data = try? Data(contentsOf: inboxUrl),
           let decoded = try? JSONDecoder().decode([ReadingDocument].self, from: data) {
            inboxDocuments = decoded.sorted(by: { $0.lastReadDate > $1.lastReadDate })
        }

        // 4. Process migration (extract legacy content out of JSON and into separate files)
        for i in 0..<documents.count {
            if let migrationContent = documents[i].migrationContent {
                print("Migrating rich content for \(documents[i].name) out of database...")
                saveContent(migrationContent, for: documents[i].id)
                documents[i].migrationContent = nil
                needsMigrationSave = true
            }
        }

        // 5. Merge checkpoint data: the checkpoint file is written synchronously on every
        // progress update, so it may contain newer data than library.json (which uses a
        // 2-second debounced write). If the app was killed in that window, this recovers
        // the user's true reading position.
        let checkpoints = loadProgressCheckpoints()
        if !checkpoints.isEmpty {
            var checkpointSaveNeeded = false
            for checkpoint in checkpoints {
                if let i = documents.firstIndex(where: { $0.id == checkpoint.id }),
                   checkpoint.lastReadDate > documents[i].lastReadDate {
                    print("Restoring progress from checkpoint for \(documents[i].name): word \(checkpoint.wordIndex)")
                    documents[i].currentWordIndex = checkpoint.wordIndex
                    documents[i].wordsPerMinute = checkpoint.wpm
                    documents[i].lastReadDate = checkpoint.lastReadDate
                    checkpointSaveNeeded = true
                }
            }
            if checkpointSaveNeeded {
                needsMigrationSave = true
            }
        }

        if needsMigrationSave {
            saveDocuments()
        }

        // 6. Process Shared Inbox (Merge new items from Share Extension)
        processSharedInbox()
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
    
    /// Merge files from Shared Inbox into the main inbox
    func processSharedInbox() {
        guard let inbox = sharedInboxURL else { return }
        
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
                             // No companion .txt: a v1.x share extension wrote the
                             // full text inside the JSON itself (legacy "content"
                             // key, surfaced as migrationContent) — recover it
                             // rather than truncating to the excerpt.
                             newDocs.append((doc, doc.migrationContent ?? doc.excerpt))
                        }
                        
                        // Delete processed file
                        try FileManager.default.removeItem(at: url)
                        print("Processed and deleted shared inbox item: \(doc.name)")
                    } catch {
                        print("Failed to process shared inbox item at \(url): \(error)")
                    }
                }
            }
            
            if !newDocs.isEmpty {
                // Merge into main inbox
                // We add them to the top
                for item in newDocs {
                    var doc = item.doc
                    // Content lives in its own file; drop any legacy inline copy
                    doc.migrationContent = nil
                    // Save content
                    saveContent(item.content, for: doc.id)
                    // Avoid duplicates by ID or Name
                    if let existingIndex = inboxDocuments.firstIndex(where: { $0.id == doc.id || $0.name == doc.name }) {
                        var updatedDoc = inboxDocuments[existingIndex]
                        updatedDoc.lastReadDate = Date()
                        inboxDocuments.remove(at: existingIndex)
                        inboxDocuments.insert(updatedDoc, at: 0)
                    } else {
                        inboxDocuments.insert(doc, at: 0)
                    }
                }
                saveInbox()
            }
        } catch {
            print("Error processing Shared Inbox: \(error)")
        }
    }
    
    // MARK: - Inbox & Folder Operations
    
    /// Accept a document from the inbox into the main library
    func acceptInboxItem(_ document: ReadingDocument, intoFolder folderId: UUID? = nil) {
        guard let index = inboxDocuments.firstIndex(where: { $0.id == document.id }) else { return }
        
        var docToMove = inboxDocuments.remove(at: index)
        docToMove.lastReadDate = Date()
        docToMove.folderId = folderId
        
        documents.insert(docToMove, at: 0)
        saveDocuments()
        saveInbox()
    }
    
    /// Delete a document from the inbox entirely
    func deleteInboxItem(_ document: ReadingDocument) {
        inboxDocuments.removeAll(where: { $0.id == document.id })
        deleteContent(for: document.id)
        deleteFigureImages(for: document.id)
        saveInbox()
    }
    
    /// Create a new folder
    @discardableResult
    func createFolder(name: String) -> DocumentFolder {
        let nextOrder = (folders.map(\.sortOrder).max() ?? -1) + 1
        let folder = DocumentFolder(name: name, sortOrder: nextOrder)
        folders.append(folder)
        saveFolders()
        return folder
    }

    /// Reorder a folder by moving it before the target folder
    func reorderFolder(_ movedId: UUID, before targetId: UUID) {
        guard movedId != targetId,
              let fromIndex = folders.firstIndex(where: { $0.id == movedId }),
              let toIndex = folders.firstIndex(where: { $0.id == targetId }) else { return }
        let folder = folders.remove(at: fromIndex)
        folders.insert(folder, at: toIndex)
        // Reassign sortOrder to match new array positions
        for i in folders.indices {
            folders[i].sortOrder = i
        }
        saveFolders()
    }
    
    /// Rename a folder
    func renameFolder(id: UUID, newName: String) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders[index].name = newName
            saveFolders()
        }
    }
    
    /// Delete a folder without deleting its contents
    func deleteFolder(id: UUID) {
        folders.removeAll(where: { $0.id == id })
        // Clear folderId from any documents associated with it
        for i in 0..<documents.count {
            if documents[i].folderId == id {
                documents[i].folderId = nil
            }
        }
        saveDocuments()
        saveFolders()
    }
    
    /// Hide a document from the Recents section (it remains in the library)
    func removeFromRecents(for documentId: UUID) {
        if let index = documents.firstIndex(where: { $0.id == documentId }) {
            documents[index].hiddenFromRecents = true
            saveDocuments()
        }
    }

    /// Assign a document to a folder
    func assignDocument(id: UUID, to folderId: UUID?) {
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index].folderId = folderId
            saveDocuments() // Force an immediate save since this is an explicit structural action
        }
    }
}

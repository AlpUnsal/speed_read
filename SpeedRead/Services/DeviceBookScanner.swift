import SwiftUI
import UniformTypeIdentifiers

struct DiscoveredBook: Identifiable {
    let id: String  // relative path from scanned folder — stable across launches
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSize: Int64

    var displayName: String {
        // Clean up filename for display
        fileName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var fileTypeBadge: String {
        fileExtension.uppercased()
    }
}

class DeviceBookScanner: ObservableObject {
    static let shared = DeviceBookScanner()

    @Published var discoveredBooks: [DiscoveredBook] = []
    @Published var isScanning = false
    @Published var hasScannedOnce = false

    private let bookmarkKey = "DeviceBookScanner.folderBookmark"
    private let folderNameKey = "DeviceBookScanner.folderName"
    private let importedPathsKey = "DeviceBookScanner.importedPaths"
    private let appGroupIdentifier = "group.com.alpunsal.axilo"

    private let supportedExtensions: Set<String> = ["epub", "pdf", "txt", "rtf", "docx"]

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    var hasFolderAccess: Bool {
        defaults.data(forKey: bookmarkKey) != nil
    }

    var folderName: String? {
        defaults.string(forKey: folderNameKey)
    }

    private init() {}

    // MARK: - Folder Access

    func saveFolderBookmark(for url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmarkData, forKey: bookmarkKey)
            defaults.set(url.lastPathComponent, forKey: folderNameKey)
        } catch {
            print("DeviceBookScanner: Failed to create bookmark: \(error)")
        }
    }

    func removeFolderAccess() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: folderNameKey)
        defaults.removeObject(forKey: importedPathsKey)
        discoveredBooks = []
        hasScannedOnce = false
    }

    private var importedPaths: Set<String> {
        get { Set(defaults.stringArray(forKey: importedPathsKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: importedPathsKey) }
    }

    private func markImported(_ relativePath: String) {
        var paths = importedPaths
        paths.insert(relativePath)
        importedPaths = paths
    }

    // MARK: - Scanning

    func scan() {
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else { return }

        isScanning = true

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let results = self.performScan(bookmarkData: bookmarkData)

            await MainActor.run {
                self.discoveredBooks = results
                self.isScanning = false
                self.hasScannedOnce = true
            }
        }
    }

    private func performScan(bookmarkData: Data) -> [DiscoveredBook] {
        var isStale = false
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else { return [] }

        guard folderURL.startAccessingSecurityScopedResource() else { return [] }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        // If bookmark is stale, try to refresh it
        if isStale {
            if let newData = try? folderURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(newData, forKey: bookmarkKey)
            }
        }

        // Get already-imported paths to filter them out
        let alreadyImported = importedPaths

        var found: [DiscoveredBook] = []

        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

            let fileName = fileURL.deletingPathExtension().lastPathComponent

            // Use relative path as stable ID
            let relativePath = fileURL.path.replacingOccurrences(of: folderURL.path, with: "")

            // Skip if already imported
            if alreadyImported.contains(relativePath) { continue }

            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            found.append(DiscoveredBook(
                id: relativePath,
                url: fileURL,
                fileName: fileName,
                fileExtension: ext,
                fileSize: Int64(fileSize)
            ))
        }

        // Sort by filename
        return found.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    // MARK: - Import

    func importBook(_ book: DiscoveredBook) async -> ReadingDocument? {
        // Resolve bookmark to get security-scoped access
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else { return nil }

        var isStale = false
        guard let folderURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard folderURL.startAccessingSecurityScopedResource() else { return nil }
        defer { folderURL.stopAccessingSecurityScopedResource() }

        // Copy file to temp directory for parsing
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(book.url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: book.url, to: tempURL)
        } catch {
            print("DeviceBookScanner: Failed to copy file: \(error)")
            return nil
        }

        // Create bookmark for the original file (for thumbnails)
        let fileBookmark = try? book.url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Parse
        let result = await Task.detached(priority: .userInitiated) {
            DocumentParser.parseWithNavigation(url: tempURL)
        }.value

        // Cleanup temp file
        try? FileManager.default.removeItem(at: tempURL)

        guard let parsed = result else { return nil }

        let doc = await MainActor.run {
            LibraryManager.shared.addDocument(
                name: parsed.title ?? book.fileName,
                content: parsed.text,
                sourceBookmark: fileBookmark,
                navigationPoints: parsed.navigationPoints,
                figureAnnotations: parsed.figures,
                figureImages: parsed.figureImages
            )
        }

        // Mark as imported and remove from discovered list
        markImported(book.id)
        await MainActor.run {
            discoveredBooks.removeAll { $0.id == book.id }
        }

        return doc
    }
}

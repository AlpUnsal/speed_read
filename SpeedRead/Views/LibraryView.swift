import SwiftUI
import UniformTypeIdentifiers

#if !APPEXTENSION
extension UTType {
    static let documentFolder = UTType(exportedAs: "com.alpunsal.axilo.documentFolder")
}

extension DocumentFolder: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .documentFolder)
    }
}
#endif

struct LibraryView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var deviceScanner = DeviceBookScanner.shared
    @Binding var selectedDocument: ReadingDocument?
    @Binding var isPresented: Bool
    @Binding var isReading: Bool

    @State private var documentToRename: ReadingDocument?
    @State private var newDocumentName: String = ""
    @State private var documentForFolderSelection: ReadingDocument?
    @State private var importingBookId: String? = nil
    @State private var isImportingAll = false

    // Add folder states
    @State private var showCreateFolder = false
    @State private var newFolderName: String = ""
    @State private var presentedFolderItem: SelectedFolderItem?
    
    // Virtual folder enumerator
    enum SelectedFolderItem: Identifiable {
        case library
        case real(DocumentFolder)
        
        var id: String {
            switch self {
            case .library: return "library"
            case .real(let folder): return folder.id.uuidString
            }
        }
        
        var folder: DocumentFolder? {
            switch self {
            case .library: return nil
            case .real(let f): return f
            }
        }
    }
    
    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    ORPStyledTitle(text: "Library")
                    
                    Spacer()
                    
                    Button {
                        showCreateFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(settings.accentColor)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                if libraryManager.folders.isEmpty && !deviceScanner.hasFolderAccess {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            // "On Your Device" section
                            deviceBooksSection

                            // Folders grid
                            if !libraryManager.folders.isEmpty {
                                foldersGrid
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
            
            // Custom Overlays for Popups (must be inside ZStack)
            if documentToRename != nil {
                CustomAlertView(
                    title: "Rename Document",
                    text: $newDocumentName,
                    placeholder: "Document name",
                    saveTitle: "Save",
                    onCancel: {
                        withAnimation {
                            documentToRename = nil
                        }
                    },
                    onSave: {
                        if let doc = documentToRename, !newDocumentName.trimmingCharacters(in: .whitespaces).isEmpty {
                            libraryManager.renameDocument(id: doc.id, newName: newDocumentName.trimmingCharacters(in: .whitespaces))
                        }
                        withAnimation {
                            documentToRename = nil
                        }
                    }
                )
            }
            
            if showCreateFolder {
                CustomAlertView(
                    title: "New Folder",
                    text: $newFolderName,
                    placeholder: "Folder name",
                    saveTitle: "Create",
                    onCancel: {
                        withAnimation {
                            showCreateFolder = false
                            newFolderName = ""
                        }
                    },
                    onSave: {
                        if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                            libraryManager.createFolder(name: newFolderName.trimmingCharacters(in: .whitespaces))
                        }
                        withAnimation {
                            showCreateFolder = false
                            newFolderName = ""
                        }
                    }
                )
            }
        }
        // Sheets and FullScreenCovers
        .sheet(item: Binding<FolderSelectionItem?>(
            get: { documentForFolderSelection.map { FolderSelectionItem(document: $0) } },
            set: { documentForFolderSelection = $0?.document }
        )) { item in
            FolderSelectionView(
                document: item.document,
                onSelect: { folder in
                    libraryManager.assignDocument(id: item.document.id, to: folder?.id)
                    documentForFolderSelection = nil
                },
                onCancel: {
                    documentForFolderSelection = nil
                }
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(settings.backgroundColor)
        }
        .sheet(item: $presentedFolderItem) { item in
            FolderDetailView(
                folder: item.folder,
                selectedDocument: $selectedDocument,
                isReading: $isReading
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(settings.backgroundColor)
        }
    }
    
    // MARK: - Folders Section

    private let folderColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var foldersGrid: some View {
        LazyVGrid(columns: folderColumns, spacing: 20) {
            // 0. "All Books"
            VirtualFolderCard(
                name: "All Books",
                icon: "books.vertical",
                documents: libraryManager.documents,
                onDrop: nil
            ) {
                presentedFolderItem = .library
            }

            // 1. "Read Later"
            if let readLater = libraryManager.folders.first(where: { $0.name == "Read Later" }) {
                FolderCard(folder: readLater) {
                    presentedFolderItem = .real(readLater)
                }
            } else {
                VirtualFolderCard(
                    name: "Read Later",
                    icon: "bookmark",
                    documents: [],
                    onDrop: { doc in
                        let folder = libraryManager.createFolder(name: "Read Later")
                        libraryManager.assignDocument(id: doc.id, to: folder.id)
                    }
                ) {
                    let newFolder = libraryManager.createFolder(name: "Read Later")
                    presentedFolderItem = .real(newFolder)
                }
            }

            // 2. User Folders (draggable for reordering)
            ForEach(libraryManager.folders.filter { $0.name != "Read Later" }) { folder in
                folderCard(for: folder)
            }
        }
        .padding(.horizontal, 24)
    }
    
    @ViewBuilder
    private func folderCard(for folder: DocumentFolder) -> some View {
        #if !APPEXTENSION
        FolderCard(folder: folder, onFolderDrop: { droppedFolder in
            guard droppedFolder.id != folder.id else { return }
            withAnimation {
                libraryManager.reorderFolder(droppedFolder.id, before: folder.id)
            }
        }) {
            presentedFolderItem = .real(folder)
        }
        .draggable(folder)
        #else
        FolderCard(folder: folder) {
            presentedFolderItem = .real(folder)
        }
        #endif
    }

    // MARK: - Device Books Section

    @ViewBuilder
    private var deviceBooksSection: some View {
        if !deviceScanner.hasFolderAccess {
            // CTA banner — invite user to link a folder
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("ShowFolderPicker"), object: nil)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(settings.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Find books on your device")
                            .font(.custom("EBGaramond-Regular", size: 17))
                            .foregroundColor(settings.textColor)
                        Text("Select the folder where your books are stored")
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(settings.mutedTextColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(settings.mutedTextColor)
                }
                .padding(16)
                .background(settings.cardBackgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(settings.accentColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
        } else if deviceScanner.isScanning {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(settings.accentColor)
                Text("Scanning for books...")
                    .font(.custom("EBGaramond-Regular", size: 15))
                    .foregroundColor(settings.secondaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(settings.cardBackgroundColor)
            .cornerRadius(12)
            .padding(.horizontal, 24)
        } else if deviceScanner.discoveredBooks.isEmpty && deviceScanner.hasScannedOnce {
            // No books found — offer to change folder
            VStack(spacing: 12) {
                Text("No new books found")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.secondaryTextColor)

                if let name = deviceScanner.folderName {
                    Text("in \"\(name)\"")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(settings.mutedTextColor)
                }

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowFolderPicker"), object: nil)
                } label: {
                    Text("Try a different folder")
                        .font(.custom("EBGaramond-Regular", size: 15))
                        .foregroundColor(settings.accentColor)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(settings.accentColor.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(settings.cardBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
            )
            .padding(.horizontal, 24)
        } else if !deviceScanner.discoveredBooks.isEmpty {
            // Discovered books list
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("On Your Device")
                        .font(.custom("EBGaramond-Regular", size: 18))
                        .foregroundColor(settings.textColor)

                    Spacer()

                    if deviceScanner.discoveredBooks.count > 1 && !isImportingAll {
                        Button {
                            importAllBooks()
                        } label: {
                            Text("Import All")
                                .font(.custom("EBGaramond-Regular", size: 14))
                                .foregroundColor(settings.accentColor)
                        }
                    }

                    if isImportingAll {
                        ProgressView()
                            .tint(settings.accentColor)
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(deviceScanner.discoveredBooks) { book in
                            DiscoveredBookCard(
                                book: book,
                                isImporting: importingBookId == book.id,
                                onImport: { importBook(book) }
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private func importBook(_ book: DiscoveredBook) {
        importingBookId = book.id
        Task {
            let doc = await deviceScanner.importBook(book)
            await MainActor.run {
                importingBookId = nil
                if let doc {
                    selectedDocument = doc
                }
            }
        }
    }

    private func importAllBooks() {
        isImportingAll = true
        let books = deviceScanner.discoveredBooks
        Task {
            for book in books {
                _ = await deviceScanner.importBook(book)
            }
            await MainActor.run {
                isImportingAll = false
            }
        }
    }

    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(settings.mutedTextColor)
            Text("No folders yet")
                .font(.custom("EBGaramond-Regular", size: 18))
                .foregroundColor(settings.secondaryTextColor)
            Text("Tap + to create a folder")
                .font(.custom("EBGaramond-Regular", size: 14))
                .foregroundColor(settings.mutedTextColor)
        }
    }
    
}

// MARK: - Virtual Folder Card
struct VirtualFolderCard: View {
    let name: String
    let icon: String // e.g. "books.vertical"
    let documents: [ReadingDocument]
    /// Called when a document is dropped onto this virtual folder.
    /// Receives the document; callers are responsible for creating the folder if needed.
    var onDrop: ((ReadingDocument) -> Void)? = nil
    let action: () -> Void
    
    @ObservedObject var settings = SettingsManager.shared
    @State private var isDropTargeted = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.cardBackgroundColor)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                    
                    Group {
                        if documents.isEmpty {
                            Image(systemName: icon)
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(settings.mutedTextColor.opacity(0.5))
                        } else if documents.count < 4 {
                            // Single full-size thumbnail for < 4 items
                            DocumentThumbnail(document: documents[0])
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            // Four quadrant thumbnails
                            VStack(spacing: 2) {
                                HStack(spacing: 2) {
                                    QuadrantThumbnail(document: documents[0])
                                    QuadrantThumbnail(document: documents[1])
                                }
                                HStack(spacing: 2) {
                                    QuadrantThumbnail(document: documents[2])
                                    QuadrantThumbnail(document: documents[3])
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Drop highlight overlay
                    if isDropTargeted && onDrop != nil {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(settings.accentColor, lineWidth: 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(settings.accentColor.opacity(0.12))
                            )
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(isDropTargeted && onDrop != nil ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTargeted)
                
                Text(name)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.textColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .dropDestination(for: ReadingDocument.self) { droppedItems, _ in
            guard let doc = droppedItems.first, let handler = onDrop else { return false }
            handler(doc)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}

// MARK: - Folder Card (Apple Music Style)
struct FolderCard: View {
    let folder: DocumentFolder
    var onFolderDrop: ((DocumentFolder) -> Void)? = nil
    let action: () -> Void

    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @State private var isDropTargeted = false
    
    var folderDocuments: [ReadingDocument] {
        libraryManager.documents.filter { $0.folderId == folder.id }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.cardBackgroundColor)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                    
                    Group {
                        if folderDocuments.isEmpty {
                            Image(systemName: "folder")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(settings.mutedTextColor.opacity(0.5))
                        } else if folderDocuments.count < 4 {
                            // Single full-size thumbnail for < 4 items
                            DocumentThumbnail(document: folderDocuments[0])
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            // Four quadrant thumbnails
                            VStack(spacing: 2) {
                                HStack(spacing: 2) {
                                    QuadrantThumbnail(document: folderDocuments[0])
                                    QuadrantThumbnail(document: folderDocuments[1])
                                }
                                HStack(spacing: 2) {
                                    QuadrantThumbnail(document: folderDocuments[2])
                                    QuadrantThumbnail(document: folderDocuments[3])
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Drop highlight overlay
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(settings.accentColor, lineWidth: 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(settings.accentColor.opacity(0.12))
                            )
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .scaleEffect(isDropTargeted ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTargeted)
                
                Text(folder.name)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.textColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        #if !APPEXTENSION
        .onDrop(of: [.readingDocument, .documentFolder], isTargeted: $isDropTargeted) { providers in
            // Folder reorder
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.documentFolder.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.documentFolder.identifier) { data, _ in
                    guard let data = data,
                          let dropped = try? JSONDecoder().decode(DocumentFolder.self, from: data),
                          let handler = onFolderDrop,
                          dropped.id != folder.id else { return }
                    DispatchQueue.main.async { handler(dropped) }
                }
                return true
            }
            // Document assignment
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.readingDocument.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.readingDocument.identifier) { data, _ in
                    guard let data = data,
                          let doc = try? JSONDecoder().decode(ReadingDocument.self, from: data),
                          doc.folderId != folder.id else { return }
                    DispatchQueue.main.async {
                        libraryManager.assignDocument(id: doc.id, to: folder.id)
                    }
                }
                return true
            }
            return false
        }
        #else
        .dropDestination(for: ReadingDocument.self) { droppedItems, _ in
            guard let doc = droppedItems.first else { return false }
            guard doc.folderId != folder.id else { return false }
            libraryManager.assignDocument(id: doc.id, to: folder.id)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        #endif
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    libraryManager.deleteFolder(id: folder.id)
                }
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}

struct QuadrantThumbnail: View {
    let document: ReadingDocument?
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        Group {
            if let doc = document {
                DocumentThumbnail(document: doc)
                    .clipped()
            } else {
                Rectangle()
                    .fill(settings.backgroundColor.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Discovered Book Card

struct DiscoveredBookCard: View {
    let book: DiscoveredBook
    let isImporting: Bool
    let onImport: () -> Void

    @ObservedObject var settings = SettingsManager.shared

    var body: some View {
        Button(action: { if !isImporting { onImport() } }) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.cardBackgroundColor)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)

                    VStack(spacing: 6) {
                        if isImporting {
                            ProgressView()
                                .tint(settings.accentColor)
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(settings.accentColor)
                        }

                        Text(book.fileTypeBadge)
                            .font(.custom("EBGaramond-Regular", size: 11))
                            .foregroundColor(settings.mutedTextColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(settings.mutedTextColor.opacity(0.1))
                            .cornerRadius(4)

                        Text(book.fileSizeFormatted)
                            .font(.custom("EBGaramond-Regular", size: 11))
                            .foregroundColor(settings.mutedTextColor)
                    }
                }
                .frame(width: 100, height: 100)

                Text(book.displayName)
                    .font(.custom("EBGaramond-Regular", size: 13))
                    .foregroundColor(settings.textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isImporting ? 0.6 : 1.0)
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: ReadingDocument
    let onContinue: () -> Void
    let onRestart: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: (() -> Void)? = nil
    var onRemoveFromFolder: (() -> Void)? = nil
    
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        Button(action: onContinue) {
            HStack(spacing: 14) {
                // Thumbnail
                DocumentThumbnail(document: document)
                    .frame(width: 50, height: 70)
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.name)
                        .font(.custom("EBGaramond-Regular", size: 17))
                        .foregroundColor(settings.textColor)
                        .lineLimit(1)
                    
                    HStack(spacing: 10) {
                        // Progress
                        Text("\(Int(document.progress * 100))%")
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(document.isComplete ? settings.completedColor : settings.secondaryTextColor)
                        
                        // Word count
                        Text("\(document.totalWords) words")
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(settings.mutedTextColor)
                        
                        Spacer()
                        
                        // Last read
                        Text(timeAgo(from: document.lastReadDate))
                            .font(.custom("EBGaramond-Regular", size: 12))
                            .foregroundColor(settings.mutedTextColor)
                    }
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(settings.progressBarBackgroundColor)
                                .frame(height: 3)
                            
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(document.isComplete ? settings.completedColor : settings.accentColor)
                                .frame(width: geo.size.width * document.progress, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
                
                // Continue indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(settings.mutedTextColor)
            }
            .padding(14)
            .background(settings.cardBackgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: onContinue) {
                Label(document.currentWordIndex > 0 ? "Continue" : "Start", systemImage: "play")
            }
            Button(action: onRestart) {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            if onMoveToFolder != nil {
                Button(action: { onMoveToFolder?() }) {
                    Label("Move to Folder", systemImage: "folder")
                }
            }
            if let removeFromFolder = onRemoveFromFolder {
                Button(action: removeFromFolder) {
                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                }
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

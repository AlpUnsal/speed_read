import SwiftUI

struct LibraryView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Binding var selectedDocument: ReadingDocument?
    @Binding var isPresented: Bool
    @Binding var isReading: Bool
    
    @State private var documentToRename: ReadingDocument?
    @State private var newDocumentName: String = ""
    @State private var documentForFolderSelection: ReadingDocument?
    
    // Add folder states
    @State private var showCreateFolder = false
    @State private var newFolderName: String = ""
    @State private var presentedFolderItem: SelectedFolderItem?
    
    // Auto-scroll state (for drag-to-edge folder traversal)
    @State private var autoScrollTimer: Timer? = nil
    @State private var autoScrollInterval: TimeInterval = 0.45
    @State private var autoScrollDirection: Int = 0  // -1 = left, 0 = stopped, 1 = right
    @State private var autoScrollIndex: Int = 0
    
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
                    Text("Library")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .foregroundColor(settings.textColor)
                    
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
                
                foldersSection
                
                if libraryManager.documents.isEmpty && libraryManager.folders.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else if !libraryManager.documents.isEmpty {
                    documentList
                } else {
                    Spacer()
                }
            }
        }
        .alert("Rename Document", isPresented: Binding(
            get: { documentToRename != nil },
            set: { if !$0 { documentToRename = nil } }
        )) {
            TextField("Name", text: $newDocumentName)
            Button("Cancel", role: .cancel) {
                documentToRename = nil
            }
            Button("Save") {
                if let doc = documentToRename, !newDocumentName.isEmpty {
                    libraryManager.renameDocument(id: doc.id, newName: newDocumentName)
                }
                newFolderName = ""
            }
        }
        .alert("New Folder", isPresented: $showCreateFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                if !newFolderName.isEmpty {
                    libraryManager.createFolder(name: newFolderName)
                }
                newFolderName = ""
            }
        }
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
        }
        .fullScreenCover(item: $presentedFolderItem) { item in
            FolderDetailView(
                folder: item.folder,
                selectedDocument: $selectedDocument,
                isReading: $isReading
            )
        }
    }
    
    // MARK: - Folders Section

    /// Ordered list of folder IDs used for programmatic scrolling (Read Later first).
    private var orderedFolderIDs: [UUID] {
        let readLater = libraryManager.folders.filter { $0.name == "Read Later" }
        let others = libraryManager.folders.filter { $0.name != "Read Later" }
        return (readLater + others).map { $0.id }
    }

    private func startAutoScroll(direction: Int, proxy: ScrollViewProxy) {
        guard autoScrollDirection != direction else { return }
        stopAutoScroll()
        autoScrollDirection = direction
        autoScrollInterval = 0.45  // always reset speed at the start

        func scheduleNext() {
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: autoScrollInterval, repeats: false) { _ in
                let ids = orderedFolderIDs
                guard !ids.isEmpty else { return }
                autoScrollIndex = max(0, min(ids.count - 1, autoScrollIndex + direction))
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(ids[autoScrollIndex], anchor: .center)
                }
                // Accelerate: shorten interval each tick, floor at 0.08s
                autoScrollInterval = max(0.08, autoScrollInterval * 0.85)
                if autoScrollDirection != 0 { scheduleNext() }
            }
        }
        scheduleNext()
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollDirection = 0
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Folders")
                    .font(.custom("EBGaramond-Regular", size: 18))
                    .foregroundColor(settings.secondaryTextColor)
                
                Spacer()
            }
            .padding(.horizontal, 24)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        // 1. "Read Later"
                        if let readLater = libraryManager.folders.first(where: { $0.name == "Read Later" }) {
                            FolderCard(folder: readLater) {
                                presentedFolderItem = .real(readLater)
                            }
                            .id(readLater.id)
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

                        // 2. User Folders
                        ForEach(libraryManager.folders.filter { $0.name != "Read Later" }) { folder in
                            FolderCard(folder: folder) {
                                presentedFolderItem = .real(folder)
                            }
                            .id(folder.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                // Left edge zone: drag here → scroll left
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 56)
                        .contentShape(Rectangle())
                        .dropDestination(for: ReadingDocument.self) { _, _ in false } isTargeted: { over in
                            if over {
                                startAutoScroll(direction: -1, proxy: proxy)
                            } else if autoScrollDirection == -1 {
                                stopAutoScroll()
                            }
                        }
                }
                // Right edge zone: drag here → scroll right
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 56)
                        .contentShape(Rectangle())
                        .dropDestination(for: ReadingDocument.self) { _, _ in false } isTargeted: { over in
                            if over {
                                startAutoScroll(direction: 1, proxy: proxy)
                            } else if autoScrollDirection == 1 {
                                stopAutoScroll()
                            }
                        }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundColor(settings.mutedTextColor)
            Text("No documents yet")
                .font(.custom("EBGaramond-Regular", size: 18))
                .foregroundColor(settings.secondaryTextColor)
            Text("Import a document to get started")
                .font(.custom("EBGaramond-Regular", size: 14))
                .foregroundColor(settings.mutedTextColor)
        }
    }
    
    // MARK: - Document List
    
    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(libraryManager.documents) { document in
                    DocumentRow(
                        document: document,
                        onContinue: {
                            selectedDocument = document
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isReading = true
                            }
                            isPresented = false
                        },
                        onRestart: {
                            libraryManager.resetProgress(for: document.id)
                            if var doc = libraryManager.getDocument(id: document.id) {
                                doc.currentWordIndex = 0
                                selectedDocument = doc
                            }
                            isPresented = false
                        },
                        onRename: {
                            newDocumentName = document.name
                            documentToRename = document
                        },
                        onDelete: {
                            withAnimation {
                                libraryManager.deleteDocument(document)
                            }
                        },
                        onMoveToFolder: {
                            documentForFolderSelection = document
                        }
                    )
                    .draggable(document)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
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
            VStack(alignment: .leading, spacing: 8) {
                // 2x2 grid cover
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.cardBackgroundColor)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                    
                    if documents.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(settings.mutedTextColor.opacity(0.5))
                    } else if documents.count < 4 {
                        DocumentThumbnail(document: documents[0])
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
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
                .frame(width: 140, height: 140)
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
    let action: () -> Void
    
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @State private var isDropTargeted = false
    
    var folderDocuments: [ReadingDocument] {
        libraryManager.documents.filter { $0.folderId == folder.id }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // 2x2 grid cover
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.cardBackgroundColor)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                    
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
                .frame(width: 140, height: 140)
                .scaleEffect(isDropTargeted ? 1.05 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDropTargeted)
                
                Text(folder.name)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.textColor)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .dropDestination(for: ReadingDocument.self) { droppedItems, _ in
            guard let doc = droppedItems.first else { return false }
            // Skip if document is already in this folder
            guard doc.folderId != folder.id else { return false }
            libraryManager.assignDocument(id: doc.id, to: folder.id)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
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
        .frame(width: 69, height: 69) // Exactly half of 140 minus spacing
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

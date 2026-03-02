import SwiftUI

// Shared sort option enum
enum FolderSortOption: Int {
    case newestFirst = 0
    case oldestFirst = 1
    case titleAZ = 2
}

struct FolderDetailView: View {
    let folder: DocumentFolder? // nil means 'Library (No Folder)'
    @Binding var selectedDocument: ReadingDocument?
    @Binding var isReading: Bool
    @Environment(\.dismiss) var dismiss

    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared

    @State private var documentToRename: ReadingDocument?
    @State private var newDocumentName: String = ""
    @State private var documentForFolderSelection: ReadingDocument?
    @AppStorage("folderSortOption") private var sortOptionRaw: Int = FolderSortOption.newestFirst.rawValue

    private var sortOption: FolderSortOption {
        FolderSortOption(rawValue: sortOptionRaw) ?? .newestFirst
    }

    var folderName: String {
        folder?.name ?? "Library"
    }

    var folderDocuments: [ReadingDocument] {
        let docs: [ReadingDocument]
        if let folder = folder {
            docs = libraryManager.documents.filter { $0.folderId == folder.id }
        } else {
            docs = libraryManager.documents.filter { $0.folderId == nil }
        }

        switch sortOption {
        case .newestFirst:
            return docs
        case .oldestFirst:
            return docs.reversed()
        case .titleAZ:
            return docs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()

                if folderDocuments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundColor(settings.mutedTextColor)
                        Text("Folder is empty")
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(settings.secondaryTextColor)
                        Text("Move documents here from your library.")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(settings.mutedTextColor)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(folderDocuments) { document in
                                DocumentRow(
                                    document: document,
                                    onContinue: {
                                        selectedDocument = document
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isReading = true
                                            }
                                        }
                                    },
                                    onRestart: {
                                        libraryManager.resetProgress(for: document.id)
                                        if var doc = libraryManager.getDocument(id: document.id) {
                                            doc.currentWordIndex = 0
                                            selectedDocument = doc
                                        }
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                isReading = true
                                            }
                                        }
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
                                    },
                                    onRemoveFromFolder: folder != nil ? {
                                        libraryManager.assignDocument(id: document.id, to: nil)
                                    } : nil
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle(folderName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Library")
                        }
                        .foregroundColor(settings.accentColor)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            withAnimation { sortOptionRaw = FolderSortOption.newestFirst.rawValue }
                        } label: {
                            Label("Newest First", systemImage: sortOption == .newestFirst ? "checkmark" : "")
                        }

                        Button {
                            withAnimation { sortOptionRaw = FolderSortOption.oldestFirst.rawValue }
                        } label: {
                            Label("Oldest First", systemImage: sortOption == .oldestFirst ? "checkmark" : "")
                        }

                        Button {
                            withAnimation { sortOptionRaw = FolderSortOption.titleAZ.rawValue }
                        } label: {
                            Label("Title A–Z", systemImage: sortOption == .titleAZ ? "checkmark" : "")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(settings.accentColor)
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
                    documentToRename = nil
                }
            }
            .sheet(item: Binding<FolderSelectionItem?>(
                get: { documentForFolderSelection.map { FolderSelectionItem(document: $0) } },
                set: { documentForFolderSelection = $0?.document }
            )) { item in
                FolderSelectionView(
                    document: item.document,
                    onSelect: { selectedFolder in
                        libraryManager.assignDocument(id: item.document.id, to: selectedFolder?.id)
                        documentForFolderSelection = nil
                    },
                    onCancel: {
                        documentForFolderSelection = nil
                    }
                )
            }
        }
    }
}

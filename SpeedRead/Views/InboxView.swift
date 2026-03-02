import SwiftUI

struct InboxView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Binding var isPresented: Bool
    @Binding var currentDocument: ReadingDocument?
    @Binding var isReading: Bool

    @State private var documentForFolderSelection: ReadingDocument?
    @AppStorage("inboxSortOption") private var sortOptionRaw: Int = FolderSortOption.newestFirst.rawValue

    private var sortOption: FolderSortOption {
        FolderSortOption(rawValue: sortOptionRaw) ?? .newestFirst
    }

    private var sortedDocuments: [ReadingDocument] {
        switch sortOption {
        case .newestFirst:
            return libraryManager.inboxDocuments
        case .oldestFirst:
            return libraryManager.inboxDocuments.reversed()
        case .titleAZ:
            return libraryManager.inboxDocuments.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()

                if libraryManager.inboxDocuments.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header count
                            Text("\(libraryManager.inboxDocuments.count) item\(libraryManager.inboxDocuments.count == 1 ? "" : "s")")
                                .font(.custom("EBGaramond-Regular", size: 14))
                                .foregroundColor(settings.mutedTextColor)
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                                .padding(.bottom, 16)

                            LazyVStack(spacing: 0) {
                                ForEach(Array(sortedDocuments.enumerated()), id: \.element.id) { index, doc in
                                    inboxItemRow(doc)

                                    if index < sortedDocuments.count - 1 {
                                        Divider()
                                            .background(settings.cardBorderColor.opacity(0.2))
                                            .padding(.leading, 68)
                                            .padding(.trailing, 20)
                                    }
                                }
                            }
                            .background(settings.cardBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(settings.cardBorderColor.opacity(0.15), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
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

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.accentColor)
                }
            }
            .sheet(item: Binding<FolderSelectionItem?>(
                get: { documentForFolderSelection.map { FolderSelectionItem(document: $0) } },
                set: { documentForFolderSelection = $0?.document }
            )) { item in
                FolderSelectionView(
                    document: item.document,
                    onSelect: { folder in
                        libraryManager.acceptInboxItem(item.document, intoFolder: folder?.id)
                        documentForFolderSelection = nil
                    },
                    onCancel: {
                        documentForFolderSelection = nil
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(settings.accentColor.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "tray")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundColor(settings.accentColor.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text("No new items")
                    .font(.custom("EBGaramond-Regular", size: 20))
                    .foregroundColor(settings.textColor)
                Text("Articles you share will appear here.")
                    .font(.custom("EBGaramond-Regular", size: 15))
                    .foregroundColor(settings.mutedTextColor)
            }
        }
    }

    // MARK: - Inbox Item Row

    private func inboxItemRow(_ document: ReadingDocument) -> some View {
        HStack(spacing: 14) {
            Button {
                readImmediately(document)
            } label: {
                HStack(spacing: 14) {
                    // Document thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(settings.accentColor.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(settings.accentColor.opacity(0.7))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.name)
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(settings.textColor)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("\(document.totalWords) words")
                                .font(.custom("EBGaramond-Regular", size: 13))
                                .foregroundColor(settings.mutedTextColor)

                            Text("·")
                                .foregroundColor(settings.mutedTextColor.opacity(0.5))

                            Text(timeAgo(from: document.lastReadDate))
                                .font(.custom("EBGaramond-Regular", size: 13))
                                .foregroundColor(settings.mutedTextColor)
                        }
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Action menu
            Menu {
                Button {
                    readImmediately(document)
                } label: {
                    Label("Read Now", systemImage: "book")
                }

                Button {
                    libraryManager.acceptInboxItem(document, intoFolder: nil)
                } label: {
                    Label("Save to Library", systemImage: "square.and.arrow.down")
                }

                Button {
                    documentForFolderSelection = document
                } label: {
                    Label("Save to Folder", systemImage: "folder.badge.plus")
                }

                Divider()

                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        libraryManager.deleteInboxItem(document)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(settings.mutedTextColor.opacity(0.7))
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func readImmediately(_ document: ReadingDocument) {
        libraryManager.acceptInboxItem(document, intoFolder: nil)

        if let movedDoc = libraryManager.documents.first(where: { $0.id == document.id }) {
            currentDocument = movedDoc
            isPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Folder Selection Item Wrapper

struct FolderSelectionItem: Identifiable {
    var id: UUID { document.id }
    let document: ReadingDocument
}

// MARK: - Folder Selection View

struct FolderSelectionView: View {
    @Environment(\.dismiss) var dismiss
    let document: ReadingDocument
    let onSelect: (DocumentFolder?) -> Void
    let onCancel: () -> Void

    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared

    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""

    private var readLaterFolder: DocumentFolder? {
        libraryManager.folders.first { $0.name == "Read Later" }
    }

    private var userFolders: [DocumentFolder] {
        libraryManager.folders.filter { $0.name != "Read Later" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 2) {
                        // Read Later row (first, no Library row)
                        VStack(spacing: 0) {
                            folderRow(icon: "bookmark", label: "Read Later", subtitle: folderCount(readLaterFolder)) {
                                if let folder = readLaterFolder {
                                    onSelect(folder)
                                } else {
                                    let folder = libraryManager.createFolder(name: "Read Later")
                                    onSelect(folder)
                                }
                                dismiss()
                            }
                        }
                        .background(settings.cardBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)

                        // User folders
                        if !userFolders.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(userFolders.enumerated()), id: \.element.id) { index, folder in
                                    folderRow(icon: "folder", label: folder.name, subtitle: folderCount(folder)) {
                                        onSelect(folder)
                                        dismiss()
                                    }

                                    if index < userFolders.count - 1 {
                                        rowDivider
                                    }
                                }
                            }
                            .background(settings.cardBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        }

                        // New Folder
                        Button {
                            showNewFolderAlert = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .regular))
                                Text("New Folder")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                            }
                            .foregroundColor(settings.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(settings.cardBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.mutedTextColor)
                }
            }
            .alert("New Folder", isPresented: $showNewFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) {
                    newFolderName = ""
                }
                Button("Create") {
                    if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                        let folder = libraryManager.createFolder(name: newFolderName.trimmingCharacters(in: .whitespaces))
                        onSelect(folder)
                        dismiss()
                    }
                    newFolderName = ""
                }
            }
        }
    }

    // MARK: - Row Components

    private func folderRow(icon: String, label: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundColor(settings.secondaryTextColor)
                    .frame(width: 24)

                Text(label)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.textColor)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.custom("EBGaramond-Regular", size: 13))
                        .foregroundColor(settings.mutedTextColor)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rowDivider: some View {
        Divider()
            .background(settings.cardBorderColor.opacity(0.15))
            .padding(.leading, 52)
    }

    private func folderCount(_ folder: DocumentFolder?) -> String? {
        guard let folder = folder else { return nil }
        let count = libraryManager.documents.filter { $0.folderId == folder.id }.count
        return count > 0 ? "\(count)" : nil
    }
}

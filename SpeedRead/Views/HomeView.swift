import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Binding var showSettings: Bool
    @Binding var showContent: Bool
    @Binding var currentDocument: ReadingDocument?
    @Binding var isReading: Bool
    @AppStorage("hasAddedSample") private var hasAddedSample = false
    @State private var showInbox = false
    @State private var documentForFolderSelection: ReadingDocument?
    @State private var documentToRename: ReadingDocument?
    @State private var newDocumentName: String = ""
    
    // Most recent document for Continue Reading feature
    private var mostRecentDocument: ReadingDocument? {
        libraryManager.documents.first { $0.hasBeenOpened && !$0.hiddenFromRecents }
    }
    
    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header - matches Library/Explore pattern
                HStack {
                    ORPStyledTitle(text: "Axilo")
                    
                    Spacer()
                    
                    // Inbox button
                    Button(action: { showInbox = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: libraryManager.inboxDocuments.isEmpty ? "tray" : "tray.full")
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(libraryManager.inboxDocuments.isEmpty ? settings.mutedTextColor : settings.accentColor)
                                .padding(8)
                            
                            if !libraryManager.inboxDocuments.isEmpty {
                                Text("\(libraryManager.inboxDocuments.count)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                    
                    // Settings button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(settings.mutedTextColor)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .opacity(showContent ? 1 : 0)
                
                // Main content
                if libraryManager.documents.isEmpty {
                    // Empty state - first time user or no documents
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Continue Reading card (most recent document)
                            if let doc = mostRecentDocument {
                                continueReadingCard(for: doc)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 24)
                            }
                            
                            // Recent section
                            if libraryManager.documents.count > 1 {
                                recentSection
                            }
                        }
                        .padding(.bottom, 100) // Padding for bottom tab bar
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                }
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
            .presentationDragIndicator(.visible)
            .presentationBackground(settings.backgroundColor)
        }
        .sheet(isPresented: $showInbox) {
            InboxView(
                isPresented: $showInbox,
                currentDocument: $currentDocument,
                isReading: $isReading
            )
        }
        .overlay {
            if documentToRename != nil {
                CustomAlertView(
                    title: "Rename Document",
                    text: $newDocumentName,
                    placeholder: "Document name",
                    saveTitle: "Save",
                    onCancel: {
                        withAnimation { documentToRename = nil }
                    },
                    onSave: {
                        if let doc = documentToRename, !newDocumentName.trimmingCharacters(in: .whitespaces).isEmpty {
                            libraryManager.renameDocument(id: doc.id, newName: newDocumentName.trimmingCharacters(in: .whitespaces))
                        }
                        withAnimation { documentToRename = nil }
                    }
                )
            }
        }
    }
    
    // MARK: - Continue Reading Card
    
    private func continueReadingCard(for doc: ReadingDocument) -> some View {
        Button(action: {
            currentDocument = doc
            withAnimation(.easeInOut(duration: 0.3)) {
                isReading = true
            }
        }) {
            HStack(spacing: 14) {
                // Cover thumbnail
                DocumentThumbnail(document: doc)
                    .id(doc.id)
                    .frame(width: 80, height: 110)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Continue Reading")
                        .font(.custom("EBGaramond-Regular", size: 13))
                        .foregroundColor(settings.secondaryTextColor)
                    
                    Text(doc.name)
                        .font(.custom("EBGaramond-Regular", size: 19))
                        .foregroundColor(settings.textColor)
                        .lineLimit(2)
                    
                    Spacer(minLength: 4)
                    
                    HStack(spacing: 8) {
                        Text("\(Int(doc.progress * 100))%")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(doc.isComplete ? settings.completedColor : settings.secondaryTextColor)
                        
                        Text("\(doc.totalWords.formatted()) words")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(settings.mutedTextColor)
                    }
                    
                    Text(timeAgo(from: doc.lastReadDate))
                        .font(.custom("EBGaramond-Regular", size: 12))
                        .foregroundColor(settings.mutedTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(settings.cardBorderColor.opacity(0.15))
                        )
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(settings.mutedTextColor)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(settings.cardBackgroundColor)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(settings.cardBorderColor.opacity(0.4), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                currentDocument = doc
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }) {
                Label(doc.currentWordIndex > 0 ? "Continue" : "Start", systemImage: "play")
            }
            Button(action: {
                libraryManager.resetProgress(for: doc.id)
                if var updated = libraryManager.getDocument(id: doc.id) {
                    updated.currentWordIndex = 0
                    currentDocument = updated
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }) {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            Button(action: {
                newDocumentName = doc.name
                documentToRename = doc
            }) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: {
                documentForFolderSelection = doc
            }) {
                Label("Move to Folder", systemImage: "folder")
            }
            Button(action: {
                withAnimation {
                    libraryManager.removeFromRecents(for: doc.id)
                }
            }) {
                Label("Remove from Recents", systemImage: "xmark.circle")
            }
            Divider()
            Button(role: .destructive, action: {
                withAnimation {
                    libraryManager.deleteDocument(doc)
                }
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Recent Section
    
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let openedDocs = libraryManager.documents.filter { $0.hasBeenOpened && !$0.hiddenFromRecents }
            if openedDocs.count > 1 {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent")
                        .font(.custom("EBGaramond-Regular", size: 22))
                        .foregroundColor(settings.textColor)
                        .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        ForEach(openedDocs.dropFirst().prefix(10)) { doc in
                            recentDocumentRow(for: doc)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    // MARK: - Recent Document Row
    
    private func recentDocumentRow(for document: ReadingDocument) -> some View {
        Button(action: {
            currentDocument = document
            withAnimation(.easeInOut(duration: 0.3)) {
                isReading = true
            }
        }) {
            HStack(spacing: 14) {
                // Thumbnail
                DocumentThumbnail(document: document)
                    .frame(width: 50, height: 70)
                    .cornerRadius(6)
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.name)
                        .font(.custom("EBGaramond-Regular", size: 17))
                        .foregroundColor(settings.textColor)
                        .lineLimit(1)
                    
                    HStack(spacing: 10) {
                        Text("\(Int(document.progress * 100))%")
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(document.isComplete ? settings.completedColor : settings.secondaryTextColor)
                        
                        Text("\(document.totalWords.formatted()) words")
                            .font(.custom("EBGaramond-Regular", size: 13))
                            .foregroundColor(settings.mutedTextColor)
                        
                        Spacer()
                        
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
            Button(action: {
                currentDocument = document
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }) {
                Label(document.currentWordIndex > 0 ? "Continue" : "Start", systemImage: "play")
            }
            Button(action: {
                libraryManager.resetProgress(for: document.id)
                if var updated = libraryManager.getDocument(id: document.id) {
                    updated.currentWordIndex = 0
                    currentDocument = updated
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }) {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
            Button(action: {
                newDocumentName = document.name
                documentToRename = document
            }) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: {
                documentForFolderSelection = document
            }) {
                Label("Move to Folder", systemImage: "folder")
            }
            Button(action: {
                withAnimation {
                    libraryManager.removeFromRecents(for: document.id)
                }
            }) {
                Label("Remove from Recents", systemImage: "xmark.circle")
            }
            Divider()
            Button(role: .destructive, action: {
                withAnimation {
                    libraryManager.deleteDocument(document)
                }
            }) {
                Label("Delete", systemImage: "trash")
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
        .opacity(showContent ? 1 : 0)
    }
    
    // MARK: - Helpers
    
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

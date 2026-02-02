import SwiftUI

struct LibraryView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Binding var selectedDocument: ReadingDocument?
    @Binding var isPresented: Bool
    
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
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(settings.mutedTextColor)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                if libraryManager.documents.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    documentList
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
                        onDelete: {
                            withAnimation {
                                libraryManager.deleteDocument(document)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Document Row

struct DocumentRow: View {
    let document: ReadingDocument
    let onContinue: () -> Void
    let onRestart: () -> Void
    let onDelete: () -> Void
    
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

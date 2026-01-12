import SwiftUI

struct LibraryView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @Binding var selectedDocument: ReadingDocument?
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color(hex: "1A1A1A")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Library")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .foregroundColor(Color(hex: "E5E5E5"))
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(Color(hex: "666666"))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                if libraryManager.documents.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(Color(hex: "444444"))
                        Text("No documents yet")
                            .font(.custom("EBGaramond-Regular", size: 18))
                            .foregroundColor(Color(hex: "666666"))
                        Text("Import a document to get started")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(Color(hex: "555555"))
                    }
                    Spacer()
                } else {
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
        }
    }
}

struct DocumentRow: View {
    let document: ReadingDocument
    let onContinue: () -> Void
    let onRestart: () -> Void
    let onDelete: () -> Void
    
    @State private var showActions = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.name)
                        .font(.custom("EBGaramond-Regular", size: 18))
                        .foregroundColor(Color(hex: "E5E5E5"))
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        // Progress
                        Text("\(Int(document.progress * 100))%")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(document.isComplete ? Color(hex: "4CAF50") : Color(hex: "888888"))
                        
                        // Word count
                        Text("\(document.totalWords) words")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(Color(hex: "666666"))
                        
                        // Last read
                        Text(timeAgo(from: document.lastReadDate))
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(Color(hex: "555555"))
                    }
                }
                
                Spacer()
                
                // Continue/Start button
                Button(action: onContinue) {
                    Text(document.currentWordIndex > 0 ? "Continue" : "Start")
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(Color(hex: "1A1A1A"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(hex: "E5E5E5"))
                        .cornerRadius(6)
                }
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(hex: "2A2A2A"))
                        .frame(height: 3)
                        .cornerRadius(1.5)
                    
                    Rectangle()
                        .fill(document.isComplete ? Color(hex: "4CAF50") : Color(hex: "E63946"))
                        .frame(width: geo.size.width * document.progress, height: 3)
                        .cornerRadius(1.5)
                }
            }
            .frame(height: 3)
        }
        .padding(16)
        .background(Color(hex: "232323"))
        .cornerRadius(12)
        .contextMenu {
            Button(action: onRestart) {
                Label("Restart", systemImage: "arrow.counterclockwise")
            }
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

import SwiftUI

struct ExploreView: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var searchService = BookSearchService()
    @ObservedObject var libraryManager = LibraryManager.shared
    @State private var searchText = ""
    
    // Binding to the root content view to trigger opening the reader
    // We could pass an action closure instead
    
    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Explore")
                        .font(.custom("EBGaramond-Regular", size: 28))
                        .foregroundColor(settings.textColor)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(settings.mutedTextColor)
                    
                    TextField("Search books, authors...", text: $searchText, onCommit: {
                        searchService.search(query: searchText)
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(settings.textColor)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchService.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(settings.mutedTextColor)
                        }
                    }
                }
                .padding(12)
                .background(settings.cardBackgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
                // Results Area
                ZStack {
                    if searchService.isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                            .scaleEffect(1.5)
                    } else if let errorMessage = searchService.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else if searchService.searchResults.isEmpty {
                        Text("No results found.")
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(settings.mutedTextColor)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(searchService.searchResults) { book in
                                    let isDownloaded = libraryManager.documents.contains(where: { $0.name == book.title })
                                    ExploreBookRow(book: book, isDownloaded: isDownloaded, onDownload: {
                                        // Download Action
                                        downloadAndParse(book)
                                    })
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Padding for bottom tab bar
                            Color.clear.frame(height: 100)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // Fetch initial books on load
            if searchService.searchResults.isEmpty && !searchService.isSearching {
                searchService.fetchPopularBooks()
            }
        }
    }
    
    private func downloadAndParse(_ book: GutenbergBook) {
        guard let url = book.bestDownloadURL else {
            print("No readable format found for book")
            return
        }
        
        let ext = book.epubURL != nil ? "epub" : "txt"
        
        // Let's trigger a notification or post via NotificationCenter to show loading in ContentView 
        // OR pass a binding. For now, we will post a notification that ContentView listens to
        NotificationCenter.default.post(name: NSNotification.Name("DownloadAndReadBook"), object: nil, userInfo: ["url": url, "title": book.title, "ext": ext])
    }
}

// MARK: - Explore Book Row

struct ExploreBookRow: View {
    let book: GutenbergBook
    let isDownloaded: Bool
    let onDownload: () -> Void
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        HStack(spacing: 14) {
            // Cover Art
            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 75)
                            .clipped()
                    } else if phase.error != nil {
                        fallbackCover
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.cardBackgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 1)
                                )
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .frame(width: 50, height: 75)
                .cornerRadius(6)
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            } else {
                fallbackCover
                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.custom("EBGaramond-Regular", size: 17))
                    .foregroundColor(settings.textColor)
                    .lineLimit(2)
                
                Text(book.primaryAuthorName)
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(settings.secondaryTextColor)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                    .padding(8)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(settings.accentColor)
                        .padding(8)
                }
            }
        }
        .padding(14)
        .background(settings.cardBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private var fallbackCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(settings.cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                )
            
            VStack(spacing: 4) {
                Image(systemName: "book.pages")
                    .font(.system(size: 14))
                    .foregroundColor(settings.mutedTextColor.opacity(0.7))
                
                if let firstLetter = book.title.first {
                    Text(String(firstLetter))
                        .font(.custom("EBGaramond-Regular", size: 24))
                        .foregroundColor(settings.mutedTextColor)
                }
            }
        }
        .frame(width: 50, height: 75)
    }
}

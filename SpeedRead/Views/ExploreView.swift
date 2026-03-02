import SwiftUI

struct ExploreView: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var searchService = BookSearchService()
    @ObservedObject var libraryManager = LibraryManager.shared
    @State private var searchText = ""
    @State private var selectedGenre: String? = nil
    
    let genres = ["Fantasy", "Mystery", "Romance", "Philosophy", "History", "Horror"]
    
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
                    
                    TextField("Search books, authors...", text: $searchText, onCommit: performSearch)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(settings.textColor)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            performSearch()
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
                .padding(.bottom, 8)
                
                // Category Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        GenreChip(title: "All", isSelected: selectedGenre == nil) {
                            selectedGenre = nil
                            performSearch()
                        }
                        
                        ForEach(genres, id: \.self) { genre in
                            GenreChip(title: genre, isSelected: selectedGenre == genre) {
                                if selectedGenre == genre {
                                    selectedGenre = nil
                                } else {
                                    selectedGenre = genre
                                }
                                performSearch()
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
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
                            searchResultsView
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
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ResetExploreView"))) { _ in
            searchText = ""
            selectedGenre = nil
            searchService.clearSearch()
        }
    }
    
    // MARK: - Subviews
    
    private var storefrontView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Trending Section
            if !searchService.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Trending Now")
                        .font(.custom("EBGaramond-Regular", size: 22))
                        .foregroundColor(settings.textColor)
                        .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(searchService.searchResults.prefix(15))) { book in
                                let isDownloaded = libraryManager.documents.contains(where: { $0.name == book.title || $0.originalName == book.title })
                                StorefrontBookCard(book: book, isDownloaded: isDownloaded) {
                                    downloadAndParse(book)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 8)
            }
            
            // Padding for bottom tab bar
            Color.clear.frame(height: 100)
        }
    }
    
    private var searchResultsView: some View {
        LazyVStack(spacing: 12) {
            ForEach(searchService.searchResults) { book in
                // Check against both current name and original name to handle renamed books
                let isDownloaded = libraryManager.documents.contains(where: { $0.name == book.title || $0.originalName == book.title })
                ExploreBookRow(book: book, isDownloaded: isDownloaded, onDownload: {
                    // Download Action
                    downloadAndParse(book)
                })
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 100) // Padding for bottom tab bar
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        searchService.search(query: searchText, topic: selectedGenre)
    }
    
    private func downloadAndParse(_ book: GutenbergBook) {
        guard let url = book.bestDownloadURL else {
            print("No readable format found for book")
            return
        }
        
        let ext = book.epubURL != nil ? "epub" : "txt"
        
        // Let's trigger a notification or post via NotificationCenter to show loading in ContentView 
        // OR pass a binding. For now, we will post a notification that ContentView listens to
        var userInfo: [String: Any] = ["url": url, "title": book.title, "ext": ext]
        if let coverURL = book.coverURL {
            userInfo["coverURL"] = coverURL
        }
        NotificationCenter.default.post(name: NSNotification.Name("DownloadAndReadBook"), object: nil, userInfo: userInfo)
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
                
                if let genre = book.primaryGenre {
                    Text(genre.uppercased())
                        .font(.custom("EBGaramond-Regular", size: 10))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(settings.cardBorderColor.opacity(0.15))
                        .foregroundColor(settings.secondaryTextColor)
                        .cornerRadius(6)
                        .padding(.top, 2)
                }
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
        .contentShape(Rectangle()) // Makes the whole row tappable, even empty spaces
        .onTapGesture(perform: onDownload)
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

// MARK: - Genre Chip

struct GenreChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("EBGaramond-Regular", size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? settings.accentColor : settings.cardBackgroundColor)
                .foregroundColor(isSelected ? .white : settings.textColor)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? settings.accentColor : settings.cardBorderColor.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Storefront Book Card

struct StorefrontBookCard: View {
    let book: GutenbergBook
    let isDownloaded: Bool
    let onDownload: () -> Void
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Art
            if let coverURL = book.coverURL {
                AsyncImage(url: coverURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 180)
                            .clipped()
                    } else if phase.error != nil {
                        fallbackCover
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.cardBackgroundColor)
                            ProgressView()
                        }
                    }
                }
                .frame(width: 120, height: 180)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
            } else {
                fallbackCover
                    .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.textColor)
                    .lineLimit(2)
                    .frame(height: 44, alignment: .topLeading) // Fixed height to keep cards aligned
                
                HStack {
                    Text(book.primaryAuthorName)
                        .font(.custom("EBGaramond-Regular", size: 14))
                        .foregroundColor(settings.secondaryTextColor)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if isDownloaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                    } else {
                        Button(action: onDownload) {
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.system(size: 16))
                                .foregroundColor(settings.accentColor)
                        }
                    }
                }
            }
            .frame(width: 120)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDownload)
    }
    
    private var fallbackCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(settings.cardBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                )
            
            VStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 24))
                    .foregroundColor(settings.mutedTextColor.opacity(0.7))
                
                if let firstLetter = book.title.first {
                    Text(String(firstLetter))
                        .font(.custom("EBGaramond-Regular", size: 36))
                        .foregroundColor(settings.mutedTextColor)
                }
            }
        }
        .frame(width: 120, height: 180)
    }
}

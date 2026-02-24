import SwiftUI

struct ContentView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @State private var showDocumentPicker = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var currentDocument: ReadingDocument? = nil
    @State private var isReading = false
    @State private var showContent = false
    @State private var selectedTab = 0
    @State private var isProcessingDocument = false
    
    // Most recent document for Resume feature
    private var mostRecentDocument: ReadingDocument? {
        libraryManager.documents.first
    }
    
    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()
            
            if isReading, let doc = currentDocument {
                RSVPView(
                    text: doc.content,
                    documentId: doc.id,
                    startIndex: doc.currentWordIndex,
                    initialWPM: doc.wordsPerMinute,
                    onExit: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isReading = false
                            currentDocument = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                ZStack(alignment: .bottom) {
                    TabView(selection: $selectedTab) {
                        HomeView(
                            showDocumentPicker: $showDocumentPicker,
                            showSettings: $showSettings,
                            showContent: $showContent,
                            currentDocument: $currentDocument,
                            isReading: $isReading
                        )
                        .tag(0)
                        
                        LibraryView(
                            selectedDocument: $currentDocument,
                            isPresented: .constant(true) // Not dismissible here
                        )
                        .tag(1)
                        
                        ExploreView()
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea(edges: .bottom) // Ensure content goes behind the tab bar
                    
                    // Custom Floating Liquid Glass Tab Bar
                    CustomTabBar(selectedTab: $selectedTab)
                }
            }
            if isProcessingDocument {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: settings.accentColor))
                        .scaleEffect(1.5)
                    
                    Text("Downloading...")
                        .font(.custom("EBGaramond-Regular", size: 18))
                        .foregroundColor(settings.textColor)
                }
                .padding(32)
                .background(settings.cardBackgroundColor)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .animation(.easeInOut(duration: 0.3), value: isReading)
        .animation(.easeInOut(duration: 0.2), value: isProcessingDocument)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { pickedDoc in
                let fileName = pickedDoc.url.deletingPathExtension().lastPathComponent
                
                // Check if document already exists
                if let existingDoc = libraryManager.documents.first(where: { $0.name == fileName }) {
                    currentDocument = existingDoc
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                    return
                }
                
                // If content is already present (small text files), use it.
                if let availableContent = pickedDoc.content {
                    let doc = libraryManager.addDocument(name: fileName, content: availableContent, sourceBookmark: pickedDoc.bookmark)
                    currentDocument = doc
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                } else {
                    isProcessingDocument = true
                    // Content is nil, meaning we need to parse it asynchronously
                    // Show some loading state or just process in background while sheet dismisses
                    Task {
                        // Offload parsing to background
                        if let result = await Task.detached(priority: .userInitiated, operation: {
                            return DocumentParser.parseWithNavigation(url: pickedDoc.url)
                        }).value {
                            
                            // Back on Main Actor
                            await MainActor.run {
                                let doc = libraryManager.addDocument(
                                    name: fileName, 
                                    content: result.text, 
                                    sourceBookmark: pickedDoc.bookmark,
                                    navigationPoints: result.navigationPoints // Pass the sections!
                                )
                                currentDocument = doc
                                isProcessingDocument = false
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isReading = true
                                }
                            }
                        } else {
                             // Handle failure (e.g. show alert)
                             print("Failed to parse document async")
                             await MainActor.run {
                                 isProcessingDocument = false
                             }
                        }
                        
                        // Clean up temp file
                        try? FileManager.default.removeItem(at: pickedDoc.url)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DownloadAndReadBook")), perform: { notification in
            guard let userInfo = notification.userInfo,
                  let url = userInfo["url"] as? URL,
                  let title = userInfo["title"] as? String else { return }
            
            let ext = userInfo["ext"] as? String ?? "txt"
            downloadAndOpenBook(url: url, title: title, ext: ext)
        })
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                showContent = true
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }
    
    // MARK: - Downloading
    
    private func downloadAndOpenBook(url: URL, title: String, ext: String) {
        // Check if document already exists
        if let existingDoc = libraryManager.documents.first(where: { $0.name == title }) {
            currentDocument = existingDoc
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }
            return
        }
        
        isProcessingDocument = true
        // Show a loading indicator ideally, but for now we'll just download in the background
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("Failed to download book")
                    await MainActor.run { isProcessingDocument = false }
                    return
                }
                
                // Temporary file to let the parser try to parse it
                let tempDir = FileManager.default.temporaryDirectory
                let safeTitle = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                let tempFileURL = tempDir.appendingPathComponent("\(safeTitle).\(ext)")
                try data.write(to: tempFileURL)
                
                // Parse it (we can reuse existing DocumentParser)
                if let result = await Task.detached(priority: .userInitiated, operation: {
                    return DocumentParser.parseWithNavigation(url: tempFileURL)
                }).value {
                    // Back on main
                    await MainActor.run {
                        let doc = libraryManager.addDocument(
                            name: title,
                            content: result.text,
                            sourceBookmark: nil,
                            navigationPoints: result.navigationPoints
                        )
                        currentDocument = doc
                        isProcessingDocument = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isReading = true
                        }
                    }
                } else {
                    await MainActor.run { isProcessingDocument = false }
                }
                
                // Cleanup
                try? FileManager.default.removeItem(at: tempFileURL)
                
            } catch {
                print("Failed to download text: \(error)")
                await MainActor.run { isProcessingDocument = false }
            }
        }
    }
    
    // MARK: - URL Handling
    
    private func handleOpenURL(_ url: URL, retryCount: Int = 0) {
        guard url.scheme == "axilo",
              url.host == "open",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idString)
        else { return }
        
        // Force reload from disk
        libraryManager.refresh()
        libraryManager.objectWillChange.send()
        
        if let doc = libraryManager.getDocument(id: id) {
            currentDocument = doc
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }
        } else if retryCount < 3 {
             // Retry mechanism for race condition
             print("Document not found yet, retrying... (\(retryCount + 1)/3)")
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                 handleOpenURL(url, retryCount: retryCount + 1)
             }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}

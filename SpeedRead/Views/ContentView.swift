import SwiftUI

struct ContentView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var deviceScanner = DeviceBookScanner.shared
    @State private var showDocumentPicker = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var currentDocument: ReadingDocument? = nil
    @State private var isReading = false
    @State private var showContent = false
    @State private var selectedTab = 1
    @State private var isProcessingDocument = false
    @State private var explorePagerLocked = false
    @State private var showFolderPicker = false
    @State private var showContentLoadError = false
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @AppStorage("hasAddedSample") private var hasAddedSample = false
    
    // Download completion popup state
    @State private var showDownloadActionPopup = false
    @State private var newlyDownloadedDocument: ReadingDocument? = nil
    @State private var documentToAssignFolder: ReadingDocument? = nil
    
    // Most recent document for Resume feature
    private var mostRecentDocument: ReadingDocument? {
        libraryManager.documents.first
    }
    
    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()
            
            if isReading, let doc = currentDocument {
                if let text = libraryManager.loadContent(for: doc.id) {
                    RSVPView(
                        text: text,
                        documentId: doc.id,
                        startIndex: doc.currentWordIndex,
                        initialWPM: doc.wordsPerMinute,
                        isSampleText: doc.name == "Tutorial",
                        onExit: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isReading = false
                                currentDocument = nil
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                } else {
                    // Content file unreadable — back out instead of
                    // presenting a silently blank reader.
                    Color.clear.onAppear {
                        isReading = false
                        currentDocument = nil
                        showContentLoadError = true
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    TabView(selection: $selectedTab) {
                        LibraryView(
                            selectedDocument: $currentDocument,
                            isPresented: .constant(true),
                            isReading: $isReading
                        )
                        .tag(0)
                        
                        HomeView(
                            showSettings: $showSettings,
                            showContent: $showContent,
                            currentDocument: $currentDocument,
                            isReading: $isReading
                        )
                        .tag(1)
                        
                        ExploreView()
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea(edges: .bottom)
                    .onChange(of: selectedTab) { _, newTab in
                        #if !APPEXTENSION
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                        // Insurance: never leave the pager locked after
                        // navigating away from Explore (tag 2) via the tab
                        // bar mid-scroll — its idle event may not arrive.
                        if newTab != 2 {
                            explorePagerLocked = false
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToHomeTab"))) { _ in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = 1
                        }
                    }
                    // Explore locks the pager while its browse list is in
                    // motion so a catch-touch's horizontal drag can't slide
                    // the page (the carousels can't receive that touch).
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExplorePagerLock"))) { note in
                        explorePagerLocked = (note.userInfo?["locked"] as? Bool) ?? false
                    }
                    // Disable the UIKit scroll view backing the paged TabView during drag
                    .background(
                        TabViewScrollDisabler(disabled: libraryManager.isDraggingDocument || explorePagerLocked)
                    )
                    
                    // Custom Floating Liquid Glass Tab Bar
                    CustomTabBar(selectedTab: $selectedTab, showDocumentPicker: $showDocumentPicker) {
                        #if !APPEXTENSION
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        #endif
                    }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
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
            
            if showDownloadActionPopup, let doc = newlyDownloadedDocument {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDownloadActionPopup = false
                            newlyDownloadedDocument = nil
                        }
                    }
                
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(settings.completedColor)
                        
                        Text("Download Complete")
                            .font(.custom("EBGaramond-Regular", size: 24))
                            .foregroundColor(settings.textColor)
                            .multilineTextAlignment(.center)
                        
                        Text(doc.name)
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(settings.secondaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    
                    VStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDownloadActionPopup = false
                            }
                            // Give popup time to dismiss
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                currentDocument = newlyDownloadedDocument
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isReading = true
                                }
                                newlyDownloadedDocument = nil
                            }
                        } label: {
                            Text("Read Now")
                                .font(.custom("EBGaramond-Regular", size: 18))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(settings.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            let docToAssign = newlyDownloadedDocument
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDownloadActionPopup = false
                                newlyDownloadedDocument = nil
                            }
                            // Give popup time to dismiss
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                documentToAssignFolder = docToAssign
                            }
                        } label: {
                            Text("Add to Folder")
                                .font(.custom("EBGaramond-Regular", size: 18))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(settings.backgroundColor)
                                .foregroundColor(settings.textColor)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(settings.cardBorderColor, lineWidth: 1)
                                )
                        }
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showDownloadActionPopup = false
                                newlyDownloadedDocument = nil
                            }
                        } label: {
                            Text("Dismiss")
                                .font(.custom("EBGaramond-Regular", size: 16))
                                .foregroundColor(settings.mutedTextColor)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(24)
                .background(settings.cardBackgroundColor)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
                .padding(.horizontal, 40)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .animation(.easeInOut(duration: 0.3), value: isReading)
        .animation(.easeInOut(duration: 0.2), value: isProcessingDocument)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
                .presentationBackground(settings.backgroundColor)
        }
        .sheet(item: $documentToAssignFolder) { doc in
            FolderSelectionView(
                document: doc,
                onSelect: { folder in
                    libraryManager.assignDocument(id: doc.id, to: folder?.id)
                    documentToAssignFolder = nil
                },
                onCancel: {
                    documentToAssignFolder = nil
                }
            )
            .presentationDragIndicator(.visible)
            .presentationBackground(settings.backgroundColor)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { pickedDoc in
                showDocumentPicker = false
                let fileName = pickedDoc.url.deletingPathExtension().lastPathComponent
                
                // Check if document already exists by current name or original name
                if let existingDoc = libraryManager.documents.first(where: { $0.name == fileName || $0.originalName == fileName }) {
                    currentDocument = existingDoc
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                    return
                }
                
                // If content is already present (small text files), use it.
                if let availableContent = pickedDoc.content {
                    let doc = libraryManager.addDocument(name: fileName, content: availableContent, sourceBookmark: pickedDoc.bookmark)
                    newlyDownloadedDocument = doc
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showDownloadActionPopup = true
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
                                        name: result.title ?? fileName, 
                                        content: result.text, 
                                        sourceBookmark: pickedDoc.bookmark,
                                        navigationPoints: result.navigationPoints,
                                        figureAnnotations: result.figures,
                                        figureImages: result.figureImages
                                    )
                                currentDocument = doc
                                isProcessingDocument = false
                                newlyDownloadedDocument = doc
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showDownloadActionPopup = true
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
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker { url in
                showFolderPicker = false
                deviceScanner.saveFolderBookmark(for: url)
                deviceScanner.scan()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowFolderPicker"))) { _ in
            showFolderPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DownloadAndReadBook")), perform: { notification in
            guard let userInfo = notification.userInfo,
                  let url = userInfo["url"] as? URL,
                  let title = userInfo["title"] as? String else { return }
            
            let ext = userInfo["ext"] as? String ?? "txt"
            let coverURL = userInfo["coverURL"] as? URL
            downloadAndOpenBook(url: url, title: title, ext: ext, coverURL: coverURL)
        })
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                showContent = true
            }
            
            // Auto-scan linked folder for books
            if deviceScanner.hasFolderAccess {
                deviceScanner.scan()
            }

            // First-launch: auto-open the sample text in the reader.
            // Only for genuinely fresh installs — v1.x upgraders have
            // hasAddedSample set (or an existing library) and must land on
            // their books, not get pushed into the tutorial.
            if !hasLaunchedBefore {
                hasLaunchedBefore = true
                if !hasAddedSample && libraryManager.documents.isEmpty {
                    hasAddedSample = true
                    let doc = LibraryManager.shared.addDocument(name: "Tutorial", content: SampleText.content)
                    currentDocument = doc
                    // Small delay to let the UI settle before transitioning
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isReading = true
                        }
                    }
                }
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
        .alert("Couldn't Open Document", isPresented: $showContentLoadError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This document's text couldn't be loaded. Try importing it again.")
        }
    }
    
    // MARK: - Downloading
    
    private func downloadAndOpenBook(url: URL, title: String, ext: String, coverURL: URL? = nil) {
        // Check if document already exists
        if let existingDoc = libraryManager.documents.first(where: { $0.name == title || $0.originalName == title }) {
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
                            name: result.title ?? title,
                            content: result.text,
                            sourceBookmark: nil,
                            navigationPoints: result.navigationPoints,
                            figureAnnotations: result.figures,
                            figureImages: result.figureImages
                        )
                        
                        if let coverURL = coverURL {
                            Task.detached {
                                if let (coverData, _) = try? await URLSession.shared.data(from: coverURL),
                                   let coverImage = UIImage(data: coverData) {
                                    ThumbnailManager.shared.saveManualThumbnail(image: coverImage, for: doc.id)
                                }
                            }
                        }
                        
                        isProcessingDocument = false
                        newlyDownloadedDocument = doc
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDownloadActionPopup = true
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
        if url.isFileURL {
            let fileName = url.deletingPathExtension().lastPathComponent
            
            if let existingDoc = libraryManager.documents.first(where: { $0.name == fileName || $0.originalName == fileName }) {
                currentDocument = existingDoc
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                }
                return
            }
            
            isProcessingDocument = true
            Task {
                if let result = await Task.detached(priority: .userInitiated, operation: {
                    return DocumentParser.parseWithNavigation(url: url)
                }).value {
                    await MainActor.run {
                        let doc = libraryManager.addDocument(
                            name: result.title ?? fileName, 
                            content: result.text, 
                            sourceBookmark: nil,
                            navigationPoints: result.navigationPoints,
                            figureAnnotations: result.figures,
                            figureImages: result.figureImages
                        )
                        isProcessingDocument = false
                        newlyDownloadedDocument = doc
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDownloadActionPopup = true
                        }
                    }
                } else {
                     await MainActor.run { isProcessingDocument = false }
                }
            }
            return
        }

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

// MARK: - TabView Scroll Disabler
/// Finds the UIScrollView or UICollectionView backing a paged TabView and disables its scroll
/// when a drag-and-drop operation is active. This uses the view's window
/// to traverse down the entire hierarchy, avoiding `UIApplication.shared`
/// which is unavailable in app extensions.
struct TabViewScrollDisabler: UIViewRepresentable {
    let disabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let window = uiView.window else { return }
            findPagingScrollViews(in: window).forEach { scrollView in
                scrollView.isScrollEnabled = !disabled
            }
        }
    }

    private func findPagingScrollViews(in view: UIView) -> [UIScrollView] {
        var result: [UIScrollView] = []
        if let scrollView = view as? UIScrollView {
            // Only the real tab pager. The old full-width+horizontal
            // fallback (for iOS 16/17 collection views without paging set)
            // also matched the Explore carousels and browse list, disabling
            // the very views the user was trying to scroll.
            if scrollView.isPagingEnabled {
                result.append(scrollView)
            }
        }
        for subview in view.subviews {
            result.append(contentsOf: findPagingScrollViews(in: subview))
        }
        return result
    }
}

#Preview {
    ContentView()
}

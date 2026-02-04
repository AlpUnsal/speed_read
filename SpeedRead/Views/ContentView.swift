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
                homeScreen
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .animation(.easeInOut(duration: 0.3), value: isReading)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { pickedDoc in
                let fileName = pickedDoc.url.deletingPathExtension().lastPathComponent
                let doc = libraryManager.addDocument(name: fileName, content: pickedDoc.content, sourceBookmark: pickedDoc.bookmark)
                currentDocument = doc
                withAnimation(.easeInOut(duration: 0.3)) {
                    isReading = true
                }
            }
        }
        .sheet(isPresented: $showLibrary, onDismiss: {
            if currentDocument != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                }
            }
        }) {
            LibraryView(
                selectedDocument: $currentDocument,
                isPresented: $showLibrary
            )
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                showContent = true
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
    }
    
    // MARK: - Home Screen
    
    private var homeScreen: some View {
        VStack(spacing: 0) {
            // Settings button in top-right
            HStack {
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(settings.mutedTextColor)
                        .padding(12)
                        .background(Color.clear)
                }
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            .opacity(showContent ? 1 : 0)
            
            Spacer()
            
            // Main content
            VStack(spacing: 28) {
                // App Title
                Text("Axilo")
                    .font(.custom("EBGaramond-Regular", size: 52))
                    .foregroundColor(settings.textColor)
                
                // Resume button (if document available)
                if let doc = mostRecentDocument {
                    resumeButton(for: doc)
                }
                
                // Action buttons row
                HStack(spacing: 12) {
                    // Import Document
                    actionButton(
                        icon: "square.and.arrow.down",
                        title: "Import Document",
                        action: { showDocumentPicker = true }
                    )
                    
                    // Open Library (if documents exist)
                    if !libraryManager.documents.isEmpty {
                        actionButton(
                            icon: "books.vertical",
                            title: "Open Library (\(libraryManager.documents.count))",
                            action: { showLibrary = true }
                        )
                    }
                }
                .padding(.horizontal, 24)
                
                // Try Sample
                Button(action: {
                    let doc = libraryManager.addDocument(name: "Sample Text", content: SampleText.content)
                    currentDocument = doc
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 14, weight: .light))
                        Text("Try Sample")
                            .font(.custom("EBGaramond-Regular", size: 15))
                    }
                    .foregroundColor(settings.mutedTextColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
            
            Spacer()
            
            // Recent Library Section
            if libraryManager.documents.count > 0 {
                recentLibrarySection
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
            }
        }
    }
    
    // MARK: - Resume Button
    
    private func resumeButton(for doc: ReadingDocument) -> some View {
        Button(action: {
            currentDocument = doc
            withAnimation(.easeInOut(duration: 0.3)) {
                isReading = true
            }
        }) {
            HStack(spacing: 14) {
                // Book icon with subtle background
                ZStack {
                    Circle()
                        .fill(settings.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "book.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(settings.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue Reading")
                        .font(.custom("EBGaramond-Regular", size: 12))
                        .foregroundColor(settings.secondaryTextColor)
                    
                    Text(doc.name)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .foregroundColor(settings.textColor)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Progress indicator
                Text("\(Int(doc.progress * 100))%")
                    .font(.custom("EBGaramond-Regular", size: 14))
                    .foregroundColor(settings.secondaryTextColor)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(settings.mutedTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
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
        .padding(.horizontal, 24)
    }
    
    // MARK: - Action Button
    
    private func actionButton(icon: String, title: String, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                Text(title)
                    .font(.custom("EBGaramond-Regular", size: 15))
            }
            .foregroundColor(isPrimary ? settings.primaryButtonTextColor : settings.textColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPrimary ? settings.primaryButtonBackgroundColor : settings.cardBackgroundColor)
                    .shadow(color: Color.black.opacity(isPrimary ? 0.15 : 0.06), radius: isPrimary ? 6 : 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(settings.cardBorderColor.opacity(isPrimary ? 0 : 0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Recent Library Section
    
    private var recentLibrarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent")
                .font(.custom("EBGaramond-Regular", size: 18))
                .foregroundColor(settings.secondaryTextColor)
                .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(libraryManager.documents.prefix(10)) { document in
                        DocumentCard(
                            document: document,
                            onTap: {
                                currentDocument = document
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isReading = true
                                }
                            },
                            onDelete: {
                                withAnimation {
                                    libraryManager.deleteDocument(document)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 32)
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

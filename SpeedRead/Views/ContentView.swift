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
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                VStack(spacing: 32) {
                    Spacer()
                    
                    Text("SpeedRead")
                        .font(.custom("EBGaramond-Regular", size: 48))
                        .foregroundColor(settings.textColor)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                    
                    VStack(spacing: 16) {
                        // Import Document button
                        Button(action: { showDocumentPicker = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 18))
                                Text("Import Document")
                                    .font(.custom("EBGaramond-Regular", size: 18))
                            }
                            .foregroundColor(Color(hex: "1A1A1A"))
                            .frame(width: 200)
                            .padding(.vertical, 14)
                            .background(Color(hex: "E5E5E5"))
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Library button (if has documents)
                        if !libraryManager.documents.isEmpty {
                            Button(action: { showLibrary = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "books.vertical")
                                        .font(.system(size: 18))
                                    Text("Library (\(libraryManager.documents.count))")
                                        .font(.custom("EBGaramond-Regular", size: 18))
                                }
                                .foregroundColor(Color(hex: "888888"))
                                .frame(width: 200)
                                .padding(.vertical, 14)
                                .background(Color(hex: "2A2A2A"))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Try Sample button
                        Button(action: {
                            let doc = libraryManager.addDocument(name: "Sample Text", content: SampleText.content)
                            currentDocument = doc
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isReading = true
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 16))
                                Text("Try Sample")
                                    .font(.custom("EBGaramond-Regular", size: 16))
                            }
                            .foregroundColor(Color(hex: "666666"))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 20)
                    
                    Spacer()
                }
            }
        }
            // Settings Button
            if !isReading {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20))
                        .foregroundColor(settings.secondaryTextColor)
                        .padding()
                        .background(Color.black.opacity(0.01)) // Increase touch target
                }
                .padding(.top, 40)
                .padding(.trailing, 20)
                .opacity(showContent ? 1 : 0)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .animation(.easeInOut(duration: 0.3), value: isReading)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in
                if let text = DocumentParser.parse(url: url) {
                    let fileName = url.deletingPathExtension().lastPathComponent
                    let doc = libraryManager.addDocument(name: fileName, content: text)
                    currentDocument = doc
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isReading = true
                    }
                }
            }
        }
        .sheet(isPresented: $showLibrary, onDismiss: {
            // When library closes, start reading if a document was selected
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

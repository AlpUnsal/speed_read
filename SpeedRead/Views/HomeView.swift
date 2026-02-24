import SwiftUI

struct HomeView: View {
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @Binding var showDocumentPicker: Bool
    @Binding var showSettings: Bool
    @Binding var showContent: Bool
    @Binding var currentDocument: ReadingDocument?
    @Binding var isReading: Bool
    @AppStorage("hasAddedSample") private var hasAddedSample = false
    
    // Most recent document for Resume feature
    private var mostRecentDocument: ReadingDocument? {
        libraryManager.documents.first
    }
    
    var body: some View {
        ZStack {
            settings.backgroundColor
                .ignoresSafeArea()
            
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
                    }
                    .padding(.horizontal, 24)
                    
                    
                    // Try Sample
                    if !hasAddedSample {
                        Button(action: {
                            let doc = libraryManager.addDocument(name: "Sample Text", content: SampleText.content)
                            currentDocument = doc
                            hasAddedSample = true
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
                
                // Padding for bottom tab bar
                Spacer().frame(height: 80)
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
}

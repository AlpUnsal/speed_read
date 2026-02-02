import SwiftUI

/// A view that generates aesthetically pleasing thumbnails for documents
/// Uses text-based abstract covers derived from document content
struct DocumentThumbnail: View {
    let document: ReadingDocument
    let settings = SettingsManager.shared
    
    // Generate a consistent color from document name
    private var coverColor: Color {
        let hash = abs(document.name.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.25, brightness: settings.theme == .light ? 0.85 : 0.25)
    }
    
    // Get first sentence or fragment for display
    private var excerpt: String {
        let words = document.content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let excerptWords = Array(words.prefix(12))
        let text = excerptWords.joined(separator: " ")
        return text.count > 60 ? String(text.prefix(60)) + "..." : text
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background with subtle gradient
                LinearGradient(
                    colors: [coverColor, coverColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Content overlay
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    
                    // Excerpt text (subtle, like a quote)
                    if !excerpt.isEmpty {
                        Text(""\(excerpt)"")
                            .font(.custom("EBGaramond-Italic", size: 9))
                            .foregroundColor(settings.textColor.opacity(0.4))
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                    
                    // Title area with frosted effect
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.name)
                            .font(.custom("EBGaramond-Regular", size: 12))
                            .fontWeight(.medium)
                            .foregroundColor(settings.textColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Text("\(document.totalWords) words")
                            .font(.custom("EBGaramond-Regular", size: 9))
                            .foregroundColor(settings.secondaryTextColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        settings.cardBackgroundColor.opacity(0.85)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.cardBorderColor.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}

/// A document card for the home screen carousel
struct DocumentCard: View {
    let document: ReadingDocument
    let onTap: () -> Void
    let settings = SettingsManager.shared
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                DocumentThumbnail(document: document)
                    .aspectRatio(2/3, contentMode: .fit)
                    .frame(width: 100, height: 150)
                
                // Title
                Text(document.name)
                    .font(.custom("EBGaramond-Regular", size: 13))
                    .foregroundColor(settings.textColor)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
                
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
                .frame(width: 100, height: 3)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack {
        DocumentCard(
            document: ReadingDocument(name: "The Great Gatsby", content: "In my younger and more vulnerable years my father gave me some advice that I've been turning over in my mind ever since."),
            onTap: {}
        )
        .padding()
    }
    .background(Color(hex: "1A1A1A"))
}

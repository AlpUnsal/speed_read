import Foundation

/// Represents a figure/exhibit extracted from a document (e.g., PDF)
struct FigureAnnotation: Codable, Identifiable, Equatable {
    let id: UUID
    let wordIndex: Int        // Word index in the document where the figure appears
    let caption: String?      // Detected caption text (e.g., "Figure 1: ...")
    let imageFileName: String // Filename stored in Figures/<documentId>/ directory
    
    init(id: UUID = UUID(), wordIndex: Int, caption: String?, imageFileName: String) {
        self.id = id
        self.wordIndex = wordIndex
        self.caption = caption
        self.imageFileName = imageFileName
    }
}

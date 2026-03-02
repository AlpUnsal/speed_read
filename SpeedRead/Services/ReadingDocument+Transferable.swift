import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTType for in-app drag & drop

extension UTType {
    /// Private type used exclusively for dragging ReadingDocument within the app.
    static let readingDocument = UTType(exportedAs: "com.alpunsal.axilo.readingDocument")
}

// MARK: - Transferable conformance

extension ReadingDocument: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .readingDocument)
    }
}

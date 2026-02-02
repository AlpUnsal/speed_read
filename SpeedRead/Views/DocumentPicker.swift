import SwiftUI
import UniformTypeIdentifiers

/// Result of picking a document with all necessary data
struct PickedDocument {
    let url: URL
    let content: String
    let bookmark: Data?
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentPicked: (PickedDocument) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .pdf,
            .plainText,
            .rtf,
            UTType("org.openxmlformats.wordprocessingml.document") ?? .data, // DOCX
            UTType("org.idpf.epub-container") ?? .data // EPUB
        ]
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (PickedDocument) -> Void
        
        init(onDocumentPicked: @escaping (PickedDocument) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            
            // Create bookmark WHILE we have access
            let bookmark = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            // Parse content WHILE we have access
            guard let content = DocumentParser.parse(url: url) else { return }
            
            onDocumentPicked(PickedDocument(url: url, content: content, bookmark: bookmark))
        }
    }
}

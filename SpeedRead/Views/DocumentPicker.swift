import SwiftUI
import UniformTypeIdentifiers

/// Result of picking a document with all necessary data
struct PickedDocument {
    let url: URL
    let content: String? // Changed to Optional
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
            
            // COPY file to temp directory so we can access it after this scope ends
            let tempDir = FileManager.default.temporaryDirectory
            let tempURL = tempDir.appendingPathComponent(url.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
                
                // Return immediately with temp URL, NO PARSING yet
                onDocumentPicked(PickedDocument(url: tempURL, content: nil, bookmark: bookmark))
                
            } catch {
                print("Failed to copy file from picker: \(error)")
            }
        }
    }
}

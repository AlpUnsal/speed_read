import SwiftUI
import UIKit

/// A wrapper struct for presenting a dictionary definition sheet via Identifiable
struct DefinedWord: Identifiable {
    let id = UUID()
    let term: String
}

extension String {
    /// Cleans the string for dictionary lookup by removing common punctuation
    func cleanForDictionary() -> String {
        let charactersToRemove = CharacterSet(charactersIn: ".,;:!?()[]\"'“”‘’")
        return self.components(separatedBy: charactersToRemove).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A SwiftUI wrapper for the native iOS dictionary view controller
struct DictionaryView: UIViewControllerRepresentable {
    let term: String
    
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        return UIReferenceLibraryViewController(term: term)
    }
    
    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {
        // No updates needed
    }
}

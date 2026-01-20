import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
        
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }
        
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                // Check for URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                        guard let self = self else { return }
                        
                        if let url = item as? URL {
                            self.handleURL(url)
                        } else if let urlString = item as? String, let url = URL(string: urlString) {
                             self.handleURL(url)
                        } else {
                             // Fallback or error
                             self.completeRequest()
                        }
                    }
                    return // Handle only the first valid URL found
                }
            }
        }
    
        // If we didn't find any URL
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }
    
    private func handleURL(_ url: URL) {
        // Fetch content from URL
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let htmlString = String(data: data, encoding: .utf8) else {
                self?.completeRequest()
                return
            }
            
            // Parse HTML
            let text = HTMLHelper.extractTextFromHTML(htmlString)
            let contentText = self.contentText ?? ""
            let title = contentText.isEmpty ? (response?.suggestedFilename ?? "New Article") : contentText
            
            if !text.isEmpty {
                 // Save to Library
                 DispatchQueue.main.async {
                     // Using the shared LibraryManager instance which now uses App Groups
                     let newDoc = LibraryManager.shared.addDocument(name: title, content: text)
                     
                     // Open the main app to read the document
                     let urlString = "speedread://open?id=\(newDoc.id.uuidString)"
                     if let url = URL(string: urlString) {
                         self.openURL(url)
                     }
                     
                     self.completeRequest()
                 }
            } else {
                self.completeRequest()
            }
            
        }.resume()
    }
    
    private func completeRequest() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    @objc func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = responder?.next
        }
        
        // Fallback for Extension (UIApplication is not available essentially, but openURL on extensionContext might work)
        // Actually, NSExtensionContext has an openURL method but it's not exposed in Swift perfectly sometimes.
        // Let's try to use the extensionContext open method which is the standard way.
        self.extensionContext?.open(url, completionHandler: nil)
    }
}

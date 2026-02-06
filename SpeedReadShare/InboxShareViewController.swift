import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

@objc(InboxShareViewController) // Explicit ObjC name to avoid module namespace/mangling issues in Storyboard
class InboxShareViewController: SLComposeServiceViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
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
                             self.completeRequest()
                        }
                    }
                    return 
                }
                
                // Fallback: Check for Plain Text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                        guard let self = self else { return }
                        
                        if let text = item as? String {
                            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                               let match = detector.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
                               let url = match.url {
                                self.handleURL(url)
                            } else {
                                self.completeRequest()
                            }
                        } else {
                             self.completeRequest()
                        }
                    }
                    return
                }
            }
        }
    
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
    
    private func handleURL(_ url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        let supportedExtensions = ["pdf", "epub", "docx", "txt", "rtf"]
        
        if url.isFileURL || supportedExtensions.contains(fileExtension) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // print("SHARE_DEBUG: Calling DocumentParser.parseAndSave...")
                if let savedID = DocumentParser.parseAndSave(url: url) {
                    // print("SHARE_DEBUG: Saved ID: \(savedID). Opening App...")
                    
                    DispatchQueue.main.async {
                        self.openMainApp(documentId: savedID)
                        self.completeRequest()
                    }
                } else {
                    // print("SHARE_DEBUG: parseAndSave Failed")
                    DispatchQueue.main.async {
                        self.completeRequest()
                    }
                }
            }
            return
        }
        
        guard url.scheme?.hasPrefix("http") == true else {
            self.completeRequest()
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let htmlString = String(data: data, encoding: .utf8) else {
                self?.completeRequest()
                return
            }
            
            let text = HTMLHelper.extractTextFromHTML(htmlString)
            let contentText = self.contentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let extractedTitle = HTMLHelper.extractTitle(from: htmlString)
            
            var title = contentText
            if title.isEmpty || self.isURL(title) {
                 if let validExtracted = extractedTitle, !validExtracted.isEmpty {
                     title = validExtracted
                 } else if title.isEmpty {
                     title = response?.suggestedFilename ?? "New Article"
                 }
            }
            
            if !text.isEmpty {
                 DispatchQueue.main.async {
                     let newDoc = LibraryManager.shared.addDocument(name: title, content: text)
                     self.openMainApp(documentId: newDoc.id)
                     self.completeRequest()
                 }
            } else {
                self.completeRequest()
            }
        }.resume()
    }
    
    private func openMainApp(documentId: UUID) {
        let urlString = "axilo://open?id=\(documentId.uuidString)"
        if let url = URL(string: urlString) {
            self.openURL(url)
        }
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
        self.extensionContext?.open(url, completionHandler: nil)
    }
    
    private func isURL(_ string: String) -> Bool {
        if string.contains(" ") { return false }
        if let url = URL(string: string), url.scheme != nil {
            return true
        }
        return false
    }
}

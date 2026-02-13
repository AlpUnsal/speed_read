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
            completeRequest()
            return
        }
        
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            
            // 1. Try JavaScript Preprocessing Results (Richest Content)
            if let jsProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) }) {
                jsProvider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    
                    if let dict = item as? [String: Any],
                       let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                        
                        let html = results["html"] as? String ?? ""
                        let title = results["title"] as? String ?? (results["url"] as? String) ?? "New Article"
                        // let urlString = results["url"] as? String ?? ""
                        
                        if !html.isEmpty {
                            self.processHTMLContent(html: html, title: title)
                            return
                        }
                    }
                    
                    // Fallback if JS data was valid but empty (unlikely) or parsing failed
                    // We dispatch back to main to try finding a URL since we are already in async closure
                    DispatchQueue.main.async {
                        self.findAndHandleURL(attachments: attachments)
                    }
                }
                return // Stop here, wait for async load
            }
            
            // 2. Fallback: Standard URL/Text handling
            self.findAndHandleURL(attachments: attachments)
            return
        }
        
        completeRequest()
    }

    private func findAndHandleURL(attachments: [NSItemProvider]) {
        // Check for URL
        if let urlProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
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
        
        // Check for Plain Text
        if let textProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                guard let self = self else { return }
                
                if let text = item as? String {
                    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                       let match = detector.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
                       let url = match.url {
                        self.handleURL(url)
                    } else {
                        // Treat as plain text content? Not for now.
                        self.completeRequest()
                    }
                } else {
                     self.completeRequest()
                }
            }
            return
        }
        
        completeRequest()
    }

    override func configurationItems() -> [Any]! {
        return []
    }
    
    private func processHTMLContent(html: String, title: String) {
        let text = HTMLHelper.extractTextFromHTML(html)
        
        if !text.isEmpty {
             // Use safer lightweight saving mechanism that doesn't load whole library
             let newDoc = ReadingDocument(name: title, content: text)
             LibraryManager.saveToInbox(newDoc)
             
             DispatchQueue.main.async {
                 self.openMainApp(documentId: newDoc.id)
                 self.completeRequest()
             }
        } else {
            completeRequest()
        }
    }
    
    private func handleURL(_ url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        let supportedExtensions = ["pdf", "epub", "docx", "txt", "rtf"]
        
        if url.isFileURL || supportedExtensions.contains(fileExtension) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                if let savedID = DocumentParser.parseAndSave(url: url) {
                    DispatchQueue.main.async {
                        self.openMainApp(documentId: savedID)
                        self.completeRequest()
                    }
                } else {
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

        // Fallback for non-Safari shares (e.g. Messages app) that don't run JS
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let htmlString = String(data: data, encoding: .utf8) else {
                self?.completeRequest()
                return
            }
            
            let extractedTitle = HTMLHelper.extractTitle(from: htmlString)
            let userContentText = self.contentText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            var title = userContentText
            if title.isEmpty || self.isURL(title) {
                 if let validExtracted = extractedTitle, !validExtracted.isEmpty {
                     title = validExtracted
                 } else if title.isEmpty {
                     title = response?.suggestedFilename ?? "New Article"
                 }
            }
            
            self.processHTMLContent(html: htmlString, title: title)
            
        }.resume()
    }
    
    private func openMainApp(documentId: UUID) {
        let urlString = "axilo://open?id=\(documentId.uuidString)"
        if let url = URL(string: urlString) {
            self.extensionContext?.open(url, completionHandler: nil)
        }
    }
    
    private func completeRequest() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    private func isURL(_ string: String) -> Bool {
        if string.contains(" ") { return false }
        if let url = URL(string: string), url.scheme != nil {
            return true
        }
        return false
    }
}

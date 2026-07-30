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
                        let urlString = results["url"] as? String ?? ""

                        // X/Twitter pages share as an app-shell DOM full of UI chrome —
                        // fetch the post text through the tweet API instead.
                        if let pageURL = URL(string: urlString), let statusID = TweetFetcher.statusID(from: pageURL) {
                            self.processTweet(statusID: statusID)
                            return
                        }

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
             LibraryManager.saveToInbox(newDoc, content: text)
             
             DispatchQueue.main.async {
                 self.openMainApp(documentId: newDoc.id)
             }
        } else {
            completeRequest()
        }
    }
    
    private func processTweet(statusID: String) {
        TweetFetcher.fetch(statusID: statusID) { [weak self] tweet in
            guard let self = self else { return }

            guard let tweet = tweet else {
                DispatchQueue.main.async { self.completeRequest() }
                return
            }

            let body = TweetFetcher.documentBody(for: tweet)
            let newDoc = ReadingDocument(name: TweetFetcher.documentTitle(for: tweet), content: body)
            LibraryManager.saveToInbox(newDoc, content: body)

            DispatchQueue.main.async {
                self.openMainApp(documentId: newDoc.id)
            }
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

        // X/Twitter serves a JS-only shell to plain fetches, so the generic
        // download below would come back empty — use the tweet API instead.
        if let statusID = TweetFetcher.statusID(from: url) {
            processTweet(statusID: statusID)
            return
        }

        // Fallback for non-Safari shares (e.g. Messages app) that don't run JS
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            // A shortened link (e.g. t.co) may have redirected to an X post
            if let finalURL = response?.url, let statusID = TweetFetcher.statusID(from: finalURL) {
                self.processTweet(statusID: statusID)
                return
            }

            guard let data = data, let htmlString = String(data: data, encoding: .utf8) else {
                self.completeRequest()
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
        guard let url = URL(string: urlString) else { 
            self.completeRequest()
            return 
        }
        
        var responder: UIResponder? = self as UIResponder
        let selectorOpenURL = sel_registerName("openURL:")
        
        while let currentResponder = responder {
            if currentResponder.responds(to: selectorOpenURL) {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: { _ in
                    currentResponder.perform(selectorOpenURL, with: url)
                })
                return
            }
            responder = currentResponder.next
        }
        
        self.completeRequest()
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

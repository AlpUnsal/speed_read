import Foundation
import SwiftUI
import PDFKit
import QuickLookThumbnailing

/// Manages thumbnail generation and caching for documents
class ThumbnailManager {
    static let shared = ThumbnailManager()
    
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let thumbnailSize = CGSize(width: 200, height: 300)
    
    private var thumbnailDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let thumbnailDir = appSupport.appendingPathComponent("Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        return thumbnailDir
    }
    
    private init() {}
    
    /// Get thumbnail for a document, generating if needed (sync — cache + PDF only)
    func thumbnail(for documentId: UUID, sourceBookmark: Data?) -> UIImage? {
        let cacheKey = documentId.uuidString as NSString
        
        // Check memory cache
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        // Check disk cache
        let diskPath = thumbnailDirectory.appendingPathComponent("\(documentId.uuidString).jpg")
        if let diskImage = UIImage(contentsOfFile: diskPath.path) {
            cache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }
        
        // Generate from source if available (sync path for PDFs only)
        if let bookmark = sourceBookmark {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource() else {
                return nil
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            if url.pathExtension.lowercased() == "pdf" {
                if let image = generatePDFThumbnail(url: url) {
                    cache.setObject(image, forKey: cacheKey)
                    saveToDisk(image: image, documentId: documentId)
                    return image
                }
            }
        }
        
        return nil
    }
    
    /// Generate thumbnail from PDF using PDFKit
    private func generatePDFThumbnail(url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            return nil
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(thumbnailSize.width / pageRect.width, thumbnailSize.height / pageRect.height)
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            context.cgContext.translateBy(x: 0, y: scaledSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        return image
    }
    
    /// Save thumbnail to disk cache
    private func saveToDisk(image: UIImage, documentId: UUID) {
        let diskPath = thumbnailDirectory.appendingPathComponent("\(documentId.uuidString).jpg")
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: diskPath)
        }
    }
    
    /// Clear thumbnail for a document
    func clearThumbnail(for documentId: UUID) {
        let cacheKey = documentId.uuidString as NSString
        cache.removeObject(forKey: cacheKey)
        
        let diskPath = thumbnailDirectory.appendingPathComponent("\(documentId.uuidString).jpg")
        try? fileManager.removeItem(at: diskPath)
    }
    
    /// Generate thumbnail asynchronously (non-blocking)
    func generateThumbnailAsync(for documentId: UUID, sourceBookmark: Data?, completion: @escaping (UIImage?) -> Void) {
        // First try sync path (memory/disk cache + PDF)
        if let image = thumbnail(for: documentId, sourceBookmark: sourceBookmark) {
            completion(image)
            return
        }
        
        // For non-PDF files, use QuickLook with callback (no semaphore, no blocking)
        guard let bookmark = sourceBookmark else {
            completion(nil)
            return
        }
        
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            completion(nil)
            return
        }
        
        // Capture screen scale on current thread (likely main)
        let screenScale = UIScreen.main.scale
        
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: screenScale,
            representationTypes: .thumbnail
        )
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, error in
            url.stopAccessingSecurityScopedResource()
            
            let image = representation?.uiImage
            
            if let image = image, let self = self {
                let cacheKey = documentId.uuidString as NSString
                self.cache.setObject(image, forKey: cacheKey)
                self.saveToDisk(image: image, documentId: documentId)
            }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}

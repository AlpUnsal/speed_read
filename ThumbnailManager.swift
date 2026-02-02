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
    
    /// Get thumbnail for a document, generating if needed
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
        
        // Generate from source if available
        if let bookmark = sourceBookmark,
           let image = generateThumbnail(from: bookmark, documentId: documentId) {
            cache.setObject(image, forKey: cacheKey)
            saveToDisk(image: image, documentId: documentId)
            return image
        }
        
        return nil
    }
    
    /// Generate thumbnail from bookmark data
    private func generateThumbnail(from bookmark: Data, documentId: UUID) -> UIImage? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else {
            return nil
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "pdf":
            return generatePDFThumbnail(url: url)
        default:
            return generateQuickLookThumbnail(url: url)
        }
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
    
    /// Generate thumbnail using QuickLook (for other file types)
    private func generateQuickLookThumbnail(url: URL) -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )
        
        var resultImage: UIImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            resultImage = representation?.uiImage
            semaphore.signal()
        }
        
        semaphore.wait()
        return resultImage
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
    
    /// Generate thumbnail asynchronously
    func generateThumbnailAsync(for documentId: UUID, sourceBookmark: Data?, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = self?.thumbnail(for: documentId, sourceBookmark: sourceBookmark)
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}

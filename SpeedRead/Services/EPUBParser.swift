import Foundation
import ZIPFoundation
import OSLog

class EPUBParser {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SpeedRead", category: "EPUBParser")
    
    static func parse(url: URL) -> String? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            // Unzip the EPUB file
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: url, to: tempDir)
            
            // 1. Find the OPF file path from META-INF/container.xml
            let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
            guard let containerData = try? Data(contentsOf: containerURL) else {
                logger.error("Could not find container.xml")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            let containerParser = ContainerXMLParser(data: containerData)
            guard let opfPath = containerParser.parse(), !opfPath.isEmpty else {
                logger.error("Could not find OPF path in container.xml")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            // 2. Parse the OPF file to get manifest and spine
            let opfURL = tempDir.appendingPathComponent(opfPath)
            // The OPF path might be relative to the root, so we handle that.
            // But wait, if opfPath contains directories (e.g. "OEBPS/content.opf"), appending it to tempDir works.
            
            // We need the base path of the OPF file to resolve relative paths in the manifest
            let opfBasePath = opfURL.deletingLastPathComponent()
            
            guard let opfData = try? Data(contentsOf: opfURL) else {
                logger.error("Could not read OPF file at \(opfURL.path)")
                try? fileManager.removeItem(at: tempDir)
                return nil
            }
            
            let opfParser = OPFParser(data: opfData)
            let (manifest, spine) = opfParser.parse()
            
            // 3. Extract text from each chapter in spine order
            var fullText = ""
            
            for itemRef in spine {
                if let href = manifest[itemRef] {
                    // Resolve href relative to OPF file location
                    let chapterURL = opfBasePath.appendingPathComponent(href)
                    
                    if let chapterData = try? Data(contentsOf: chapterURL),
                       let chapterContent = String(data: chapterData, encoding: .utf8) {
                        
                        // Use DocumentParser's HTML extraction (we will update DocumentParser to make this internal)
                        let text = DocumentParser.extractTextFromHTML(chapterContent)
                        fullText += text + "\n\n"
                    } else {
                        logger.warning("Could not read chapter: \(href)")
                    }
                }
            }
            
            // Cleanup
            try? fileManager.removeItem(at: tempDir)
            
            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            logger.error("EPUB parsing failed: \(error.localizedDescription)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }
}

// MARK: - XML Parsers

private class ContainerXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var opfPath: String?
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> String? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return opfPath
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "rootfile", let fullPath = attributeDict["full-path"] {
            self.opfPath = fullPath
        }
    }
}

private class OPFParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var manifest: [String: String] = [:] // id -> href
    private var spine: [String] = [] // list of idrefs
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() -> ([String: String], [String]) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return (manifest, spine)
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "item" || elementName == "opf:item" { // handle optional namespaces roughly
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            }
        }
        
        if elementName == "itemref" || elementName == "opf:itemref" {
            if let idref = attributeDict["idref"] {
                spine.append(idref)
            }
        }
    }
}

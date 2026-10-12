import Foundation
import PreviewContracts

/// Descriptive metadata from an EPUB package document. Values are whitespace-collapsed single lines.
struct EPUBMetadata: Equatable, Sendable {
    var title: String?
    var creators: [String] = []
    var language: String?
    var publisher: String?
    var date: String?
    var identifier: String?
    var description: String?
}

struct EPUBManifestItem: Equatable, Sendable {
    let id: String
    let href: String
    let mediaType: String
    let properties: Set<String>
}

struct EPUBSpineItem: Equatable, Sendable {
    let idref: String
    let isLinear: Bool
}

/// The parts of an EPUB 2 or EPUB 3 package document this preview reads. Nothing is executed or fetched: the
/// package is data that names which archive members hold the cover, the navigation and the chapters.
struct EPUBPackage: Equatable, Sendable {
    static let maximumSpineItems = 2_000
    static let maximumManifestItems = 10_000

    let path: String
    var metadata = EPUBMetadata()
    var manifest: [String: EPUBManifestItem] = [:]
    var manifestOrder: [EPUBManifestItem] = []
    var spine: [EPUBSpineItem] = []
    /// `toc` attribute of the spine (EPUB 2 navigation control file).
    var ncxID: String?
    var coverID: String?

    var navigationItem: EPUBManifestItem? { manifestOrder.first { $0.properties.contains("nav") } }
    var ncxItem: EPUBManifestItem? { ncxID.flatMap { manifest[$0] } ?? manifestOrder.first { $0.mediaType == "application/x-dtbncx+xml" } }
    var coverItem: EPUBManifestItem? { coverID.flatMap { manifest[$0] } }

    /// Chapters in reading order. A package with an empty or dangling spine falls back to its markup documents
    /// in manifest order, because some generators omit the spine of single-file books.
    func chapters() -> [EPUBManifestItem] {
        let ordered = spine.compactMap { manifest[$0.idref] }.filter(Self.isMarkupDocument)
        return ordered.isEmpty ? manifestOrder.filter { Self.isMarkupDocument($0) && !$0.properties.contains("nav") } : ordered
    }

    static func isMarkupDocument(_ item: EPUBManifestItem) -> Bool {
        ["application/xhtml+xml", "text/html", "text/x-oeb1-document", "application/xml"].contains(item.mediaType)
    }

    // MARK: Container

    /// Archive path of the package document named by `META-INF/container.xml`.
    static func packagePath(inContainer container: MarkupElement) -> String? {
        let roots = container.descendants(named: "rootfile", limit: 16)
        let chosen = roots.first { ($0.attribute("media-type") ?? "").contains("oebps-package") } ?? roots.first
        guard let fullPath = chosen?.attribute("full-path") else { return nil }
        return ArchiveMemberIndex.resolve(fullPath, relativeTo: "")
    }

    // MARK: Package document

    static func parse(_ document: MarkupElement, path: String, context: RequestContext) throws -> EPUBPackage {
        guard let root = document.firstDescendant(named: "package") else { throw PreviewFailure.malformedDocument }
        var package = EPUBPackage(path: path)
        if let metadata = root.firstChild(named: "metadata") {
            package.metadata = try readMetadata(metadata, uniqueIdentifier: root.attribute("unique-identifier"), context: context)
            if let cover = metadata.children(named: "meta").first(where: { $0.attribute("name")?.lowercased() == "cover" }) {
                package.coverID = cover.attribute("content")
            }
        }
        if let manifest = root.firstChild(named: "manifest") {
            for element in manifest.children(named: "item").prefix(maximumManifestItems) {
                guard let id = element.attribute("id"), let href = element.attribute("href") else { continue }
                let item = EPUBManifestItem(
                    id: id, href: href, mediaType: (element.attribute("media-type") ?? "").lowercased(),
                    properties: Set((element.attribute("properties") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)))
                // The first declaration of an id wins, as the specification requires ids to be unique.
                if package.manifest[id] == nil {
                    package.manifest[id] = item
                    package.manifestOrder.append(item)
                }
            }
        }
        if let spine = root.firstChild(named: "spine") {
            package.ncxID = spine.attribute("toc")
            package.spine = spine.children(named: "itemref").prefix(maximumSpineItems).compactMap { reference in
                reference.attribute("idref").map { EPUBSpineItem(idref: $0, isLinear: reference.attribute("linear")?.lowercased() != "no") }
            }
        }
        // EPUB 3 marks the cover in the manifest; it wins over the EPUB 2 `<meta name="cover">` hint.
        if let cover = package.manifestOrder.first(where: { $0.properties.contains("cover-image") }) { package.coverID = cover.id }
        try context.checkpoint()
        return package
    }

    private static func readMetadata(_ element: MarkupElement, uniqueIdentifier: String?,
                                     context: RequestContext) throws -> EPUBMetadata {
        func text(_ name: String) -> String? {
            element.children(named: name).lazy.map { MarkdownEscaping.singleLine($0.textContent) }.first { !$0.isEmpty }
        }
        var metadata = EPUBMetadata()
        metadata.title = text("title")
        metadata.creators = element.children(named: "creator").map { MarkdownEscaping.singleLine($0.textContent) }
            .filter { !$0.isEmpty }.prefix(8).map { $0 }
        metadata.language = text("language")
        metadata.publisher = text("publisher")
        metadata.date = text("date")
        let identifiers = element.children(named: "identifier")
        let preferred = uniqueIdentifier.flatMap { id in identifiers.first { $0.attribute("id") == id } } ?? identifiers.first
        metadata.identifier = preferred.map { MarkdownEscaping.singleLine($0.textContent) }.flatMap { $0.isEmpty ? nil : $0 }
        if let description = element.firstChild(named: "description") {
            // Descriptions are often escaped or nested HTML; keep only the readable words.
            let stripped = try MarkupPlainText.strip(description.textContent, context: context)
            metadata.description = stripped.isEmpty ? nil : stripped
        }
        return metadata
    }
}

/// Table of contents entries: a title for each archive path. Only the first entry for a path is kept.
struct EPUBTableOfContents: Equatable, Sendable {
    static let maximumEntries = 2_000
    private(set) var titles: [String: String] = [:]
    private(set) var count = 0

    func title(for path: String) -> String? { titles[path] ?? titles[path.lowercased()] }

    /// EPUB 3 navigation document: the `nav` element typed `toc` (or the first `nav`).
    static func parseNavigation(_ document: MarkupElement, path: String) -> EPUBTableOfContents {
        let navigations = document.descendants(named: "nav", limit: 32)
        let chosen = navigations.first { ($0.qualifiedAttribute("epub:type") ?? $0.attribute("type") ?? "").contains("toc") }
            ?? navigations.first
        var toc = EPUBTableOfContents()
        for link in chosen?.descendants(named: "a", limit: maximumEntries) ?? [] {
            toc.add(title: link.textContent, reference: link.attribute("href"), base: path)
        }
        return toc
    }

    /// EPUB 2 NCX: `navPoint` elements with a `navLabel` text and a `content` source.
    static func parseNCX(_ document: MarkupElement, path: String) -> EPUBTableOfContents {
        var toc = EPUBTableOfContents()
        for point in document.descendants(named: "navpoint", limit: maximumEntries) {
            let label = point.firstChild(named: "navlabel")?.textContent ?? ""
            toc.add(title: label, reference: point.firstChild(named: "content")?.attribute("src"), base: path)
        }
        return toc
    }

    private mutating func add(title: String, reference: String?, base: String) {
        let cleaned = MarkdownEscaping.singleLine(title)
        guard count < Self.maximumEntries, !cleaned.isEmpty, let reference,
              let path = ArchiveMemberIndex.resolve(reference, relativeTo: base) else { return }
        count += 1
        let capped = cleaned.count > 256 ? String(cleaned.prefix(256)) + "…" : cleaned
        if titles[path] == nil { titles[path] = capped }
        if titles[path.lowercased()] == nil { titles[path.lowercased()] = capped }
    }
}

/// What `META-INF/encryption.xml`, `rights.xml` and `sinf.xml` say about protected content.
struct EPUBEncryption: Equatable, Sendable {
    /// Archive paths of parts encrypted with something other than font obfuscation.
    var protectedPaths: Set<String> = []
    /// A rights or FairPlay descriptor exists; the package declares digital rights management.
    var hasRightsDescriptor = false

    var isProtected: Bool { hasRightsDescriptor || !protectedPaths.isEmpty }

    /// Algorithms that only obfuscate embedded fonts. They are part of ordinary, unprotected books and do not
    /// affect any text, so they never count as protection.
    static let fontObfuscationAlgorithms: Set<String> = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#rc"]

    static func parse(_ document: MarkupElement) -> EPUBEncryption {
        var result = EPUBEncryption()
        for data in document.descendants(named: "encrypteddata", limit: 20_000) {
            let algorithm = data.descendants(named: "encryptionmethod", limit: 1).first?.attribute("algorithm")?.lowercased() ?? ""
            guard !fontObfuscationAlgorithms.contains(algorithm) else { continue }
            guard let uri = data.descendants(named: "cipherreference", limit: 1).first?.attribute("uri"),
                  let path = ArchiveMemberIndex.resolve(uri, relativeTo: "") else { continue }
            result.protectedPaths.insert(path)
            result.protectedPaths.insert(path.lowercased())
        }
        return result
    }

    func protects(_ path: String) -> Bool { protectedPaths.contains(path) || protectedPaths.contains(path.lowercased()) }
}

/// Reduces markup embedded in a metadata string (an escaped or nested description) to readable text.
enum MarkupPlainText {
    static let maximumCharacters = 2_048

    static func strip(_ text: String, context: RequestContext) throws -> String {
        guard text.contains("<") else { return MarkdownEscaping.singleLine(text) }
        var tokenizer = MarkupTokenizer(text, rawTextElements: ["script", "style"], context: context)
        var pieces: [String] = []
        let separators: Set<String> = ["p", "div", "br", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "tr", "td"]
        var events = 0
        while let event = try tokenizer.next() {
            events += 1
            guard events <= 4_096 else { break }
            switch event {
            case .text(let value): pieces.append(value)
            case .start(let name, _, _), .end(let name): if separators.contains(name) { pieces.append(" ") }
            }
        }
        var result = MarkdownEscaping.singleLine(pieces.joined())
        if result.count > maximumCharacters { result = String(result.prefix(maximumCharacters)) + "…" }
        return result
    }
}

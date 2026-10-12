import Foundation
import PreviewContracts

/// One `<file>` element of a XAR table of contents. Offsets are relative to the start of the heap, which
/// follows the header and the compressed table of contents.
struct XARFileEntry: Equatable {
    var name: String?
    /// Index of the enclosing directory entry, or `nil` for a top-level entry.
    var parent: Int?
    var type: String?
    var offset: Int?
    var length: Int?
    /// Uncompressed size of the entry's data, from `<size>`.
    var size: Int?
    /// The `style` of `<data><encoding>`: `application/x-gzip` is zlib-wrapped deflate and
    /// `application/octet-stream` is stored without compression.
    var encoding = ""
    var modified: Date?
    var isDirectory: Bool { type == "directory" }
}

struct XARArchive {
    /// Distance from the start of the file to the heap, where entry offsets are anchored.
    let heapStart: Int64
    /// Bytes charged to the request while reading the header and the compressed table of contents.
    let bytesRead: Int
    let entries: [XARFileEntry]
    /// Base64 certificate texts found in the table of contents' signature, in stored order.
    let signatureCertificates: [String]
    let hasSignature: Bool

    /// Slash-joined path of the entry from the archive root, or `nil` when a name is missing or the nesting is implausible.
    func path(of index: Int) -> String? {
        var parts: [String] = []
        var current: Int? = index
        var steps = 0
        while let position = current {
            steps += 1
            guard steps <= 64, entries.indices.contains(position), let name = entries[position].name, !name.isEmpty else { return nil }
            parts.append(name)
            current = entries[position].parent
        }
        return parts.reversed().joined(separator: "/")
    }
}

/// A bounded reader for the XAR (eXtensible ARchive) container used by Apple installer packages and
/// XIP archives. It reads the header and the zlib-compressed XML table of contents; entry data is read
/// separately, and only when a caller asks, through `readData`. Nothing is extracted or executed.
enum XARArchiveReader {
    private static let magic: UInt64 = 0x7861_7221
    private static let minimumHeaderLength = 28
    static let maximumSignatureCertificates = 8

    static func read(_ source: any PreviewByteSource, context: RequestContext, limits: ContainerLimits) throws -> XARArchive {
        try context.checkpoint()
        guard source.byteCount >= Int64(minimumHeaderLength) else { throw PreviewFailure.malformedDocument }
        var cursor = BinaryCursor(try source.read(offset: 0, count: minimumHeaderLength, context: context))
        guard try cursor.integer(4) == magic else { throw PreviewFailure.malformedDocument }
        let headerSize = try boundedInt(cursor.integer(2))
        guard headerSize >= minimumHeaderLength, try cursor.integer(2) == 1 else { throw PreviewFailure.unsupportedFormat }
        let compressedTOC = try boundedInt(cursor.integer(8))
        let decodedTOC = try boundedInt(cursor.integer(8))
        _ = try cursor.integer(4)
        guard compressedTOC <= limits.maxMetadataBytes, decodedTOC <= limits.maxMetadataBytes,
              Int64(headerSize) <= source.byteCount, Int64(compressedTOC) <= source.byteCount - Int64(headerSize) else {
            throw PreviewFailure.inputTooLarge
        }
        let toc = try BoundedDecompression.zlibWrapped(source.read(offset: Int64(headerSize), count: compressedTOC, context: context),
                                                        context: context, maximum: decodedTOC)
        guard toc.count == decodedTOC else { throw PreviewFailure.malformedDocument }
        // XMLParser can expand internal entities before its delegate sees them.
        let tocText = String(decoding: toc, as: UTF8.self)
        guard !tocText.localizedCaseInsensitiveContains("<!DOCTYPE"), !tocText.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw PreviewFailure.unsupportedFormat
        }
        let delegate = XARTOCReader(context: context, maximumEntries: limits.maxEntries)
        let parser = XMLParser(data: toc)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil else { throw delegate.failure ?? .malformedDocument }
        return XARArchive(heapStart: Int64(headerSize) + Int64(compressedTOC), bytesRead: minimumHeaderLength + compressedTOC,
                          entries: delegate.entries,
                          signatureCertificates: delegate.certificates, hasSignature: delegate.hasSignature)
    }

    /// Reads and decodes one entry's data. `maximumBytes` bounds the decoded result before any payload is read.
    static func readData(_ entry: XARFileEntry, in archive: XARArchive, from source: any PreviewByteSource,
                         maximumBytes: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard let offset = entry.offset, let length = entry.length, offset >= 0, length >= 0 else { throw PreviewFailure.malformedDocument }
        guard Int64(offset) <= source.byteCount - archive.heapStart,
              Int64(length) <= source.byteCount - archive.heapStart - Int64(offset) else { throw PreviewFailure.malformedDocument }
        let expected = entry.size ?? maximumBytes
        guard expected >= 0, expected <= maximumBytes else { throw PreviewFailure.inputTooLarge }
        switch entry.encoding {
        case "application/octet-stream":
            guard length <= maximumBytes else { throw PreviewFailure.inputTooLarge }
            return try source.read(offset: archive.heapStart + Int64(offset), count: length, context: context)
        case "application/x-gzip":
            let packed = try source.read(offset: archive.heapStart + Int64(offset), count: length, context: context)
            return try BoundedDecompression.zlibWrapped(packed, context: context, maximum: expected)
        default:
            throw PreviewFailure.unsupportedFormat
        }
    }
}

/// Collects every file entry, with the nesting, and the certificates of the table of contents'
/// signature. Declaring entities or a document type stops the parse.
private final class XARTOCReader: NSObject, XMLParserDelegate {
    let context: RequestContext
    let maximumEntries: Int
    var failure: PreviewFailure?
    var entries: [XARFileEntry] = []
    var certificates: [String] = []
    var hasSignature = false
    private var path: [String] = []
    private var open: [Int] = []
    private var characters = ""
    private var nodes = 0
    private var seenFields: [Int: Set<String>] = [:]

    init(context: RequestContext, maximumEntries: Int) {
        self.context = context
        self.maximumEntries = maximumEntries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        do {
            try context.checkpoint()
            nodes += 1
            guard nodes <= context.budget.maxJSONNodes, path.count < context.budget.maxJSONDepth else { throw PreviewFailure.tooManyNodes }
            if elementName == "file" {
                guard entries.count < maximumEntries else { throw PreviewFailure.tooManyNodes }
                entries.append(XARFileEntry(parent: open.last))
                open.append(entries.count - 1)
            }
            path.append(elementName)
            characters = ""
            if elementName == "signature", path.suffix(2).first == "toc" { hasSignature = true }
            if elementName == "encoding", path.suffix(2).first == "data", let index = open.last {
                entries[index].encoding = attributeDict["style"] ?? ""
            }
        } catch { stop(parser, error: error) }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard characters.utf8.count + string.utf8.count <= context.budget.maxLineUTF8Bytes else {
            stop(parser, error: PreviewFailure.outputTooLarge)
            return
        }
        characters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        do {
            try context.checkpoint()
            guard path.last == elementName else { throw PreviewFailure.malformedDocument }
            let text = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "X509Certificate", path.contains("signature") {
                if certificates.count < XARArchiveReader.maximumSignatureCertificates, !text.isEmpty { certificates.append(text) }
            } else if let index = open.last {
                try record(elementName, text: text, for: index)
            }
            if elementName == "file" {
                seenFields[open.removeLast()] = nil
            }
            path.removeLast()
            characters = ""
        } catch { stop(parser, error: error) }
    }

    /// Records a leaf element of the innermost open file. Only the entry's own fields count: an element
    /// nested in a child file is attributed to that child when it closes.
    private func record(_ element: String, text: String, for index: Int) throws {
        let parent = path.count >= 2 ? path[path.count - 2] : ""
        let grandparent = path.count >= 3 ? path[path.count - 3] : ""
        switch (element, parent) {
        case ("name", "file"): try once("name", index) { entries[index].name = text }
        case ("type", "file"): entries[index].type = text
        case ("mtime", "file"): entries[index].modified = ISO8601DateFormatter().date(from: text)
        case ("offset", "data") where grandparent == "file": try once("offset", index) { entries[index].offset = Int(text).flatMap { $0 >= 0 ? $0 : nil } }
        case ("length", "data") where grandparent == "file": try once("length", index) { entries[index].length = Int(text).flatMap { $0 >= 0 ? $0 : nil } }
        case ("size", "data") where grandparent == "file": entries[index].size = Int(text).flatMap { $0 >= 0 ? $0 : nil }
        default: break
        }
    }

    private func once(_ field: String, _ index: Int, _ assign: () -> Void) throws {
        guard seenFields[index, default: []].insert(field).inserted else { throw PreviewFailure.malformedDocument }
        assign()
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        stop(parser, error: PreviewFailure.unsupportedFormat)
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        stop(parser, error: PreviewFailure.unsupportedFormat)
    }
    private func stop(_ parser: XMLParser, error: any Error) {
        failure = error as? PreviewFailure ?? .deadlineExceeded
        parser.abortParsing()
    }
}

import Foundation
import PreviewContracts

/// Read-only EPUB 2 and EPUB 3 preview.
///
/// The package is read through the shared bounded ZIP reader: `META-INF/container.xml` names the package
/// document, which lists the cover, the navigation and the chapters. Chapters are converted, in reading
/// order, by `HTMLMarkdownConverter` into safe Markdown text with front matter (title, author, language and
/// the rest of the descriptive metadata). The cover image is the only picture extracted.
///
/// - Nothing is executed, rendered as web content or fetched: scripts, styles, frames, forms and media are
///   dropped, links and image sources are discarded, and no member outside the archive is ever read.
/// - Digital rights management (`rights.xml`, `sinf.xml` or an `encryption.xml` entry that is not font
///   obfuscation) is never bypassed. Protected chapters are omitted, the document carries a `drm: true`
///   front-matter flag for the status line, and a book with neither metadata nor readable text fails with
///   `PreviewFailure.encryptedContent`.
/// - Output stops at a ceiling below the native Rendered view's own limit and reports `partial: true`; a
///   chapter that is missing, oversized or corrupt is skipped and also reports `partial: true`. Whenever a chapter
///   is not represented, the front matter also carries `chaptersShown` (chapters converted) and `chaptersTotal`
///   (chapters in the reading order), which the status line states in the reader's language.
public struct EPUBAdapter: RandomAccessFormatAdapter {
    public init() {}

    private static let opfVoidElements: Set<String> = ["item", "itemref", "reference", "link", "meta"]

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let limits = DocumentLimits(context: context)
        let archive = try ZIPArchiveReader.read(source, context: context, encryptedEntries: .list)
        let reader = PackageReader(source: source, index: ArchiveMemberIndex(archive), context: context)

        // Required parts: failing to find them means this is not an EPUB package.
        guard let containerBytes = try reader.read("META-INF/container.xml", maximum: limits.metadataMemberBytes),
              let containerPath = try EPUBPackage.packagePath(inContainer: reader.tree(containerBytes)) else {
            throw PreviewFailure.malformedDocument
        }
        guard let packageBytes = try reader.read(containerPath, maximum: limits.metadataMemberBytes) else {
            throw PreviewFailure.malformedDocument
        }
        let package = try EPUBPackage.parse(reader.tree(packageBytes, voidElements: Self.opfVoidElements),
                                            path: containerPath, context: context)

        var encryption = EPUBEncryption()
        if let bytes = try reader.readOptional("META-INF/encryption.xml", maximum: limits.metadataMemberBytes) {
            encryption = EPUBEncryption.parse(try reader.tree(bytes))
        }
        encryption.hasRightsDescriptor = reader.exists("META-INF/rights.xml") || reader.exists("META-INF/sinf.xml")

        let contents = try tableOfContents(of: package, reader: reader, limits: limits)
        var images = ImageCollector(limits: limits)
        if let cover = try cover(of: package, reader: reader, encryption: encryption, limits: limits) { images.append(cover) }

        var body = MarkdownWriter(context: context, reservesFrontMatter: true)
        let chapters = try convertChapters(of: package, reader: reader, encryption: encryption, contents: contents,
                                           into: &body, context: context)
        let isProtected = encryption.hasRightsDescriptor || chapters.protectedOmitted > 0
        if chapters.incomplete { body.markIncomplete() }

        let metadata = package.metadata
        let fields: [(key: String, value: String)] = [
            ("title", metadata.title ?? ""), ("author", metadata.creators.joined(separator: "; ")),
            ("language", metadata.language ?? ""), ("publisher", metadata.publisher ?? ""),
            ("date", metadata.date ?? ""), ("identifier", metadata.identifier ?? ""),
            ("description", metadata.description ?? "")
        ]
        let hasMetadata = fields.contains { !$0.value.isEmpty }
        if body.isEmpty, !hasMetadata, images.count == 0 {
            throw isProtected ? PreviewFailure.encryptedContent : PreviewFailure.malformedDocument
        }
        try context.checkpoint()
        let text = MarkdownWriter.document(fields: fields, flags: isProtected ? ["drm"] : [], counts: chapters.counts,
                                           body: body, context: context)
        return ParsedTextDocument(text: text, syntax: .markdown, images: images.images, origin: .converted)
    }

    // MARK: Parts

    private func tableOfContents(of package: EPUBPackage, reader: PackageReader,
                                 limits: DocumentLimits) throws -> EPUBTableOfContents {
        if let item = package.navigationItem, let path = ArchiveMemberIndex.resolve(item.href, relativeTo: package.path),
           let bytes = try reader.readOptional(path, maximum: limits.textMemberBytes) {
            let toc = EPUBTableOfContents.parseNavigation(try reader.tree(bytes, voidElements: HTMLVoidElements.names), path: path)
            if toc.count > 0 { return toc }
        }
        if let item = package.ncxItem, let path = ArchiveMemberIndex.resolve(item.href, relativeTo: package.path),
           let bytes = try reader.readOptional(path, maximum: limits.metadataMemberBytes) {
            return EPUBTableOfContents.parseNCX(try reader.tree(bytes), path: path)
        }
        return EPUBTableOfContents()
    }

    /// The cover picture, when the package declares one and it fits the image and read bounds. A cover read must
    /// leave most of the read budget to the text, so it is limited to 60% of it.
    private func cover(of package: EPUBPackage, reader: PackageReader, encryption: EPUBEncryption,
                       limits: DocumentLimits) throws -> PreviewImage? {
        guard let item = package.coverItem, let path = ArchiveMemberIndex.resolve(item.href, relativeTo: package.path),
              !encryption.protects(path), let entry = reader.index.entry(at: path), !entry.isEncrypted else { return nil }
        let maximum = min(DocumentLimits.maximumEncodedImageBytes, reader.context.budget.maxInputBytes * 3 / 5)
        guard entry.uncompressedSize <= maximum, EmbeddedImageValidator.hasImageSuffix(path) || item.mediaType.hasPrefix("image/") else {
            return nil
        }
        guard let data = try reader.readMemberTolerantly(entry, maximum: maximum) else { return nil }
        return try EmbeddedImageValidator.validate(data, role: .cover, context: reader.context)
    }

    private struct ChapterSummary {
        /// Front-matter keys the status line reads; the renderer's `EbookChapterFacts` spells the same two.
        static let shownKey = "chaptersShown"
        static let totalKey = "chaptersTotal"

        var protectedOmitted = 0
        var incomplete = false
        /// Chapters in the reading order, and how many of them were converted. The last one converted can still be
        /// cut short by the output ceiling; a chapter that is missing, protected or unreadable is not counted.
        var total = 0
        var converted = 0

        /// What the status line needs to say how much of the book is shown: written only when some chapter is not
        /// represented, so a whole book carries no counts.
        var counts: [(key: String, value: Int)] {
            guard total > 0, converted < total else { return [] }
            return [(key: Self.shownKey, value: converted), (key: Self.totalKey, value: total)]
        }
    }

    private func convertChapters(of package: EPUBPackage, reader: PackageReader, encryption: EPUBEncryption,
                                 contents: EPUBTableOfContents, into body: inout MarkdownWriter,
                                 context: RequestContext) throws -> ChapterSummary {
        var summary = ChapterSummary()
        var nodeBudget = context.budget.maxJSONNodes * 4
        let limits = DocumentLimits(context: context)
        let readingOrder = package.chapters()
        summary.total = readingOrder.count
        for item in readingOrder {
            try context.checkpoint()
            if body.isFull || nodeBudget <= 0 { summary.incomplete = true; break }
            guard let path = ArchiveMemberIndex.resolve(item.href, relativeTo: package.path),
                  let entry = reader.index.entry(at: path) else { summary.incomplete = true; continue }
            if encryption.protects(path) || entry.isEncrypted { summary.protectedOmitted += 1; summary.incomplete = true; continue }
            guard entry.uncompressedSize <= limits.textMemberBytes else { summary.incomplete = true; continue }
            let data: Data
            do {
                guard let read = try reader.readMemberTolerantly(entry, maximum: limits.textMemberBytes) else {
                    summary.incomplete = true
                    continue
                }
                data = read
            } catch PreviewFailure.inputTooLarge {
                // The cumulative read budget is spent; everything after this chapter is out of reach.
                summary.incomplete = true
                break
            }
            // Ciphertext from a descriptor-less scheme is not markup; it is never shown as text.
            guard data.prefix(4_096).contains(UInt8(ascii: "<")) else {
                if encryption.isProtected { summary.protectedOmitted += 1 }
                summary.incomplete = true
                continue
            }
            let html = try MarkupDecoder.decode(data, context: context)
            let outcome = try HTMLMarkdownConverter.convert(html, into: &body, fallbackHeading: contents.title(for: path),
                                                            nodeBudget: &nodeBudget, context: context)
            summary.converted += 1
            if outcome.truncated { summary.incomplete = true; break }
        }
        return summary
    }
}

/// Bounded access to the members of one opened package. A member that is absent returns `nil`; cancellation,
/// the deadline and the cumulative read budget always propagate.
struct PackageReader {
    let source: any PreviewByteSource
    let index: ArchiveMemberIndex
    let context: RequestContext

    func exists(_ path: String) -> Bool { index.entry(at: path) != nil }

    /// A required member: `nil` when absent, otherwise its bytes or the failure that made it unreadable.
    func read(_ path: String, maximum: Int) throws -> Data? {
        guard let entry = index.entry(at: path) else { return nil }
        return try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: maximum, context: context)
    }

    /// An optional descriptor: unreadable or corrupt members are treated as absent.
    func readOptional(_ path: String, maximum: Int) throws -> Data? {
        guard let entry = index.entry(at: path) else { return nil }
        return try readMemberTolerantly(entry, maximum: maximum)
    }

    /// Bytes of `entry`, or `nil` when the member itself is defective (corrupt, unsupported method, encrypted).
    func readMemberTolerantly(_ entry: ZIPEntry, maximum: Int) throws -> Data? {
        do {
            return try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: maximum, context: context)
        } catch let failure as PreviewFailure {
            switch failure {
            case .malformedDocument, .unsupportedFormat, .notRegularFile, .encryptedContent: return nil
            default: throw failure
            }
        }
    }

    func tree(_ data: Data, voidElements: Set<String> = []) throws -> MarkupElement {
        try MarkupTreeBuilder.parse(MarkupDecoder.decode(data, context: context), rawTextElements: voidElements.isEmpty ? [] : ["script", "style"],
                                    voidElements: voidElements, context: context)
    }
}

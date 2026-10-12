import Foundation
import PreviewContracts

/// Read-only preview of ZIP comic books (`.cbz`).
///
/// Pages are the archive's image members in natural name order (`page2` before `page10`), read through the
/// shared bounded ZIP reader and validated by `EmbeddedImageValidator`: only JPEG, PNG, GIF, WebP, HEIC and
/// AVIF, at most 8 MiB each, 500 pages and `min(48 MiB, 4 × maxInputBytes)` in total. `__MACOSX` folders,
/// hidden files and non-images are ignored. Adapters never decode pixels; the native Pages view decodes
/// lazily at display size.
///
/// The safe text is a concealed JSON summary built from `ComicInfo.xml` (title, series, issue number,
/// writer and declared page count) and the page counts. Pages that do not fit the bounds are not shown;
/// `shownPages` and `pageCount` say so. Comics whose members are encrypted fail with `encryptedContent`.
/// CBR, CB7 and CBT are not ZIP archives and are out of scope.
public struct ComicBookAdapter: RandomAccessFormatAdapter {
    public init() {}

    private static let maximumInfoBytes = 262_144

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let limits = DocumentLimits(context: context)
        let archive = try ZIPArchiveReader.read(source, context: context, encryptedEntries: .list)
        let pages = archive.entries.filter(Self.isPage).sorted { NaturalOrder.areInIncreasingOrder($0.path, $1.path) }
        let info = try comicInfo(in: archive, source: source, context: context)

        var images = ImageCollector(limits: limits)
        pageLoop: for entry in pages {
            try context.checkpoint()
            // A page that does not fit ends the list: skipping it would silently reorder the comic.
            guard images.canAccept(encodedBytes: entry.uncompressedSize) else { break }
            if entry.isEncrypted {
                if images.count == 0 { throw PreviewFailure.encryptedContent }
                break
            }
            let data: Data
            do {
                data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: DocumentLimits.maximumEncodedImageBytes,
                                                       context: context)
            } catch let failure as PreviewFailure {
                switch failure {
                case .inputTooLarge: break pageLoop   // The cumulative read budget is spent.
                case .malformedDocument, .unsupportedFormat, .notRegularFile: continue pageLoop
                default: throw failure
                }
            }
            // A page carries no label: its archive member path is untrusted text that would bypass the privacy stage.
            if let page = try EmbeddedImageValidator.validate(data, role: .page, context: context) {
                images.append(page)
            }
        }
        return try summary(info: info, pageCount: pages.count, images: images.images, context: context)
    }

    // MARK: Page selection

    /// An image member that is not a macOS resource fork, a hidden file or inside a hidden folder.
    static func isPage(_ entry: ZIPEntry) -> Bool {
        guard entry.kind == "file" else { return false }
        let components = entry.path.split(separator: "/", omittingEmptySubsequences: true)
        guard let name = components.last,
              !components.contains(where: { $0 == "__MACOSX" || $0.hasPrefix(".") }) else { return false }
        return EmbeddedImageValidator.hasImageSuffix(String(name))
    }

    // MARK: ComicInfo.xml

    struct ComicInfo: Equatable, Sendable {
        var title: String?
        var series: String?
        var number: String?
        var writer: String?
        var pageCount: Int?
    }

    /// Reads the shallowest `ComicInfo.xml`. A missing, oversized or malformed file simply contributes nothing.
    private func comicInfo(in archive: ZIPArchive, source: any PreviewByteSource, context: RequestContext) throws -> ComicInfo {
        let candidates = archive.entries.filter { $0.kind == "file" && ($0.path as NSString).lastPathComponent.lowercased() == "comicinfo.xml" }
        guard let entry = candidates.min(by: { $0.path.split(separator: "/").count < $1.path.split(separator: "/").count }),
              !entry.isEncrypted, entry.uncompressedSize <= Self.maximumInfoBytes else { return ComicInfo() }
        let data: Data
        do {
            data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: Self.maximumInfoBytes, context: context)
        } catch let failure as PreviewFailure {
            switch failure {
            case .malformedDocument, .unsupportedFormat, .notRegularFile, .inputTooLarge: return ComicInfo()
            default: throw failure
            }
        }
        let root = try MarkupTreeBuilder.parse(MarkupDecoder.decode(data, context: context), rawTextElements: [], voidElements: [],
                                               context: context)
        guard let info = root.firstDescendant(named: "comicinfo") else { return ComicInfo() }
        func text(_ name: String) -> String? {
            let value = MarkdownEscaping.singleLine(info.firstChild(named: name)?.textContent ?? "")
            return value.isEmpty ? nil : String(value.prefix(256))
        }
        return ComicInfo(title: text("title"), series: text("series"), number: text("number"), writer: text("writer"),
                         pageCount: text("pagecount").flatMap { Int($0) }.flatMap { (0...1_000_000).contains($0) ? $0 : nil })
    }

    // MARK: Summary

    /// The wire keys below are the schema the renderer localizes (`SafeSchemaLabels+Documents`).
    private func summary(info: ComicInfo, pageCount: Int, images: [PreviewImage],
                         context: RequestContext) throws -> ParsedTextDocument {
        var fields: [(String, SummaryValue)] = []
        if let title = info.title { fields.append(("title", .string(title))) }
        if let series = info.series { fields.append(("series", .string(series))) }
        if let number = info.number { fields.append(("issueNumber", .string(number))) }
        if let writer = info.writer { fields.append(("writer", .string(writer))) }
        fields.append(("pageCount", .integer(pageCount)))
        if let declared = info.pageCount, declared != pageCount { fields.append(("declaredPageCount", .integer(declared))) }
        fields.append(("shownPages", .integer(images.count)))
        fields.append(("partial", .boolean(images.count < pageCount)))
        var writer = SummaryWriter(context: context)
        let document = try writer.document(.object(fields))
        return ParsedTextDocument(text: document.text, sensitiveRanges: document.sensitiveRanges, usesStructuredPrivacy: true,
                                  syntax: .json, images: images, origin: document.origin)
    }
}

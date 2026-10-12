import Foundation
import PreviewContracts

/// Read-only FictionBook 2 (`.fb2`) preview.
///
/// The XML (in its declared encoding, commonly Windows-1251) is read through the bounded tolerant markup
/// tree. `title-info` and `publish-info` become front matter; `body` sections become Markdown headings,
/// paragraphs, quotes, poems and tables. The cover is the `<binary>` that `coverpage` references: its
/// base64 payload is located with a bounded byte scan, decoded, and validated as an image.
///
/// A file larger than the input budget is read as its beginning plus a tail window: the text is cut at the
/// end of the head (reported as `partial: true`) while the tail still usually holds the trailing `<binary>`
/// elements where generators store the cover.
public struct FictionBookAdapter: RandomAccessFormatAdapter {
    public init() {}

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = source.byteCount
        guard size > 0 else { throw PreviewFailure.malformedDocument }
        let budget = context.budget.maxInputBytes
        let limits = DocumentLimits(context: context)

        let head: Data
        var tail: Data?
        let isTruncated = size > Int64(budget)
        if isTruncated {
            let tailBytes = budget / 3
            head = try source.read(offset: 0, count: budget - tailBytes, context: context)
            tail = try source.read(offset: size - Int64(tailBytes), count: tailBytes, context: context)
        } else {
            head = try source.read(offset: 0, count: Int(size), context: context)
        }
        let text = try MarkupDecoder.decode(head, context: context)
        let document = try MarkupTreeBuilder.parse(text, rawTextElements: ["binary"], voidElements: [], context: context)
        guard let root = document.firstDescendant(named: "fictionbook") else { throw PreviewFailure.malformedDocument }

        let description = root.firstChild(named: "description")
        let titleInfo = description?.firstChild(named: "title-info")
        let publishInfo = description?.firstChild(named: "publish-info")

        var body = MarkdownWriter(context: context, reservesFrontMatter: true)
        var converter = FictionBookConverter(nodesRemaining: context.budget.maxJSONNodes * 4, context: context)
        for element in root.children(named: "body") {
            try converter.convert(body: element, into: &body)
            if body.isFull || converter.nodesRemaining < 0 { break }
        }
        if isTruncated || converter.nodesRemaining < 0 { body.markIncomplete() }

        let fields: [(key: String, value: String)] = [
            ("title", Self.plain(titleInfo?.firstChild(named: "book-title"))),
            ("author", (titleInfo?.children(named: "author") ?? []).prefix(8).map(Self.authorName).filter { !$0.isEmpty }
                .joined(separator: "; ")),
            ("language", Self.plain(titleInfo?.firstChild(named: "lang"))),
            ("publisher", Self.plain(publishInfo?.firstChild(named: "publisher"))),
            ("date", Self.date(titleInfo?.firstChild(named: "date")) ?? Self.plain(publishInfo?.firstChild(named: "year"))),
            ("identifier", Self.plain(publishInfo?.firstChild(named: "isbn"))),
            ("description", Self.plain(titleInfo?.firstChild(named: "annotation")))
        ]
        let hasMetadata = fields.contains { !$0.value.isEmpty }
        let cover = try cover(titleInfo: titleInfo, head: head, tail: tail, isTruncated: isTruncated, limits: limits, context: context)
        if body.isEmpty, !hasMetadata, cover == nil { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        return ParsedTextDocument(text: MarkdownWriter.document(fields: fields, flags: [], body: body, context: context),
                                  syntax: .markdown, images: cover.map { [$0] } ?? [], origin: .converted)
    }

    // MARK: Metadata

    private static func plain(_ element: MarkupElement?) -> String { MarkdownEscaping.singleLine(element?.textContent ?? "") }

    private static func authorName(_ author: MarkupElement) -> String {
        let parts = ["first-name", "middle-name", "last-name"].map { plain(author.firstChild(named: $0)) }.filter { !$0.isEmpty }
        return parts.isEmpty ? plain(author.firstChild(named: "nickname")) : parts.joined(separator: " ")
    }

    /// The date's machine-readable `value` when present, otherwise its text.
    private static func date(_ element: MarkupElement?) -> String? {
        guard let element else { return nil }
        let value = MarkdownEscaping.singleLine(element.attribute("value") ?? "")
        let text = value.isEmpty ? plain(element) : value
        return text.isEmpty ? nil : text
    }

    // MARK: Cover

    private func cover(titleInfo: MarkupElement?, head: Data, tail: Data?, isTruncated: Bool, limits: DocumentLimits,
                       context: RequestContext) throws -> PreviewImage? {
        guard let reference = titleInfo?.firstChild(named: "coverpage")?.firstDescendant(named: "image")?.attribute("href"),
              reference.hasPrefix("#"), reference.count > 1 else { return nil }
        let identifier = String(reference.dropFirst())
        // The decoded cover must fit the image ceiling; base64 is 4/3 the size of the bytes it carries.
        let maximumEncoded = DocumentLimits.maximumEncodedImageBytes / 3 * 4 + 64
        let windows = isTruncated ? [tail, head].compactMap { $0 } : [head]
        for window in windows {
            guard let payload = try FictionBookBinaries.payload(id: identifier, in: window, maximumEncodedBytes: maximumEncoded,
                                                                context: context) else { continue }
            let decoded = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) ?? Data()
            guard decoded.count <= limits.totalImageBytes else { return nil }
            return try EmbeddedImageValidator.validate(decoded, role: .cover, context: context)
        }
        return nil
    }
}

/// Finds one `<binary id="…">` element in raw bytes without building a tree: a payload is megabytes of base64
/// that no markup pass should materialize. An element cut off by the end of the window is not returned.
enum FictionBookBinaries {
    static func payload(id: String, in data: Data, maximumEncodedBytes: Int, context: RequestContext) throws -> Data? {
        let bytes = [UInt8](data)
        let opening = Array("<binary".utf8)
        let closing = Array("</binary>".utf8)
        var index = 0
        var scanned = 0
        while index + opening.count < bytes.count {
            scanned += 1
            if scanned.isMultiple(of: 16_384) { try context.checkpoint() }
            guard bytes[index] == opening[0], bytes[index..<(index + opening.count)].elementsEqual(opening),
                  [32, 9, 10, 13, 62].contains(bytes[index + opening.count]) else { index += 1; continue }
            var tagEnd = index + opening.count
            while tagEnd < bytes.count, tagEnd - index < 1_024, bytes[tagEnd] != 62 { tagEnd += 1 }
            guard tagEnd < bytes.count, bytes[tagEnd] == 62 else { return nil }
            let tag = String(decoding: bytes[index...tagEnd], as: UTF8.self)
            var tokenizer = MarkupTokenizer(tag, rawTextElements: [], voidElements: [], context: context)
            guard case .start(_, let attributes, let selfClosing)? = try tokenizer.next() else { index = tagEnd; continue }
            var contentEnd = tagEnd + 1
            if !selfClosing {
                // Locate the end tag; the payload is everything in between.
                var cursor = tagEnd + 1
                var found: Int?
                while cursor + closing.count <= bytes.count {
                    if cursor.isMultiple(of: 65_536) { try context.checkpoint() }
                    if bytes[cursor] == closing[0], bytes[cursor..<(cursor + closing.count)].elementsEqual(closing) { found = cursor; break }
                    cursor += 1
                }
                guard let end = found else { return nil }
                contentEnd = end
            }
            if attributes.first(where: { $0.name == "id" })?.value == id, contentEnd - (tagEnd + 1) <= maximumEncodedBytes {
                return Data(bytes[(tagEnd + 1)..<contentEnd])
            }
            index = max(index + 1, contentEnd)
        }
        return nil
    }
}

/// FictionBook body to Markdown. Sections nest to six heading levels; epigraphs, cites and poems become
/// quotes and stanzas; tables become pipe rows. Inline emphasis, strong text and code are kept, links and
/// image sources are dropped (an image with a title or alt text becomes `![text]()`, a description without a source).
struct FictionBookConverter {
    private static let maximumDepth = 24
    var nodesRemaining: Int
    let context: RequestContext

    init(nodesRemaining: Int, context: RequestContext) {
        self.nodesRemaining = nodesRemaining
        self.context = context
    }

    mutating func convert(body element: MarkupElement, into writer: inout MarkdownWriter) throws {
        let hasTitle = element.firstChild(named: "title") != nil
        if let title = element.firstChild(named: "title") { writer.heading(level: 1, content: heading(of: title)) }
        try blocks(of: element, depth: 1, headingBase: hasTitle ? 1 : 0, quote: 0, into: &writer)
    }

    // MARK: Blocks

    private mutating func blocks(of element: MarkupElement, depth: Int, headingBase: Int, quote: Int,
                                 into writer: inout MarkdownWriter) throws {
        guard depth <= Self.maximumDepth else { nodesRemaining = -1; return }
        let prefix = LinePrefix(quoteDepth: quote)
        for child in element.childElements {
            try context.checkpoint()
            nodesRemaining -= 1
            if writer.isFull || nodesRemaining < 0 { return }
            switch child.name {
            case "section":
                if let title = child.firstChild(named: "title") {
                    writer.heading(level: min(6, depth + headingBase), content: heading(of: title), prefix: prefix)
                }
                try blocks(of: child, depth: depth + 1, headingBase: headingBase, quote: quote, into: &writer)
            case "title": continue   // Written by the enclosing section or body.
            case "p": writer.paragraph(lines: [inline(child)], prefix: prefix, tight: false)
            case "subtitle":
                let text = inline(child)
                if !text.isEmpty { writer.paragraph(lines: ["**" + text + "**"], prefix: prefix, tight: false) }
            case "empty-line": writer.ensureBlankLine()
            case "epigraph", "cite", "annotation":
                try blocks(of: child, depth: depth + 1, headingBase: headingBase, quote: min(quote + 1, 4), into: &writer)
            case "text-author":
                // Inside a quote the author line stays attached to the quoted text above it.
                let text = inline(child)
                if !text.isEmpty { writer.paragraph(lines: ["— " + text], prefix: prefix, tight: quote > 0) }
            case "poem": poem(child, prefix: prefix, into: &writer)
            case "table": table(child, prefix: prefix, into: &writer)
            case "image":
                if let image = MarkdownEscaping.image(description: child.attribute("alt") ?? child.attribute("title") ?? "") {
                    writer.paragraph(lines: [image], prefix: prefix, tight: false)
                }
            default: continue
            }
        }
    }

    private func heading(of title: MarkupElement) -> String {
        title.childElements.filter { $0.name == "p" || $0.name == "subtitle" }.map { inline($0) }.filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private mutating func poem(_ element: MarkupElement, prefix: LinePrefix, into writer: inout MarkdownWriter) {
        for child in element.childElements {
            nodesRemaining -= 1
            switch child.name {
            case "title":
                let text = heading(of: child)
                if !text.isEmpty { writer.paragraph(lines: ["**" + text + "**"], prefix: prefix, tight: false) }
            case "stanza":
                let verses = child.children(named: "v").map { inline($0) }
                writer.paragraph(lines: verses, prefix: prefix, tight: false)
            case "text-author":
                let text = inline(child)
                if !text.isEmpty { writer.paragraph(lines: ["— " + text], prefix: prefix, tight: false) }
            default: continue
            }
        }
    }

    private mutating func table(_ element: MarkupElement, prefix: LinePrefix, into writer: inout MarkdownWriter) {
        var rows: [[String]] = []
        for row in element.descendants(named: "tr", limit: 1_000) {
            nodesRemaining -= 1
            let cells = row.childElements.filter { $0.name == "td" || $0.name == "th" }.prefix(32).map { cell -> String in
                var text = MarkdownEscaping.singleLine(cell.textContent)
                if text.count > 200 { text = String(text.prefix(200)) + "…" }
                return text.replacingOccurrences(of: "|", with: "¦")
            }
            if !cells.isEmpty { rows.append(Array(cells)) }
        }
        writer.table(rows: rows, prefix: prefix)
    }

    // MARK: Inline text

    /// Escaped single-line inline Markdown for `element`'s content.
    private func inline(_ element: MarkupElement) -> String {
        func render(_ node: MarkupElement, depth: Int) -> String {
            guard depth <= 16 else { return "" }
            var output = ""
            for child in node.children {
                switch child {
                case .text(let text): output += MarkdownEscaping.prose(text)
                case .element(let nested):
                    switch nested.name {
                    case "emphasis", "strong":
                        let inner = render(nested, depth: depth + 1)
                        let marker = nested.name == "strong" ? "**" : "*"
                        // Emphasis around nothing but whitespace would only leave stray markers.
                        output += MarkdownEscaping.singleLine(inner).isEmpty ? inner : marker + inner + marker
                    case "code":
                        let code = MarkdownEscaping.singleLine(nested.textContent)
                        if !code.isEmpty { output += "`" + MarkdownEscaping.code(code) + "`" }
                    case "image":
                        if let image = MarkdownEscaping.image(description: nested.attribute("alt") ?? nested.attribute("title") ?? "") {
                            output += image
                        }
                    default: output += render(nested, depth: depth + 1)   // strikethrough, sub, sup, style and links keep their text.
                    }
                }
            }
            return output
        }
        return MarkdownEscaping.singleLine(render(element, depth: 0))
    }
}

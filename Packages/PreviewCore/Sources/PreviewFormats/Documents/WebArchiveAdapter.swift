import Foundation
import PreviewContracts

/// Read-only preview of MIME HTML saved pages (`.mht`, `.mhtml`, RFC 2557).
///
/// The message is split into its MIME parts. The main `text/html` part is decoded (base64 or
/// quoted-printable, in its declared charset) and converted to Markdown by `HTMLMarkdownConverter`; every
/// other part is listed in the front matter only by content type and URL host. The page is never rendered
/// as web content: scripts, styles and frames are dropped, and neither the page's own links nor any part's
/// location is ever requested. Only the first `maxInputBytes` of a larger file are read; the status line
/// reports `partial: true` when the file or the conversion was cut short.
public struct WebArchiveAdapter: RandomAccessFormatAdapter {
    public init() {}

    private static let maximumListedResources = 40

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard source.byteCount > 0 else { throw PreviewFailure.malformedDocument }
        let readCount = Int(min(source.byteCount, Int64(context.budget.maxInputBytes)))
        let bytes = [UInt8](try source.read(offset: 0, count: readCount, context: context))
        let isTruncated = Int64(readCount) < source.byteCount

        let message = try MIMEMessage.parse(bytes, context: context)
        guard let main = Self.mainPart(in: message) else { throw PreviewFailure.unsupportedFormat }
        let data = try MIMEMessage.decodedBody(of: main, in: bytes, context: context)
        guard !data.isEmpty else { throw PreviewFailure.malformedDocument }
        let html = try MarkupDecoder.decode(data, declaredCharset: main.contentType.parameters["charset"], context: context)

        var body = MarkdownWriter(context: context, reservesFrontMatter: true)
        var nodeBudget = context.budget.maxJSONNodes * 4
        let outcome = try HTMLMarkdownConverter.convert(html, into: &body, nodeBudget: &nodeBudget, context: context)
        if isTruncated || outcome.truncated { body.markIncomplete() }
        if body.isEmpty, outcome.title == nil { throw PreviewFailure.malformedDocument }

        let top = message.top.headers
        let subject = top.value("subject").map(MIMEMessage.decodeHeaderText)
        let fields: [(key: String, value: String)] = [
            ("title", outcome.title ?? subject ?? ""),
            ("source", Self.host(of: main.location ?? message.top.location) ?? ""),
            ("date", top.value("date") ?? ""),
            ("resources", Self.resourceSummary(message.leaves.filter { $0.body != main.body })),
        ]
        try context.checkpoint()
        let text = MarkdownWriter.document(fields: fields, flags: [], body: body, context: context)
        return ParsedTextDocument(text: text, syntax: .markdown, origin: .converted)
    }

    /// The part the page is built from: the one named by the multipart `start` parameter, otherwise the first HTML part.
    private static func mainPart(in message: (top: MIMEEntity, leaves: [MIMEEntity])) -> MIMEEntity? {
        let isHTML: (MIMEEntity) -> Bool = { ["text/html", "application/xhtml+xml"].contains($0.contentType.essence) }
        if let start = message.top.contentType.parameters["start"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")),
           let named = message.leaves.first(where: { $0.contentID == start && isHTML($0) }) {
            return named
        }
        return message.leaves.first(where: isHTML)
    }

    /// Host name only: a location's path and query can carry tokens and are never shown.
    static func host(of location: String?) -> String? {
        guard let location, location.utf8.count <= 2_048, let host = URL(string: location.trimmingCharacters(in: .whitespaces))?.host,
              !host.isEmpty else { return nil }
        return host
    }

    /// `type host; type host ×N; …`: other parts by content type and host, duplicates counted.
    private static func resourceSummary(_ parts: [MIMEEntity]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for part in parts {
            let key = [part.contentType.essence, host(of: part.location)].compactMap { $0 }.joined(separator: " ")
            if counts[key] == nil {
                guard order.count < maximumListedResources else { continue }
                order.append(key)
            }
            counts[key, default: 0] += 1
        }
        return order.map { key in (counts[key] ?? 1) > 1 ? "\(key) ×\(counts[key] ?? 1)" : key }.joined(separator: "; ")
    }
}

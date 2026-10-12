import Foundation
import PreviewContracts

/// Diagram sources: adapters validate bounds and supply concealment; the renderer draws the
/// diagram natively from the concealed text. Neither format is rendered by a web view, and
/// neither adapter loads anything the document references.
public enum DiagramFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .mermaid) { MermaidSourceAdapter() },
        AdapterRegistration(formatID: .drawio, binaryAdapter: { DrawioSourceAdapter() })
    ]
}

/// Mermaid source passes through unchanged. Secret-like assignments in labels, comments and front
/// matter are concealed with structure-preserving ranges (`MermaidPrivacyRanges`), and the diagram
/// view parses only that concealed text, so no derived representation can hold a value the source
/// view hides. The shared filter still conceals recognizable credential values anywhere.
public struct MermaidSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try MermaidPrivacyRanges.ranges(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, usesStructuredPrivacy: true, syntax: .mermaid)
    }
}

/// draw.io documents. The safe text is the first page's `mxGraphModel`, re-written as normalized
/// XML with exact UTF-8 ranges for every concealable value (structured privacy), so labels,
/// styles and custom properties are concealed in the source and in the drawn diagram alike. The
/// number of pages is carried in `sourceRecordCount`; only the first page is shown.
///
/// The adapter takes bytes rather than decoded text because a compressed page is one base64 line
/// that is routinely longer than the per-line limit for ordinary text; the limit still applies to
/// the normalized output, whose lines the writer bounds.
public struct DrawioSourceAdapter: BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let (source, encoding) = try Self.decode(input.data)
        try context.checkpoint()
        let page = try DrawioDocumentReader.firstPage(of: source, context: context)
        return ParsedTextDocument(text: page.text, sensitiveRanges: page.sensitive, usesStructuredPrivacy: true,
                                  syntax: .drawio, sourceRecordCount: page.pageCount, decodedEncoding: encoding,
                                  origin: .converted)
    }

    /// UTF-8 (with or without a byte-order mark) or UTF-16 with a byte-order mark; anything else is refused.
    private static func decode(_ data: Data) throws -> (String, TextEncoding) {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            let littleEndian = data[data.startIndex] == 0xFF
            guard let text = String(data: Data(data.dropFirst(2)), encoding: littleEndian ? .utf16LittleEndian : .utf16BigEndian) else {
                throw PreviewFailure.unsupportedEncoding
            }
            return (text, littleEndian ? .utf16LittleEndian : .utf16BigEndian)
        }
        let content = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        guard let text = String(data: content, encoding: .utf8) else { throw PreviewFailure.unsupportedEncoding }
        return (text, .utf8)
    }
}

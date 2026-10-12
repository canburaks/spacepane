import Foundation
import PreviewContracts

/// SubStation Alpha, TTML, SubViewer and lyrics. The adapter validates the file with the same bounded
/// parser the renderer uses to list cues (`CaptionParser`), then returns the exact decoded text; it never
/// rewrites cue text, applies styles or follows anything the document names. Source is always available;
/// the Cues mode is derived by the renderer from the concealed text.
///
/// Privacy by dialect:
/// - SubStation, SubViewer and lyrics are line formats with no field grammar around free text, so the
///   shared assignment heuristic runs (`usesStructuredPrivacy == false`), as for SubRip and WebVTT. In
///   SubStation, `;` comments and `Comment:` events are additionally concealed whole when they assign a
///   secret, like the comments of the other configuration formats.
/// - TTML is XML, where the heuristic could swallow a closing tag, so structure-aware ranges are used
///   instead: sensitive element and attribute names, comments, CDATA and instructions, and any text run
///   between tags that assigns a secret are concealed with their markup left intact.
///
/// `sourceRecordCount` carries the cue count so the renderer can detect a cue list that concealment
/// has collapsed. Line-oriented dialects show the leading complete lines of an oversized file.
public struct CaptionAdapter: FormatAdapter, TextInputPolicyProviding {
    let dialect: CaptionDialect
    public init(dialect: CaptionDialect) { self.dialect = dialect }

    public var textInputPolicy: TextInputPolicy {
        switch dialect {
        case .timedText: .strict     // XML: a truncated document is not well formed.
        case .subViewer: .leadingRecords(.blankLine)
        case .subStationAlpha, .lyrics, .microDVD: .leadingRecords(.line)
        }
    }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let bytes = Array(input.text.utf8)
        let limits = CaptionLimits(maximumCues: context.budget.maxJSONNodes, maximumDepth: context.budget.maxJSONDepth)
        var ranges: [SensitiveRange] = []
        var structured = false
        if dialect == .timedText {
            var scanner = XMLSourceScanner(bytes: bytes, context: context)
            scanner.annotatesTextRuns = true
            try scanner.scan()
            ranges = scanner.sensitive
            structured = true
        }
        let document = try CaptionParser.parse(bytes, dialect: dialect, limits: limits) { try context.checkpoint() }
        for comment in document.commentRanges {
            if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: comment, context: context) {
                guard ranges.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                ranges.append(range)
            }
        }
        try context.checkpoint()
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, usesStructuredPrivacy: structured,
                                  syntax: Self.syntax(for: dialect), sourceRecordCount: document.cues.count)
    }

    static func syntax(for dialect: CaptionDialect) -> TextSyntax {
        switch dialect {
        case .subStationAlpha: .subStationAlpha
        case .timedText: .timedText
        case .subViewer: .subViewer
        case .lyrics: .lyrics
        case .microDVD: .microDVD
        }
    }
}

/// MicroDVD (`.sub` text form). The `.sub` suffix is shared with VobSub, a binary MPEG program stream
/// of subtitle bitmaps, so this adapter receives the bytes and decides: a file that starts with the MPEG
/// pack header, contains a NUL byte or is not valid UTF-8 / BOM-marked UTF-16 is reported as binary
/// content (or an unsupported encoding) and never displayed. Text then goes through the same bounded
/// caption parser and concealment as the other line-oriented dialects. Legacy 8-bit encodings are not
/// decoded.
public struct MicroDVDAdapter: BinaryFormatAdapter {
    public init() {}

    private static let programStreamPackHeader: [UInt8] = [0x00, 0x00, 0x01, 0xBA]

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let bytes = [UInt8](input.data)
        guard !bytes.starts(with: Self.programStreamPackHeader) else { throw PreviewFailure.binaryContent }
        let decoded = try Self.decode(bytes)
        guard decoded.text.utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        let document = try CaptionAdapter(dialect: .microDVD).parse(decoded, context: context)
        return ParsedTextDocument(text: document.text, sensitiveRanges: document.sensitiveRanges,
                                  usesStructuredPrivacy: document.usesStructuredPrivacy, syntax: document.syntax,
                                  sourceRecordCount: document.sourceRecordCount, decodedEncoding: decoded.encoding)
    }

    private static func decode(_ bytes: [UInt8]) throws -> DecodedText {
        guard !bytes.contains(0) || bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) else {
            throw PreviewFailure.binaryContent
        }
        let text: String?
        let encoding: TextEncoding
        let hasMark: Bool
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            let littleEndian = bytes[0] == 0xFF
            encoding = littleEndian ? .utf16LittleEndian : .utf16BigEndian
            hasMark = true
            let body = bytes.dropFirst(2)
            guard body.count.isMultiple(of: 2) else { throw PreviewFailure.binaryContent }
            let units = stride(from: body.startIndex, to: body.endIndex, by: 2).map { index in
                littleEndian ? UInt16(body[index]) | UInt16(body[index + 1]) << 8
                             : UInt16(body[index]) << 8 | UInt16(body[index + 1])
            }
            text = String(validating: units, as: UTF16.self)
        } else {
            encoding = .utf8
            hasMark = bytes.starts(with: [0xEF, 0xBB, 0xBF])
            text = String(validating: bytes.dropFirst(hasMark ? 3 : 0), as: UTF8.self)
        }
        guard let text else { throw PreviewFailure.unsupportedEncoding }
        return DecodedText(text: text, encoding: encoding, byteCount: bytes.count, hasByteOrderMark: hasMark)
    }
}

import Foundation

/// The timed-text dialects parsed by `CaptionParser`. SubRip and WebVTT keep their own validators
/// (`SubtitleParser` and `SafeSubtitleCues`); these five were added together and share one parser,
/// because both the adapter (raw text, to validate and plan concealment) and the renderer (concealed
/// text, to list cues) must read exactly the same grammar, and contracts are the module they share.
public enum CaptionDialect: Sendable, Equatable {
    /// SubStation Alpha and Advanced SubStation Alpha: `[Events]` `Dialogue:` lines.
    case subStationAlpha
    /// TTML and DFXP: `<p begin end dur>` elements.
    case timedText
    /// YouTube SubViewer: `H:MM:SS.mmm,H:MM:SS.mmm` followed by text, blocks separated by blank lines.
    case subViewer
    /// Lyrics: `[mm:ss.xx]` lines with optional `[ti:]`-style tags.
    case lyrics
    /// MicroDVD text: `{start frame}{end frame}text`.
    case microDVD
}

/// One displayed caption. `start` and `end` are source spellings, except MicroDVD, whose frame numbers
/// are converted to `H:MM:SS.mmm` at the stated or default frame rate. `lines` hold the cue text with
/// dialect markup (SubStation `{\tag}` overrides, MicroDVD `{y:i}`, enhanced-lyrics word stamps) removed;
/// the source view keeps every original character.
public struct CaptionCue: Equatable, Sendable {
    /// SubStation style (and actor) or nothing; displayed verbatim, never localized.
    public let label: String?
    public let start: String
    public let end: String?
    public let lines: [String]
    public init(label: String? = nil, start: String, end: String? = nil, lines: [String]) {
        self.label = label
        self.start = start
        self.end = end
        self.lines = lines
    }
}

/// A metadata tag such as lyrics `[ti:Title]`. Keys and values are source text, never localized.
public struct CaptionMetadata: Equatable, Sendable {
    public let key: String
    public let value: String
    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct CaptionDocument: Equatable, Sendable {
    public let cues: [CaptionCue]
    public let metadata: [CaptionMetadata]
    /// UTF-8 ranges of free-text comments (SubStation `;` lines and `Comment:` events) that sit
    /// outside the field grammar; an adapter conceals a comment that holds a secret assignment.
    public let commentRanges: [Range<Int>]
    public init(cues: [CaptionCue], metadata: [CaptionMetadata] = [], commentRanges: [Range<Int>] = []) {
        self.cues = cues
        self.metadata = metadata
        self.commentRanges = commentRanges
    }
}

public struct CaptionLimits: Sendable, Equatable {
    public var maximumCues: Int
    public var maximumCueTextUTF8Bytes: Int
    /// Deepest TTML element nesting accepted.
    public var maximumDepth: Int
    public init(maximumCues: Int = 20_000, maximumCueTextUTF8Bytes: Int = 16_384, maximumDepth: Int = 64) {
        self.maximumCues = maximumCues
        self.maximumCueTextUTF8Bytes = maximumCueTextUTF8Bytes
        self.maximumDepth = maximumDepth
    }
}

/// Line splitting and clock helpers shared by the dialect parsers.
enum CaptionLines {
    struct Line {
        let start: Int
        let end: Int
        var isEmpty: Bool { start == end }
    }

    /// LF, CRLF and lone CR separate lines; a leading UTF-8 byte order mark is skipped.
    static func split(_ bytes: [UInt8], checkpoint: () throws -> Void) throws -> [Line] {
        var lines: [Line] = []
        var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        var index = start
        while index < bytes.count {
            if index.isMultiple(of: 1024) { try checkpoint() }
            let byte = bytes[index]
            if byte == 10 || byte == 13 {
                lines.append(Line(start: start, end: index))
                index += byte == 13 && index + 1 < bytes.count && bytes[index + 1] == 10 ? 2 : 1
                start = index
            } else {
                index += 1
            }
        }
        if start < bytes.count { lines.append(Line(start: start, end: bytes.count)) }
        return lines
    }

    static func string(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    static func isBlank(_ bytes: [UInt8], _ line: Line) -> Bool {
        bytes[line.start..<line.end].allSatisfy { $0 == 32 || $0 == 9 }
    }

    /// Digits at `index` (at most nine, so arithmetic cannot overflow) and how many there were.
    static func digits(_ bytes: [UInt8], _ index: inout Int, _ end: Int) -> (value: Int, count: Int)? {
        let start = index
        var value = 0
        while index < end, bytes[index] >= 48, bytes[index] <= 57 {
            guard index - start < 9 else { return nil }
            value = value * 10 + Int(bytes[index] - 48)
            index += 1
        }
        return index > start ? (value, index - start) : nil
    }

    /// The fraction digits after a separator as milliseconds, so `5` is 500 ms and `05` is 50 ms.
    static func milliseconds(fraction: Int, digits: Int) -> Int? {
        switch digits {
        case 1: fraction * 100
        case 2: fraction * 10
        case 3: fraction
        default: nil
        }
    }

    /// `H:MM:SS.mmm` for a millisecond count, with plain ASCII digits (technical text, never localized).
    static func clock(_ milliseconds: Int) -> String {
        let total = milliseconds / 1000
        let hours = total / 3600
        let minutes = total / 60 % 60
        let seconds = total % 60
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        func three(_ value: Int) -> String { value < 10 ? "00\(value)" : value < 100 ? "0\(value)" : "\(value)" }
        return "\(hours):\(two(minutes)):\(two(seconds)).\(three(milliseconds % 1000))"
    }
}

/// Strict, bounded parsers for the five dialects. Each throws `PreviewFailure.malformedDocument` for
/// anything that is not valid in its dialect, and `tooManyNodes` past `limits.maximumCues`; nothing is
/// silently skipped, so a misread file is never presented as a complete caption file. Input is UTF-8
/// bytes; parsing never evaluates, resolves or loads anything.
public enum CaptionParser {
    public static func parse(_ bytes: [UInt8], dialect: CaptionDialect, limits: CaptionLimits = CaptionLimits(),
                             checkpoint: () throws -> Void = {}) throws -> CaptionDocument {
        try checkpoint()
        switch dialect {
        case .subStationAlpha: return try SubStationAlphaParser.parse(bytes, limits: limits, checkpoint: checkpoint)
        case .timedText: return try TimedTextParser.parse(bytes, limits: limits, checkpoint: checkpoint)
        case .subViewer: return try SubViewerParser.parse(bytes, limits: limits, checkpoint: checkpoint)
        case .lyrics: return try LyricsParser.parse(bytes, limits: limits, checkpoint: checkpoint)
        case .microDVD: return try MicroDVDParser.parse(bytes, limits: limits, checkpoint: checkpoint)
        }
    }
}

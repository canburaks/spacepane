import Foundation
import PreviewContracts

/// The hidden-content scan ("Safety Lens", decision 012): turns invisible and deceptive characters and
/// hidden text in a file's own displayed text into typed findings.
///
/// - The pipeline calls it **after** the privacy filter, on the concealed safe text. Every reported
///   line therefore matches the line-number gutter, and a concealed secret is never examined.
/// - Passes: invisible characters (`HiddenCharacters`, shared with the renderer's Invisibles mode),
///   mixed-script look-alike words (`MixedScriptDetector`), and, for Markdown only, HTML comments and
///   link-reference comments (`MarkdownCommentScanner`). Text that is entirely ASCII can hold none of the
///   first two, so it costs one byte test.
/// - Findings carry kinds, counts and lines. The one exception is the message decoded from Unicode Tag
///   characters, which passes through the injected privacy filter before it is attached.
/// - Everything is bounded by the input the pipeline already budgeted and checks the request's
///   cancellation and deadline.
enum HiddenContentScanner {
    /// Whether a registration's displayed text is decoded or converted file content. App-made
    /// summaries are excluded regardless of input path or encoding; archive names have their own
    /// analyzer. Decoded encoding and converted origin describe content independently of I/O.
    static func appliesTo(_ inputPath: AdapterInputPath, document: ParsedTextDocument) -> Bool {
        guard document.origin != .summary else { return false }
        return switch inputPath {
        case .text: true
        case .binary, .randomAccess: document.decodedEncoding != nil || document.origin == .converted
        case .geometry, .url: false
        }
    }

    /// - Parameters:
    ///   - text: the displayed (concealed) text.
    ///   - fileName: the last path component, used to recognize AI-agent instruction files.
    ///   - privacy: the pipeline's filter; applied to text decoded from Unicode Tags.
    static func scan(text: String, formatID: FormatID, fileName: String,
                     privacy: any PreviewPrivacyFiltering, context: RequestContext) throws -> [PreviewFinding] {
        try context.checkpoint()
        // One contiguous UTF-8 copy serves every pass; it shares storage when the text already is native.
        var contiguous = text
        contiguous.makeContiguousUTF8()
        let displayed = contiguous
        let isMarkdown = formatID == .markdown
        return try UTF8Bytes.withBytes(of: displayed) { bytes in
            let isASCII = UTF8Bytes.isASCII(bytes)
            guard !isASCII || isMarkdown else { return [] }
            let locator = LineLocator(displayed, isASCII: isASCII)
            var findings: [PreviewFinding] = []
            if !isASCII {
                findings += try invisibleCharacterFindings(in: displayed, locator: locator, privacy: privacy, context: context)
                var words = Occurrences()
                try MixedScriptDetector.scan(bytes, checkpoint: context.checkpoint) { offset in
                    words.add(line: locator.line(atUTF8Offset: offset))
                }
                findings += words.finding(.hiddenMixedScripts)
            }
            if isMarkdown {
                var comments = Occurrences()
                try MarkdownCommentScanner.scan(bytes, checkpoint: context.checkpoint) { offset in
                    comments.add(line: locator.line(atUTF8Offset: offset))
                }
                findings += comments.finding(.hiddenMarkdownComments)
            }
            try context.checkpoint()
            return AgentInstructionFiles.contains(fileName) ? escalated(findings) : findings
        }
    }

    // MARK: Invisible characters

    private static func invisibleCharacterFindings(in text: String, locator: LineLocator, privacy: any PreviewPrivacyFiltering,
                                                   context: RequestContext) throws -> [PreviewFinding] {
        let spans = try HiddenCharacters.spans(in: text, checkpoint: context.checkpoint)
        guard !spans.isEmpty else { return [] }
        var tallies = Array(repeating: Occurrences(), count: HiddenCharacterClass.allCases.count)
        for span in spans {
            // One finding per class; `count` is scalars, `lines` the start line of each run.
            tallies[slot(span.kind)].add(count: span.scalarCount, line: locator.line(atUTF16Offset: span.utf16Range.lowerBound))
        }
        var findings: [PreviewFinding] = []
        for characterClass in HiddenCharacterClass.allCases {
            let kind = findingKind(characterClass)
            if characterClass == .tag, tallies[slot(.tag)].count > 0 {
                let detail = try decodedTagMessage(in: text, spans: spans, privacy: privacy, context: context)
                findings += tallies[slot(.tag)].finding(kind, detail: detail)
            } else {
                findings += tallies[slot(characterClass)].finding(kind)
            }
        }
        return findings
    }

    private static func slot(_ characterClass: HiddenCharacterClass) -> Int {
        switch characterClass {
        case .bidirectionalControl: 0
        case .zeroWidth: 1
        case .tag: 2
        case .variationSelector: 3
        case .privateUse: 4
        }
    }

    private static func findingKind(_ characterClass: HiddenCharacterClass) -> PreviewFindingKind {
        switch characterClass {
        case .bidirectionalControl: .hiddenBidirectionalControls
        case .zeroWidth: .hiddenZeroWidth
        case .tag: .hiddenUnicodeTags
        case .variationSelector: .hiddenVariationSelectors
        case .privateUse: .hiddenPrivateUse
        }
    }

    // MARK: Unicode Tag messages

    /// Tag characters U+E0020...U+E007E mirror ASCII U+0020...U+007E. Each run decodes to one string;
    /// runs join in text order with a single space and other tag characters (language tag, cancel tag)
    /// are dropped. Decoding stops at a bounded window, and only the filtered result is attached.
    ///
    /// The window is twice the display cap on purpose: the cap applies to the concealed text, so a
    /// secret that straddles the cap is still complete when the filter sees it. Without that, a token
    /// cut in half would no longer match its pattern and its first half would be shown.
    private static func decodedTagMessage(in text: String, spans: [HiddenCharacterSpan], privacy: any PreviewPrivacyFiltering,
                                          context: RequestContext) throws -> PreviewFindingDetail {
        let window = 2 * PreviewFinding.maximumDecodedCharacters
        var message = ""
        var decoded = 0
        var inspected = 0
        spanLoop: for span in spans where span.kind == .tag {
            inspected += 1
            if inspected.isMultiple(of: 64) { try context.checkpoint() }
            let lower = String.Index(utf16Offset: span.utf16Range.lowerBound, in: text)
            let upper = String.Index(utf16Offset: span.utf16Range.upperBound, in: text)
            var run = ""
            for scalar in text.unicodeScalars[lower..<upper] where (0xE0020...0xE007E).contains(scalar.value) {
                guard decoded + (message.isEmpty ? 0 : 1) + run.unicodeScalars.count < window else { break }
                run.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xE0000) ?? " ")
            }
            guard !run.isEmpty else { continue }
            if !message.isEmpty { message += " "; decoded += 1 }
            message += run
            decoded += run.unicodeScalars.count
            if decoded >= window { break spanLoop }
        }
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .none }
        let safe = try privacy.filter(ParsedTextDocument(text: trimmed), context: context)
        try context.checkpoint()
        let concealed = safe.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !concealed.isEmpty else { return .none }
        return .decodedText(displayBounded(concealed))
    }

    /// At most the contract's decoded-text bound, marking a cut with an ellipsis.
    private static func displayBounded(_ text: String) -> String {
        let limit = PreviewFinding.maximumDecodedCharacters
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }

    // MARK: AI-agent instruction files

    /// A hidden character in a file an AI agent reads as instructions can steer the agent without the
    /// reader seeing it (rules-file backdoors). Zero-width characters, variation selectors, look-alike
    /// letters and Markdown comments are ordinary elsewhere and become warnings here; private-use
    /// characters alone (icon fonts) change nothing.
    private static func escalated(_ findings: [PreviewFinding]) -> [PreviewFinding] {
        guard findings.contains(where: { $0.kind != .hiddenPrivateUse }) else { return findings }
        let raised: Set<PreviewFindingKind> = [.hiddenZeroWidth, .hiddenVariationSelectors, .hiddenMixedScripts, .hiddenMarkdownComments]
        return findings.map { finding in
            raised.contains(finding.kind)
                ? PreviewFinding(kind: finding.kind, severity: .warning, count: finding.count, lines: finding.lines, detail: finding.detail)
                : finding
        } + [PreviewFinding(kind: .hiddenAgentInstructions, count: 1)]
    }
}

/// File names that AI coding agents read as instructions. Matching is case-insensitive on the last path
/// component. This is the one place to add a name.
enum AgentInstructionFiles {
    static let names: Set<String> = [
        "agents.md", "agent.md", "claude.md", "gemini.md", "skill.md", "copilot-instructions.md",
        ".cursorrules", ".windsurfrules", ".clinerules", ".roorules", "mcp.json", ".mcp.json"
    ]
    /// Cursor rule files.
    static let suffixes = [".mdc"]

    static func contains(_ fileName: String) -> Bool {
        let name = fileName.lowercased()
        return names.contains(name) || suffixes.contains { name.hasSuffix($0) }
    }
}

// MARK: - Shared helpers

/// Occurrences of one kind: an exact count and the first lines they start on.
private struct Occurrences {
    private(set) var count = 0
    private(set) var lines: [Int] = []

    /// Offsets arrive in text order, so lines never decrease. The line is resolved only while the
    /// finding still has room for another one.
    mutating func add(count added: Int = 1, line: @autoclosure () -> Int?) {
        count += added
        guard lines.count < PreviewFinding.maximumLines, let line = line(), lines.last != line else { return }
        lines.append(line)
    }

    func finding(_ kind: PreviewFindingKind, detail: PreviewFindingDetail = .none) -> [PreviewFinding] {
        count > 0 ? [PreviewFinding(kind: kind, count: count, lines: lines, detail: detail)] : []
    }
}

/// Maps offsets in the displayed text to one-based logical lines, using the gutter's own definition.
/// Line starts are built on first use and only once, so a text without findings never pays for them.
/// Single-threaded and local to one scan.
private final class LineLocator {
    private let text: String
    private let isASCII: Bool
    private var starts: LogicalLines.Starts?

    init(_ text: String, isASCII: Bool) {
        self.text = text
        self.isASCII = isASCII
    }

    func line(atUTF16Offset offset: Int) -> Int? {
        let index = starts ?? LogicalLines.starts(in: text)
        starts = index
        return LogicalLines.lineIndex(containingUTF16: offset, in: index).map { $0 + 1 }
    }

    /// `offset` must lie on a scalar boundary.
    func line(atUTF8Offset offset: Int) -> Int? {
        guard isASCII else {
            let index = text.utf8.index(text.utf8.startIndex, offsetBy: offset)
            return line(atUTF16Offset: text.utf16.distance(from: text.utf16.startIndex, to: index))
        }
        return line(atUTF16Offset: offset)
    }
}

enum UTF8Bytes {
    /// The text's UTF-8 bytes without copying when storage is contiguous (always so for native strings).
    static func withBytes<Result>(of text: String, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        if let result = try text.utf8.withContiguousStorageIfAvailable(body) { return result }
        return try Array(text.utf8).withUnsafeBufferPointer(body)
    }

    /// Eight bytes at a time; a single pass at memory speed.
    static func isASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = bytes.baseAddress else { return true }
        let raw = UnsafeRawPointer(base)
        var combined: UInt64 = 0
        var index = 0
        while index + 8 <= bytes.count {
            combined |= raw.loadUnaligned(fromByteOffset: index, as: UInt64.self)
            index += 8
        }
        while index < bytes.count {
            combined |= UInt64(bytes[index])
            index += 1
        }
        return combined & 0x8080_8080_8080_8080 == 0
    }
}

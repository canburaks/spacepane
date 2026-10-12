import Foundation
import PreviewContracts

/// Derives a read-only cue list from caption text that privacy concealment has already run on.
/// Its only input is the safe presentation text, so no alternate representation of the source
/// exists. It re-validates the SubRip/WebVTT block structure with the same rules as
/// `SubtitleAdapter` (kept separate because renderers cannot depend on format adapters, as
/// with `SafeStructuredText` and the XML/JSON adapters) and returns `nil`, which shows the
/// structure-unavailable notice with safe source, when anything no longer fits: a missing
/// signature, an invalid timing line, a block that is not a cue/NOTE/STYLE/REGION, no cues,
/// more than `maximumCues` cues, text over `maximumUTF16Units` (the default input budget, so
/// every default-budget caption file qualifies), one cue over
/// `maximumCueTextUTF8Bytes`, or a cue count different from the adapter's `expectedCueCount`
/// (concealing a secret can swallow following cues without breaking the grammar).
///
/// Row shape: `name` is the identifier or SubRip index when present, `: `, then the start and
/// end timestamps exactly as spelled in the source joined by an arrow. `value` is the cue text
/// lines joined by " / ". Markup (`<i>`, `<v Name>`, `{\an8}`), STYLE sheets, REGION blocks, cue
/// settings and NOTE comments are neither interpreted nor listed; Source mode shows them.
/// Timestamps, identifiers and cue text are source content and are never localized, so
/// `locale` does not affect the rows.
enum SafeSubtitleCues {
    static let maximumUTF16Units = 1_048_576
    static let maximumCues = 20_000
    static let maximumCueTextUTF8Bytes = 16_384
    // Neutral punctuation between source tokens; none of it is translated text.
    private static let identifierSeparator = ": "
    private static let timingJoiner = " \u{2192} "
    private static let lineJoiner = " / "

    static func nodes(_ safeText: String, syntax: TextSyntax, locale: Locale, expectedCueCount: Int? = nil) -> [SafeOutlineNode]? {
        let variant: CueParser.Variant
        switch syntax {
        case .subRip: variant = .subRip
        case .webVTT: variant = .webVTT
        default: return nil
        }
        guard safeText.utf16.prefix(maximumUTF16Units + 1).count <= maximumUTF16Units,
              let cues = CueParser(bytes: Array(safeText.utf8), variant: variant).cues(),
              !cues.isEmpty, expectedCueCount == nil || expectedCueCount == cues.count else { return nil }
        return cues.enumerated().map { index, cue in
            let prefix = cue.identifier.map { $0 + identifierSeparator } ?? ""
            return SafeOutlineNode(id: index, name: prefix + cue.start + timingJoiner + cue.end,
                                   value: cue.text.joined(separator: lineJoiner))
        }
    }
}

private struct Cue {
    let identifier: String?
    let start: String
    let end: String
    let text: [String]
}

/// A structurally valid block: a listed cue, or a NOTE/STYLE/REGION block that is not listed.
private enum Block {
    case cue(Cue)
    case unlisted
}

private struct CueParser {
    enum Variant { case subRip, webVTT }
    let bytes: [UInt8]
    let variant: Variant

    private struct Line {
        let start: Int
        let end: Int
        var isEmpty: Bool { start == end }
    }

    private enum ASCII {
        static let tab: UInt8 = 9
        static let lineFeed: UInt8 = 10
        static let carriageReturn: UInt8 = 13
        static let space: UInt8 = 32
        static let comma: UInt8 = 44
        static let hyphen: UInt8 = 45
        static let period: UInt8 = 46
        static let colon: UInt8 = 58
        static let greaterThan: UInt8 = 62
    }

    private static let noteKeyword = Array("NOTE".utf8)
    private static let styleKeyword = Array("STYLE".utf8)
    private static let regionKeyword = Array("REGION".utf8)
    private static let signature = Array("WEBVTT".utf8)

    func cues() -> [Cue]? {
        let lines = splitLines()
        var result: [Cue] = []
        var seenCue = false
        var index = 0
        if variant == .webVTT {
            guard let first = lines.first, hasSignature(first) else { return nil }
            index = 1
            while index < lines.count, !isBlank(lines[index]), !containsArrow(lines[index]) { index += 1 }
        }
        while index < lines.count {
            if isBlank(lines[index]) { index += 1; continue }
            var end = index + 1
            while end < lines.count, !isBlank(lines[end]) { end += 1 }
            let block = index..<end
            index = end
            guard let parsed = variant == .subRip ? subRipBlock(lines, block) : webVTTBlock(lines, block, seenCue: seenCue) else {
                return nil
            }
            if case .cue(let cue) = parsed {
                guard result.count < SafeSubtitleCues.maximumCues else { return nil }
                result.append(cue)
                seenCue = true
            }
        }
        return result
    }

    // MARK: Blocks (`nil` means the block breaks the grammar)

    private func subRipBlock(_ lines: [Line], _ block: Range<Int>) -> Block? {
        var timing = block.lowerBound
        var identifier: String?
        if let index = indexText(lines[timing]) {
            identifier = index
            timing += 1
            guard timing < block.upperBound else { return nil }
        }
        guard let span = timingSpan(lines[timing]) else { return nil }
        for index in (timing + 1)..<block.upperBound where timingSpan(lines[index]) != nil { return nil }
        return makeCue(identifier: identifier, span: span, payload: lines[(timing + 1)..<block.upperBound])
    }

    private func webVTTBlock(_ lines: [Line], _ block: Range<Int>, seenCue: Bool) -> Block? {
        let first = lines[block.lowerBound]
        var timing: Int?
        if containsArrow(first) { timing = block.lowerBound }
        else if block.count > 1, containsArrow(lines[block.lowerBound + 1]) { timing = block.lowerBound + 1 }
        if let timing {
            guard let span = timingSpan(lines[timing]) else { return nil }
            for index in (timing + 1)..<block.upperBound where containsArrow(lines[index]) { return nil }
            let identifier = timing > block.lowerBound ? string(first.start, first.end) : nil
            return makeCue(identifier: identifier, span: span, payload: lines[(timing + 1)..<block.upperBound])
        }
        let isNote = hasKeyword(first, Self.noteKeyword, allowsText: true)
        let isHeaderBlock = !seenCue && (hasKeyword(first, Self.styleKeyword, allowsText: false)
                                         || hasKeyword(first, Self.regionKeyword, allowsText: false))
        guard isNote || isHeaderBlock else { return nil }
        for index in block where containsArrow(lines[index]) { return nil }
        return .unlisted
    }

    private func makeCue(identifier: String?, span: (start: Range<Int>, end: Range<Int>), payload: ArraySlice<Line>) -> Block? {
        var total = 0
        var text: [String] = []
        for line in payload {
            total += line.end - line.start
            guard total <= SafeSubtitleCues.maximumCueTextUTF8Bytes else { return nil }
            text.append(string(line.start, line.end))
        }
        return .cue(Cue(identifier: identifier, start: string(span.start.lowerBound, span.start.upperBound),
                        end: string(span.end.lowerBound, span.end.upperBound), text: text))
    }

    // MARK: Lines and tokens

    private func string(_ start: Int, _ end: Int) -> String { String(decoding: bytes[start..<end], as: UTF8.self) }

    private func splitLines() -> [Line] {
        var result: [Line] = []
        var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == ASCII.lineFeed || byte == ASCII.carriageReturn {
                result.append(Line(start: start, end: index))
                let crlf = byte == ASCII.carriageReturn && index + 1 < bytes.count && bytes[index + 1] == ASCII.lineFeed
                index += crlf ? 2 : 1
                start = index
            } else {
                index += 1
            }
        }
        if start < bytes.count { result.append(Line(start: start, end: bytes.count)) }
        return result
    }

    private func isSpaceOrTab(_ byte: UInt8) -> Bool { byte == ASCII.space || byte == ASCII.tab }

    private func isBlank(_ line: Line) -> Bool {
        switch variant {
        case .webVTT: line.isEmpty
        case .subRip: bytes[line.start..<line.end].allSatisfy(isSpaceOrTab)
        }
    }

    private func containsArrow(_ line: Line) -> Bool { containsArrow(from: line.start, to: line.end) }

    private func containsArrow(from start: Int, to end: Int) -> Bool {
        guard end - start >= 3 else { return false }
        for index in start...(end - 3)
        where bytes[index] == ASCII.hyphen && bytes[index + 1] == ASCII.hyphen && bytes[index + 2] == ASCII.greaterThan {
            return true
        }
        return false
    }

    private func hasSignature(_ line: Line) -> Bool {
        let length = Self.signature.count
        guard line.end - line.start >= length, bytes[line.start..<(line.start + length)].elementsEqual(Self.signature) else { return false }
        return line.end - line.start == length || isSpaceOrTab(bytes[line.start + length])
    }

    private func hasKeyword(_ line: Line, _ keyword: [UInt8], allowsText: Bool) -> Bool {
        guard line.end - line.start >= keyword.count,
              bytes[line.start..<(line.start + keyword.count)].elementsEqual(keyword) else { return false }
        let rest = line.start + keyword.count
        if rest == line.end { return true }
        guard isSpaceOrTab(bytes[rest]) else { return false }
        return allowsText || bytes[rest..<line.end].allSatisfy(isSpaceOrTab)
    }

    /// The digits of a SubRip index line, trimmed of spaces and tabs.
    private func indexText(_ line: Line) -> String? {
        var start = line.start
        var end = line.end
        while start < end, isSpaceOrTab(bytes[start]) { start += 1 }
        while end > start, isSpaceOrTab(bytes[end - 1]) { end -= 1 }
        guard start < end, bytes[start..<end].allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return string(start, end)
    }

    /// Byte ranges of the start and end timestamps when the line is a valid timing line.
    private func timingSpan(_ line: Line) -> (start: Range<Int>, end: Range<Int>)? {
        var index = line.start
        skipBlanks(&index, line.end)
        let startBegin = index
        guard let start = timestamp(&index, line.end) else { return nil }
        let startRange = startBegin..<index
        skipBlanks(&index, line.end)
        guard index + 3 <= line.end, bytes[index] == ASCII.hyphen, bytes[index + 1] == ASCII.hyphen,
              bytes[index + 2] == ASCII.greaterThan else { return nil }
        index += 3
        skipBlanks(&index, line.end)
        let endBegin = index
        guard let end = timestamp(&index, line.end), end >= start else { return nil }
        let endRange = endBegin..<index
        if index < line.end {
            guard isSpaceOrTab(bytes[index]), !containsArrow(from: index, to: line.end) else { return nil }
        }
        return (startRange, endRange)
    }

    private func skipBlanks(_ index: inout Int, _ end: Int) {
        while index < end, isSpaceOrTab(bytes[index]) { index += 1 }
    }

    private func timestamp(_ index: inout Int, _ end: Int) -> Int? {
        func digits() -> (value: Int, count: Int)? {
            let start = index
            var value = 0
            while index < end, bytes[index] >= 48, bytes[index] <= 57 {
                guard index - start < 9 else { return nil }
                value = value * 10 + Int(bytes[index] - 48)
                index += 1
            }
            return index > start ? (value, index - start) : nil
        }
        func colon() -> Bool {
            guard index < end, bytes[index] == ASCII.colon else { return false }
            index += 1
            return true
        }
        guard let first = digits(), colon(), let second = digits(), second.count == 2 else { return nil }
        let hours: Int, minutes: Int, seconds: Int
        switch variant {
        case .subRip:
            guard colon(), let third = digits(), third.count == 2 else { return nil }
            (hours, minutes, seconds) = (first.value, second.value, third.value)
        case .webVTT:
            let needsHours = first.count != 2 || first.value > 59 || (index < end && bytes[index] == ASCII.colon)
            if needsHours {
                guard first.count >= 2, colon(), let third = digits(), third.count == 2 else { return nil }
                (hours, minutes, seconds) = (first.value, second.value, third.value)
            } else {
                (hours, minutes, seconds) = (0, first.value, second.value)
            }
        }
        guard minutes <= 59, seconds <= 59, index < end else { return nil }
        let separator = bytes[index]
        guard separator == ASCII.period || (variant == .subRip && separator == ASCII.comma) else { return nil }
        index += 1
        guard let fraction = digits(), fraction.count == 3 else { return nil }
        return ((hours * 60 + minutes) * 60 + seconds) * 1000 + fraction.value
    }
}

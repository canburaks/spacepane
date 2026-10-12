import PreviewContracts

/// Facts the adapter needs from a validated caption file; nothing here carries source text.
struct SubtitleOutline {
    let cueCount: Int
    /// UTF-8 ranges of WebVTT `NOTE` bodies that the shared policy classes as sensitive.
    let commentRanges: [SensitiveRange]
}

/// Strict block validator for SubRip and WebVTT. It operates on UTF-8 bytes because every
/// grammar delimiter is ASCII; cue text is never decoded, copied or interpreted.
///
/// Common rules
/// - Lines end with LF, CRLF or a lone CR. A leading UTF-8 byte-order mark is ignored.
/// - A cue is `[identifier] timing-line text...`. Cue text may be empty. Timestamps need
///   minutes and seconds in 0...59, exactly three fraction digits, and end >= start.
///   Anything after the end timestamp must be separated by a space or tab (SubRip
///   coordinates, WebVTT settings); it is never interpreted and must not contain `-->`.
///   Start times are not required to be ordered.
/// - Cue limit: `RequestContext.budget.maxJSONNodes`. Line count/length limits are applied
///   by `ExpandedTextLimits` before parsing.
///
/// SubRip (no formal standard; de-facto format as described by Matroska)
/// - Blocks are separated by one or more blank lines; a line of only spaces/tabs is blank.
/// - A block is an optional all-digit index line, a timing line, then text lines.
/// - Timestamp `H+:MM:SS,mmm` with one or more hour digits; `.` is accepted for `,`.
///   Whitespace around `-->` is optional.
/// - A text line that is itself a valid timing line means a blank separator is missing and
///   is rejected rather than merged into the previous cue. Cues need at least one block.
///
/// WebVTT (https://www.w3.org/TR/webvtt1/)
/// - The first line must be `WEBVTT`, optionally followed by a space or tab and any text.
/// - Header lines follow until the first blank line, or until a line containing `-->`, which
///   starts the first cue (the specification's parser does the same). Blank means empty.
/// - Timestamp `[HH:]MM:SS.mmm`: hours need two or more digits and are mandatory when the
///   first group is not exactly two digits or exceeds 59. The separator is `.` only, so
///   SubRip commas are rejected. Whitespace around `-->` is optional, as in the specification's
///   parser, though its grammar asks for at least one.
/// - A block is a cue when its first line (no identifier) or second line (first line is the
///   identifier) contains `-->`; the timing line must then be valid and no payload line may
///   contain `-->`. Otherwise the block must be a `NOTE` block (any position), or a `STYLE` or
///   `REGION` block before the first cue; those must not contain `-->`. STYLE sheets,
///   REGION settings and cue settings are never parsed or applied.
/// - A valid file with no cue is accepted; its signature establishes the format.
///
/// Malformed policy: any block that is not one of the above, or any invalid timing line,
/// missing WebVTT signature, SubRip file without a cue, or exceeded cue limit, throws
/// `PreviewFailure.malformedDocument` (or `tooManyNodes`). Nothing is silently skipped, so a
/// misparsed file is never presented as a complete caption file.
struct SubtitleParser {
    let bytes: [UInt8]
    let variant: SubtitleAdapter.Variant
    let context: RequestContext

    private struct Line {
        let start: Int
        let end: Int
        var isEmpty: Bool { start == end }
    }

    private struct State {
        var cueCount = 0
        var seenCue = false
        var comments: [SensitiveRange] = []
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

    func parse() throws -> SubtitleOutline {
        let lines = try splitLines()
        var state = State()
        var index = 0
        if variant == .webVTT {
            guard let first = lines.first, hasSignature(first) else { throw PreviewFailure.malformedDocument }
            index = 1
            while index < lines.count, !isBlank(lines[index]), !containsArrow(lines[index]) {
                if index.isMultiple(of: 256) { try context.checkpoint() }
                index += 1
            }
        }
        while index < lines.count {
            if isBlank(lines[index]) { index += 1; continue }
            var end = index + 1
            while end < lines.count, !isBlank(lines[end]) { end += 1 }
            try context.checkpoint()
            switch variant {
            case .subRip: try subRipBlock(lines, index..<end, &state)
            case .webVTT: try webVTTBlock(lines, index..<end, &state)
            }
            index = end
        }
        if variant == .subRip, state.cueCount == 0 { throw PreviewFailure.malformedDocument }
        return SubtitleOutline(cueCount: state.cueCount, commentRanges: state.comments)
    }

    // MARK: Blocks

    private func subRipBlock(_ lines: [Line], _ block: Range<Int>, _ state: inout State) throws {
        var timing = block.lowerBound
        if isIndex(lines[timing]) {
            timing += 1
            guard timing < block.upperBound else { throw PreviewFailure.malformedDocument }
        }
        guard isTimingLine(lines[timing]) else { throw PreviewFailure.malformedDocument }
        for index in (timing + 1)..<block.upperBound where isTimingLine(lines[index]) {
            throw PreviewFailure.malformedDocument
        }
        try addCue(&state)
    }

    private func webVTTBlock(_ lines: [Line], _ block: Range<Int>, _ state: inout State) throws {
        let first = lines[block.lowerBound]
        var timing: Int?
        if containsArrow(first) { timing = block.lowerBound }
        else if block.count > 1, containsArrow(lines[block.lowerBound + 1]) { timing = block.lowerBound + 1 }
        if let timing {
            guard isTimingLine(lines[timing]) else { throw PreviewFailure.malformedDocument }
            for index in (timing + 1)..<block.upperBound where containsArrow(lines[index]) {
                throw PreviewFailure.malformedDocument
            }
            try addCue(&state)
        } else if hasKeyword(first, Self.noteKeyword, allowsText: true) {
            for index in block where containsArrow(lines[index]) { throw PreviewFailure.malformedDocument }
            if let content = commentContent(lines, block),
               let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: content, context: context) {
                state.comments.append(range)
            }
        } else if !state.seenCue, hasKeyword(first, Self.styleKeyword, allowsText: false)
                    || hasKeyword(first, Self.regionKeyword, allowsText: false) {
            for index in block where containsArrow(lines[index]) { throw PreviewFailure.malformedDocument }
        } else {
            throw PreviewFailure.malformedDocument
        }
    }

    private func addCue(_ state: inout State) throws {
        state.cueCount += 1
        state.seenCue = true
        guard state.cueCount <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
    }

    /// Body of a `NOTE` block after the keyword and its single separator, so that concealing
    /// it leaves `NOTE` and its separator intact and the block structure unchanged.
    private func commentContent(_ lines: [Line], _ block: Range<Int>) -> Range<Int>? {
        let first = lines[block.lowerBound]
        let separator = first.start + Self.noteKeyword.count
        var start = separator < first.end ? separator + 1 : first.end
        if start >= first.end, block.count > 1 { start = lines[block.lowerBound + 1].start }
        let end = lines[block.upperBound - 1].end
        return start < end ? start..<end : nil
    }

    // MARK: Lines

    private func splitLines() throws -> [Line] {
        var result: [Line] = []
        var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        var index = start
        while index < bytes.count {
            if index.isMultiple(of: 1024) { try context.checkpoint() }
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

    private func isBlank(_ line: Line) -> Bool {
        switch variant {
        case .webVTT: line.isEmpty
        case .subRip: bytes[line.start..<line.end].allSatisfy(isSpaceOrTab)
        }
    }

    private func isSpaceOrTab(_ byte: UInt8) -> Bool { byte == ASCII.space || byte == ASCII.tab }

    private func containsArrow(_ line: Line) -> Bool { containsArrow(from: line.start, to: line.end) }

    private func containsArrow(from start: Int, to end: Int) -> Bool {
        guard end - start >= 3 else { return false }
        for index in start...(end - 3)
        where bytes[index] == ASCII.hyphen && bytes[index + 1] == ASCII.hyphen && bytes[index + 2] == ASCII.greaterThan {
            return true
        }
        return false
    }

    // MARK: Tokens

    private func hasSignature(_ line: Line) -> Bool {
        let length = Self.signature.count
        guard line.end - line.start >= length, bytes[line.start..<(line.start + length)].elementsEqual(Self.signature) else { return false }
        return line.end - line.start == length || isSpaceOrTab(bytes[line.start + length])
    }

    /// Keyword followed by end of line or a space/tab. STYLE and REGION allow only blanks after.
    private func hasKeyword(_ line: Line, _ keyword: [UInt8], allowsText: Bool) -> Bool {
        guard line.end - line.start >= keyword.count,
              bytes[line.start..<(line.start + keyword.count)].elementsEqual(keyword) else { return false }
        let rest = line.start + keyword.count
        if rest == line.end { return true }
        guard isSpaceOrTab(bytes[rest]) else { return false }
        return allowsText || bytes[rest..<line.end].allSatisfy(isSpaceOrTab)
    }

    private func isIndex(_ line: Line) -> Bool {
        var start = line.start
        var end = line.end
        while start < end, isSpaceOrTab(bytes[start]) { start += 1 }
        while end > start, isSpaceOrTab(bytes[end - 1]) { end -= 1 }
        return start < end && bytes[start..<end].allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    private func isTimingLine(_ line: Line) -> Bool {
        var index = line.start
        skipBlanks(&index, line.end)
        guard let start = timestamp(&index, line.end) else { return false }
        skipBlanks(&index, line.end)
        guard index + 3 <= line.end, bytes[index] == ASCII.hyphen, bytes[index + 1] == ASCII.hyphen,
              bytes[index + 2] == ASCII.greaterThan else { return false }
        index += 3
        skipBlanks(&index, line.end)
        guard let end = timestamp(&index, line.end), end >= start else { return false }
        guard index < line.end else { return true }
        return isSpaceOrTab(bytes[index]) && !containsArrow(from: index, to: line.end)
    }

    private func skipBlanks(_ index: inout Int, _ end: Int) {
        while index < end, isSpaceOrTab(bytes[index]) { index += 1 }
    }

    /// Milliseconds for one timestamp, advancing `index`; `nil` when it breaks the variant's grammar.
    private func timestamp(_ index: inout Int, _ end: Int) -> Int? {
        // Hour groups are capped at nine digits so all arithmetic stays far from overflow.
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

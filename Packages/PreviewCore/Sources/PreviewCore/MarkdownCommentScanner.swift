import Foundation

/// Finds text a Markdown reader never sees: HTML comments (`<!-- ... -->`) and link-reference
/// "comments" (`[//]: # (...)`, `[comment]: <> (...)`). Both render as nothing, so they can carry
/// instructions to an AI agent that reads the source. Occurrences inside code are visible text and are
/// not reported.
///
/// This is a line scanner over UTF-8 bytes, not a Markdown parser. It tracks:
///
/// - fenced code blocks of ``` or ~~~, including fences indented, quoted (`>`) or opened in a list item,
///   which stay open to the end of the text when never closed (as CommonMark does);
/// - inline code spans: a run of backticks pairs with the next run of the same length on the same line;
/// - comments that continue over several lines, whose content is neither code nor another opening;
/// - `\<!--`, which is literal text.
///
/// Known limits: indented code blocks, code spans that cross a line, backslash-escaped backticks and
/// HTML blocks such as `<pre>` are not modelled, so a comment shown there is counted. The scan costs
/// two byte searches unless the text holds `<!--` or `]:`.
enum MarkdownCommentScanner {
    /// Calls `onOpening` with the UTF-8 offset of each comment opening, in text order.
    static func scan(_ bytes: UnsafeBufferPointer<UInt8>, checkpoint: () throws -> Void,
                     onOpening: (_ utf8Offset: Int) -> Void) throws {
        guard contains("<!--", in: bytes) || contains("]:", in: bytes) else { return }
        let count = bytes.count
        var inFence: Fence?
        var inComment = false
        var inline = InlineScanner(bytes)
        var lineStart = 0
        var lines = 0
        while lineStart < count {
            lines += 1
            if lines.isMultiple(of: 1024) { try checkpoint() }
            var lineEnd = lineStart
            while lineEnd < count, bytes[lineEnd] != 0x0A, bytes[lineEnd] != 0x0D { lineEnd += 1 }
            scanLine(lineStart..<lineEnd, bytes, &inFence, &inComment, &inline, onOpening)
            lineStart = lineEnd
            if lineStart < count {
                // CRLF is one separator.
                lineStart += bytes[lineStart] == 0x0D && lineStart + 1 < count && bytes[lineStart + 1] == 0x0A ? 2 : 1
            }
        }
    }

    private static func scanLine(_ line: Range<Int>, _ bytes: UnsafeBufferPointer<UInt8>, _ inFence: inout Fence?,
                                 _ inComment: inout Bool, _ inline: inout InlineScanner, _ onOpening: (Int) -> Void) {
        var from = line.lowerBound
        if inComment {
            guard let close = indexOfCommentClose(bytes, from: from, to: line.upperBound) else { return }
            inComment = false
            from = close + 3
        } else if let fence = inFence {
            if closes(fence, bytes, line) { inFence = nil }
            return
        } else {
            if let opened = fenceOpening(bytes, line) { inFence = opened; return }
            if let start = linkReferenceComment(bytes, line) { onOpening(start); return }
        }
        inline.scan(from, line.upperBound, &inComment, onOpening)
    }

    // MARK: Fenced code

    private struct Fence {
        let marker: UInt8
        let length: Int
    }

    private static let backtick: UInt8 = 0x60
    private static let tilde: UInt8 = 0x7E

    /// Skips indentation, block-quote markers and list markers (`-`, `*`, `+`, `1.`, `1)`), so a fence in a
    /// quote or a list item is recognized. Returns the index of the first other byte.
    private static func contentStart(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> Int {
        var index = line.lowerBound
        let end = line.upperBound
        func isBlank(_ position: Int) -> Bool { position < end && (bytes[position] == 0x20 || bytes[position] == 0x09) }
        while index < end {
            let byte = bytes[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x3E {
                index += 1
            } else if byte == 0x2D || byte == 0x2A || byte == 0x2B, isBlank(index + 1) {
                index += 2
            } else if (0x30...0x39).contains(byte) {
                var digits = index
                while digits < end, (0x30...0x39).contains(bytes[digits]), digits - index < 9 { digits += 1 }
                guard digits < end, bytes[digits] == 0x2E || bytes[digits] == 0x29, isBlank(digits + 1) else { break }
                index = digits + 2
            } else {
                break
            }
        }
        return index
    }

    private static func fenceOpening(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> Fence? {
        let start = contentStart(bytes, line)
        guard start < line.upperBound, bytes[start] == backtick || bytes[start] == tilde else { return nil }
        let marker = bytes[start]
        var end = start
        while end < line.upperBound, bytes[end] == marker { end += 1 }
        guard end - start >= 3 else { return nil }
        // A backtick fence's info string holds no backtick; otherwise the run is inline code.
        if marker == backtick, bytes[end..<line.upperBound].contains(backtick) { return nil }
        return Fence(marker: marker, length: end - start)
    }

    private static func closes(_ fence: Fence, _ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> Bool {
        let start = contentStart(bytes, line)
        var end = start
        while end < line.upperBound, bytes[end] == fence.marker { end += 1 }
        guard end - start >= fence.length else { return false }
        return bytes[end..<line.upperBound].allSatisfy { $0 == 0x20 || $0 == 0x09 }
    }

    // MARK: Link-reference comments

    /// `[//]: # (text)`, `[//]: <> "text"`, `[comment]: <> (text)`: a definition whose destination is empty or
    /// `#` and whose title holds the text. Up to three spaces of indentation, as for any definition.
    private static func linkReferenceComment(_ bytes: UnsafeBufferPointer<UInt8>, _ line: Range<Int>) -> Int? {
        var index = line.lowerBound
        while index < line.upperBound, index - line.lowerBound < 3, bytes[index] == 0x20 { index += 1 }
        let start = index
        guard index < line.upperBound, bytes[index] == 0x5B else { return nil }
        index += 1
        let labelStart = index
        while index < line.upperBound, bytes[index] != 0x5D, index - labelStart <= 8 { index += 1 }
        guard index + 1 < line.upperBound, bytes[index] == 0x5D, bytes[index + 1] == 0x3A else { return nil }
        let label = bytes[labelStart..<index].map { $0 | 0x20 }
        guard label.elementsEqual("//".utf8) || label.elementsEqual("comment".utf8) else { return nil }
        index += 2
        let spaceStart = index
        while index < line.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        guard index > spaceStart, index < line.upperBound else { return nil }
        if bytes[index] == 0x23 { index += 1 }
        else if index + 1 < line.upperBound, bytes[index] == 0x3C, bytes[index + 1] == 0x3E { index += 2 }
        else { return nil }
        let titleSpace = index
        while index < line.upperBound, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        guard index > titleSpace, index < line.upperBound, [0x28, 0x22, 0x27].contains(bytes[index]) else { return nil }
        return start
    }

    // MARK: HTML comments

    /// Index of `-->` at or after `from` and before `end`, if any.
    fileprivate static func indexOfCommentClose(_ bytes: UnsafeBufferPointer<UInt8>, from: Int, to end: Int) -> Int? {
        var index = from
        while index + 2 < end {
            if bytes[index] == 0x2D, bytes[index + 1] == 0x2D, bytes[index + 2] == 0x3E { return index }
            index += 1
        }
        return nil
    }

    private static func contains(_ needle: StaticString, in bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = bytes.baseAddress, !bytes.isEmpty else { return false }
        return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
    }

    /// Scans the inline part of one line for comment openings, skipping code spans.
    private struct InlineScanner {
        private let bytes: UnsafeBufferPointer<UInt8>
        // Backtick runs of the current line and, for each, the next run of the same length. Reused across
        // lines so pairing stays linear however many runs a line holds.
        private var runs: [(start: Int, length: Int)] = []
        private var nextSame: [Int] = []
        private var lastSeen: [Int: Int] = [:]

        init(_ bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        mutating func scan(_ from: Int, _ end: Int, _ inComment: inout Bool, _ onOpening: (Int) -> Void) {
            indexRuns(from, end)
            var runIndex = 0
            var index = from
            while index < end {
                let byte = bytes[index]
                if byte == MarkdownCommentScanner.backtick {
                    // `index` is the start of runs[runIndex]: runs are consumed whole, in order.
                    while runIndex < runs.count, runs[runIndex].start < index { runIndex += 1 }
                    guard runIndex < runs.count, runs[runIndex].start == index else { index += 1; continue }
                    let following = nextSame[runIndex]
                    if following >= 0 {
                        index = runs[following].start + runs[following].length
                        runIndex = following + 1
                    } else {
                        index += runs[runIndex].length
                        runIndex += 1
                    }
                } else if byte == 0x3C, index + 3 < end, bytes[index + 1] == 0x21, bytes[index + 2] == 0x2D, bytes[index + 3] == 0x2D {
                    let escaped = index > from && bytes[index - 1] == 0x5C
                    if escaped { index += 4; continue }
                    onOpening(index)
                    var body = index + 4
                    if body < end, bytes[body] == 0x3E { index = body + 1 }                       // <!-->
                    else if body + 1 < end, bytes[body] == 0x2D, bytes[body + 1] == 0x3E { index = body + 2 } // <!--->
                    else if let close = MarkdownCommentScanner.indexOfCommentClose(bytes, from: body, to: end) { index = close + 3 }
                    else { inComment = true; return }
                    body = index
                    while runIndex < runs.count, runs[runIndex].start < body { runIndex += 1 }
                } else {
                    index += 1
                }
            }
        }

        private mutating func indexRuns(_ from: Int, _ end: Int) {
            runs.removeAll(keepingCapacity: true)
            guard memchr(bytes.baseAddress! + from, Int32(MarkdownCommentScanner.backtick), end - from) != nil else {
                nextSame.removeAll(keepingCapacity: true)
                return
            }
            var index = from
            while index < end {
                guard bytes[index] == MarkdownCommentScanner.backtick else { index += 1; continue }
                let start = index
                while index < end, bytes[index] == MarkdownCommentScanner.backtick { index += 1 }
                runs.append((start, index - start))
            }
            nextSame = [Int](repeating: -1, count: runs.count)
            lastSeen.removeAll(keepingCapacity: true)
            for position in runs.indices.reversed() {
                nextSame[position] = lastSeen[runs[position].length] ?? -1
                lastSeen[runs[position].length] = position
            }
        }
    }
}

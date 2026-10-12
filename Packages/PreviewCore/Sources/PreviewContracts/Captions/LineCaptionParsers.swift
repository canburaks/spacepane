import Foundation

/// YouTube SubViewer (`.sbv`): blocks separated by blank lines, each a timing line
/// `H:MM:SS.mmm,H:MM:SS.mmm` followed by text lines. Hours take one or more digits, minutes and seconds
/// two, the fraction exactly three; `end >= start`. A block whose first line is not a timing line, and a
/// file without a cue, are malformed. Markup in the text is never interpreted.
enum SubViewerParser {
    static func parse(_ bytes: [UInt8], limits: CaptionLimits, checkpoint: () throws -> Void) throws -> CaptionDocument {
        let lines = try CaptionLines.split(bytes, checkpoint: checkpoint)
        var cues: [CaptionCue] = []
        var index = 0
        while index < lines.count {
            if index.isMultiple(of: 256) { try checkpoint() }
            if CaptionLines.isBlank(bytes, lines[index]) { index += 1; continue }
            var end = index + 1
            while end < lines.count, !CaptionLines.isBlank(bytes, lines[end]) { end += 1 }
            guard let timing = timing(bytes, lines[index]) else { throw PreviewFailure.malformedDocument }
            guard cues.count < limits.maximumCues else { throw PreviewFailure.tooManyNodes }
            var total = 0
            var text: [String] = []
            for line in lines[(index + 1)..<end] {
                total += line.end - line.start
                guard total <= limits.maximumCueTextUTF8Bytes else { throw PreviewFailure.malformedDocument }
                text.append(CaptionLines.string(bytes, line.start, line.end))
            }
            cues.append(CaptionCue(start: timing.start, end: timing.end, lines: text))
            index = end
        }
        guard !cues.isEmpty else { throw PreviewFailure.malformedDocument }
        return CaptionDocument(cues: cues)
    }

    private static func timing(_ bytes: [UInt8], _ line: CaptionLines.Line) -> (start: String, end: String)? {
        var index = line.start
        let startBegin = index
        guard let start = timestamp(bytes, &index, line.end), index < line.end, bytes[index] == 44 else { return nil }
        let startEnd = index
        index += 1
        let endBegin = index
        guard let end = timestamp(bytes, &index, line.end), end >= start else { return nil }
        while index < line.end, bytes[index] == 32 || bytes[index] == 9 { index += 1 }
        guard index == line.end else { return nil }
        var endEnd = endBegin
        while endEnd < line.end, bytes[endEnd] != 32, bytes[endEnd] != 9 { endEnd += 1 }
        return (CaptionLines.string(bytes, startBegin, startEnd), CaptionLines.string(bytes, endBegin, endEnd))
    }

    private static func timestamp(_ bytes: [UInt8], _ index: inout Int, _ end: Int) -> Int? {
        guard let hours = CaptionLines.digits(bytes, &index, end), index < end, bytes[index] == 58 else { return nil }
        index += 1
        guard let minutes = CaptionLines.digits(bytes, &index, end), minutes.count == 2, minutes.value <= 59,
              index < end, bytes[index] == 58 else { return nil }
        index += 1
        guard let seconds = CaptionLines.digits(bytes, &index, end), seconds.count == 2, seconds.value <= 59,
              index < end, bytes[index] == 46 else { return nil }
        index += 1
        guard let fraction = CaptionLines.digits(bytes, &index, end), fraction.count == 3 else { return nil }
        return ((hours.value * 60 + minutes.value) * 60 + seconds.value) * 1000 + fraction.value
    }
}

/// Lyrics (`.lrc`). A line is either metadata, `[key:value]` with an alphabetic key such as `ti`, `ar`,
/// `al`, `au`, `by`, `offset` or `length`, or lyrics, one or more `[mm:ss.xx]` time tags followed by text.
/// Minutes take one or more digits, seconds two, the optional fraction one to three digits after `.`
/// (or `:`). Each time tag becomes one cue, so `[00:12.00][00:48.50]Chorus` is two cues. Enhanced
/// word timings (`<00:12.30>`) are removed from the cue text. Blank lines are allowed; any other line
/// shape, a line that mixes both tag kinds, and a file without a time tag are malformed.
enum LyricsParser {
    static func parse(_ bytes: [UInt8], limits: CaptionLimits, checkpoint: () throws -> Void) throws -> CaptionDocument {
        let lines = try CaptionLines.split(bytes, checkpoint: checkpoint)
        var cues: [CaptionCue] = []
        var metadata: [CaptionMetadata] = []
        for (number, line) in lines.enumerated() {
            if number.isMultiple(of: 256) { try checkpoint() }
            var index = line.start
            while index < line.end, bytes[index] == 32 || bytes[index] == 9 { index += 1 }
            if index == line.end { continue }
            var stamps: [String] = []
            var tagKey: String?
            var tagValue = ""
            while index < line.end, bytes[index] == 91 {
                guard let close = bytes[index..<line.end].firstIndex(of: 93) else { throw PreviewFailure.malformedDocument }
                let inner = (index + 1)..<close
                if isTimeTag(bytes, inner) {
                    guard tagKey == nil else { throw PreviewFailure.malformedDocument }
                    stamps.append(CaptionLines.string(bytes, inner.lowerBound, inner.upperBound))
                } else if let colon = bytes[inner].firstIndex(of: 58), isMetadataKey(bytes, inner.lowerBound..<colon) {
                    guard stamps.isEmpty, tagKey == nil else { throw PreviewFailure.malformedDocument }
                    tagKey = CaptionLines.string(bytes, inner.lowerBound, colon)
                    tagValue = CaptionLines.string(bytes, colon + 1, inner.upperBound)
                } else if !stamps.isEmpty {
                    break // A bracketed annotation such as `[Chorus]` after the time tags is lyric text.
                } else {
                    throw PreviewFailure.malformedDocument
                }
                index = close + 1
            }
            if let key = tagKey {
                // A metadata line is only its tag.
                guard index == line.end else { throw PreviewFailure.malformedDocument }
                metadata.append(CaptionMetadata(key: key, value: tagValue))
                continue
            }
            guard !stamps.isEmpty else { throw PreviewFailure.malformedDocument }
            let text = try lyricText(bytes, index, line.end, limit: limits.maximumCueTextUTF8Bytes)
            for stamp in stamps {
                guard cues.count < limits.maximumCues else { throw PreviewFailure.tooManyNodes }
                cues.append(CaptionCue(start: stamp, lines: [text]))
            }
        }
        guard !cues.isEmpty else { throw PreviewFailure.malformedDocument }
        return CaptionDocument(cues: cues, metadata: metadata)
    }

    private static func isTimeTag(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        var index = range.lowerBound
        guard let minutes = CaptionLines.digits(bytes, &index, range.upperBound), minutes.count >= 1,
              index < range.upperBound, bytes[index] == 58 else { return false }
        index += 1
        guard let seconds = CaptionLines.digits(bytes, &index, range.upperBound), seconds.count == 2, seconds.value <= 59 else { return false }
        if index == range.upperBound { return true }
        guard bytes[index] == 46 || bytes[index] == 58 else { return false }
        index += 1
        guard let fraction = CaptionLines.digits(bytes, &index, range.upperBound), fraction.count <= 3 else { return false }
        return index == range.upperBound
    }

    private static func isMetadataKey(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        guard !range.isEmpty, range.count <= 16, let first = bytes[range].first, (65...90).contains(first) || (97...122).contains(first) else { return false }
        return bytes[range].allSatisfy { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
    }

    /// The text after the time tags with enhanced `<mm:ss.xx>` word stamps removed.
    private static func lyricText(_ bytes: [UInt8], _ start: Int, _ end: Int, limit: Int) throws -> String {
        guard end - start <= limit else { throw PreviewFailure.malformedDocument }
        var output: [UInt8] = []
        var index = start
        while index < end {
            if bytes[index] == 60, let close = bytes[index..<end].firstIndex(of: 62),
               isTimeTag(bytes, (index + 1)..<close) {
                index = close + 1
                continue
            }
            output.append(bytes[index])
            index += 1
        }
        return String(decoding: output, as: UTF8.self)
    }
}

/// MicroDVD text (`.sub`): `{start}{end}text` per line, with frame numbers. `|` separates lines and
/// `{...}` style codes (`{y:i}`, `{c:$0000FF}`) are removed from the cue text. A first line `{1}{1}fps`
/// whose text is a decimal number from 1 to 120 states the frame rate and is not a cue; otherwise the
/// rate is 25. Frames convert to `H:MM:SS.mmm` at that rate. Blank lines are allowed; any other line
/// shape, `end < start` and a file without a cue are malformed.
enum MicroDVDParser {
    static let defaultFramesPerSecond = 25.0

    static func parse(_ bytes: [UInt8], limits: CaptionLimits, checkpoint: () throws -> Void) throws -> CaptionDocument {
        let lines = try CaptionLines.split(bytes, checkpoint: checkpoint)
        var parsed: [(start: Int, end: Int, text: [UInt8])] = []
        for (number, line) in lines.enumerated() {
            if number.isMultiple(of: 256) { try checkpoint() }
            if CaptionLines.isBlank(bytes, line) { continue }
            var index = line.start
            guard let start = frame(bytes, &index, line.end), let end = frame(bytes, &index, line.end), end >= start else {
                throw PreviewFailure.malformedDocument
            }
            guard parsed.count < limits.maximumCues + 1 else { throw PreviewFailure.tooManyNodes }
            parsed.append((start, end, Array(bytes[index..<line.end])))
        }
        var framesPerSecond = defaultFramesPerSecond
        if let first = parsed.first, first.start == 1, first.end == 1,
           let rate = Double(String(decoding: first.text, as: UTF8.self).trimmingCharacters(in: .whitespaces)),
           (1.0...120.0).contains(rate) {
            framesPerSecond = rate
            parsed.removeFirst()
        }
        guard !parsed.isEmpty else { throw PreviewFailure.malformedDocument }
        var cues: [CaptionCue] = []
        for item in parsed {
            guard item.text.count <= limits.maximumCueTextUTF8Bytes else { throw PreviewFailure.malformedDocument }
            cues.append(CaptionCue(start: CaptionLines.clock(milliseconds(item.start, framesPerSecond)),
                                   end: CaptionLines.clock(milliseconds(item.end, framesPerSecond)),
                                   lines: cleaned(item.text)))
        }
        return CaptionDocument(cues: cues)
    }

    private static func milliseconds(_ frames: Int, _ framesPerSecond: Double) -> Int {
        Int((Double(frames) * 1000 / framesPerSecond).rounded())
    }

    /// `{digits}` at `index`, advancing past the closing brace.
    private static func frame(_ bytes: [UInt8], _ index: inout Int, _ end: Int) -> Int? {
        guard index < end, bytes[index] == 123 else { return nil }
        var position = index + 1
        guard let value = CaptionLines.digits(bytes, &position, end), position < end, bytes[position] == 125 else { return nil }
        index = position + 1
        return value.value
    }

    /// `|` starts a new line; `{...}` style codes are dropped (an unterminated `{` is text).
    private static func cleaned(_ text: [UInt8]) -> [String] {
        var lines: [[UInt8]] = [[]]
        var index = 0
        while index < text.count {
            let byte = text[index]
            if byte == 123, let close = text[index...].firstIndex(of: 125) {
                index = close + 1
                continue
            }
            if byte == 124 { lines.append([]) } else { lines[lines.count - 1].append(byte) }
            index += 1
        }
        return lines.map { String(decoding: $0, as: UTF8.self) }
    }
}

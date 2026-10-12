import Foundation

/// SubStation Alpha (`.ssa`) and Advanced SubStation Alpha (`.ass`).
///
/// Grammar accepted: the file starts with a `[Script Info]` section (comment lines may precede it);
/// sections are `[Name]` lines; every line in an ordinary section is `Key: value`, a `;` or `!:`
/// comment, or blank; `[Fonts]` and `[Graphics]` hold uuencoded data lines that are skipped. In
/// `[Events]`, `Format:` names the columns (it must include `Start`, `End` and `Text`, with `Text`
/// last) and each `Dialogue:` has exactly that many comma-separated fields, the last one taking
/// the remaining text, commas included. Without a `Format:` line the SSA v4+ column list is used.
/// Timestamps are `H:MM:SS.cc` (one to three fraction digits) and `end >= start`.
///
/// Cue text drops `{...}` override blocks and turns `\N` into a line break and `\n` and `\h` into a
/// space. Nothing is rendered, positioned, animated or fetched: styles, fonts and drawing commands
/// are inert characters that only the source view shows.
enum SubStationAlphaParser {
    private static let defaultColumns = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]

    private enum Section { case scriptInfo, events, data, other }

    static func parse(_ bytes: [UInt8], limits: CaptionLimits, checkpoint: () throws -> Void) throws -> CaptionDocument {
        let lines = try CaptionLines.split(bytes, checkpoint: checkpoint)
        var section: Section?
        var columns: [String]?
        var cues: [CaptionCue] = []
        var comments: [Range<Int>] = []
        for (number, line) in lines.enumerated() {
            if number.isMultiple(of: 256) { try checkpoint() }
            var content = line.start
            while content < line.end, bytes[content] == 32 || bytes[content] == 9 { content += 1 }
            guard content < line.end else { continue }
            let first = bytes[content]
            if first == 59 || (first == 33 && content + 1 < line.end && bytes[content + 1] == 58) {
                comments.append((content + (first == 59 ? 1 : 2))..<line.end)
                continue
            }
            if first == 91 {
                var end = line.end
                while end > content, bytes[end - 1] == 32 || bytes[end - 1] == 9 { end -= 1 }
                guard end - content >= 2, bytes[end - 1] == 93 else {
                    if section == .data { continue }
                    throw PreviewFailure.malformedDocument
                }
                let name = CaptionLines.string(bytes, content + 1, end - 1).trimmingCharacters(in: .whitespaces).lowercased()
                if section == nil, name != "script info" { throw PreviewFailure.malformedDocument }
                switch name {
                case "script info": section = .scriptInfo
                case "events": section = .events
                case "fonts", "graphics": section = .data
                default: section = .other
                }
                continue
            }
            guard let current = section else { throw PreviewFailure.malformedDocument }
            if current == .data { continue }
            guard let colon = bytes[content..<line.end].firstIndex(of: 58) else { throw PreviewFailure.malformedDocument }
            guard current == .events else { continue }
            let key = CaptionLines.string(bytes, content, colon).trimmingCharacters(in: .whitespaces).lowercased()
            let valueStart = colon + 1
            switch key {
            case "format":
                columns = try parseColumns(bytes, valueStart, line.end)
            case "dialogue", "comment":
                let names = columns ?? defaultColumns
                let fields = try splitFields(bytes, valueStart, line.end, count: names.count)
                guard let start = clockValue(fields.texts, names, "start"), let end = clockValue(fields.texts, names, "end"),
                      end >= start else { throw PreviewFailure.malformedDocument }
                if key == "comment" {
                    comments.append(fields.lastRange)
                } else {
                    guard cues.count < limits.maximumCues else { throw PreviewFailure.tooManyNodes }
                    let style = field(fields.texts, names, "style")
                    let actor = field(fields.texts, names, "name")
                    let label = [style, actor].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / ")
                    let text = try cleaned(Array(bytes[fields.lastRange]), limit: limits.maximumCueTextUTF8Bytes)
                    cues.append(CaptionCue(label: label.isEmpty ? nil : label,
                                           start: field(fields.texts, names, "start") ?? "",
                                           end: field(fields.texts, names, "end"), lines: text))
                }
            case "picture", "sound", "movie", "command":
                break
            default:
                throw PreviewFailure.malformedDocument
            }
        }
        guard section != nil else { throw PreviewFailure.malformedDocument }
        return CaptionDocument(cues: cues, commentRanges: comments)
    }

    // MARK: Fields

    private static func parseColumns(_ bytes: [UInt8], _ start: Int, _ end: Int) throws -> [String] {
        let names = CaptionLines.string(bytes, start, end).split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard Set(names).count == names.count, names.last == "text", names.contains("start"), names.contains("end"),
              names.count <= 32 else { throw PreviewFailure.malformedDocument }
        return names
    }

    /// Splits at the first `count - 1` commas; the last field keeps its commas. A single space after
    /// the colon is a separator, the rest of each field is kept (non-text fields are trimmed on read).
    private static func splitFields(_ bytes: [UInt8], _ start: Int, _ end: Int, count: Int) throws -> (texts: [String], lastRange: Range<Int>) {
        var begin = start
        if begin < end, bytes[begin] == 32 { begin += 1 }
        var texts: [String] = []
        var index = begin
        var fieldStart = begin
        while index < end, texts.count < count - 1 {
            if bytes[index] == 44 {
                texts.append(CaptionLines.string(bytes, fieldStart, index).trimmingCharacters(in: .whitespaces))
                fieldStart = index + 1
            }
            index += 1
        }
        guard texts.count == count - 1 else { throw PreviewFailure.malformedDocument }
        texts.append(CaptionLines.string(bytes, fieldStart, end))
        return (texts, fieldStart..<end)
    }

    private static func field(_ texts: [String], _ names: [String], _ name: String) -> String? {
        names.firstIndex(of: name).map { texts[$0] }
    }

    private static func clockValue(_ texts: [String], _ names: [String], _ name: String) -> Int? {
        field(texts, names, name).flatMap(clock)
    }

    /// `H:MM:SS.cc` in milliseconds; the fraction has one to three digits.
    private static func clock(_ text: String) -> Int? {
        let bytes = Array(text.utf8)
        var index = 0
        guard let hours = CaptionLines.digits(bytes, &index, bytes.count), index < bytes.count, bytes[index] == 58 else { return nil }
        index += 1
        guard let minutes = CaptionLines.digits(bytes, &index, bytes.count), minutes.count == 2, minutes.value <= 59,
              index < bytes.count, bytes[index] == 58 else { return nil }
        index += 1
        guard let seconds = CaptionLines.digits(bytes, &index, bytes.count), seconds.count == 2, seconds.value <= 59,
              index < bytes.count, bytes[index] == 46 else { return nil }
        index += 1
        guard let fraction = CaptionLines.digits(bytes, &index, bytes.count), index == bytes.count,
              let millis = CaptionLines.milliseconds(fraction: fraction.value, digits: fraction.count) else { return nil }
        return ((hours.value * 60 + minutes.value) * 60 + seconds.value) * 1000 + millis
    }

    // MARK: Cue text

    /// Removes `{...}` override blocks and interprets `\N`, `\n` and `\h`. An unterminated `{` is text.
    private static func cleaned(_ text: [UInt8], limit: Int) throws -> [String] {
        guard text.count <= limit else { throw PreviewFailure.malformedDocument }
        var lines: [[UInt8]] = [[]]
        var index = 0
        while index < text.count {
            let byte = text[index]
            if byte == 123, let close = text[index...].firstIndex(of: 125) {
                index = close + 1
                continue
            }
            if byte == 92, index + 1 < text.count {
                switch text[index + 1] {
                case 78: lines.append([]); index += 2; continue
                case 110, 104: lines[lines.count - 1].append(32); index += 2; continue
                default: break
                }
            }
            lines[lines.count - 1].append(byte)
            index += 1
        }
        return lines.map { String(decoding: $0, as: UTF8.self) }
    }
}

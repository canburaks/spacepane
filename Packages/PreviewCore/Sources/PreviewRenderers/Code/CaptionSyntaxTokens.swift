import Foundation
import PreviewContracts

/// Decoration for the caption dialects the code family adds (TTML uses the markup tokenizer). Each is
/// line oriented, reads only concealed text and colors the parts a reader scans for: times, section and
/// tag names, comments and inline codes.
enum CaptionSyntaxTokens {
    static func tokens(_ units: [UInt16], syntax: TextSyntax, maximumTokens: Int) -> [JSONSyntaxToken] {
        var tokens = LineSyntaxTokens.TokenList(maximum: maximumTokens)
        var lineStart = 0
        var section = Section.other
        while lineStart < units.count, !tokens.isFull {
            var lineEnd = lineStart
            while lineEnd < units.count, units[lineEnd] != 10, units[lineEnd] != 13 { lineEnd += 1 }
            switch syntax {
            case .subStationAlpha: subStationLine(units, lineStart, lineEnd, &tokens, &section)
            case .subViewer: subViewerLine(units, lineStart, lineEnd, &tokens)
            case .lyrics: lyricsLine(units, lineStart, lineEnd, &tokens)
            case .microDVD: microDVDLine(units, lineStart, lineEnd, &tokens)
            default: break
            }
            lineStart = lineEnd < units.count ? lineEnd + (units[lineEnd] == 13 && lineEnd + 1 < units.count && units[lineEnd + 1] == 10 ? 2 : 1) : lineEnd
        }
        return tokens.values
    }

    // MARK: SubStation Alpha

    private enum Section { case events, data, other }

    private static func subStationLine(_ units: [UInt16], _ start: Int, _ end: Int, _ tokens: inout LineSyntaxTokens.TokenList, _ section: inout Section) {
        var first = start
        while first < end, units[first] == 32 || units[first] == 9 { first += 1 }
        guard first < end else { return }
        if units[first] == 59 || (units[first] == 33 && first + 1 < end && units[first + 1] == 58) {
            tokens.append(first, end, .comment); return
        }
        if units[first] == 91 {
            var close = first + 1
            while close < end, units[close] != 93 { close += 1 }
            if close < end {
                let name = String(decoding: units[(first + 1)..<close], as: UTF16.self).lowercased()
                section = name == "events" ? .events : (name == "fonts" || name == "graphics") ? .data : .other
                tokens.append(first, close + 1, .heading)
            }
            return
        }
        guard section != .data else { return }
        var colon = first
        while colon < end, units[colon] != 58 { colon += 1 }
        guard colon < end else { return }
        tokens.append(first, colon, .key)
        guard section == .events else { return }
        let key = String(decoding: units[first..<colon], as: UTF16.self).lowercased()
        guard key == "dialogue" || key == "comment" else { return }
        var index = colon + 1
        while index < end, !tokens.isFull {
            if units[index] == 123, let close = units[index..<end].firstIndex(of: 125) {
                tokens.append(index, close + 1, .tag)
                index = close + 1
            } else if isDigit(units[index]), index == colon + 1 || !isIdentifier(units[index - 1]), let stamp = clockEnd(units, index, end) {
                tokens.append(index, stamp, .number)
                index = stamp
            } else {
                index += 1
            }
        }
    }

    // MARK: SubViewer and lyrics

    private static func subViewerLine(_ units: [UInt16], _ start: Int, _ end: Int, _ tokens: inout LineSyntaxTokens.TokenList) {
        guard start < end, isDigit(units[start]), let first = clockEnd(units, start, end), first < end, units[first] == 44,
              let second = clockEnd(units, first + 1, end) else { return }
        tokens.append(start, first, .number)
        tokens.append(first + 1, second, .number)
    }

    private static func lyricsLine(_ units: [UInt16], _ start: Int, _ end: Int, _ tokens: inout LineSyntaxTokens.TokenList) {
        var index = start
        while index < end, units[index] == 32 || units[index] == 9 { index += 1 }
        while index < end, units[index] == 91, let close = units[index..<end].firstIndex(of: 93) {
            if index + 1 < close, isDigit(units[index + 1]) {
                tokens.append(index + 1, close, .number)
            } else if let colon = units[index..<close].firstIndex(of: 58) {
                tokens.append(index + 1, colon, .key)
            } else { break }
            index = close + 1
        }
        // Enhanced lyrics put `<mm:ss.xx>` word times inline; dim them.
        while index < end, !tokens.isFull {
            if units[index] == 60, let close = units[index..<end].firstIndex(of: 62), close > index + 1, isDigit(units[index + 1]) {
                tokens.append(index, close + 1, .comment)
                index = close + 1
            } else { index += 1 }
        }
    }

    // MARK: MicroDVD

    private static func microDVDLine(_ units: [UInt16], _ start: Int, _ end: Int, _ tokens: inout LineSyntaxTokens.TokenList) {
        var index = start
        for _ in 0..<2 {
            guard index < end, units[index] == 123, let close = units[index..<end].firstIndex(of: 125) else { return }
            tokens.append(index + 1, close, .number)
            index = close + 1
        }
        while index < end, !tokens.isFull {
            if units[index] == 123, let close = units[index..<end].firstIndex(of: 125) {
                tokens.append(index, close + 1, .tag)
                index = close + 1
            } else if units[index] == 124 {
                tokens.append(index, index + 1, .operator)
                index += 1
            } else { index += 1 }
        }
    }

    // MARK: Helpers

    /// `H:MM:SS.fff` starting at `start`, returning where it ends.
    private static func clockEnd(_ units: [UInt16], _ start: Int, _ end: Int) -> Int? {
        var index = start
        var groups = 0
        while index < end, isDigit(units[index]) { index += 1 }
        guard index > start, index < end, units[index] == 58 else { return nil }
        while groups < 2, index < end, units[index] == 58 {
            let digitsStart = index + 1
            var position = digitsStart
            while position < end, isDigit(units[position]) { position += 1 }
            guard position > digitsStart else { return nil }
            index = position
            groups += 1
        }
        guard groups == 2 else { return nil }
        if index + 1 < end, units[index] == 46 {
            var position = index + 1
            while position < end, isDigit(units[position]) { position += 1 }
            if position > index + 1 { index = position }
        }
        return index
    }

    private static func isDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
    private static func isIdentifier(_ unit: UInt16) -> Bool { isDigit(unit) || (65...90).contains(unit) || (97...122).contains(unit) }
}

import Foundation
import PreviewContracts

/// Line-oriented decoration for INI-family files and logs. Both walk the text once, line by line,
/// over UTF-16 code units, and emit exact, non-overlapping ranges in reading order. They only read the
/// concealed text and never classify by content they cannot see: a concealed value is just `••••`.
enum LineSyntaxTokens {
    // MARK: INI

    /// Sections are headings, setting names are keys, comments are comments, and a value that is a quoted
    /// string, a number or a boolean word is colored like it is in the other configuration formats.
    static func ini(_ units: [UInt16], maximumTokens: Int) -> [JSONSyntaxToken] {
        var tokens = TokenList(maximum: maximumTokens)
        var lineStart = 0
        while lineStart < units.count, !tokens.isFull {
            var lineEnd = lineStart
            while lineEnd < units.count, units[lineEnd] != 10, units[lineEnd] != 13 { lineEnd += 1 }
            iniLine(units, lineStart, lineEnd, &tokens)
            lineStart = lineEnd < units.count ? lineEnd + (units[lineEnd] == 13 && lineEnd + 1 < units.count && units[lineEnd + 1] == 10 ? 2 : 1) : lineEnd
        }
        return tokens.values
    }

    private static func iniLine(_ units: [UInt16], _ start: Int, _ end: Int, _ tokens: inout TokenList) {
        var first = start
        while first < end, units[first] == 32 || units[first] == 9 { first += 1 }
        guard first < end else { return }
        let lead = units[first]
        if lead == 59 || lead == 35 || lead == 33 { tokens.append(first, end, .comment); return }
        if lead == 91 {
            var close = first + 1
            while close < end, units[close] != 93 { close += 1 }
            if close < end { tokens.append(first, close + 1, .heading) }
            return
        }
        // The first `=` or `:` separates name and value; a name with no separator ends at its first blank.
        var separator = first
        while separator < end, units[separator] != 61, units[separator] != 58 { separator += 1 }
        var nameEnd = separator
        if separator == end {
            nameEnd = first
            while nameEnd < end, units[nameEnd] != 32, units[nameEnd] != 9 { nameEnd += 1 }
        }
        var trimmedEnd = nameEnd
        while trimmedEnd > first, units[trimmedEnd - 1] == 32 || units[trimmedEnd - 1] == 9 { trimmedEnd -= 1 }
        tokens.append(first, trimmedEnd, .key)
        var valueStart = separator == end ? nameEnd : separator + 1
        while valueStart < end, units[valueStart] == 32 || units[valueStart] == 9 { valueStart += 1 }
        var valueEnd = end
        while valueEnd > valueStart, units[valueEnd - 1] == 32 || units[valueEnd - 1] == 9 { valueEnd -= 1 }
        guard valueStart < valueEnd else { return }
        tokens.append(valueStart, valueEnd, iniValueRole(units[valueStart..<valueEnd]))
    }

    private static let literalWords: Set<String> = ["true", "false", "yes", "no", "on", "off", "null", "none"]

    private static func iniValueRole(_ value: ArraySlice<UInt16>) -> PreviewSyntaxRole? {
        guard let first = value.first else { return nil }
        if first == 34 || first == 39 { return .string }
        if value.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 46 || $0 == 45 || $0 == 43 || $0 == 95 }),
           value.contains(where: { $0 >= 48 && $0 <= 57 }) { return .number }
        return literalWords.contains(String(decoding: value, as: UTF16.self).lowercased()) ? .literal : nil
    }

    // MARK: Log

    /// Timestamps are numbers, severity words take the severity's role, stack frames and `... N more`
    /// lines are dimmed as comments, and exception headlines are errors.
    static func log(_ units: [UInt16], maximumTokens: Int) -> [JSONSyntaxToken] {
        var tokens = TokenList(maximum: maximumTokens)
        var context = LogContext()
        var lineStart = 0
        while lineStart < units.count, !tokens.isFull {
            var lineEnd = lineStart
            while lineEnd < units.count, units[lineEnd] != 10, units[lineEnd] != 13 { lineEnd += 1 }
            logLine(units, lineStart, lineEnd, &tokens, &context)
            lineStart = lineEnd < units.count ? lineEnd + (units[lineEnd] == 13 && lineEnd + 1 < units.count && units[lineEnd + 1] == 10 ? 2 : 1) : lineEnd
        }
        return tokens.values
    }

    /// Multi-line stack formats whose frame lines carry no marker of their own.
    private struct LogContext {
        /// After `File "x", line N` a Python source excerpt line follows.
        var expectsPythonSource = false
        /// After `goroutine N [state]:` every non-blank line is a frame until a blank line.
        var inGoStack = false
    }

    private static func logLine(_ units: [UInt16], _ start: Int, _ end: Int, _ tokens: inout TokenList, _ context: inout LogContext) {
        var first = start
        while first < end, units[first] == 32 || units[first] == 9 { first += 1 }
        let indented = first > start
        guard first < end else { context.inGoStack = false; context.expectsPythonSource = false; return }
        let body = units[first..<end]
        let expectsSource = context.expectsPythonSource
        context.expectsPythonSource = false

        if hasPrefix(body, "goroutine "), body.last == 58 || body.contains(91) { context.inGoStack = true; tokens.append(first, end, .deletion); return }
        if isHeadline(body) { tokens.append(first, end, .deletion); return }
        if hasPrefix(body, "File \""), indented { context.expectsPythonSource = true; tokens.append(first, end, .comment); return }
        if expectsSource, indented { tokens.append(first, end, .comment); return }
        if context.inGoStack || isFrame(body, indented: indented) { tokens.append(first, end, .comment); return }

        var position = first
        if let stampEnd = timestampEnd(units, from: first, limit: end) {
            // A bracketed stamp (`[05/Oct/2026:14:03:22 +0000]`) is colored inside its brackets.
            tokens.append(first, stampEnd, .number)
            position = stampEnd
        } else if units[first] == 91, let stampEnd = timestampEnd(units, from: first + 1, limit: end) {
            tokens.append(first + 1, stampEnd, .number)
            position = stampEnd
        }
        if position == first {
            // Access logs lead with an address and carry the stamp in brackets: `... [05/Oct/2026:14:03:22 +0000] ...`.
            var index = first
            let window = min(end, first + 96)
            while index < window {
                if units[index] == 91, let stampEnd = timestampEnd(units, from: index + 1, limit: end), stampEnd < end, units[stampEnd] == 93 {
                    tokens.append(index + 1, stampEnd, .number)
                    position = stampEnd
                    break
                }
                index += 1
            }
        }
        if let (levelStart, levelEnd, role) = level(units, from: position, limit: end) { tokens.append(levelStart, levelEnd, role) }
    }

    // MARK: Log shapes

    private static func hasPrefix(_ body: ArraySlice<UInt16>, _ prefix: String) -> Bool {
        let units = Array(prefix.utf16)
        guard body.count >= units.count else { return false }
        return body.prefix(units.count).elementsEqual(units)
    }

    private static let headlinePrefixes = [
        "Traceback (most recent call last)", "Exception in thread", "Caused by:", "panic:", "Fatal error:", "stack backtrace:",
        "Terminating app due to uncaught exception", "Unhandled exception", "Thread 0 Crashed", "Exception Type:"
    ]

    private static func isHeadline(_ body: ArraySlice<UInt16>) -> Bool {
        headlinePrefixes.contains { hasPrefix(body, $0) }
    }

    /// Java/Kotlin/JS `at x(y)`, `... 12 more`, numbered Swift/Objective-C crash frames, Rust backtrace
    /// numbers, and Go `path/file.go:12 +0x1d` lines.
    private static func isFrame(_ body: ArraySlice<UInt16>, indented: Bool) -> Bool {
        if hasPrefix(body, "at "), body.count > 3 { return body.contains(40) || body.contains(58) }
        if hasPrefix(body, "... ") {
            // Java elides repeated frames as `... 12 more` or `... 12 common frames omitted`.
            return String(decoding: body.prefix(48), as: UTF16.self).range(of: #"^\.\.\. \d+ (more|common frames omitted)"#, options: .regularExpression) != nil
        }
        if let first = body.first, first >= 48, first <= 57 {
            // `0   libswiftCore.dylib   0x0000000180a1b2c4 symbol + 12` or Rust `  3: std::rt::lang_start`.
            let text = String(decoding: body.prefix(96), as: UTF16.self)
            if text.range(of: #"^\d+\s+\S+\s+0x[0-9A-Fa-f]+"#, options: .regularExpression) != nil { return true }
            if indented, text.range(of: #"^\d+:\s"#, options: .regularExpression) != nil { return true }
        }
        if indented {
            let text = String(decoding: body.prefix(160), as: UTF16.self)
            if text.range(of: #"^\S+\.(go|rs|py|swift|java|kt|js|ts|rb|c|cc|cpp|m|mm|cs|php):\d+( \+0x[0-9a-f]+)?$"#, options: .regularExpression) != nil { return true }
        }
        return false
    }

    // MARK: Timestamps

    private static func digits(_ units: [UInt16], _ index: Int, _ count: Int, limit: Int) -> Bool {
        guard index + count <= limit else { return false }
        for offset in 0..<count where units[index + offset] < 48 || units[index + offset] > 57 { return false }
        return true
    }

    private static let months: Set<String> = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// The end of an ISO 8601 / RFC 3339, time-only, syslog or Apache timestamp at `start`, if one starts there.
    static func timestampEnd(_ units: [UInt16], from start: Int, limit: Int) -> Int? {
        var index = start
        guard index < limit else { return nil }
        // `dddd-dd-dd` or `dddd/dd/dd`, then `T` or a space and a time.
        if digits(units, index, 4, limit: limit), index + 10 <= limit, units[index + 4] == 45 || units[index + 4] == 47,
           digits(units, index + 5, 2, limit: limit), units[index + 7] == units[index + 4], digits(units, index + 8, 2, limit: limit) {
            index += 10
            if index + 1 < limit, units[index] == 84 || units[index] == 32, let timeEnd = timeEnd(units, from: index + 1, limit: limit) {
                index = timeEnd
                index = zoneEnd(units, from: index, limit: limit)
            }
            return index
        }
        // Apache/nginx `05/Oct/2026:14:03:22 +0000`.
        if digits(units, index, 2, limit: limit), index + 11 <= limit, units[index + 2] == 47, units[index + 6] == 47,
           months.contains(String(decoding: units[(index + 3)..<(index + 6)], as: UTF16.self).lowercased()),
           digits(units, index + 7, 4, limit: limit), index + 12 <= limit, units[index + 11] == 58,
           let timeEnd = timeEnd(units, from: index + 12, limit: limit) {
            return zoneEnd(units, from: timeEnd, limit: limit)
        }
        // Syslog `Oct  5 14:03:22`.
        if index + 3 < limit, months.contains(String(decoding: units[index..<(index + 3)], as: UTF16.self).lowercased()),
           units[index + 3] == 32 {
            var position = index + 4
            while position < limit, units[position] == 32 { position += 1 }
            var dayDigits = 0
            while position < limit, units[position] >= 48, units[position] <= 57, dayDigits < 2 { position += 1; dayDigits += 1 }
            if dayDigits > 0, position < limit, units[position] == 32, let timeEnd = timeEnd(units, from: position + 1, limit: limit) {
                return timeEnd
            }
            return nil
        }
        // A bare time `14:03:22.123`.
        return timeEnd(units, from: index, limit: limit)
    }

    /// `dd:dd:dd` with an optional `.fff` or `,fff` fraction.
    private static func timeEnd(_ units: [UInt16], from start: Int, limit: Int) -> Int? {
        guard digits(units, start, 2, limit: limit), start + 8 <= limit, units[start + 2] == 58,
              digits(units, start + 3, 2, limit: limit), units[start + 5] == 58, digits(units, start + 6, 2, limit: limit) else { return nil }
        var index = start + 8
        if index < limit, units[index] == 46 || units[index] == 44 {
            var position = index + 1
            while position < limit, units[position] >= 48, units[position] <= 57 { position += 1 }
            if position > index + 1 { index = position }
        }
        return index
    }

    /// `Z`, `+hh:mm`, `+hhmm` or ` +hhmm` after a time.
    private static func zoneEnd(_ units: [UInt16], from start: Int, limit: Int) -> Int {
        var index = start
        if index < limit, units[index] == 90 { return index + 1 }
        if index < limit, units[index] == 32, index + 1 < limit, units[index + 1] == 43 || units[index + 1] == 45 { index += 1 }
        guard index < limit, units[index] == 43 || units[index] == 45, digits(units, index + 1, 2, limit: limit) else { return start }
        index += 3
        if index < limit, units[index] == 58 { index += 1 }
        if digits(units, index, 2, limit: limit) { index += 2 }
        return index
    }

    // MARK: Severity

    private static let levels: [String: PreviewSyntaxRole] = [
        "trace": .comment, "debug": .comment, "verbose": .comment, "info": .addition, "notice": .addition,
        "warn": .number, "warning": .number, "error": .deletion, "err": .deletion, "fatal": .deletion,
        "critical": .deletion, "crit": .deletion, "severe": .deletion, "emerg": .deletion, "emergency": .deletion,
        "alert": .deletion, "panic": .deletion
    ]

    /// The first severity word in the first 160 units after the timestamp: an upper-case word anywhere, or a
    /// word of any case in brackets, after `=`, or before `:`.
    private static func level(_ units: [UInt16], from start: Int, limit: Int) -> (Int, Int, PreviewSyntaxRole)? {
        var index = start
        let window = min(limit, start + 160)
        while index < window {
            guard isLetter(units[index]) else { index += 1; continue }
            let wordStart = index
            while index < limit, isLetter(units[index]) { index += 1 }
            guard index - wordStart >= 3, index - wordStart <= 9 else { continue }
            let word = String(decoding: units[wordStart..<index], as: UTF16.self)
            guard let role = levels[word.lowercased()] else { continue }
            let isUpper = word == word.uppercased()
            let before = wordStart > start ? units[wordStart - 1] : 32
            let after: UInt16 = index < limit ? units[index] : 32
            let delimited = before == 91 || before == 60 || before == 61 || before == 124 || before == 40 || after == 93 || after == 62 || after == 58
            if isUpper || delimited { return (wordStart, index, role) }
        }
        return nil
    }

    private static func isLetter(_ unit: UInt16) -> Bool { (65...90).contains(unit) || (97...122).contains(unit) }

    // MARK: Shared

    /// Tokens in reading order, bounded; a token that is empty or arrives after the cap is dropped.
    struct TokenList {
        let maximum: Int
        private(set) var values: [JSONSyntaxToken] = []
        init(maximum: Int) { self.maximum = maximum }
        var isFull: Bool { values.count >= maximum }
        mutating func append(_ start: Int, _ end: Int, _ role: PreviewSyntaxRole?) {
            guard let role, end > start, !isFull else { return }
            values.append(JSONSyntaxToken(range: NSRange(location: start, length: end - start), role: role))
        }
    }
}

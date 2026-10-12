import Foundation

/// Decides which delimited-text columns can sort by value instead of by spelling.
///
/// A column is numeric or a date only when *every* non-blank cell in it parses strictly; a single
/// other cell, including the concealment token, keeps the whole column textual. The result only feeds
/// sorting: cells are displayed and copied exactly as written, and a cell is never reinterpreted
/// (no locale decimal separators, no thousands separators, no formulas, no time-zone guessing).
enum SafeTableColumnTypes {
    static func infer(rows: [[String]], columnCount: Int) -> (kinds: [SafeTable.ColumnKind], keys: [Int: [Double?]]) {
        var kinds = [SafeTable.ColumnKind](repeating: .text, count: columnCount)
        var keys: [Int: [Double?]] = [:]
        for column in 0..<columnCount {
            if let values = typedKeys(rows, column: column, parse: { number($0) }) {
                kinds[column] = .number
                keys[column] = values
            } else if let values = typedKeys(rows, column: column, parse: { date($0) }) {
                kinds[column] = .date
                keys[column] = values
            }
        }
        return (kinds, keys)
    }

    /// One key per row, or nil unless the column has at least one non-blank cell and all of them parse.
    private static func typedKeys(_ rows: [[String]], column: Int, parse: (Substring) -> Double?) -> [Double?]? {
        var values: [Double?] = []
        values.reserveCapacity(rows.count)
        var sawValue = false
        for row in rows {
            var trimmed: Substring = column < row.count ? row[column][...] : ""
            while let first = trimmed.first, isBlank(first) { trimmed = trimmed.dropFirst() }
            while let last = trimmed.last, isBlank(last) { trimmed = trimmed.dropLast() }
            guard !trimmed.isEmpty else { values.append(nil); continue }
            guard let key = parse(trimmed) else { return nil }
            values.append(key)
            sawValue = true
        }
        return sawValue ? values : nil
    }

    private static func isBlank(_ character: Character) -> Bool { character == " " || character == "\t" }

    // MARK: Numbers

    /// `[+-]digits[.digits][(e|E)[+-]digits]` in ASCII. Anything else (separators, spelled values such
    /// as "NaN" or "inf", hexadecimal, a bare fraction) is not a number here.
    static func number(_ text: Substring) -> Double? {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.count <= 40 else { return nil }
        var index = 0
        if bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
        let integerStart = index
        while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        guard index > integerStart else { return nil }
        if index < bytes.count, bytes[index] == 0x2E {
            index += 1
            let fractionStart = index
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            guard index > fractionStart else { return nil }
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            let exponentStart = index
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            guard index > exponentStart else { return nil }
        }
        guard index == bytes.count, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    // MARK: Dates

    /// ISO 8601 calendar dates and date-times: `YYYY-MM-DD`, optionally followed by `T` or a space,
    /// `HH:MM[:SS[.fraction]]` and a `Z`, `±HH`, `±HHMM` or `±HH:MM` offset. A date-time without an
    /// offset is read as UTC so that sorting never depends on the viewer's time zone. Returns seconds
    /// since 1970-01-01T00:00:00Z.
    static func date(_ text: Substring) -> Double? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 10, bytes.count <= 40 else { return nil }
        guard let year = digits(bytes, 0, 4), bytes[4] == 0x2D, let month = digits(bytes, 5, 2), bytes[7] == 0x2D,
              let day = digits(bytes, 8, 2), (1...12).contains(month),
              (1...daysInMonth(year: year, month: month)).contains(day) else { return nil }
        var seconds = Double(daysFromCivil(year: year, month: month, day: day)) * 86_400
        var index = 10
        if index == bytes.count { return seconds }
        guard bytes[index] == 0x54 || bytes[index] == 0x20 else { return nil }
        index += 1
        guard let hour = digits(bytes, index, 2), index + 2 < bytes.count, bytes[index + 2] == 0x3A,
              let minute = digits(bytes, index + 3, 2), hour < 24, minute < 60 else { return nil }
        index += 5
        var second = 0
        var fraction = 0.0
        if index < bytes.count, bytes[index] == 0x3A {
            guard let value = digits(bytes, index + 1, 2), value < 60 else { return nil }
            second = value
            index += 3
            if index < bytes.count, bytes[index] == 0x2E || bytes[index] == 0x2C {
                index += 1
                var scale = 0.1
                let start = index
                while index < bytes.count, isDigit(bytes[index]) {
                    fraction += Double(bytes[index] - 0x30) * scale
                    scale /= 10
                    index += 1
                }
                guard index > start else { return nil }
            }
        }
        seconds += Double(hour * 3_600 + minute * 60 + second) + fraction
        guard index < bytes.count else { return seconds }
        if bytes[index] == 0x5A { return index + 1 == bytes.count ? seconds : nil }
        guard bytes[index] == 0x2B || bytes[index] == 0x2D else { return nil }
        let sign: Double = bytes[index] == 0x2D ? -1 : 1
        index += 1
        guard let offsetHours = digits(bytes, index, 2), offsetHours < 24 else { return nil }
        index += 2
        var offsetMinutes = 0
        if index < bytes.count {
            if bytes[index] == 0x3A { index += 1 }
            guard let value = digits(bytes, index, 2), value < 60 else { return nil }
            offsetMinutes = value
            index += 2
        }
        guard index == bytes.count else { return nil }
        return seconds - sign * Double(offsetHours * 3_600 + offsetMinutes * 60)
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    private static func digits(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
        guard start >= 0, start + count <= bytes.count else { return nil }
        var value = 0
        for byte in bytes[start..<(start + count)] {
            guard isDigit(byte) else { return nil }
            value = value * 10 + Int(byte - 0x30)
        }
        return value
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days from 1970-01-01 to the proleptic Gregorian date (Howard Hinnant's civil-days algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

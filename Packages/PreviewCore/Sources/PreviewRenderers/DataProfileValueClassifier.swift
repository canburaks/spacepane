import Foundation

/// Classifies the exact spelling of one table cell for the data profile.
///
/// Pure and read-only: it looks at UTF-8 bytes and never converts, trims or reformats the cell that is
/// shown. A cell is an integer or decimal only when its whole spelling is an optional sign, digits, an
/// optional `.` fraction and an optional exponent. A `,` thousands separator, a currency sign, a percent
/// sign or a trailing `.` make the cell text on purpose: the file does not say what they mean, and a
/// guess would hide the very ambiguity the profile exists to show. Dates are limited to the three
/// spellings documented on `DateFormat`.
enum DataProfileValueClassifier {
    enum Kind: Int, CaseIterable, Sendable { case integer, decimal, boolean, date, text }

    /// The recognized date spellings. The raw values index bit masks, so keep them dense.
    enum DateFormat: Int, CaseIterable, Sendable {
        /// `yyyy-mm-dd`, optionally followed by `T` or a space, `hh:mm[:ss[.fraction]]` and a zone.
        case iso
        /// `mm/dd/yyyy`; the month comes first, as the profile documents.
        case monthDayYear
        /// `dd.mm.yyyy`.
        case dotted
    }

    struct Facts: Sendable {
        var kind = Kind.text
        /// Empty or whitespace-only; every other field is meaningless then.
        var isBlank = false
        var hasSurroundingWhitespace = false
        /// An integer part longer than one digit that starts with `0`, such as `007`.
        var hasLeadingZeros = false
        /// The finite value of an integer or decimal; nil for a spelling that overflows a Double.
        var number: Double?
        var dateFormat: DateFormat?
        /// Seconds since 1970 in UTC for ISO dates only; the other spellings are ambiguous.
        var timestamp: Double?
    }

    static func classify(_ bytes: UnsafeBufferPointer<UInt8>) -> Facts {
        var facts = Facts()
        var start = 0
        var end = bytes.count
        while start < end {
            let byte = bytes[start]
            if byte < 0x80 {
                guard isASCIISpace(byte) else { break }
                start += 1
            } else {
                let (scalar, width) = scalarForward(bytes, at: start)
                guard scalar.properties.isWhitespace else { break }
                start += width
            }
        }
        guard start < end else {
            facts.isBlank = true
            return facts
        }
        while end > start {
            let byte = bytes[end - 1]
            if byte < 0x80 {
                guard isASCIISpace(byte) else { break }
                end -= 1
            } else {
                let (scalar, width) = scalarBackward(bytes, endingAt: end, lowerBound: start)
                guard scalar.properties.isWhitespace else { break }
                end -= width
            }
        }
        facts.hasSurroundingWhitespace = start > 0 || end < bytes.count
        let trimmed = UnsafeBufferPointer(rebasing: bytes[start..<end])
        let first = trimmed[0]
        if first == 0x2B || first == 0x2D || first == 0x2E || isDigit(first) {
            if parseNumber(trimmed, into: &facts) { return facts }
            if isDigit(first), parseDate(trimmed, into: &facts) { return facts }
        } else if isBoolean(trimmed) {
            facts.kind = .boolean
        }
        return facts
    }

    // MARK: Numbers

    private static let powersOfTen: [Double] = [
        1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11,
        1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
    ]
    /// Values below this exact-integer limit convert to Double without rounding.
    private static let exactMantissaLimit: UInt64 = 1 << 53

    private static func parseNumber(_ text: UnsafeBufferPointer<UInt8>, into facts: inout Facts) -> Bool {
        let count = text.count
        var index = 0
        var isNegative = false
        if text[0] == 0x2B || text[0] == 0x2D {
            isNegative = text[0] == 0x2D
            index = 1
        }
        let integerStart = index
        while index < count, isDigit(text[index]) { index += 1 }
        let integerEnd = index
        var fractionStart = index
        var fractionEnd = index
        var hasFraction = false
        if index < count, text[index] == 0x2E {
            fractionStart = index + 1
            var cursor = fractionStart
            while cursor < count, isDigit(text[cursor]) { cursor += 1 }
            guard cursor > fractionStart else { return false }
            fractionEnd = cursor
            hasFraction = true
            index = cursor
        }
        guard integerEnd > integerStart || hasFraction else { return false }
        var exponent = 0
        var hasExponent = false
        if index < count, text[index] == 0x65 || text[index] == 0x45 {
            var cursor = index + 1
            var exponentIsNegative = false
            if cursor < count, text[cursor] == 0x2B || text[cursor] == 0x2D {
                exponentIsNegative = text[cursor] == 0x2D
                cursor += 1
            }
            let exponentStart = cursor
            var magnitude = 0
            while cursor < count, isDigit(text[cursor]) {
                // Saturate: anything this large overflows or underflows a Double anyway.
                if magnitude < 100_000 { magnitude = magnitude * 10 + Int(text[cursor] &- 0x30) }
                cursor += 1
            }
            guard cursor > exponentStart else { return false }
            exponent = exponentIsNegative ? -magnitude : magnitude
            hasExponent = true
            index = cursor
        }
        guard index == count else { return false }
        facts.hasLeadingZeros = integerEnd - integerStart > 1 && text[integerStart] == 0x30
        facts.kind = hasFraction || hasExponent ? .decimal : .integer
        facts.number = value(of: text, integerRange: integerStart..<integerEnd,
                             fractionRange: fractionStart..<fractionEnd, exponent: exponent, isNegative: isNegative)
        return true
    }

    /// Clinger's exact fast path covers ordinary spellings; anything else defers to the standard
    /// library's correctly rounded parser. Overflowing spellings yield nil.
    private static func value(of text: UnsafeBufferPointer<UInt8>, integerRange: Range<Int>, fractionRange: Range<Int>,
                              exponent: Int, isNegative: Bool) -> Double? {
        var mantissa: UInt64 = 0
        var significant = 0
        var decimalExponent = exponent
        for index in integerRange {
            if significant < 19 {
                mantissa = mantissa &* 10 &+ UInt64(text[index] &- 0x30)
                if mantissa != 0 { significant += 1 }
            } else {
                decimalExponent += 1
            }
        }
        for index in fractionRange where significant < 19 {
            mantissa = mantissa &* 10 &+ UInt64(text[index] &- 0x30)
            if mantissa != 0 { significant += 1 }
            decimalExponent -= 1
        }
        if mantissa == 0 { return 0 }
        var result: Double
        if mantissa < exactMantissaLimit, decimalExponent >= -22, decimalExponent <= 22 {
            result = Double(mantissa)
            result = decimalExponent < 0 ? result / powersOfTen[-decimalExponent] : result * powersOfTen[decimalExponent]
        } else {
            guard let parsed = Double(String(decoding: text, as: UTF8.self)), parsed.isFinite else { return nil }
            return parsed
        }
        return isNegative ? -result : result
    }

    // MARK: Booleans

    private static func isBoolean(_ text: UnsafeBufferPointer<UInt8>) -> Bool {
        // ASCII letters differ from their lowercase form only in bit 5, and no other byte maps onto a letter.
        func matches(_ word: StaticString) -> Bool {
            word.withUTF8Buffer { word in
                for index in 0..<word.count where text[index] | 0x20 != word[index] { return false }
                return true
            }
        }
        switch text.count {
        case 2: return matches("no")
        case 3: return matches("yes")
        case 4: return matches("true")
        case 5: return matches("false")
        default: return false
        }
    }

    // MARK: Dates

    private static func parseDate(_ text: UnsafeBufferPointer<UInt8>, into facts: inout Facts) -> Bool {
        parseISO(text, into: &facts) || parseSeparated(text, into: &facts)
    }

    private static func parseISO(_ text: UnsafeBufferPointer<UInt8>, into facts: inout Facts) -> Bool {
        let count = text.count
        guard count >= 10, text[4] == 0x2D, text[7] == 0x2D,
              let year = digits(text, at: 0, count: 4), let month = digits(text, at: 5, count: 2),
              let day = digits(text, at: 8, count: 2), isValid(year: year, month: month, day: day) else { return false }
        var seconds = 0
        var fraction = 0.0
        var offset = 0
        if count > 10 {
            guard text[10] == 0x54 || text[10] == 0x74 || text[10] == 0x20, count >= 16, text[13] == 0x3A,
                  let hour = digits(text, at: 11, count: 2), let minute = digits(text, at: 14, count: 2),
                  hour < 24, minute < 60 else { return false }
            seconds = hour * 3_600 + minute * 60
            var index = 16
            if index < count, text[index] == 0x3A {
                guard let second = digits(text, at: index + 1, count: 2), second < 60 else { return false }
                seconds += second
                index += 3
                if index < count, text[index] == 0x2E || text[index] == 0x2C {
                    var cursor = index + 1
                    var scale = 0.1
                    while cursor < count, isDigit(text[cursor]) {
                        fraction += Double(text[cursor] &- 0x30) * scale
                        scale /= 10
                        cursor += 1
                    }
                    guard cursor > index + 1 else { return false }
                    index = cursor
                }
            }
            if index < count {
                if text[index] == 0x5A || text[index] == 0x7A {
                    index += 1
                } else if text[index] == 0x2B || text[index] == 0x2D {
                    let sign = text[index] == 0x2D ? -1 : 1
                    guard let hours = digits(text, at: index + 1, count: 2), hours < 24 else { return false }
                    index += 3
                    var minutes = 0
                    if index < count {
                        if text[index] == 0x3A { index += 1 }
                        guard let value = digits(text, at: index, count: 2), value < 60 else { return false }
                        minutes = value
                        index += 2
                    }
                    offset = sign * (hours * 3_600 + minutes * 60)
                } else {
                    return false
                }
            }
            guard index == count else { return false }
        }
        facts.kind = .date
        facts.dateFormat = .iso
        facts.timestamp = Double(daysFromCivil(year: year, month: month, day: day) * 86_400 + seconds - offset) + fraction
        return true
    }

    /// `mm/dd/yyyy` and `dd.mm.yyyy`: one or two digits, a separator, one or two digits, the same
    /// separator and a four-digit year.
    private static func parseSeparated(_ text: UnsafeBufferPointer<UInt8>, into facts: inout Facts) -> Bool {
        let count = text.count
        guard count >= 8, count <= 10 else { return false }
        var index = 0
        var first = 0
        while index < count, index < 2, isDigit(text[index]) { first = first * 10 + Int(text[index] &- 0x30); index += 1 }
        guard index > 0, index < count else { return false }
        let separator = text[index]
        guard separator == 0x2F || separator == 0x2E else { return false }
        index += 1
        let secondStart = index
        var second = 0
        while index < count, index - secondStart < 2, isDigit(text[index]) { second = second * 10 + Int(text[index] &- 0x30); index += 1 }
        guard index > secondStart, index < count, text[index] == separator, count - index - 1 == 4,
              let year = digits(text, at: index + 1, count: 4) else { return false }
        let isMonthFirst = separator == 0x2F
        guard isValid(year: year, month: isMonthFirst ? first : second, day: isMonthFirst ? second : first) else { return false }
        facts.kind = .date
        facts.dateFormat = isMonthFirst ? .monthDayYear : .dotted
        return true
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        switch month {
        case 4, 6, 9, 11: return day <= 30
        case 2: return day <= (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28)
        default: return day <= 31
        }
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Hinnant's civil-days algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    // MARK: Bytes

    private static func digits(_ text: UnsafeBufferPointer<UInt8>, at start: Int, count: Int) -> Int? {
        guard start + count <= text.count else { return nil }
        var value = 0
        for index in start..<(start + count) {
            guard isDigit(text[index]) else { return nil }
            value = value * 10 + Int(text[index] &- 0x30)
        }
        return value
    }

    @inline(__always) private static func isDigit(_ byte: UInt8) -> Bool { byte &- 0x30 < 10 }

    @inline(__always) private static func isASCIISpace(_ byte: UInt8) -> Bool { byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) }

    /// Cell text is valid UTF-8, so a lead byte determines the sequence length.
    private static func scalarForward(_ bytes: UnsafeBufferPointer<UInt8>, at index: Int) -> (Unicode.Scalar, Int) {
        let lead = bytes[index]
        let width = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : 2
        guard index + width <= bytes.count else { return ("\u{FFFD}", 1) }
        return (decode(bytes, from: index, width: width), width)
    }

    private static func scalarBackward(_ bytes: UnsafeBufferPointer<UInt8>, endingAt end: Int, lowerBound: Int) -> (Unicode.Scalar, Int) {
        var start = end - 1
        while start > lowerBound, bytes[start] & 0xC0 == 0x80 { start -= 1 }
        let width = end - start
        guard width <= 4 else { return ("\u{FFFD}", 1) }
        return (decode(bytes, from: start, width: width), width)
    }

    private static func decode(_ bytes: UnsafeBufferPointer<UInt8>, from index: Int, width: Int) -> Unicode.Scalar {
        var value: UInt32
        switch width {
        case 1: value = UInt32(bytes[index])
        case 2: value = UInt32(bytes[index] & 0x1F)
        case 3: value = UInt32(bytes[index] & 0x0F)
        default: value = UInt32(bytes[index] & 0x07)
        }
        for offset in 1..<max(width, 1) { value = value << 6 | UInt32(bytes[index + offset] & 0x3F) }
        return Unicode.Scalar(value) ?? "\u{FFFD}"
    }
}

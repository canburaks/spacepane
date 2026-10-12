import Foundation

/// Byte-level tokenizer shared by the text mesh formats. It never allocates per token: tokens are
/// ranges into the caller's buffer. Numbers are parsed by a strict decimal grammar, so `nan`, `inf`
/// and hexadecimal spellings are rejected rather than reaching geometry.
struct ASCIIScanner {
    let bytes: UnsafeBufferPointer<UInt8>
    private(set) var position: Int

    init(_ bytes: UnsafeBufferPointer<UInt8>, position: Int = 0) {
        self.bytes = bytes
        self.position = position
    }

    var isAtEnd: Bool { position >= bytes.count }

    private static let backslash: UInt8 = 0x5C

    static func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0B || byte == 0x0C }
    static func isLineBreak(_ byte: UInt8) -> Bool { byte == 0x0A || byte == 0x0D }

    /// Length of a line-continuation (a backslash directly before a line break) at `index`, or 0.
    private func continuationLength(at index: Int) -> Int {
        guard index + 1 < bytes.count, bytes[index] == Self.backslash, Self.isLineBreak(bytes[index + 1]) else { return 0 }
        if bytes[index + 1] == 0x0D, index + 2 < bytes.count, bytes[index + 2] == 0x0A { return 3 }
        return 2
    }

    /// Skips spaces, tabs and continuations, but stops at a line break.
    mutating func skipBlanks() {
        while position < bytes.count {
            if Self.isBlank(bytes[position]) { position += 1; continue }
            let continuation = continuationLength(at: position)
            if continuation > 0 { position += continuation; continue }
            break
        }
    }

    /// Skips every kind of whitespace, including line breaks.
    mutating func skipWhitespace() {
        while position < bytes.count, Self.isBlank(bytes[position]) || Self.isLineBreak(bytes[position]) { position += 1 }
    }

    /// Next token on the current line; `nil` at a line break or the end of input.
    mutating func tokenOnLine() -> Range<Int>? {
        skipBlanks()
        return scanToken(honoringContinuations: true)
    }

    /// Next token anywhere, crossing line breaks; `nil` at the end of input.
    mutating func token() -> Range<Int>? {
        skipWhitespace()
        return scanToken(honoringContinuations: false)
    }

    private mutating func scanToken(honoringContinuations: Bool) -> Range<Int>? {
        guard position < bytes.count else { return nil }
        let start = position
        while position < bytes.count {
            let byte = bytes[position]
            if Self.isBlank(byte) || Self.isLineBreak(byte) { break }
            if honoringContinuations, byte == Self.backslash, continuationLength(at: position) > 0 { break }
            position += 1
        }
        if position == start { return nil }
        return start..<position
    }

    /// Advances past the rest of the current line, honouring continuations, and past its break.
    mutating func skipToNextLine() {
        while position < bytes.count {
            let continuation = continuationLength(at: position)
            if continuation > 0 { position += continuation; continue }
            let byte = bytes[position]
            position += 1
            if byte == 0x0A { return }
            if byte == 0x0D {
                if position < bytes.count, bytes[position] == 0x0A { position += 1 }
                return
            }
        }
    }

    // MARK: Token interpretation

    func matches(_ range: Range<Int>, _ keyword: StaticString) -> Bool {
        guard range.count == keyword.utf8CodeUnitCount else { return false }
        let expected = keyword.utf8Start
        for offset in 0..<range.count {
            var byte = bytes[range.lowerBound + offset]
            if byte >= 0x41, byte <= 0x5A { byte += 0x20 }
            if byte != expected[offset] { return false }
        }
        return true
    }

    func double(_ range: Range<Int>) -> Double? {
        Self.parseDouble(bytes, range)
    }

    func integer(_ range: Range<Int>) -> Int? {
        Self.parseInteger(bytes, range)
    }

    private static let powersOfTen: [Double] = (0...22).map { pow(10, Double($0)) }

    /// `[+-]digits[.digits][(e|E)[+-]digits]` with at least one mantissa digit. The value is correctly
    /// scaled for any practical mesh coordinate; non-finite results are rejected.
    static func parseDouble(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Double? {
        var index = range.lowerBound
        let end = range.upperBound
        guard index < end else { return nil }
        var negative = false
        if bytes[index] == 0x2D { negative = true; index += 1 } else if bytes[index] == 0x2B { index += 1 }
        var mantissa: UInt64 = 0
        var significant = 0
        var exponent = 0
        var sawDigit = false
        while index < end, bytes[index] >= 0x30, bytes[index] <= 0x39 {
            let digit = UInt64(bytes[index] - 0x30)
            sawDigit = true
            if mantissa == 0 && digit == 0 {
                // Leading zero carries no weight.
            } else if significant < 19 {
                mantissa = mantissa * 10 + digit
                significant += 1
            } else {
                exponent += 1
            }
            index += 1
        }
        if index < end, bytes[index] == 0x2E {
            index += 1
            while index < end, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                let digit = UInt64(bytes[index] - 0x30)
                sawDigit = true
                if mantissa == 0 && digit == 0 {
                    exponent -= 1
                } else if significant < 19 {
                    mantissa = mantissa * 10 + digit
                    significant += 1
                    exponent -= 1
                }
                index += 1
            }
        }
        guard sawDigit else { return nil }
        if index < end, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            var exponentNegative = false
            if index < end, bytes[index] == 0x2D { exponentNegative = true; index += 1 }
            else if index < end, bytes[index] == 0x2B { index += 1 }
            var magnitude = 0
            var sawExponentDigit = false
            while index < end, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                sawExponentDigit = true
                if magnitude < 100_000 { magnitude = magnitude * 10 + Int(bytes[index] - 0x30) }
                index += 1
            }
            guard sawExponentDigit else { return nil }
            exponent += exponentNegative ? -magnitude : magnitude
        }
        guard index == end else { return nil }
        if mantissa == 0 { return negative ? -0.0 : 0.0 }
        var value = Double(mantissa)
        if exponent > 0 {
            value *= exponent <= 22 ? powersOfTen[exponent] : pow(10, Double(exponent))
        } else if exponent < 0 {
            value = -exponent <= 22 ? value / powersOfTen[-exponent] : value * pow(10, Double(exponent))
        }
        guard value.isFinite else { return nil }
        return negative ? -value : value
    }

    /// `[+-]digits`, at most 18 digits so the value always fits.
    static func parseInteger(_ bytes: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> Int? {
        var index = range.lowerBound
        let end = range.upperBound
        guard index < end else { return nil }
        var negative = false
        if bytes[index] == 0x2D { negative = true; index += 1 } else if bytes[index] == 0x2B { index += 1 }
        guard index < end, end - index <= 18 else { return nil }
        var value = 0
        while index < end {
            let byte = bytes[index]
            guard byte >= 0x30, byte <= 0x39 else { return nil }
            value = value * 10 + Int(byte - 0x30)
            index += 1
        }
        return negative ? -value : value
    }
}

import Foundation

/// Lexical rules of the JSON5 superset shared by the JSON-with-comments adapter and the safe outline
/// that re-reads its concealed text. They live in the contracts module because both sides must agree
/// on where a token ends, and contracts are the only module they both import. Everything works on UTF-8
/// bytes: every delimiter is ASCII, and non-ASCII bytes are treated as identifier characters, which is
/// permissive but never splits a scalar.
///
/// Accepted beyond RFC 8259 JSON: `//` and `/* */` comments (handled by the callers), trailing commas,
/// unquoted object keys, single-quoted strings, hexadecimal numbers, a leading `+`, leading or trailing
/// decimal points, `Infinity` and `NaN`, string escapes `\x`, `\v`, `\0` and line continuations.
public enum JSON5Lexicon {
    public static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 11 || byte == 12 || byte == 13
    }

    public static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte == 36 || byte >= 0x80
    }

    public static func isIdentifierPart(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || (48...57).contains(byte)
    }

    /// `true`, `false`, `null`, `Infinity` and `NaN` (a sign may precede the last two as part of a number).
    public static let literals: Set<String> = ["true", "false", "null", "Infinity", "NaN"]

    /// Whether `token` is a complete JSON5 number: optional sign, then `Infinity`, `NaN`, hexadecimal
    /// digits after `0x`, or a decimal with an optional fraction and exponent (`.5` and `5.` included).
    public static func isNumber(_ token: ArraySlice<UInt8>) -> Bool {
        var bytes = token
        if let first = bytes.first, first == 43 || first == 45 { bytes = bytes.dropFirst() }
        guard let first = bytes.first else { return false }
        let text = String(decoding: bytes, as: UTF8.self)
        if text == "Infinity" || text == "NaN" { return true }
        if first == 48, bytes.count > 2, bytes[bytes.startIndex + 1] == 120 || bytes[bytes.startIndex + 1] == 88 {
            return bytes.dropFirst(2).allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        }
        var index = bytes.startIndex
        var integerDigits = 0
        while index < bytes.endIndex, (48...57).contains(bytes[index]) { index += 1; integerDigits += 1 }
        var fractionDigits = 0
        if index < bytes.endIndex, bytes[index] == 46 {
            index += 1
            while index < bytes.endIndex, (48...57).contains(bytes[index]) { index += 1; fractionDigits += 1 }
        }
        guard integerDigits + fractionDigits > 0 else { return false }
        if index < bytes.endIndex, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            if index < bytes.endIndex, bytes[index] == 43 || bytes[index] == 45 { index += 1 }
            var exponentDigits = 0
            while index < bytes.endIndex, (48...57).contains(bytes[index]) { index += 1; exponentDigits += 1 }
            guard exponentDigits > 0 else { return false }
        }
        return index == bytes.endIndex
    }

    /// The characters of a quoted string, given its content without the quotes; `nil` for a malformed
    /// escape, an unpaired surrogate or text that is not valid UTF-8.
    public static func decodeString(_ content: ArraySlice<UInt8>) -> String? {
        var output: [UInt8] = []
        output.reserveCapacity(content.count)
        var index = content.startIndex
        func hexValue(_ byte: UInt8) -> UInt32? {
            switch byte {
            case 48...57: UInt32(byte - 48)
            case 65...70: UInt32(byte - 55)
            case 97...102: UInt32(byte - 87)
            default: nil
            }
        }
        func hex(_ count: Int) -> UInt32? {
            guard index + count <= content.endIndex else { return nil }
            var value: UInt32 = 0
            for offset in 0..<count {
                guard let digit = hexValue(content[index + offset]) else { return nil }
                value = value << 4 | digit
            }
            index += count
            return value
        }
        func append(_ scalar: UInt32) -> Bool {
            guard let value = Unicode.Scalar(scalar) else { return false }
            output.append(contentsOf: Array(String(Character(value)).utf8))
            return true
        }
        while index < content.endIndex {
            let byte = content[index]
            index += 1
            guard byte == 92 else { output.append(byte); continue }
            guard index < content.endIndex else { return nil }
            let escaped = content[index]
            index += 1
            switch escaped {
            case 110: output.append(10)
            case 114: output.append(13)
            case 116: output.append(9)
            case 98: output.append(8)
            case 102: output.append(12)
            case 118: output.append(11)
            case 48:
                // `\0` must not be followed by a digit.
                if index < content.endIndex, (48...57).contains(content[index]) { return nil }
                output.append(0)
            case 49...57: return nil
            case 120:
                guard let value = hex(2), append(value) else { return nil }
            case 117:
                guard let unit = hex(4) else { return nil }
                if (0xD800...0xDBFF).contains(unit) {
                    guard index + 1 < content.endIndex, content[index] == 92, content[index + 1] == 117 else { return nil }
                    index += 2
                    guard let low = hex(4), (0xDC00...0xDFFF).contains(low),
                          append(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)) else { return nil }
                } else {
                    guard append(unit) else { return nil }
                }
            case 10: break // Line continuations contribute nothing.
            case 13:
                if index < content.endIndex, content[index] == 10 { index += 1 }
            case 0xE2:
                // U+2028 / U+2029 are continuations too; any other escaped scalar stands for itself.
                if index + 1 < content.endIndex, content[index] == 0x80, content[index + 1] == 0xA8 || content[index + 1] == 0xA9 {
                    index += 2
                } else { output.append(escaped) }
            default: output.append(escaped)
            }
        }
        return String(validating: output, as: UTF8.self)
    }
}

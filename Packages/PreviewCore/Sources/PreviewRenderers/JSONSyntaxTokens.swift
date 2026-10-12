import Foundation
import PreviewContracts

typealias JSONTokenRole = PreviewSyntaxRole

struct JSONSyntaxToken: Equatable, Sendable {
    let range: NSRange
    let role: JSONTokenRole
}

struct JSONTokenization: Sendable {
    let tokens: [JSONSyntaxToken]
    /// Conservatively counts code units visited by bounded collection and lexical scans.
    let visitedUTF16Units: Int
}

/// A lexical decoration of already-concealed text, never a parser or a source of display text.
/// UTF-16 ranges match NSTextStorage, including strings containing non-BMP characters.
enum JSONSyntaxTokens {
    // Decoration happens in the native text system, so keep its work below the content budget.
    static let maximumUTF16Units = 262_144
    static let maximumTokens = 20_000

    static func tokens(in text: String, maximumUTF16Units: Int = maximumUTF16Units,
                       maximumTokens: Int = maximumTokens) -> [JSONSyntaxToken] {
        scan(in: text, maximumUTF16Units: maximumUTF16Units, maximumTokens: maximumTokens).tokens
    }

    static func scan(in text: String, maximumUTF16Units: Int = maximumUTF16Units,
                     maximumTokens: Int = maximumTokens) -> JSONTokenization {
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max, maximumTokens > 0 else {
            return JSONTokenization(tokens: [], visitedUTF16Units: 0)
        }
        // Prefix before allocation: callers can construct a presentation outside the pipeline.
        let units = Array(text.utf16.prefix(maximumUTF16Units + 1))
        guard units.count <= maximumUTF16Units else {
            return JSONTokenization(tokens: [], visitedUTF16Units: units.count)
        }
        var tokens: [JSONSyntaxToken] = []
        var visited = units.count
        var index = 0
        while index < units.count {
            visited += 1
            let start = index
            let role: JSONTokenRole?
            switch units[index] {
            case 0x22: // quoted string; a backslash consumes the following code unit
                index += 1
                var closed = false
                while index < units.count {
                    visited += 1
                    let unit = units[index]
                    index += 1
                    if unit == 0x5C {
                        if index < units.count { index += 1; visited += 1 }
                    } else if unit == 0x22 {
                        closed = true
                        break
                    }
                }
                guard closed else { return JSONTokenization(tokens: tokens, visitedUTF16Units: visited) }
                var next = index
                while next < units.count && isWhitespace(units[next]) { next += 1; visited += 1 }
                if next < units.count { visited += 1 }
                role = next < units.count && units[next] == 0x3A ? .key : .string
            case 0x2D, 0x30...0x39:
                let number = scanNumber(in: units, from: index)
                index = number.end
                visited += number.end - start
                if number.valid, isBoundary(before: start, in: units), isBoundary(after: index, in: units) {
                    role = .number
                } else {
                    role = nil
                }
            case 0x74, 0x66, 0x6E:
                // Literal spellings live only at this JSON syntax boundary.
                let literal: [UInt16]
                switch units[index] {
                case 0x74: literal = [0x74, 0x72, 0x75, 0x65]
                case 0x66: literal = [0x66, 0x61, 0x6C, 0x73, 0x65]
                default: literal = [0x6E, 0x75, 0x6C, 0x6C]
                }
                let end = index + literal.count
                visited += literal.count
                if end <= units.count, isBoundary(before: start, in: units), isBoundary(after: end, in: units),
                   units[index..<end].elementsEqual(literal) {
                    index = end
                    role = .literal
                } else {
                    index += 1
                    role = nil
                }
            default:
                index += 1
                role = nil
            }
            if let role {
                guard tokens.count < maximumTokens else {
                    return JSONTokenization(tokens: [], visitedUTF16Units: visited)
                }
                tokens.append(JSONSyntaxToken(range: NSRange(location: start, length: index - start), role: role))
            }
        }
        return JSONTokenization(tokens: tokens, visitedUTF16Units: visited)
    }

    private static func scanNumber(in units: [UInt16], from start: Int) -> (end: Int, valid: Bool) {
        var index = start
        if units[index] == 0x2D { index += 1 }
        guard index < units.count else { return (index, false) }
        if units[index] == 0x30 {
            index += 1
        } else {
            guard (0x31...0x39).contains(units[index]) else { return (max(index, start + 1), false) }
            repeat { index += 1 } while index < units.count && isDigit(units[index])
        }
        if index < units.count && units[index] == 0x2E {
            index += 1
            guard index < units.count && isDigit(units[index]) else { return (index, false) }
            repeat { index += 1 } while index < units.count && isDigit(units[index])
        }
        if index < units.count && (units[index] == 0x65 || units[index] == 0x45) {
            index += 1
            if index < units.count && (units[index] == 0x2B || units[index] == 0x2D) { index += 1 }
            guard index < units.count && isDigit(units[index]) else { return (index, false) }
            repeat { index += 1 } while index < units.count && isDigit(units[index])
        }
        // Consume even rejected candidates once, rather than rescanning each digit of malformed input.
        return (index, true)
    }

    private static func isDigit(_ unit: UInt16) -> Bool { (0x30...0x39).contains(unit) }
    private static func isWhitespace(_ unit: UInt16) -> Bool { [0x20, 0x09, 0x0A, 0x0D].contains(unit) }
    private static func isBoundary(before index: Int, in units: [UInt16]) -> Bool {
        index == 0 || isWhitespace(units[index - 1]) || [0x5B, 0x7B, 0x3A, 0x2C].contains(units[index - 1])
    }
    private static func isBoundary(after index: Int, in units: [UInt16]) -> Bool {
        index == units.count || isWhitespace(units[index]) || [0x5D, 0x7D, 0x2C, 0x3A].contains(units[index])
    }
}

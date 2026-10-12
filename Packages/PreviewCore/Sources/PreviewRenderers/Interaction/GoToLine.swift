import Foundation

/// Resolves what the user typed into the Go to Line field against the displayed, already-concealed text.
/// Line numbers are the logical lines of `LogicalLineIndex` (soft wraps never count), starting at one.
enum GoToLine {
    enum Failure: Error, Equatable, Sendable {
        /// The text has no lines at all, so there is nothing to jump to.
        case noLines
        /// Not a whole number, zero, negative or beyond the last line; `lineCount` is the valid upper bound.
        case outOfRange(lineCount: Int)
    }

    struct Target: Equatable, Sendable {
        /// One-based number of the line that was resolved.
        let line: Int
        let lineCount: Int
        /// The line's UTF-16 range in the displayed text without its terminating separator.
        let range: NSRange
    }

    static func resolve(_ input: String, in text: NSString, index: LogicalLineIndex) -> Result<Target, Failure> {
        guard index.count > 0 else { return .failure(.noLines) }
        guard let line = lineNumber(from: input), (1...index.count).contains(line),
              let range = index.contentRange(ofLine: line - 1, in: text) else {
            return .failure(.outOfRange(lineCount: index.count))
        }
        return .success(Target(line: line, lineCount: index.count, range: range))
    }

    /// Whole numbers only, in ASCII or any script's decimal digits, with surrounding whitespace ignored.
    /// Signs, fractions, grouping separators and anything else are rejected rather than guessed.
    static func lineNumber(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 32 else { return nil }
        if trimmed.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) { return Int(trimmed) }
        // Native digits (for example Arabic-Indic or Bengali) are all decimal digits of their script.
        var digits = ""
        for scalar in trimmed.unicodeScalars {
            guard scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue,
                  value >= 0, value <= 9 else { return nil }
            digits += String(Int(value))
        }
        return Int(digits)
    }
}

extension LogicalLineIndex {
    /// The zero-based line's UTF-16 range without its line separator (CRLF counts as one), or nil when the
    /// line does not exist or the index no longer describes `text`.
    func contentRange(ofLine line: Int, in text: NSString) -> NSRange? {
        guard starts.indices.contains(line), text.length == utf16Length else { return nil }
        let start = starts[line]
        var end = line + 1 < starts.count ? starts[line + 1] : utf16Length
        if line + 1 < starts.count, end > start {
            let last = text.character(at: end - 1)
            if last == 10, end - 1 > start, text.character(at: end - 2) == 13 { end -= 2 }
            else if [10, 13, 0x85, 0x2028, 0x2029].contains(last) { end -= 1 }
        }
        return NSRange(location: start, length: end - start)
    }
}

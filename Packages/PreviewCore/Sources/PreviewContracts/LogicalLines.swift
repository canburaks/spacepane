import Foundation

/// The one definition of a logical line in displayed (already concealed) text, shared by the
/// line-number gutter and by findings that report lines. Offsets are UTF-16 code units.
/// Empty text has no lines; a final separator creates a trailing empty line. CRLF is one
/// separator; CR, LF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR are breaks.
public enum LogicalLines {
    public struct Starts: Equatable, Sendable {
        public let starts: [Int]
        public let utf16Length: Int
    }

    public static func starts(in text: String) -> Starts {
        var starts: [Int] = text.isEmpty ? [] : [0]
        var offset = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            offset += scalar.utf16.count
            switch scalar.value {
            case 10:
                if previousWasCR { starts[starts.count - 1] = offset }
                else { starts.append(offset) }
            case 13, 0x85, 0x2028, 0x2029:
                starts.append(offset)
            default: break
            }
            previousWasCR = scalar.value == 13
        }
        return Starts(starts: starts, utf16Length: offset)
    }

    /// Zero-based line containing a UTF-16 offset; separators belong to the line they end.
    public static func lineIndex(containingUTF16 offset: Int, in index: Starts) -> Int? {
        guard !index.starts.isEmpty, (0...index.utf16Length).contains(offset) else { return nil }
        var lower = 0
        var upper = index.starts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if index.starts[middle] <= offset { lower = middle + 1 }
            else { upper = middle }
        }
        return lower - 1
    }

    /// One-based line numbers for UTF-16 offsets in `text`, in the order given. Offsets outside
    /// the text are dropped. One scan of the text serves every offset.
    public static func lineNumbers(forUTF16Offsets offsets: [Int], in text: String) -> [Int] {
        guard !offsets.isEmpty else { return [] }
        let index = starts(in: text)
        return offsets.compactMap { lineIndex(containingUTF16: $0, in: index).map { $0 + 1 } }
    }
}

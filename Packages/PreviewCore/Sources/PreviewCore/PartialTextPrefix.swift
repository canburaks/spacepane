import Foundation
import PreviewContracts

/// Chooses how much of the leading bytes of an oversized text file may be shown.
///
/// The reader returns at most `maxInputBytes`; this scan keeps the longest prefix that ends at a
/// record boundary and whose lines the later decoding and validation will accept: complete lines,
/// at most `maxTextLines` of them, none longer than `maxLineUTF8Bytes`. It works on the raw bytes
/// and understands UTF-8 and BOM-marked UTF-16, so the cut is always at a whole code unit after an
/// ASCII line terminator and never inside a multi-byte sequence or surrogate pair. Line terminators
/// and counting follow `TextMetrics` except that NEL, LS and PS are never used as cut points.
enum PartialTextPrefix {
    /// Number of leading bytes (BOM included) to keep, or `PreviewFailure.inputTooLarge` when no
    /// complete record fits: a single record longer than the budget cannot be shown partially.
    static func keptByteCount(of data: Data, boundary: PartialRecordBoundary, budget: PreviewBudget,
                              context: RequestContext) throws -> Int {
        try context.checkpoint()
        let bytes = [UInt8](data)
        let utf16: (littleEndian: Bool, start: Int)?
        let start: Int
        if bytes.starts(with: [0xFF, 0xFE]) { utf16 = (true, 2); start = 2 }
        else if bytes.starts(with: [0xFE, 0xFF]) { utf16 = (false, 2); start = 2 }
        else { utf16 = nil; start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0 }
        let width = utf16 == nil ? 1 : 2

        var lines = 1
        var lineBytes = 0
        var previousWasCR = false
        var lineIsBlank = true
        var inQuotes = false
        var recordBoundary: Int?
        var index = start
        var visited = 0
        while index + width <= bytes.count {
            visited += 1
            if visited.isMultiple(of: 4096) { try context.checkpoint() }
            let unit: UInt16
            if let utf16 {
                unit = utf16.littleEndian ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                                          : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            } else {
                unit = UInt16(bytes[index])
            }
            index += width
            if unit == 0x0A && previousWasCR {
                // The LF of a CRLF pair is part of the separator the CR already counted; it only
                // extends the boundary the CR set, and cannot make an empty line of its own.
                if recordBoundary == index - width { recordBoundary = index }
                previousWasCR = false
                continue
            }
            if unit == 0x0A || unit == 0x0D {
                let newLines = lines + 1
                guard newLines <= budget.maxTextLines else { break }
                lines = newLines
                let endsRecord: Bool
                switch boundary {
                case .line: endsRecord = true
                case .blankLine: endsRecord = lineIsBlank
                case .quotedRecord: endsRecord = !inQuotes
                }
                if endsRecord { recordBoundary = index }
                lineBytes = 0
                lineIsBlank = true
                previousWasCR = unit == 0x0D
                continue
            }
            previousWasCR = false
            if unit == 0x22 { inQuotes.toggle() }
            if unit != 0x20 && unit != 0x09 { lineIsBlank = false }
            if utf16 == nil {
                lineBytes += 1 // Every raw UTF-8 byte is one byte of the line's UTF-8 length.
            } else {
                switch unit {
                case 0..<0x80: lineBytes += 1
                case 0x80..<0x800: lineBytes += 2
                case 0xD800...0xDBFF: lineBytes += 4 // A surrogate pair is four UTF-8 bytes; the low unit adds none.
                case 0xDC00...0xDFFF: break
                default: lineBytes += 3
                }
            }
            guard lineBytes <= budget.maxLineUTF8Bytes else { break }
        }
        guard let kept = recordBoundary, kept > start else { throw PreviewFailure.inputTooLarge }
        return kept
    }
}

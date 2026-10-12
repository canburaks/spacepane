import Foundation

/// Sorting for `SafeTable`. Both orders are computed over row *indexes* and never touch the table's
/// cells, so the data, its exact spelling and its copy output stay as they were.
enum SafeTableOrdering {
    /// Row indexes sorted by `column`, stably: rows with equal keys keep their source order in both
    /// directions. Blank cells always sort last, whichever way the column is sorted.
    ///
    /// Number and date columns sort by their typed keys; every other column sorts by natural name order.
    static func sorted(_ table: SafeTable, by column: Int, ascending: Bool) -> [Int] {
        var indexes = Array(table.rows.indices)
        guard column >= 0, column < table.columns.count else { return indexes }
        if table.kind(ofColumn: column) != .text, let keys = table.sortKeys[column], keys.count == indexes.count {
            indexes.sort { lhs, rhs in
                switch (keys[lhs], keys[rhs]) {
                case let (left?, right?): return left == right ? lhs < rhs : ascending == (left < right)
                case (nil, nil): return lhs < rhs
                case (nil, _): return false
                case (_, nil): return true
                }
            }
            return indexes
        }
        let values = indexes.map { table.cell(row: $0, column: column) }
        let compare = NaturalOrder.comparison(for: values)
        indexes.sort { lhs, rhs in
            let (left, right) = (values[lhs], values[rhs])
            if left.isEmpty || right.isEmpty { return left.isEmpty == right.isEmpty ? lhs < rhs : right.isEmpty }
            let result = compare(left, right)
            return result == .orderedSame ? lhs < rhs : ascending == (result == .orderedAscending)
        }
        return indexes
    }
}

/// Row filtering by typed text, ignoring case, accents and character width.
///
/// A row stays when any of its cells contains the text. Only the displayed (already concealed) cells are
/// searched, so a filter can never reveal or confirm concealed content. The needle is capped, ASCII
/// cells are matched in place without allocating, and the folded spelling of any other cell is cached
/// (up to a fixed number of cells) so repeated keystrokes stay cheap on a large table.
struct SafeTableFilter {
    static let maximumNeedleCharacters = 256
    private static let maximumCachedCells = 150_000
    private static let foldOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    private var folded: [Int: [UInt8]] = [:]

    /// The rows of `order` that contain `query`, in the same order. An empty query keeps every row.
    mutating func rows(in order: [Int], of table: SafeTable, matching query: String) -> [Int] {
        let text = String(query.prefix(Self.maximumNeedleCharacters))
        guard !text.isEmpty else { return order }
        let needle = Array(Self.fold(text).utf8)
        guard !needle.isEmpty else { return order }
        let needleIsASCII = needle.allSatisfy { $0 < 0x80 }
        let stride = max(table.columns.count, 1)
        return order.filter { row in
            guard table.rows.indices.contains(row) else { return false }
            return table.rows[row].indices.contains { column in
                matches(table.rows[row][column], key: row * stride + column, needle: needle, needleIsASCII: needleIsASCII)
            }
        }
    }

    mutating func reset() { folded = [:] }

    private mutating func matches(_ cell: String, key: Int, needle: [UInt8], needleIsASCII: Bool) -> Bool {
        var cell = cell
        let isASCII = cell.withUTF8 { $0.allSatisfy { $0 < 0x80 } }
        if isASCII {
            // An ASCII cell can only contain an ASCII needle once the needle's accents are folded away.
            guard needleIsASCII else { return false }
            return cell.withUTF8 { Self.contains($0, needle, foldingCase: true) }
        }
        if let cached = folded[key] { return cached.withUnsafeBufferPointer { Self.contains($0, needle, foldingCase: false) } }
        let bytes = Array(Self.fold(cell).utf8)
        if folded.count < Self.maximumCachedCells { folded[key] = bytes }
        return bytes.withUnsafeBufferPointer { Self.contains($0, needle, foldingCase: false) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: foldOptions, locale: nil)
    }

    /// Plain substring search over bytes; `needle` is already folded, and ASCII cells fold case on the fly.
    private static func contains(_ haystack: UnsafeBufferPointer<UInt8>, _ needle: [UInt8], foldingCase: Bool) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count) {
            var offset = 0
            while offset < needle.count {
                var byte = haystack[start + offset]
                if foldingCase, byte >= 0x41, byte <= 0x5A { byte += 0x20 }
                if byte != needle[offset] { break }
                offset += 1
            }
            if offset == needle.count { return true }
        }
        return false
    }
}

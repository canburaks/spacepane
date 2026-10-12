import Foundation

/// "Natural" name order as Finder shows it: digit runs compare by value ("2" before "10"), letters
/// without regard to case, accents and other scripts by the user's collation rules.
///
/// `localizedStandardCompare` is the reference. It is slow enough to matter when thousands of rows are
/// sorted on the main thread, so a column whose strings are all ASCII uses an allocation-free
/// comparison with the same digit and case behavior. The choice is made once per group of strings and
/// never mixes the two orders, which keeps every sort a consistent total order.
enum NaturalOrder {
    /// A comparison valid for exactly the strings it was made for.
    typealias Comparison = @Sendable (String, String) -> ComparisonResult

    static func comparison(for values: [String]) -> Comparison {
        if values.allSatisfy({ $0.utf8.allSatisfy { $0 < 0x80 } }) { return { compareASCII($0, $1) } }
        return { $0.localizedStandardCompare($1) }
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        comparison(for: [lhs, rhs])(lhs, rhs)
    }

    static func compareASCII(_ lhs: String, _ rhs: String) -> ComparisonResult {
        var lhs = lhs, rhs = rhs
        return lhs.withUTF8 { left in rhs.withUTF8 { right in compare(left, right) } }
    }

    private static func compare(_ left: UnsafeBufferPointer<UInt8>, _ right: UnsafeBufferPointer<UInt8>) -> ComparisonResult {
        var i = 0, j = 0
        while i < left.count, j < right.count {
            let a = left[i], b = right[j]
            if isDigit(a), isDigit(b) {
                var iEnd = i, jEnd = j
                while iEnd < left.count, isDigit(left[iEnd]) { iEnd += 1 }
                while jEnd < right.count, isDigit(right[jEnd]) { jEnd += 1 }
                var iStart = i, jStart = j
                while iStart < iEnd - 1, left[iStart] == 0x30 { iStart += 1 }
                while jStart < jEnd - 1, right[jStart] == 0x30 { jStart += 1 }
                let leftLength = iEnd - iStart, rightLength = jEnd - jStart
                if leftLength != rightLength { return leftLength < rightLength ? .orderedAscending : .orderedDescending }
                for offset in 0..<leftLength where left[iStart + offset] != right[jStart + offset] {
                    return left[iStart + offset] < right[jStart + offset] ? .orderedAscending : .orderedDescending
                }
                i = iEnd
                j = jEnd
            } else {
                let x = lowercase(a), y = lowercase(b)
                if x != y { return x < y ? .orderedAscending : .orderedDescending }
                i += 1
                j += 1
            }
        }
        if i < left.count { return .orderedDescending }
        if j < right.count { return .orderedAscending }
        return .orderedSame
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
    private static func lowercase(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }
}

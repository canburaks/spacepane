import Foundation

/// Natural ordering for archive member names: digit runs compare by numeric value, so `page2` precedes
/// `page10`. The comparison is deterministic and locale independent (a reading order must not change with
/// the user's language), compares case-insensitively and falls back to the exact spelling on ties.
enum NaturalOrder {
    static func areInIncreasingOrder(_ lhs: String, _ rhs: String) -> Bool { compare(lhs, rhs) == .orderedAscending }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = Array(lhs.unicodeScalars)
        let right = Array(rhs.unicodeScalars)
        var i = 0
        var j = 0
        while i < left.count, j < right.count {
            if isDigit(left[i]), isDigit(right[j]) {
                let leftRun = digitRun(left, from: i)
                let rightRun = digitRun(right, from: j)
                let leftValue = leftRun.drop { $0 == "0" }
                let rightValue = rightRun.drop { $0 == "0" }
                // A longer digit string (after leading zeros) is the larger number; equal lengths compare as text.
                if leftValue.count != rightValue.count {
                    return leftValue.count < rightValue.count ? .orderedAscending : .orderedDescending
                }
                if let difference = zip(leftValue, rightValue).first(where: { $0 != $1 }) {
                    return difference.0.value < difference.1.value ? .orderedAscending : .orderedDescending
                }
                i += leftRun.count
                j += rightRun.count
                continue
            }
            let l = folded(left[i])
            let r = folded(right[j])
            if l != r { return l.value < r.value ? .orderedAscending : .orderedDescending }
            i += 1
            j += 1
        }
        if left.count - i != right.count - j { return (left.count - i) < (right.count - j) ? .orderedAscending : .orderedDescending }
        // Same natural key (case and leading zeros aside): the exact spelling decides, deterministically.
        if lhs == rhs { return .orderedSame }
        return lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars) ? .orderedAscending : .orderedDescending
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 48 && scalar.value <= 57 }

    private static func digitRun(_ scalars: [Unicode.Scalar], from start: Int) -> [Unicode.Scalar] {
        var end = start
        while end < scalars.count, isDigit(scalars[end]) { end += 1 }
        return Array(scalars[start..<end])
    }

    /// ASCII case folding only; other scripts compare by code point.
    private static func folded(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        (65...90).contains(scalar.value) ? Unicode.Scalar(scalar.value + 32) ?? scalar : scalar
    }
}

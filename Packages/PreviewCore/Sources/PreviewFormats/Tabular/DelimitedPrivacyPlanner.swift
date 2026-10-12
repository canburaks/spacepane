import Foundation
import PreviewContracts

/// Chooses the cells to conceal while records stream past, one at a time.
///
/// - The first record is the header. Every non-empty cell of a column whose header satisfies
///   `SecretFieldPolicy.isSensitive` is concealed in every later record.
/// - A record that is *wider* than the header has shifted (typically an unquoted delimiter inside
///   free text), so a sensitive value may sit up to `overflow` columns to the right of its header:
///   those cells are concealed too. Shorter records stay positional (trailing fields are commonly
///   omitted, and a value moving left would need a missing delimiter in the middle of a row).
/// - Any cell whose decoded value contains a sensitive `key=value`/`key: value` assignment is
///   concealed, header cells included. This mirrors the line heuristic in `DefaultPrivacyFilter`,
///   which structured privacy replaces, applied to the cell as the unit.
/// - A short bare-name cell (no `:`/`=`) that names a secret (`api_key`, `Password`) is treated as the key of a
///   row-wise key/value pair: the next cell in that record is concealed. This covers key/value exports
///   under neutral headers such as `name,value`. In the header record it applies only to two-column
///   files, where the "header" may itself be the first key/value pair of a headerless export.
/// - Empty cells are not concealed: there is nothing to hide and a token would imply a value.
///
/// Ranges cover each cell's complete raw span, including enclosing quotes, so the replacement
/// token (which contains no delimiter, quote or line break) leaves the row/column shape unchanged.
struct DelimitedPrivacyPlanner {
    /// Same pattern as `DefaultPrivacyFilter`'s assignment heuristic; a parity test keeps them aligned.
    private static let assignmentPattern = SecretFieldPolicy.assignmentPattern
    private static let colon: UInt8 = 0x3A
    /// Longer cells are prose, not key names; the cap also bounds the per-cell policy check.
    private static let maximumKeyCellBytes = 128
    private static let equals: UInt8 = 0x3D

    private let bytes: [UInt8]
    private let maxRanges: Int
    private let context: RequestContext
    private let assignment: NSRegularExpression
    private var sensitiveColumns: [Int] = []
    private var headerWidth = 0
    private var mask: [Bool] = []
    private(set) var ranges: [SensitiveRange] = []

    init(bytes: [UInt8], maxRanges: Int, context: RequestContext) throws {
        self.bytes = bytes
        self.maxRanges = maxRanges
        self.context = context
        assignment = try NSRegularExpression(pattern: Self.assignmentPattern)
    }

    mutating func consume(record: Int, fields: [DelimitedRecords.Field]) throws {
        try context.checkpoint()
        mask.removeAll(keepingCapacity: true)
        mask.append(contentsOf: repeatElement(false, count: fields.count))
        if record == 0 {
            headerWidth = fields.count
            sensitiveColumns = fields.filter {
                SecretFieldPolicy.isSensitive(DelimitedRecords.text(of: $0, in: bytes))
            }.map(\.column)
        } else if !sensitiveColumns.isEmpty {
            markSensitiveColumns(fieldCount: fields.count)
        }
        if record > 0 || fields.count == 2 { markKeyValuePairs(fields) }
        for field in fields where !field.content.isEmpty {
            if mask[field.column] {
                try conceal(field)
            } else if try containsSensitiveAssignment(field) {
                try conceal(field)
            }
        }
    }

    private mutating func markSensitiveColumns(fieldCount: Int) {
        let overflow = max(0, fieldCount - headerWidth)
        var covered = -1
        for column in sensitiveColumns {
            let lower = max(column, covered + 1)
            let upper = min(fieldCount - 1, column + overflow)
            guard lower <= upper else { continue }
            for index in lower...upper { mask[index] = true }
            covered = upper
        }
    }

    private mutating func markKeyValuePairs(_ fields: [DelimitedRecords.Field]) {
        // Left to right: a cell already concealed as a value is never reinterpreted as a key, and a
        // cell holding its own assignment is a value handled by the assignment rule, not a bare name.
        for field in fields.dropLast() where !mask[field.column] && !field.content.isEmpty
            && field.content.count <= Self.maximumKeyCellBytes
            && !bytes[field.content].contains(where: { $0 == Self.colon || $0 == Self.equals }) {
            if SecretFieldPolicy.isSensitive(DelimitedRecords.text(of: field, in: bytes)) { mask[field.column + 1] = true }
        }
    }

    private mutating func conceal(_ field: DelimitedRecords.Field) throws {
        guard ranges.count < maxRanges else { throw PreviewFailure.tooManyNodes }
        ranges.append(SensitiveRange(utf8Range: field.raw))
    }

    private func containsSensitiveAssignment(_ field: DelimitedRecords.Field) throws -> Bool {
        // An assignment needs one of these separators; most cells have neither, so skip the regex.
        guard bytes[field.content].contains(where: { $0 == Self.colon || $0 == Self.equals }) else { return false }
        let text = DelimitedRecords.text(of: field, in: bytes)
        var found = false
        var failure: (any Error)?
        let ns = text as NSString
        assignment.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(location: 0, length: ns.length)) { match, _, stop in
            do { try context.checkpoint() }
            catch { failure = error; stop.pointee = true; return }
            if let match, SecretFieldPolicy.isSensitive(ns.substring(with: match.range(at: 1))) {
                found = true
                stop.pointee = true
            }
        }
        if let failure { throw failure }
        return found
    }
}

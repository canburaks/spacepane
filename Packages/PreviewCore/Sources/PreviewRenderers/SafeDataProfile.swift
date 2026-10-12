import Foundation
import PreviewContracts

/// A bounded, per-column summary of a delimited table, computed only from the already-concealed
/// `SafeTable`. It never reads source bytes, so it can show nothing that the Table view does not.
///
/// Values keep their exact spelling: a minimum, maximum or common value is the original cell, never a
/// reformatted number or date. The profile is plain immutable data; `SafeDataProfilePresentation`
/// turns it into localized text.
///
/// Privacy: a column is *concealed* when its header names a sensitive field
/// (`SecretFieldPolicy.isSensitive`) or when any cell of the table, the header included, holds the
/// concealment token. A concealed column reports only how many of its cells are empty (an empty cell is
/// never concealed). No type, distinct count, extreme, mean, common value, distribution or note is
/// derived from its content, because each of those could confirm or narrow down a hidden value.
struct SafeDataProfile: Equatable, Sendable {
    typealias DateFormat = DataProfileValueClassifier.DateFormat

    enum ColumnType: Equatable, Sendable { case empty, integer, decimal, boolean, date, text, mixed, concealed }

    /// How many non-empty cells fell into one kind; `type` is never `.empty`, `.mixed` or `.concealed`.
    struct TypeCount: Equatable, Sendable {
        let type: ColumnType
        let count: Int
    }

    enum Note: Equatable, Sendable {
        /// More than one kind of value, listed with counts, largest first.
        case mixedTypes([TypeCount])
        /// Numeric-looking values such as `007` whose leading zeros a spreadsheet would drop.
        case leadingZeros(Int)
        /// Dates written in more than one of the recognized spellings.
        case inconsistentDateFormats([DateFormat])
        case surroundingWhitespace(Int)
        /// The column's name is also the name of another column.
        case duplicateName
    }

    struct ValueCount: Equatable, Sendable {
        /// The exact cell text.
        let value: String
        let count: Int
    }

    struct Distinct: Equatable, Sendable {
        let count: Int
        /// True when counting stopped at the cap, so the real number is at least `count`.
        let isLowerBound: Bool
    }

    struct Histogram: Equatable, Sendable {
        /// Counts of equal-width ranges between the extremes, low to high.
        let bins: [Int]
        /// The exact spellings of the smallest and largest value.
        let lower: String
        let upper: String
    }

    struct Column: Equatable, Sendable {
        let name: String
        let type: ColumnType
        /// Empty, whitespace-only and absent cells among the profiled rows.
        let missing: Int
        let distinct: Distinct?
        let minimum: String?
        let maximum: String?
        let mean: Double?
        let commonValues: [ValueCount]
        let histogram: Histogram?
        let notes: [Note]
    }

    enum TableNote: Equatable, Sendable {
        case sampled(profiled: Int, total: Int)
        /// Records whose field count differs from the header's.
        case raggedRows(Int)
        /// Columns whose name another column shares.
        case duplicateNames(Int)
        /// At least one column shows only its missing count.
        case concealedColumns(Int)
    }

    struct Limits: Equatable, Sendable {
        /// Rows profiled; a taller table is sampled from its first rows.
        var maximumRows = 10_000
        /// Distinct values tracked per column before the count becomes a lower bound.
        var maximumDistinctValues = 10_000
        var commonValueCount = 3
    }

    static let histogramBinCount = 8
    /// The marker the privacy stage writes in place of a concealed value.
    static let concealmentToken = SecretFieldPolicy.concealmentToken

    let columns: [Column]
    let profiledRows: Int
    let totalRows: Int
    /// Carried over from the table so the shortened-table notice still applies to the profile.
    let truncation: SafeTable.Truncation
    let tableNotes: [TableNote]

    static func make(from table: SafeTable, limits: Limits = Limits()) -> SafeDataProfile {
        let profiledRows = min(table.rows.count, limits.maximumRows)
        let tokenBytes = Array(concealmentToken.utf8)
        let duplicates = duplicateNames(in: table.columns, tokenBytes: tokenBytes)
        var columns: [Column] = []
        columns.reserveCapacity(table.columns.count)
        for (index, name) in table.columns.enumerated() {
            let isConcealed = SecretFieldPolicy.isSensitive(name)
                || containsToken(name, tokenBytes)
                || table.rows.contains { index < $0.count && containsToken($0[index], tokenBytes) }
            if isConcealed {
                columns.append(Column(name: name, type: .concealed, missing: missingCount(in: table, column: index, rows: profiledRows),
                                      distinct: nil, minimum: nil, maximum: nil, mean: nil,
                                      commonValues: [], histogram: nil, notes: []))
            } else {
                var accumulator = ColumnAccumulator(limits: limits)
                accumulator.consume(table, column: index, rows: profiledRows)
                columns.append(accumulator.finish(name: name, repeatsName: duplicates.contains(index)))
            }
        }
        var notes: [TableNote] = []
        if profiledRows < table.rows.count { notes.append(.sampled(profiled: profiledRows, total: table.rows.count)) }
        // The header's own width is the reference; without it the table width is the best available.
        let expectedFields = min(table.headerFieldCount ?? table.columns.count, table.columns.count)
        let ragged = table.rows.prefix(profiledRows).reduce(0) { $0 + ($1.count == expectedFields ? 0 : 1) }
        if ragged > 0 { notes.append(.raggedRows(ragged)) }
        if !duplicates.isEmpty { notes.append(.duplicateNames(duplicates.count)) }
        let concealed = columns.reduce(0) { $0 + ($1.type == .concealed ? 1 : 0) }
        if concealed > 0 { notes.append(.concealedColumns(concealed)) }
        return SafeDataProfile(columns: columns, profiledRows: profiledRows, totalRows: table.rows.count,
                               truncation: table.truncation, tableNotes: notes)
    }

    // MARK: Privacy

    /// Searches UTF-8 code units, not characters: a combining mark after the token merges with its last
    /// bullet into one grapheme, so `String.contains` would miss a token that is still in the text.
    static func containsToken(_ text: String, _ token: [UInt8]) -> Bool {
        // Most cells are shorter than the token; the length check is O(1) and spares reading their bytes.
        guard text.utf8.count >= token.count, let first = token.first else { return false }
        return withUTF8Bytes(of: text) { bytes in
            token.withUnsafeBufferPointer { token in
                var index = 0
                let last = bytes.count - token.count
                while index <= last {
                    if bytes[index] == first, memcmp(bytes.baseAddress! + index, token.baseAddress!, token.count) == 0 { return true }
                    index += 1
                }
                return false
            }
        }
    }

    private static func missingCount(in table: SafeTable, column: Int, rows: Int) -> Int {
        var missing = 0
        for row in 0..<rows {
            guard column < table.rows[row].count else { missing += 1; continue }
            if withUTF8Bytes(of: table.rows[row][column], { DataProfileValueClassifier.classify($0).isBlank }) { missing += 1 }
        }
        return missing
    }

    // MARK: Table level

    /// Indexes of columns whose name another column also has. Titles are compared by exact code units, so
    /// two spellings that merely look alike stay distinct, as they do in a spreadsheet. A concealed title
    /// is a placeholder, not a name, and never counts.
    private static func duplicateNames(in titles: [String], tokenBytes: [UInt8]) -> Set<Int> {
        var firstIndex: [ExactText: Int] = [:]
        var duplicates: Set<Int> = []
        for (index, title) in titles.enumerated() where !containsToken(title, tokenBytes) {
            if let first = firstIndex[ExactText(title)] {
                duplicates.insert(first)
                duplicates.insert(index)
            } else {
                firstIndex[ExactText(title)] = index
            }
        }
        return duplicates
    }
}

// MARK: - Per-column accumulation

/// Single-column working state. It lives for one pass over at most `Limits.maximumRows` cells.
private struct ColumnAccumulator {
    struct Extreme {
        let value: Double
        let text: String
    }

    let limits: SafeDataProfile.Limits
    private var kindCounts = [Int](repeating: 0, count: DataProfileValueClassifier.Kind.allCases.count)
    private var dateFormats = 0
    private var missing = 0
    private var leadingZeros = 0
    private var whitespace = 0
    private var tally: DataProfileTally
    private var numbers: [Double] = []
    private var sum = 0.0
    private var lowest: Extreme?
    private var highest: Extreme?
    private var earliest: Extreme?
    private var latest: Extreme?

    init(limits: SafeDataProfile.Limits) {
        self.limits = limits
        tally = DataProfileTally(maximumDistinct: limits.maximumDistinctValues)
    }

    mutating func consume(_ table: SafeTable, column: Int, rows: Int) {
        for row in 0..<rows {
            let cells = table.rows[row]
            guard column < cells.count else { missing += 1; continue }
            let text = cells[column]
            // One read of the bytes serves the classification and the frequency count.
            withUTF8Bytes(of: text) { bytes in
                let facts = DataProfileValueClassifier.classify(bytes)
                guard !facts.isBlank else { missing += 1; return }
                kindCounts[facts.kind.rawValue] += 1
                if facts.hasLeadingZeros { leadingZeros += 1 }
                if facts.hasSurroundingWhitespace { whitespace += 1 }
                if let number = facts.number {
                    numbers.append(number)
                    sum += number
                    if lowest.map({ number < $0.value }) ?? true { lowest = Extreme(value: number, text: text) }
                    if highest.map({ number > $0.value }) ?? true { highest = Extreme(value: number, text: text) }
                }
                if let format = facts.dateFormat { dateFormats |= 1 << format.rawValue }
                if let timestamp = facts.timestamp {
                    if earliest.map({ timestamp < $0.value }) ?? true { earliest = Extreme(value: timestamp, text: text) }
                    if latest.map({ timestamp > $0.value }) ?? true { latest = Extreme(value: timestamp, text: text) }
                }
                tally.record(text, bytes: bytes, row: row)
            }
        }
    }

    func finish(name: String, repeatsName: Bool) -> SafeDataProfile.Column {
        typealias Kind = DataProfileValueClassifier.Kind
        let counts = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, kindCounts[$0.rawValue]) })
        let nonEmpty = kindCounts.reduce(0, +)
        let numeric = counts[.integer, default: 0] + counts[.decimal, default: 0]
        let type: SafeDataProfile.ColumnType
        if nonEmpty == 0 {
            type = .empty
        } else if numeric == nonEmpty {
            type = counts[.decimal, default: 0] > 0 ? .decimal : .integer
        } else if let only = Kind.allCases.first(where: { counts[$0] == nonEmpty }) {
            type = Self.columnType(of: only)
        } else {
            type = .mixed
        }
        var notes: [SafeDataProfile.Note] = []
        if type == .mixed {
            let breakdown = Kind.allCases.compactMap { kind in
                counts[kind, default: 0] > 0 ? SafeDataProfile.TypeCount(type: Self.columnType(of: kind), count: counts[kind, default: 0]) : nil
            }
            // Largest first; the stable order of the kinds breaks ties.
            notes.append(.mixedTypes(breakdown.enumerated().sorted { $0.element.count != $1.element.count
                ? $0.element.count > $1.element.count : $0.offset < $1.offset }.map(\.element)))
        }
        if leadingZeros > 0 { notes.append(.leadingZeros(leadingZeros)) }
        let formats = SafeDataProfile.DateFormat.allCases.filter { dateFormats & (1 << $0.rawValue) != 0 }
        if formats.count > 1 { notes.append(.inconsistentDateFormats(formats)) }
        if whitespace > 0 { notes.append(.surroundingWhitespace(whitespace)) }
        if repeatsName { notes.append(.duplicateName) }

        let isNumeric = type == .integer || type == .decimal
        // A minimum and maximum need an order the file itself defines: numbers, and ISO dates only,
        // because `mm/dd` and `dd/mm` cannot be told apart from the text.
        let isISODate = type == .date && formats == [.iso]
        let extremes = isNumeric ? (lowest, highest) : isISODate ? (earliest, latest) : (nil, nil)
        let histogram: SafeDataProfile.Histogram?
        if isNumeric, let low = extremes.0, let high = extremes.1 {
            histogram = Self.histogram(of: numbers, low: low, high: high)
        } else {
            histogram = nil
        }
        return SafeDataProfile.Column(
            name: name, type: type, missing: missing,
            distinct: .init(count: tally.distinctCount, isLowerBound: tally.reachedLimit),
            minimum: extremes.0?.text, maximum: extremes.1?.text,
            mean: isNumeric && !numbers.isEmpty ? sum / Double(numbers.count) : nil,
            commonValues: isNumeric || type == .empty ? [] : tally.mostFrequent(limits.commonValueCount)
                .map { SafeDataProfile.ValueCount(value: $0.text, count: $0.count) },
            histogram: histogram, notes: notes)
    }

    private static func columnType(of kind: DataProfileValueClassifier.Kind) -> SafeDataProfile.ColumnType {
        switch kind {
        case .integer: .integer
        case .decimal: .decimal
        case .boolean: .boolean
        case .date: .date
        case .text: .text
        }
    }

    private static func histogram(of numbers: [Double], low: Extreme, high: Extreme) -> SafeDataProfile.Histogram {
        let binCount = SafeDataProfile.histogramBinCount
        var bins = [Int](repeating: 0, count: binCount)
        // Halving first keeps the span finite even for values near the Double limits.
        let origin = low.value * 0.5
        let span = high.value * 0.5 - origin
        for number in numbers {
            let position = span > 0 ? (number * 0.5 - origin) / span : 0
            bins[min(max(Int(position * Double(binCount)), 0), binCount - 1)] += 1
        }
        return .init(bins: bins, lower: low.text, upper: high.text)
    }
}

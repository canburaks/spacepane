import Foundation

/// The profile as a table of its own: one row per source column. Everything displayed comes from the
/// `SafeDataProfile`, so the existing native table view shows it with the same selection, copy and
/// accessibility behavior as the data table.
extension SafeDataProfile {
    /// The profile's columns, in display order.
    enum Field: Int, CaseIterable {
        case column, type, missing, distinct, minimum, maximum, mean, common, distribution, notes

        var title: PreviewStrings.Key {
            switch self {
            case .column: .profileHeaderColumn
            case .type: .profileHeaderType
            case .missing: .profileHeaderMissing
            case .distinct: .profileHeaderDistinct
            case .minimum: .profileHeaderMinimum
            case .maximum: .profileHeaderMaximum
            case .mean: .profileHeaderMean
            case .common: .profileHeaderCommon
            case .distribution: .profileHeaderDistribution
            case .notes: .profileHeaderNotes
            }
        }
    }

    /// Eight levels, lowest to highest. An empty range always draws the lowest bar.
    private static let sparkBars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    /// Separates items inside one table cell. Purely visual: the spoken form uses a localized list.
    private static let itemSeparator = " · "

    func displayTable(locale: Locale) -> SafeTable {
        let formats = ProfileFormats(locale: locale)
        var descriptions: [SafeTable.CellPosition: String] = [:]
        var rows: [[String]] = []
        rows.reserveCapacity(columns.count)
        for (rowIndex, column) in columns.enumerated() {
            var cells = [String](repeating: "", count: Field.allCases.count)
            cells[Field.column.rawValue] = column.name
            cells[Field.type.rawValue] = PreviewStrings.text(Self.typeTitle(column.type))
            cells[Field.missing.rawValue] = PreviewStrings.format(
                .profileMissingValue, arguments: [formats.count(column.missing), formats.share(column.missing, of: profiledRows)],
                locale: locale)
            if let distinct = column.distinct {
                let count = formats.count(distinct.count)
                cells[Field.distinct.rawValue] = distinct.isLowerBound
                    ? PreviewStrings.format(.profileDistinctAtLeast, arguments: [count], locale: locale) : count
            }
            cells[Field.minimum.rawValue] = column.minimum ?? ""
            cells[Field.maximum.rawValue] = column.maximum ?? ""
            if let mean = column.mean { cells[Field.mean.rawValue] = formats.mean(mean) }
            if !column.commonValues.isEmpty {
                let items = column.commonValues.map {
                    PreviewStrings.format(.profileCommonValue, arguments: [$0.value, formats.count($0.count)], locale: locale)
                }
                cells[Field.common.rawValue] = items.joined(separator: Self.itemSeparator)
                if items.count > 1 {
                    descriptions[.init(row: rowIndex, column: Field.common.rawValue)] = formats.list.string(from: items)
                }
            }
            if let histogram = column.histogram {
                cells[Field.distribution.rawValue] = Self.sparkline(for: histogram.bins)
                descriptions[.init(row: rowIndex, column: Field.distribution.rawValue)] = PreviewStrings.format(
                    .profileDistributionDescription,
                    arguments: [histogram.lower, histogram.upper, formats.count(histogram.bins.count),
                                formats.list.string(from: histogram.bins.map(formats.count)) ?? ""],
                    locale: locale)
            }
            if !column.notes.isEmpty {
                let items = column.notes.map { Self.noteText($0, formats: formats, locale: locale) }
                cells[Field.notes.rawValue] = items.joined(separator: Self.itemSeparator)
                if items.count > 1 {
                    descriptions[.init(row: rowIndex, column: Field.notes.rawValue)] = formats.list.string(from: items)
                }
            }
            rows.append(cells)
        }
        return SafeTable(columns: Field.allCases.map { PreviewStrings.text($0.title) }, rows: rows,
                         truncation: truncation, headerFieldCount: Field.allCases.count, cellDescriptions: descriptions,
                         origin: .profile)
    }

    /// Table-level notes for the status line, one localized sentence each.
    func statusLines(locale: Locale) -> [String] {
        lines(for: tableNotes, locale: locale)
    }

    /// The notes the preview shows. Sampling and concealed-column notes are left out (owner, 2026-10-15): the
    /// limits strip already says how many rows the profile uses, and concealment is visible in the cells.
    func noteLines(locale: Locale) -> [String] {
        lines(for: tableNotes.filter { note in
            switch note {
            case .sampled, .concealedColumns: false
            case .raggedRows, .duplicateNames: true
            }
        }, locale: locale)
    }

    private func lines(for notes: [TableNote], locale: Locale) -> [String] {
        let formats = ProfileFormats(locale: locale)
        return notes.map { note in
            switch note {
            case .sampled(let profiled, let total):
                PreviewStrings.format(.profileStatusSampled, arguments: [formats.count(profiled), formats.count(total)], locale: locale)
            case .raggedRows(let count):
                PreviewStrings.format(.profileStatusRaggedRows, arguments: [formats.count(count)], locale: locale)
            case .duplicateNames(let count):
                PreviewStrings.format(.profileStatusDuplicateNames, arguments: [formats.count(count)], locale: locale)
            case .concealedColumns:
                PreviewStrings.text(.profileStatusConcealed)
            }
        }
    }

    static func typeTitle(_ type: ColumnType) -> PreviewStrings.Key {
        switch type {
        case .empty: .profileTypeEmpty
        case .integer: .profileTypeInteger
        case .decimal: .profileTypeDecimal
        case .boolean: .profileTypeBoolean
        case .date: .profileTypeDate
        case .text: .profileTypeText
        case .mixed: .profileTypeMixed
        case .concealed: .profileTypeConcealed
        }
    }

    /// One bar per range, scaled to the fullest. A range with any value never draws the lowest bar, so
    /// an empty range and a sparse one stay distinguishable.
    static func sparkline(for bins: [Int]) -> String {
        let fullest = bins.max() ?? 0
        guard fullest > 0 else { return String(repeating: sparkBars[0], count: bins.count) }
        let levels = sparkBars.count - 1
        return String(bins.map { count in
            count == 0 ? sparkBars[0] : sparkBars[1 + min(Int(Double(count) / Double(fullest) * Double(levels)), levels - 1)]
        })
    }

    private static func noteText(_ note: Note, formats: ProfileFormats, locale: Locale) -> String {
        switch note {
        case .mixedTypes(let counts):
            let items = counts.map {
                PreviewStrings.format(.profileNoteMixedItem, arguments: [PreviewStrings.text(typeTitle($0.type)), formats.count($0.count)],
                                      locale: locale)
            }
            return PreviewStrings.format(.profileNoteMixed, arguments: [formats.list.string(from: items) ?? ""], locale: locale)
        case .leadingZeros(let count):
            return PreviewStrings.format(.profileNoteLeadingZeros, arguments: [formats.count(count)], locale: locale)
        case .inconsistentDateFormats(let dateFormats):
            // Patterns are technical identifiers, not translatable text.
            return PreviewStrings.format(.profileNoteDateFormats, arguments: [formats.list.string(from: dateFormats.map(\.pattern)) ?? ""],
                                         locale: locale)
        case .surroundingWhitespace(let count):
            return PreviewStrings.format(.profileNoteWhitespace, arguments: [formats.count(count)], locale: locale)
        case .duplicateName:
            return PreviewStrings.text(.profileNoteDuplicateName)
        }
    }
}

private extension DataProfileValueClassifier.DateFormat {
    var pattern: String {
        switch self {
        case .iso: "yyyy-mm-dd"
        case .monthDayYear: "mm/dd/yyyy"
        case .dotted: "dd.mm.yyyy"
        }
    }
}

/// Locale-aware number and list formatting, built once per rendering of the profile.
private struct ProfileFormats {
    let list: ListFormatter
    private let integer: NumberFormatter
    private let percent: NumberFormatter
    private let precisePercent: NumberFormatter
    private let decimal: NumberFormatter
    private let scientific: NumberFormatter

    init(locale: Locale) {
        list = ListFormatter()
        list.locale = locale
        integer = Self.formatter(.decimal, locale: locale)
        integer.maximumFractionDigits = 0
        percent = Self.formatter(.percent, locale: locale)
        percent.maximumFractionDigits = 1
        precisePercent = Self.formatter(.percent, locale: locale)
        precisePercent.maximumFractionDigits = 2
        decimal = Self.formatter(.decimal, locale: locale)
        scientific = Self.formatter(.scientific, locale: locale)
        scientific.maximumSignificantDigits = 6
    }

    private static func formatter(_ style: NumberFormatter.Style, locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = style
        return formatter
    }

    func count(_ value: Int) -> String { integer.string(from: NSNumber(value: value)) ?? String(value) }

    /// A part of the profiled rows. A nonzero share that would round to zero keeps a second digit, so a
    /// few missing values never read as none.
    func share(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return percent.string(from: 0) ?? "0" }
        let fraction = Double(part) / Double(whole)
        let rounded = percent.string(from: NSNumber(value: fraction)) ?? ""
        if part > 0, percent.number(from: rounded)?.doubleValue == 0 { return precisePercent.string(from: NSNumber(value: fraction)) ?? rounded }
        return rounded
    }

    /// Two digits after the point for ordinary magnitudes, more for small ones so they stay readable,
    /// scientific notation only for magnitudes a plain number cannot show usefully.
    func mean(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude >= 1e15 || (magnitude > 0 && magnitude < 1e-9) {
            return scientific.string(from: NSNumber(value: value)) ?? String(value)
        }
        // Below one, keep three significant digits: count the zeros after the point and add three.
        let digits = magnitude > 0 && magnitude < 1 ? Int(-floor(log10(magnitude))) + 2 : 2
        decimal.maximumFractionDigits = min(digits, 12)
        return decimal.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Computes the profile the first time it is needed and keeps it for the lifetime of one presentation.
/// A new presentation or locale builds new modes, which drops the cache with them. The profile reads
/// only the already-concealed table it was created with.
final class LazyDataProfile {
    struct Result {
        let profile: SafeDataProfile
        let table: SafeTable
        let statusLines: [String]
        let noteLines: [String]
    }

    private let source: SafeTable
    private let locale: Locale
    private var result: Result?

    init(source: SafeTable, locale: Locale) {
        self.source = source
        self.locale = locale
    }

    /// False until the Profile mode is first shown, so previews that never open it pay nothing.
    var isComputed: Bool { result != nil }

    var value: Result {
        if let result { return result }
        let profile = SafeDataProfile.make(from: source)
        // The profile covers the rows the source table read, so it is a partial read exactly when the source is.
        var table = profile.displayTable(locale: locale)
        table.isPartialRead = source.isPartialRead
        let computed = Result(profile: profile, table: table, statusLines: profile.statusLines(locale: locale),
                              noteLines: profile.noteLines(locale: locale))
        result = computed
        return computed
    }
}

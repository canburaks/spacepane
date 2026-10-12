import Foundation
import PreviewContracts

/// One cell of a data table. A cell never holds binary content, only its length.
enum DataCell {
    case text(String)
    case null
    case binary(byteCount: Int)
    /// Parts joined by the view; a part may be concealed on its own, which keeps the rest readable.
    case segments([(text: String, sensitive: Bool)])

    var utf8Count: Int {
        switch self {
        case .text(let text): text.utf8.count
        case .null, .binary: 4
        case .segments(let parts): parts.reduce(0) { $0 + $1.text.utf8.count + 2 }
        }
    }

    func summary(sensitive: Bool) -> SummaryValue {
        switch self {
        case .text(let text): .string(text, sensitive: sensitive)
        case .null: .null
        case .binary(let count): .object([(DataSummaryKeys.binaryByteCount, .integer(count))])
        case .segments(let parts): .array(parts.map { .string($0.text, sensitive: sensitive || $0.sensitive) })
        }
    }
}

/// Builds the bounded `table` member of a data summary. Rows and columns beyond the limits are
/// dropped and flagged. Values in a column whose name looks secret are concealed in every row.
///
/// The limits keep the whole document inside what the native views derive from: 20,000 outline
/// nodes and 256 Ki UTF-16 units. Concealed text has the same size as the original, so the
/// estimate counts the unconcealed bytes.
struct DataTable {
    struct Limits {
        var maximumRows = 100
        var maximumColumns = 20
        var maximumCellCharacters = 200
        var maximumBytes = 120_000
    }

    enum ColumnKind {
        /// Technical identifiers that a view may translate.
        case identifiers
        /// Names taken from the document; shown verbatim.
        case documentNames
    }

    let kind: ColumnKind
    let columns: [String]
    let limits: Limits
    private let sensitiveColumns: Set<Int>
    private(set) var rows: [[DataCell]] = []
    private(set) var truncated: Bool
    private var estimatedBytes: Int

    init(kind: ColumnKind, columns: [String], limits: Limits = Limits(), alreadyTruncated: Bool = false) {
        self.kind = kind
        self.limits = limits
        let kept = Array(columns.prefix(limits.maximumColumns))
        self.columns = kept
        truncated = alreadyTruncated || columns.count > kept.count
        sensitiveColumns = kind == .documentNames
            ? Set(kept.indices.filter { SecretFieldPolicy.isSensitive(kept[$0]) }) : []
        estimatedBytes = kept.reduce(0) { $0 + $1.utf8.count + 4 }
    }

    var isFull: Bool { rows.count >= limits.maximumRows || estimatedBytes >= limits.maximumBytes }
    var columnCount: Int { columns.count }

    /// Adds a row; returns false (and marks the table truncated) once a limit is reached.
    @discardableResult
    mutating func append(_ cells: [DataCell]) -> Bool {
        guard !isFull else { truncated = true; return false }
        if cells.count > columns.count { truncated = true }
        var kept: [DataCell] = []
        kept.reserveCapacity(columns.count)
        for cell in cells.prefix(columns.count) {
            let (clipped, wasClipped) = clip(cell)
            if wasClipped { truncated = true }
            estimatedBytes += clipped.utf8Count + 4
            kept.append(clipped)
        }
        rows.append(kept)
        return true
    }

    /// Notes that the source held more rows than were appended.
    mutating func markTruncated() { truncated = true }

    var summary: SummaryValue {
        let names: [SummaryValue] = columns.map { .string($0) }
        let body: [SummaryValue] = rows.map { row in
            .array(row.enumerated().map { index, cell in cell.summary(sensitive: sensitiveColumns.contains(index)) })
        }
        return .object([
            (kind == .identifiers ? DataSummaryKeys.columns : DataSummaryKeys.columnNames, .array(names)),
            (DataSummaryKeys.rows, .array(body)),
            (DataSummaryKeys.truncated, .boolean(truncated))
        ])
    }

    private func clip(_ cell: DataCell) -> (DataCell, Bool) {
        switch cell {
        case .text(let text):
            let (clipped, wasClipped) = Self.clip(text, to: limits.maximumCellCharacters)
            return (.text(clipped), wasClipped)
        case .segments(let parts):
            // Only the leading parts are kept once the cell is long enough; a part is never cut,
            // because that could split a concealed value from its marker.
            var kept: [(text: String, sensitive: Bool)] = []
            var length = 0
            for part in parts {
                if length >= limits.maximumCellCharacters {
                    return (.segments(kept + [("…", false)]), true)
                }
                let (text, wasClipped) = Self.clip(part.text, to: limits.maximumCellCharacters - length)
                kept.append((text, part.sensitive))
                length += text.count
                if wasClipped { return (.segments(kept), true) }
            }
            return (.segments(kept), false)
        case .null, .binary: return (cell, false)
        }
    }

    /// Clips at a character boundary, marking the cut with an ellipsis.
    static func clip(_ text: String, to characters: Int) -> (String, Bool) {
        guard text.utf8.count > characters else { return (text, false) }
        guard text.count > characters else { return (text, false) }
        return (String(text.prefix(max(0, characters - 1))) + "…", true)
    }
}

/// Assembles a data summary document from named members and writes it with shared concealment.
enum DataDocument {
    static func make(_ members: [(String, SummaryValue)], context: RequestContext,
                     facts: PresentationFacts = .none) throws -> ParsedTextDocument {
        var writer = SummaryWriter(context: context)
        return try writer.document(.object(members), facts: facts)
    }

    /// Ordinary text members are omitted when empty instead of being written as empty strings.
    static func string(_ text: String?, clippedTo characters: Int = 200) -> SummaryValue? {
        guard let text, !text.isEmpty else { return nil }
        return .string(DataTable.clip(text, to: characters).0)
    }
}

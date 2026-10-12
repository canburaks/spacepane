import CoreGraphics
import Foundation
import PreviewContracts

/// Semantic ink for a drawn run. The renderer owns the paired light-page colors.
public enum ThumbnailTone: Sendable, CaseIterable {
    case text, muted, key, string, number, literal, keyword, comment, tag, heading, addition, deletion
}

public enum ThumbnailEmphasis: Equatable, Sendable { case normal, heading }

public struct ThumbnailRun: Equatable, Sendable {
    public let text: String
    public let tone: ThumbnailTone
    public init(_ text: String, tone: ThumbnailTone = .text) {
        self.text = text
        self.tone = tone
    }
}

/// One drawn text line. `indent` and every run are measured in cells and already fit the page.
public struct ThumbnailLine: Equatable, Sendable {
    public let indent: Int
    public let runs: [ThumbnailRun]
    public let emphasis: ThumbnailEmphasis
    public init(indent: Int = 0, runs: [ThumbnailRun], emphasis: ThumbnailEmphasis = .normal) {
        self.indent = indent
        self.runs = runs
        self.emphasis = emphasis
    }
    public static let blank = ThumbnailLine(runs: [])
    public var rowCost: Double { emphasis == .heading ? ThumbnailMetrics.headingRowCost : 1 }
    public var text: String { runs.map(\.text).joined() }
}

public struct ThumbnailTextPage: Equatable, Sendable {
    public let lines: [ThumbnailLine]
    public init(lines: [ThumbnailLine]) { self.lines = lines }
}

/// A table's shape, never its cell values. Kinds describe only a bounded concealed sample;
/// `unknown` means that no sample can establish the kind (for example a schema-only preview).
public struct ThumbnailGrid: Equatable, Sendable {
    public enum ColumnKind: Equatable, Sendable { case text, numeric, empty, unknown }
    public static let maximumColumns = 8
    public static let maximumSampleRows = 6
    /// Document headers only; app-authored schema identifiers are omitted.
    public let headers: [String]
    public let columnKinds: [ColumnKind]
    public let rowCount: Int
    public let columnCount: Int
    public let columnsAreLowerBound: Bool
    public let rowsAreLowerBound: Bool
    public let tableCount: Int?
    public let tablesAreLowerBound: Bool
    public let sampleRowCount: Int
    /// Locale-formatted column × row counts, followed by an optional table-count symbol.
    /// It holds no cell, path or source metadata.
    public let countLine: String

    public init?(headers: [String], columnKinds: [ColumnKind], rowCount: Int, columnCount: Int,
                 rowsAreLowerBound: Bool, sampleRowCount: Int, columnsAreLowerBound: Bool = false, tableCount: Int? = nil,
                 tablesAreLowerBound: Bool = false, locale: Locale = .current) {
        guard rowCount >= 0, columnCount > 0, sampleRowCount >= 0, tableCount.map({ $0 >= 0 }) ?? true else { return nil }
        self.headers = headers.prefix(min(columnCount, Self.maximumColumns)).map {
            ThumbnailGridText.clip(ThumbnailGridText.cell(ThumbnailDrawnText.sanitizedText($0)), to: 16)
        }
        self.columnKinds = Array(columnKinds.prefix(min(columnCount, Self.maximumColumns)))
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.columnsAreLowerBound = columnsAreLowerBound
        self.rowsAreLowerBound = rowsAreLowerBound
        self.sampleRowCount = min(sampleRowCount, min(rowCount, Self.maximumSampleRows))
        self.tableCount = tableCount
        self.tablesAreLowerBound = tablesAreLowerBound
        func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
        var line = number(columnCount) + (columnsAreLowerBound ? "+" : "") + " × " + number(rowCount) + (rowsAreLowerBound ? "+" : "")
        if let tableCount { line += " · ⊞ " + number(tableCount) + (tablesAreLowerBound ? "+" : "") }
        countLine = line
    }
}

/// A decoded document picture; the pixel size is already bounded by the request.
public struct ThumbnailPicture: Sendable {
    public let image: CGImage
    public let role: PreviewImage.Role
    public init(image: CGImage, role: PreviewImage.Role) {
        self.image = image
        self.role = role
    }
}

public enum ThumbnailContent: Sendable {
    case text(ThumbnailTextPage)
    case grid(ThumbnailGrid)
    case picture(ThumbnailPicture)

    /// Every string this content can draw. Privacy tests and review read this one place.
    public var drawnStrings: [String] {
        switch self {
        case .text(let page): page.lines.map(\.text)
        case .grid(let grid): grid.headers + [grid.countLine]
        case .picture: []
        }
    }
}

/// Everything the renderer needs: nothing in it refers back to the file.
public struct ThumbnailScene: Sendable {
    public let content: ThumbnailContent
    public let metrics: ThumbnailMetrics
    /// False when the user's syntax style asks for no color; thumbnails then draw in one ink.
    public let usesColor: Bool
    public init(content: ThumbnailContent, metrics: ThumbnailMetrics, usesColor: Bool = true) {
        self.content = content
        self.metrics = metrics
        self.usesColor = usesColor
    }
}

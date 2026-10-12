import Foundation
import SQLite3
import SQLiteSafetyShim
import PreviewContracts

/// The only SQLite connection is private in-memory storage. It never receives a source URL.
public struct SQLiteInspectionAdapter: BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try ContainerLimits(context: context).validateInput(input.data)
        guard input.data.count >= 100, input.data.prefix(16) == Data("SQLite format 3\0".utf8) else { throw PreviewFailure.malformedDocument }
        guard input.data[18] == 1, input.data[19] == 1 else { throw PreviewFailure.unavailableContent }
        var database: OpaquePointer?
        guard sqlite3_open_v2(":memory:", &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else { throw PreviewFailure.unavailableContent }
        defer { sqlite3_close(database) }
        guard let allocation = sqlite3_malloc64(UInt64(input.data.count)) else { throw PreviewFailure.inputTooLarge }
        input.data.copyBytes(to: allocation.assumingMemoryBound(to: UInt8.self), count: input.data.count)
        let memory = allocation.assumingMemoryBound(to: UInt8.self)
        let status = sqlite3_deserialize(database, "main", memory, Int64(input.data.count), Int64(input.data.count),
                                         UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_READONLY))
        guard status == SQLITE_OK else { sqlite3_free(allocation); throw PreviewFailure.malformedDocument }
        guard preview_sqlite_configure(database) == SQLITE_OK else { throw PreviewFailure.unavailableContent }
        sqlite3_limit(database, SQLITE_LIMIT_COLUMN, 50)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, Int32(min(context.budget.maxInputBytes, 16_777_216)))
        sqlite3_limit(database, SQLITE_LIMIT_SQL_LENGTH, 65_536)
        sqlite3_limit(database, SQLITE_LIMIT_EXPR_DEPTH, 64)
        sqlite3_limit(database, SQLITE_LIMIT_COMPOUND_SELECT, 4)
        sqlite3_limit(database, SQLITE_LIMIT_VDBE_OP, 100_000)
        sqlite3_busy_timeout(database, 0)
        // Neither a schema function nor an attacker supplied extension can gain code execution.
        guard sqlite3_exec(database, "PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; PRAGMA temp_store=MEMORY;", nil, nil, nil) == SQLITE_OK else {
            throw PreviewFailure.malformedDocument
        }
        sqlite3_set_authorizer(database, { _, operation, pragma, _, _, _ in
            switch operation {
            case SQLITE_SELECT, SQLITE_READ, SQLITE_FUNCTION: return SQLITE_OK
            case SQLITE_PRAGMA:
                // Only the four read-only introspection pragmas behind the schema grid. Every other
                // pragma, including any that could write or change connection behavior, is denied.
                guard let pragma else { return SQLITE_DENY }
                return SQLiteInspectionAdapter.introspectionPragmas.contains(String(cString: pragma)) ? SQLITE_OK : SQLITE_DENY
            default: return SQLITE_DENY
            }
        }, nil)
        let progress = SQLiteProgress(context: context)
        let pointer = Unmanaged.passUnretained(progress).toOpaque()
        sqlite3_progress_handler(database, 200, { pointer in
            guard let pointer else { return 1 }
            let progress = Unmanaged<SQLiteProgress>.fromOpaque(pointer).takeUnretainedValue()
            do {
                try progress.context.checkpoint()
                guard ContinuousClock.now < progress.statementDeadline else { throw PreviewFailure.deadlineExceeded }
                return 0
            }
            catch { progress.failure = error; return 1 }
        }, pointer)
        defer { sqlite3_progress_handler(database, 0, nil, nil) }
        let schema = try statement(database, sql: "SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE type IN ('table','index','view','trigger') ORDER BY type,name", context: context, progress: progress)
        defer { sqlite3_finalize(schema) }
        var objects: [SummaryValue] = []
        var tables: [(String, Bool)] = []
        let maxObjects = min(200, max(1, context.budget.maxJSONNodes / 16))
        var schemaPartial = false
        while try step(schema, database: database, context: context, progress: progress) {
            if objects.count >= maxObjects { schemaPartial = true; break }
            let type = text(schema, column: 0)
            let name = text(schema, column: 1)
            let owner = text(schema, column: 2)
            let sql = text(schema, column: 3)
            guard sql.utf8.count <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
            // View definitions, trigger bodies and virtual table modules are displayed but never evaluated.
            let virtual = sql.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("CREATE VIRTUAL TABLE")
            if type == "table", !name.hasPrefix("sqlite_"), !virtual { tables.append((name, SecretFieldPolicy.isSensitive(name))) }
            objects.append(.object([
                ("type", .string(type)), ("name", .string(name)), ("table", .string(owner)),
                ("sql", .string(sql, sensitive: schemaMayContainSecrets(sql))), ("virtual", .boolean(virtual))
            ]))
        }
        var pages: [SummaryValue] = []
        var gridFacts = PresentationFacts.none
        var remainingRows = min(200, max(1, context.budget.maxJSONNodes / 16))
        var remainingCells = min(10_000, max(1, context.budget.maxJSONNodes / 12))
        for (table, sensitiveTable) in tables {
            try context.checkpoint()
            guard remainingRows > 0 else { break }
            let probe = try statement(database, sql: "SELECT * FROM \(quoted(table)) LIMIT 0", context: context, progress: progress)
            let count = Int(sqlite3_column_count(probe))
            guard count <= 50 else { sqlite3_finalize(probe); throw PreviewFailure.tooManyNodes }
            var names: [String] = []
            for index in 0..<count { names.append(String(cString: sqlite3_column_name(probe, Int32(index)))) }
            sqlite3_finalize(probe)
            guard count > 0, remainingCells >= count else { break }
            let rowAllowance = min(remainingRows, remainingCells / count)
            // Read lengths for blobs; never materialize blob contents into a presentation.
            let projection = names.flatMap { name -> [String] in
                let column = quoted(name)
                return ["typeof(\(column))", "CASE WHEN typeof(\(column))='blob' THEN length(\(column)) ELSE CAST(substr(CAST(\(column) AS BLOB),1,4096) AS TEXT) END", "length(CAST(\(column) AS BLOB))"]
            }.joined(separator: ",")
            // Projection has three expressions per source column; adjust only this connection.
            sqlite3_limit(database, SQLITE_LIMIT_COLUMN, 150)
            let rows = try statement(database, sql: "SELECT \(projection) FROM \(quoted(table)) LIMIT \(rowAllowance + 1)", context: context, progress: progress)
            defer { sqlite3_finalize(rows) }
            var pageRows: [SummaryValue] = []
            var partial = false
            while try step(rows, database: database, context: context, progress: progress) {
                if pageRows.count >= rowAllowance { partial = true; break }
                var cells: [(String, SummaryValue)] = []
                for (index, name) in names.enumerated() {
                    let kind = text(rows, column: Int32(index * 3))
                    let valueColumn = Int32(index * 3 + 1)
                    let originalBytes = max(0, Int(sqlite3_column_int64(rows, Int32(index * 3 + 2))))
                    let sensitive = sensitiveTable || SecretFieldPolicy.isSensitive(name)
                    let value: SummaryValue
                    if kind == "null" { value = .null }
                    else if kind == "blob" { value = .object([("blobBytes", .integer(Int(sqlite3_column_int64(rows, valueColumn))))]) }
                    else {
                        let content = text(rows, column: valueColumn)
                        value = .object([
                            ("value", .string(content, sensitive: sensitive)),
                            ("truncated", .boolean(originalBytes > 4096)), ("sourceType", .string(kind))
                        ])
                    }
                    cells.append((name, value))
                }
                pageRows.append(.object(cells))
            }
            remainingRows -= pageRows.count
            remainingCells -= pageRows.count * count
            // The first nonempty page is the thumbnail's grid. A LIMIT+1 probe proves only a lower
            // bound when more rows exist; no COUNT(*) scan is introduced for presentation facts.
            if gridFacts.isEmpty, !pageRows.isEmpty {
                gridFacts = PresentationFacts([.grid(rows: pageRows.count, columns: count, rowsAreLowerBound: partial)])
            }
            pages.append(.object([
                ("table", .string(table)), ("columns", .array(names.map { .string($0) })),
                ("offset", .integer(0)), ("loadedRows", .integer(pageRows.count)),
                ("partial", .boolean(partial)), ("rows", .array(pageRows))
            ]))
        }
        try context.checkpoint()
        // The schema grid is an addition to the summary; an introspection failure other than
        // cancellation or the deadline leaves it out rather than losing the whole preview.
        var grid: DataTable?
        do { grid = try schemaGrid(database, tables: tables, context: context, progress: progress) }
        catch let failure as PreviewFailure where failure != .deadlineExceeded { grid = nil }
        var writer = SummaryWriter(context: context)
        var members: [(String, SummaryValue)] = [
            ("databaseFormat", .string("SQLite")), ("sourceReadOnly", .boolean(true)),
            ("schemaPartial", .boolean(schemaPartial)), ("schema", .array(objects)),
            ("rowLimit", .integer(200)), ("cellByteLimit", .integer(4096)),
            ("tablesWithRows", .integer(pages.count)), ("tableCount", .integer(tables.count)),
            ("pages", .array(pages))
        ]
        if let grid, !grid.rows.isEmpty { members.append((DataSummaryKeys.table, grid.summary)) }
        return try writer.document(.object(members), facts: gridFacts)
    }

    /// The four read-only pragmas the schema grid uses; the authorizer admits no others.
    static let introspectionPragmas: Set<String> = ["table_xinfo", "foreign_key_list", "index_list", "index_xinfo"]

    // MARK: Schema grid

    private static let gridColumns = ["table", "column", "declaredType", "notNull", "defaultValue",
                                      "primaryKey", "foreignKey", "indexes"]

    private struct ColumnInfo {
        let name: String
        let declaredType: String
        let notNull: Bool
        let defaultValue: String?
        let primaryKeyPosition: Int
    }

    /// One row per column of every ordinary table: declared type, NOT NULL, default, primary-key
    /// position, foreign-key target and the indexes that use it. Everything comes from the four
    /// read-only introspection pragmas on the private snapshot; no table row is read. Defaults of a
    /// column or table whose name looks secret are concealed, like its row values.
    private func schemaGrid(_ database: OpaquePointer, tables: [(String, Bool)], context: RequestContext,
                            progress: SQLiteProgress) throws -> DataTable {
        var grid = DataTable(kind: .identifiers, columns: Self.gridColumns,
                             limits: .init(maximumRows: 300, maximumColumns: 8, maximumCellCharacters: 200, maximumBytes: 120_000))
        for (table, sensitiveTable) in tables {
            try context.checkpoint()
            guard !grid.isFull else { grid.markTruncated(); break }
            let columns = try columnInfo(database, table: table, context: context, progress: progress)
            let references = try foreignKeyTargets(database, table: table, context: context, progress: progress)
            let indexed = try indexedColumns(database, table: table, context: context, progress: progress)
            for column in columns {
                let sensitive = sensitiveTable || SecretFieldPolicy.isSensitive(column.name)
                grid.append([
                    .text(table), .text(column.name), .text(column.declaredType),
                    .text(column.notNull ? "true" : "false"),
                    column.defaultValue.map { DataCell.segments([($0, sensitive)]) } ?? .text(""),
                    .text(column.primaryKeyPosition > 0 ? String(column.primaryKeyPosition) : ""),
                    .text((references[column.name] ?? []).joined(separator: ", ")),
                    .text((indexed[column.name] ?? []).joined(separator: ", "))
                ])
            }
        }
        return grid
    }

    private func columnInfo(_ database: OpaquePointer, table: String, context: RequestContext,
                            progress: SQLiteProgress) throws -> [ColumnInfo] {
        let pragma = try statement(database, sql: "PRAGMA table_xinfo(\(quoted(table)))", context: context, progress: progress)
        defer { sqlite3_finalize(pragma) }
        var result: [ColumnInfo] = []
        while try step(pragma, database: database, context: context, progress: progress) {
            guard result.count < 50 else { break }
            // Hidden columns (value 1) belong to virtual tables; generated columns (2, 3) are shown.
            if sqlite3_column_int(pragma, 6) == 1 { continue }
            let hasDefault = sqlite3_column_type(pragma, 4) != SQLITE_NULL
            result.append(ColumnInfo(name: text(pragma, column: 1), declaredType: text(pragma, column: 2),
                                     notNull: sqlite3_column_int(pragma, 3) != 0,
                                     defaultValue: hasDefault ? text(pragma, column: 4) : nil,
                                     primaryKeyPosition: Int(sqlite3_column_int(pragma, 5))))
        }
        return result
    }

    /// Foreign-key targets by referencing column, written `table(column)` (or `table` when the
    /// constraint names no column and therefore refers to the primary key).
    private func foreignKeyTargets(_ database: OpaquePointer, table: String, context: RequestContext,
                                   progress: SQLiteProgress) throws -> [String: [String]] {
        let pragma = try statement(database, sql: "PRAGMA foreign_key_list(\(quoted(table)))", context: context, progress: progress)
        defer { sqlite3_finalize(pragma) }
        var targets: [String: [String]] = [:]
        var rows = 0
        while try step(pragma, database: database, context: context, progress: progress) {
            rows += 1
            guard rows <= 100 else { break }
            let referenced = text(pragma, column: 2)
            let column = sqlite3_column_type(pragma, 4) == SQLITE_NULL ? "" : text(pragma, column: 4)
            targets[text(pragma, column: 3), default: []].append(column.isEmpty ? referenced : "\(referenced)(\(column))")
        }
        return targets
    }

    /// Names of the indexes whose key columns include each column of `table`.
    private func indexedColumns(_ database: OpaquePointer, table: String, context: RequestContext,
                                progress: SQLiteProgress) throws -> [String: [String]] {
        let list = try statement(database, sql: "PRAGMA index_list(\(quoted(table)))", context: context, progress: progress)
        var indexNames: [String] = []
        while try step(list, database: database, context: context, progress: progress) {
            guard indexNames.count < 32 else { break }
            indexNames.append(text(list, column: 1))
        }
        sqlite3_finalize(list)
        var indexed: [String: [String]] = [:]
        for name in indexNames {
            try context.checkpoint()
            let info = try statement(database, sql: "PRAGMA index_xinfo(\(quoted(name)))", context: context, progress: progress)
            defer { sqlite3_finalize(info) }
            var columns = 0
            while try step(info, database: database, context: context, progress: progress) {
                columns += 1
                guard columns <= 64 else { break }
                // Key columns only; auxiliary columns and expressions carry no column name.
                guard sqlite3_column_int(info, 5) == 1, sqlite3_column_type(info, 2) != SQLITE_NULL else { continue }
                indexed[text(info, column: 2), default: []].append(name)
            }
        }
        return indexed
    }

    private func quoted(_ identifier: String) -> String { "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    private func schemaMayContainSecrets(_ sql: String) -> Bool {
        // Defaults/check constraints can contain credential strings. Conceal the entire
        // definition when a sensitive identifier occurs rather than exposing its literals.
        sql.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).contains { SecretFieldPolicy.isSensitive(String($0)) }
    }
    private func statement(_ database: OpaquePointer, sql: String, context: RequestContext, progress: SQLiteProgress) throws -> OpaquePointer {
        try context.checkpoint()
        progress.statementDeadline = ContinuousClock.now.advanced(by: .milliseconds(250))
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v3(database, sql, -1, UInt32(SQLITE_PREPARE_NO_VTAB), &statement, nil)
        guard status == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            if let failure = progress.failure { throw failure }
            throw PreviewFailure.malformedDocument
        }
        return statement
    }
    private func step(_ statement: OpaquePointer, database: OpaquePointer, context: RequestContext, progress: SQLiteProgress) throws -> Bool {
        try context.checkpoint()
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default:
            if let failure = progress.failure { throw failure }
            throw PreviewFailure.malformedDocument
        }
    }
    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        let count = min(65_536, Int(sqlite3_column_bytes(statement, column)))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self)
    }
}

private final class SQLiteProgress {
    let context: RequestContext
    var failure: (any Error)?
    var statementDeadline = ContinuousClock.now.advanced(by: .milliseconds(250))
    init(context: RequestContext) { self.context = context }
}

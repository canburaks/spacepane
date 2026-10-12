import Foundation
import PreviewContracts

/// Apache Parquet file structure: footer metadata only, never row data.
///
/// The adapter reads the four magic bytes, the little-endian footer length and the Thrift footer
/// through the request's bounded random-access source, so a multi-gigabyte file costs only its
/// footer. The footer is decoded by `ThriftCompactReader` into the schema (as a flattened table),
/// row groups, column chunk metadata and key/value metadata. Column data pages are never read, so
/// no values, dictionaries or statistics bytes can reach the preview; only null counts do.
///
/// Files with an encrypted footer (`PARE` magic) fail with `encryptedContent`. Key/value metadata
/// values are clipped and concealed when their key looks secret.
public struct ParquetAdapter: RandomAccessFormatAdapter {
    public init() {}

    private static let magic = Array("PAR1".utf8)
    private static let encryptedMagic = Array("PARE".utf8)
    private static let schemaRowLimit = 500

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = source.byteCount
        guard size >= 12 else { throw PreviewFailure.malformedDocument }
        let head = [UInt8](try source.read(offset: 0, count: 4, context: context))
        let tail = [UInt8](try source.read(offset: size - 8, count: 8, context: context))
        let tailMagic = Array(tail[4...])
        if tailMagic == Self.encryptedMagic || head == Self.encryptedMagic { throw PreviewFailure.encryptedContent }
        guard head == Self.magic, tailMagic == Self.magic else { throw PreviewFailure.malformedDocument }
        let length = Int64(tail[0]) | Int64(tail[1]) << 8 | Int64(tail[2]) << 16 | Int64(tail[3]) << 24
        guard length > 0, length <= size - 12 else { throw PreviewFailure.malformedDocument }
        guard length <= Int64(context.budget.maxInputBytes - 12) else { throw PreviewFailure.inputTooLarge }
        let footerBytes = [UInt8](try source.read(offset: size - 8 - length, count: Int(length), context: context))
        let footer = try ParquetFooter.decode(footerBytes, context: context)
        try context.checkpoint()
        // Row values are an addition: anything that goes wrong while sampling, other than cancellation
        // or the deadline, leaves them out instead of losing the footer summary. At most half the input
        // budget is spent on pages, so sampling can never push an accepted file over the limit.
        var sample: ParquetRowSampler.Sample?
        let allowance = context.budget.maxInputBytes / 2 - Int(length) - 12
        if allowance > 0 {
            do { sample = try ParquetRowSampler.sample(footer, source: source, dataEnd: size - 8 - length, readAllowance: allowance,
                                                   context: context) }
            catch let failure as PreviewFailure where failure != .deadlineExceeded { sample = nil }
        }
        return try Self.document(for: footer, sample: sample, context: context)
    }

    // MARK: Presentation

    private static func document(for footer: ParquetFooter, sample: ParquetRowSampler.Sample?,
                                 context: RequestContext) throws -> ParsedTextDocument {
        var partial = footer.schemaElementCount > footer.schema.count
            || footer.rowGroupCount > footer.rowGroups.count
            || footer.keyValueCount > footer.keyValues.count
        var table = DataTable(kind: .identifiers,
                              columns: ["name", "repetition", "physicalType", "convertedType", "logicalType"],
                              limits: .init(maximumRows: schemaRowLimit))
        try appendSchemaRows(footer, to: &table, context: context)

        var members: [(String, SummaryValue)] = [
            ("dataFormat", .string("Parquet")),
            ("formatVersion", footer.version.map { SummaryValue.integer($0) } ?? .null)
        ]
        if let created = DataDocument.string(footer.createdBy) { members.append(("createdBy", created)) }
        members.append(("rowCount", .integer(clamped(footer.rowCount ?? 0))))
        members.append(("rowGroupCount", .integer(footer.rowGroupCount)))
        members.append(("columnCount", .integer(footer.schema.dropFirst().filter { $0.physicalType != nil }.count)))
        var groups: [SummaryValue] = []
        for group in footer.rowGroups {
            try context.checkpoint()
            if group.chunkCount > group.chunks.count { partial = true }
            var fields: [(String, SummaryValue)] = []
            if let rows = group.rows { fields.append(("rows", .integer(clamped(rows)))) }
            if let bytes = group.uncompressedBytes { fields.append(("uncompressedBytes", .integer(clamped(bytes)))) }
            if let bytes = group.compressedBytes { fields.append(("compressedBytes", .integer(clamped(bytes)))) }
            fields.append(("columnChunks", .array(group.chunks.map(chunkSummary))))
            groups.append(.object(fields))
        }
        members.append(("rowGroups", .array(groups)))
        if !footer.keyValues.isEmpty {
            members.append(("metadata", .array(footer.keyValues.map { pair in
                var fields: [(String, SummaryValue)] = [("key", .string(DataTable.clip(pair.key, to: 200).0))]
                if let value = pair.value {
                    fields.append(("value", .string(DataTable.clip(value, to: 300).0,
                                                    sensitive: SecretFieldPolicy.isSensitive(pair.key))))
                }
                return .object(fields)
            })))
        }
        if partial { members.append(("partial", .boolean(true))) }
        members.append((DataSummaryKeys.table, table.summary))
        if let sample, !sample.rows.isEmpty {
            // Column names are the document's own, so a secret-looking name conceals the whole column.
            var rows = DataTable(kind: .documentNames, columns: sample.columns,
                                 limits: .init(maximumRows: ParquetRowSampler.maximumRows,
                                               maximumColumns: ParquetRowSampler.maximumColumns, maximumBytes: 60_000),
                                 alreadyTruncated: sample.skippedColumns > 0 || (footer.rowGroups.first?.rows ?? 0) > Int64(sample.rows.count))
            for row in sample.rows { rows.append(row) }
            members.append((DataSummaryKeys.rowSample, rows.summary))
        }
        guard let rowCount = footer.rowCount, rowCount >= 0 else { throw PreviewFailure.malformedDocument }
        // A truncated schema cannot prove the column total. Omit its grid fact instead of presenting
        // a sample or a lower column bound as an exact count. Footer row totals do not depend on samples.
        let facts = footer.schema.count == footer.schemaElementCount ? PresentationFacts([
            .grid(rows: Int(clamping: rowCount), columns: footer.schema.dropFirst().filter { $0.physicalType != nil }.count,
                  rowsAreLowerBound: false)
        ]) : .none
        return try DataDocument.make(members, context: context, facts: facts)
    }

    private static func chunkSummary(_ chunk: ParquetFooter.ColumnChunk) -> SummaryValue {
        var fields: [(String, SummaryValue)] = [
            ("path", .string(DataTable.clip(chunk.path.joined(separator: "."), to: 200).0))
        ]
        if let type = chunk.physicalType { fields.append(("type", .string(ParquetNames.physical(type)))) }
        if let codec = chunk.codec { fields.append(("codec", .string(ParquetNames.codec(codec)))) }
        if !chunk.encodings.isEmpty {
            fields.append(("encodings", .array(chunk.encodings.map { .string(ParquetNames.encoding($0)) })))
        }
        if let bytes = chunk.compressedBytes { fields.append(("compressedBytes", .integer(clamped(bytes)))) }
        if let bytes = chunk.uncompressedBytes { fields.append(("uncompressedBytes", .integer(clamped(bytes)))) }
        if let count = chunk.valueCount { fields.append(("valueCount", .integer(clamped(count)))) }
        if let count = chunk.nullCount { fields.append(("nullCount", .integer(clamped(count)))) }
        return .object(fields)
    }

    /// Flattens the preorder schema list into dotted paths, checking that child counts agree with
    /// the list. A declared-but-unread tail (a cut list) skips the final consistency check.
    private static func appendSchemaRows(_ footer: ParquetFooter, to table: inout DataTable,
                                         context: RequestContext) throws {
        var frames: [(remaining: Int, prefix: String)] = []
        for (index, element) in footer.schema.enumerated() {
            if index.isMultiple(of: 256) { try context.checkpoint() }
            if index == 0 {
                frames = [(element.childCount, "")]
                continue
            }
            while let top = frames.last, top.remaining == 0 { frames.removeLast() }
            guard let last = frames.indices.last else { throw PreviewFailure.malformedDocument }
            frames[last].remaining -= 1
            let prefix = frames[last].prefix
            let path = prefix.isEmpty ? element.name : prefix + "." + element.name
            if element.childCount > 0 { frames.append((element.childCount, path)) }
            table.append([
                .text(path),
                .text(element.repetition.map(ParquetNames.repetition) ?? ""),
                .text(physicalDescription(element)),
                .text(element.convertedType.map(ParquetNames.converted) ?? ""),
                .text(element.logicalType ?? "")
            ])
        }
        if footer.schema.count == footer.schemaElementCount {
            while let top = frames.last, top.remaining == 0 { frames.removeLast() }
            guard frames.isEmpty else { throw PreviewFailure.malformedDocument }
        }
    }

    private static func physicalDescription(_ element: ParquetFooter.SchemaElement) -> String {
        guard let type = element.physicalType else { return "" }
        let name = ParquetNames.physical(type)
        if type == 7, let length = element.typeLength { return "\(name)(\(length))" }
        return name
    }

    private static func clamped(_ value: Int64) -> Int { Int(clamping: value) }
}

/// Names of the Parquet enumerations, from the public `parquet.thrift` definition. Values from a
/// newer writer render as their number rather than being guessed.
enum ParquetNames {
    private static let physicalTypes = ["BOOLEAN", "INT32", "INT64", "INT96", "FLOAT", "DOUBLE", "BYTE_ARRAY", "FIXED_LEN_BYTE_ARRAY"]
    private static let repetitions = ["REQUIRED", "OPTIONAL", "REPEATED"]
    private static let codecs = ["UNCOMPRESSED", "SNAPPY", "GZIP", "LZO", "BROTLI", "LZ4", "ZSTD", "LZ4_RAW"]
    private static let convertedNames = [
        "UTF8", "MAP", "MAP_KEY_VALUE", "LIST", "ENUM", "DECIMAL", "DATE", "TIME_MILLIS", "TIME_MICROS",
        "TIMESTAMP_MILLIS", "TIMESTAMP_MICROS", "UINT_8", "UINT_16", "UINT_32", "UINT_64",
        "INT_8", "INT_16", "INT_32", "INT_64", "JSON", "BSON", "INTERVAL"
    ]
    private static let encodings: [Int: String] = [
        0: "PLAIN", 2: "PLAIN_DICTIONARY", 3: "RLE", 4: "BIT_PACKED", 5: "DELTA_BINARY_PACKED",
        6: "DELTA_LENGTH_BYTE_ARRAY", 7: "DELTA_BYTE_ARRAY", 8: "RLE_DICTIONARY", 9: "BYTE_STREAM_SPLIT"
    ]

    static func physical(_ value: Int) -> String { name(physicalTypes, value) }
    static func repetition(_ value: Int) -> String { name(repetitions, value) }
    static func codec(_ value: Int) -> String { name(codecs, value) }
    static func converted(_ value: Int) -> String { name(convertedNames, value) }
    static func encoding(_ value: Int) -> String { encodings[value] ?? "#\(value)" }

    private static func name(_ names: [String], _ value: Int) -> String {
        names.indices.contains(value) ? names[value] : "#\(value)"
    }
}

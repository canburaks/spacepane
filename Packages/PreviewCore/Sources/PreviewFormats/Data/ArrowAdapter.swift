import Foundation
import PreviewContracts

/// Arrow IPC files (`ARROW1`, including Feather v2) and streams: schema and batch structure only.
///
/// Column buffers are never read. The footer (file) or the message metadata (stream) is read
/// through the bounded random-access source and decoded by the minimal FlatBuffers reader. Record
/// batch lengths come from each batch's message metadata, visited through the footer's block list
/// or by hopping over declared body sizes, within fixed read and hop limits; a cut tally is flagged
/// `partial`. Feather v1 (`FEA1`) is a different format and is reported as unsupported.
public struct ArrowAdapter: RandomAccessFormatAdapter {
    public init() {}

    private static let fileMagic = Array("ARROW1".utf8)
    private static let featherV1Magic = Array("FEA1".utf8)
    private static let continuation: UInt32 = 0xFFFF_FFFF
    private static let maximumBatchVisits = 64
    private static let maximumStreamMessages = 1_024
    private static let maximumMessageBytes = 1_048_576
    private static let schemaRowLimit = 500

    private struct Totals {
        var rows: Int64 = 0
        var batches = 0
        var dictionaries = 0
        var partial = false

        mutating func addRows(_ count: Int64) throws {
            let (total, overflow) = rows.addingReportingOverflow(count)
            guard count >= 0, !overflow else { throw PreviewFailure.malformedDocument }
            rows = total
        }
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = source.byteCount
        guard size >= 8 else { throw PreviewFailure.malformedDocument }
        let head = [UInt8](try source.read(offset: 0, count: 8, context: context))
        if head.starts(with: Self.featherV1Magic) { throw PreviewFailure.unsupportedFormat }
        if head.starts(with: Self.fileMagic) { return try parseFile(source, size: size, context: context) }
        return try parseStream(source, size: size, context: context)
    }

    // MARK: File format

    private func parseFile(_ source: any PreviewByteSource, size: Int64, context: RequestContext) throws -> ParsedTextDocument {
        guard size >= 24 else { throw PreviewFailure.malformedDocument }
        let tail = [UInt8](try source.read(offset: size - 10, count: 10, context: context))
        guard Array(tail[4...]) == Self.fileMagic else { throw PreviewFailure.malformedDocument }
        let length = Int64(tail[0]) | Int64(tail[1]) << 8 | Int64(tail[2]) << 16 | Int64(tail[3]) << 24
        guard length > 0, length <= size - 18 else { throw PreviewFailure.malformedDocument }
        guard length <= Int64(context.budget.maxInputBytes / 2) else { throw PreviewFailure.inputTooLarge }
        let footer = FlatBuffer([UInt8](try source.read(offset: size - 10 - length, count: Int(length), context: context)))
        let root = try footer.rootTable()
        guard let schemaTable = try root.table(1) else { throw PreviewFailure.malformedDocument }
        var schema = try ArrowSchemaDecoder.decode(schemaTable, context: context)
        let footerMetadata = try ArrowSchemaDecoder.keyValues(root, slot: 4)
        schema.metadata += footerMetadata.0
        schema.metadataCount += footerMetadata.1
        var totals = Totals()
        if let dictionaries = try root.vector(2, elementSize: 24) { totals.dictionaries = dictionaries.count }
        if let batches = try root.vector(3, elementSize: 24) {
            totals.batches = batches.count
            for index in 0..<batches.count {
                guard index < Self.maximumBatchVisits else { totals.partial = true; break }
                try context.checkpoint()
                let block = batches.start + index * 24
                let offset = Int64(bitPattern: try footer.u64(at: block))
                let metadataLength = Int64(Int32(bitPattern: try footer.u32(at: block + 8)))
                guard offset >= 0, metadataLength >= 8, metadataLength <= Int64(Self.maximumMessageBytes),
                      offset + metadataLength <= size else { throw PreviewFailure.malformedDocument }
                let metadata = [UInt8](try source.read(offset: offset, count: Int(metadataLength), context: context))
                let message = try Self.message(metadata, encapsulated: true)
                guard message.type == 3 else { throw PreviewFailure.malformedDocument }
                guard let header = message.header else { throw PreviewFailure.malformedDocument }
                try totals.addRows(header.int64(0))
            }
        }
        let version = Int(try root.int16(0))
        return try Self.document(kind: "Arrow IPC file", version: version, schema: schema, totals: totals, context: context)
    }

    // MARK: Stream format

    private func parseStream(_ source: any PreviewByteSource, size: Int64, context: RequestContext) throws -> ParsedTextDocument {
        var offset: Int64 = 0
        var schema: ArrowSchemaInfo?
        var version = 0
        var totals = Totals()
        var messages = 0
        while offset + 4 <= size {
            try context.checkpoint()
            guard messages < Self.maximumStreamMessages else { totals.partial = true; break }
            messages += 1
            let prefix = [UInt8](try source.read(offset: offset, count: Int(min(8, size - offset)), context: context))
            var cursor = LittleEndianCursor(prefix)
            var metadataLength = Int64(try cursor.u32())
            var prefixLength: Int64 = 4
            if metadataLength == Int64(Self.continuation) {
                guard prefix.count >= 8 else { throw PreviewFailure.malformedDocument }
                metadataLength = Int64(try cursor.u32())
                prefixLength = 8
            }
            if metadataLength == 0 { break }
            guard metadataLength <= Int64(Self.maximumMessageBytes), offset + prefixLength + metadataLength <= size else {
                throw PreviewFailure.malformedDocument
            }
            let metadata = [UInt8](try source.read(offset: offset + prefixLength, count: Int(metadataLength), context: context))
            let message = try Self.message(metadata)
            switch message.type {
            case 1:
                guard schema == nil, let table = message.header else { throw PreviewFailure.malformedDocument }
                schema = try ArrowSchemaDecoder.decode(table, context: context)
                version = message.version
            case 2: totals.dictionaries += 1
            case 3:
                totals.batches += 1
                guard let header = message.header else { throw PreviewFailure.malformedDocument }
                try totals.addRows(header.int64(0))
            default: break
            }
            guard schema != nil else { throw PreviewFailure.malformedDocument }
            let (next, overflow) = (offset + prefixLength + metadataLength).addingReportingOverflow(message.bodyLength)
            guard !overflow, message.bodyLength >= 0, next <= size else { throw PreviewFailure.malformedDocument }
            offset = next
        }
        if offset + 4 <= size, messages >= Self.maximumStreamMessages { totals.partial = true }
        guard let schema else { throw PreviewFailure.malformedDocument }
        return try Self.document(kind: "Arrow IPC stream", version: version, schema: schema, totals: totals, context: context)
    }

    // MARK: Messages

    private struct Message {
        let version: Int
        let type: UInt8
        let header: FlatTable?
        let bodyLength: Int64
    }

    /// The message in a flatbuffer; `encapsulated` is true when the bytes still carry the 4-byte
    /// length (and optional continuation marker) that frames every IPC message.
    private static func message(_ bytes: [UInt8], encapsulated: Bool = false) throws -> Message {
        var start = 0
        if encapsulated {
            start = bytes.count >= 8 && bytes[0..<4].elementsEqual([0xFF, 0xFF, 0xFF, 0xFF]) ? 8 : 4
        }
        guard bytes.count > start else { throw PreviewFailure.malformedDocument }
        let root = try FlatBuffer(Array(bytes[start...])).rootTable()
        return Message(version: Int(try root.int16(0)), type: try root.uint8(1), header: try root.table(2),
                       bodyLength: try root.int64(3))
    }

    // MARK: Presentation

    private static func document(kind: String, version: Int, schema: ArrowSchemaInfo, totals: Totals,
                                 context: RequestContext) throws -> ParsedTextDocument {
        var table = DataTable(kind: .identifiers, columns: ["name", "type", "nullable"],
                              limits: .init(maximumRows: schemaRowLimit))
        var visited = 0
        try appendRows(schema.fields, prefix: "", to: &table, visited: &visited, context: context)
        var members: [(String, SummaryValue)] = [
            ("dataFormat", .string(kind)),
            ("formatVersion", .string("V\(version + 1)")),
            ("columnCount", .integer(schema.fields.count)),
            ("rowCount", .integer(Int(clamping: totals.rows))),
            ("recordBatchCount", .integer(totals.batches)),
            ("dictionaryCount", .integer(totals.dictionaries))
        ]
        if totals.partial || schema.metadataCount > schema.metadata.count { members.append(("partial", .boolean(true))) }
        if !schema.metadata.isEmpty {
            members.append(("metadata", .array(schema.metadata.map { pair in
                var fields: [(String, SummaryValue)] = [("key", .string(DataTable.clip(pair.key, to: 200).0))]
                if let value = pair.value {
                    fields.append(("value", .string(DataTable.clip(value, to: 300).0,
                                                    sensitive: SecretFieldPolicy.isSensitive(pair.key))))
                }
                return .object(fields)
            })))
        }
        members.append((DataSummaryKeys.table, table.summary))
        return try DataDocument.make(members, context: context, facts: PresentationFacts([
            .grid(rows: Int(clamping: totals.rows), columns: schema.fields.count, rowsAreLowerBound: totals.partial)
        ]))
    }

    private static func appendRows(_ fields: [ArrowField], prefix: String, to table: inout DataTable,
                                   visited: inout Int, context: RequestContext) throws {
        for field in fields {
            visited += 1
            if visited.isMultiple(of: 128) { try context.checkpoint() }
            let path = prefix.isEmpty ? field.name : prefix + "." + field.name
            table.append([.text(path), .text(field.type), .text(field.nullable ? "true" : "false")])
            try appendRows(field.children, prefix: path, to: &table, visited: &visited, context: context)
        }
    }
}

/// A tiny little-endian cursor over the first bytes of a stream message.
private struct LittleEndianCursor {
    private let bytes: [UInt8]
    private var position = 0
    init(_ bytes: [UInt8]) { self.bytes = bytes }
    mutating func u32() throws -> UInt32 {
        guard position + 4 <= bytes.count else { throw PreviewFailure.malformedDocument }
        defer { position += 4 }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[position + $1]) << UInt32($1 * 8) }
    }
}

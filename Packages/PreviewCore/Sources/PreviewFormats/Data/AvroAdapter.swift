import Foundation
import zlib
import PreviewContracts

/// Avro object container files: header metadata, schema and the first records.
///
/// The header (magic, metadata map, sync marker) is read from the start of the bounded random-
/// access source in growing windows; the schema is parsed by `AvroSchema`. Blocks are then
/// visited by hopping over their declared byte sizes, which counts records without reading
/// payloads. Only the first block(s) needed for `maximumRows` records are read, decompressed
/// (codecs `null`, `deflate` and `snappy`) and decoded by `AvroValueDecoder`. A top-level record schema
/// becomes a table; every schema also gets a bounded type-tree summary.
///
/// Binary values (`bytes`, `fixed`) are reduced to their length. Columns whose field name looks
/// secret are concealed in every row, and so are nested values that contain a secret-looking key.
public struct AvroAdapter: RandomAccessFormatAdapter {
    public init() {}

    static let magic: [UInt8] = [0x4F, 0x62, 0x6A, 0x01]
    static let maximumRows = 100
    static let maximumColumns = 40
    static let maximumBlockHops = 1_024
    static let maximumMetadataEntries = 1_000

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = source.byteCount
        guard size >= 21 else { throw PreviewFailure.malformedDocument }
        let header = try Self.readHeader(source, size: size, context: context)
        let schema = try Self.parseSchema(header, context: context)
        let scan = try Self.scanBlocks(source, size: size, header: header, schema: schema, context: context)
        try context.checkpoint()
        return try Self.document(header: header, schema: schema, scan: scan, context: context)
    }

    // MARK: Header

    struct Header {
        var schemaBytes: [UInt8] = []
        var codec = "null"
        var metadata: [(key: String, value: String)] = []
        var metadataCount = 0
        var sync: [UInt8] = []
        var end = 0
    }

    private static func readHeader(_ source: any PreviewByteSource, size: Int64, context: RequestContext) throws -> Header {
        var buffer = [UInt8](try source.read(offset: 0, count: Int(min(size, 16_384)), context: context))
        guard buffer.starts(with: magic) else { throw PreviewFailure.malformedDocument }
        let limit = Int64(max(16_384, min(context.budget.maxInputBytes / 2, 4_194_304)))
        var parsed: Header?
        while parsed == nil {
            try context.checkpoint()
            do { parsed = try parseHeader(buffer, schemaLimit: Int(limit), context: context) }
            catch is AvroUnderflow {
                let have = Int64(buffer.count)
                guard have < size, have < limit else { throw PreviewFailure.malformedDocument }
                let next = min(size, min(have * 2, limit))
                buffer += try source.read(offset: have, count: Int(next - have), context: context)
            }
        }
        guard let header = parsed else { throw PreviewFailure.malformedDocument }
        return header
    }

    private static func parseHeader(_ bytes: [UInt8], schemaLimit: Int, context: RequestContext) throws -> Header {
        var reader = AvroBinaryReader(bytes)
        _ = try reader.take(magic.count)
        var header = Header()
        var sawSchema = false
        while true {
            try context.checkpoint()
            var count = try reader.long()
            if count == 0 { break }
            if count < 0 {
                guard count != Int64.min else { throw PreviewFailure.malformedDocument }
                count = -count
                _ = try reader.long()
            }
            guard count <= Int64(maximumMetadataEntries) else { throw PreviewFailure.tooManyNodes }
            for _ in 0..<Int(count) {
                header.metadataCount += 1
                guard header.metadataCount <= maximumMetadataEntries else { throw PreviewFailure.tooManyNodes }
                let key = try reader.string(maximumBytes: 256)
                let valueLength = try reader.length()
                let value = try reader.take(valueLength)
                switch key {
                case "avro.schema":
                    guard valueLength <= schemaLimit else { throw PreviewFailure.inputTooLarge }
                    header.schemaBytes = Array(value)
                    sawSchema = true
                case "avro.codec":
                    header.codec = String(decoding: value.prefix(32), as: UTF8.self)
                default:
                    if header.metadata.count < 30 {
                        header.metadata.append((key, String(decoding: value.prefix(512), as: UTF8.self)))
                    }
                }
            }
        }
        guard sawSchema else { throw PreviewFailure.malformedDocument }
        header.sync = Array(try reader.take(16))
        header.end = reader.position
        return header
    }

    private static func parseSchema(_ header: Header, context: RequestContext) throws -> AvroSchema {
        var reader = DataJSONReader(bytes: header.schemaBytes, context: context)
        var allowance = min(context.budget.maxJSONNodes, 20_000)
        var tree: DataJSONValue?
        try reader.document { reader in tree = try reader.value(depth: 1, nodes: &allowance) }
        guard let tree else { throw PreviewFailure.malformedDocument }
        return try AvroSchema.parse(tree, nodeAllowance: min(context.budget.maxJSONNodes, 20_000))
    }

    // MARK: Blocks

    enum Codec {
        case null, deflate, snappy
        case unsupported
        init(_ name: String) {
            switch name {
            case "null": self = .null
            case "deflate": self = .deflate
            case "snappy": self = .snappy
            default: self = .unsupported
            }
        }
    }

    struct Scan {
        var recordCount = 0
        var blockCount = 0
        var partial = false
        var table: DataTable?
    }

    private static func scanBlocks(_ source: any PreviewByteSource, size: Int64, header: Header,
                                   schema: AvroSchema, context: RequestContext) throws -> Scan {
        var scan = Scan()
        let codec = Codec(header.codec)
        let root = try schema.resolve(schema.root)
        var table: DataTable?
        if root.kind == .record, !root.fields.isEmpty, codec != .unsupported {
            table = DataTable(kind: .documentNames, columns: root.fields.map(\.name),
                              limits: .init(maximumRows: maximumRows, maximumColumns: maximumColumns))
        }
        let maximumPayload = max(1, context.budget.maxInputBytes / 2)
        var offset = Int64(header.end)
        while offset < size {
            try context.checkpoint()
            guard scan.blockCount < maximumBlockHops else { scan.partial = true; break }
            let window = Int(min(20, size - offset))
            var head = AvroBinaryReader([UInt8](try source.read(offset: offset, count: window, context: context)))
            let count: Int64
            let payloadSize: Int64
            do {
                count = try head.long()
                payloadSize = try head.long()
            } catch is AvroUnderflow { throw PreviewFailure.malformedDocument }
            guard count >= 0, payloadSize >= 0 else { throw PreviewFailure.malformedDocument }
            let payloadStart = offset + Int64(head.position)
            let (payloadEnd, overflow) = payloadStart.addingReportingOverflow(payloadSize)
            guard !overflow, payloadEnd <= size - 16 else { throw PreviewFailure.malformedDocument }
            if var current = table, !current.isFull, payloadSize <= Int64(maximumPayload), count > 0 {
                let payload = [UInt8](try source.read(offset: payloadStart, count: Int(payloadSize), context: context))
                try decodeRows(payload, count: Int(min(count, Int64(Int.max))), codec: codec, schema: schema,
                               root: root, into: &current, context: context)
                table = current
            }
            let sync = [UInt8](try source.read(offset: payloadEnd, count: 16, context: context))
            guard sync == header.sync else { throw PreviewFailure.malformedDocument }
            let (total, totalOverflow) = scan.recordCount.addingReportingOverflow(Int(clamping: count))
            guard !totalOverflow else { throw PreviewFailure.malformedDocument }
            scan.recordCount = total
            scan.blockCount += 1
            offset = payloadEnd + 16
        }
        if let table, scan.recordCount > table.rows.count {
            var marked = table
            marked.markTruncated()
            scan.table = marked
        } else {
            scan.table = table
        }
        return scan
    }

    private static func decodeRows(_ payload: [UInt8], count: Int, codec: Codec, schema: AvroSchema,
                                   root: AvroSchemaNode, into table: inout DataTable,
                                   context: RequestContext) throws {
        let maximumDecoded = min(context.budget.maxInputBytes * 8, 16_777_216)
        let block: [UInt8]
        switch codec {
        case .null:
            block = payload
        case .deflate:
            block = [UInt8](try BoundedDecompression.rawDeflate(Data(payload), context: context, maximum: maximumDecoded))
        case .snappy:
            // Avro's snappy blocks end with a big-endian CRC-32 of the uncompressed data.
            guard payload.count >= 4 else { throw PreviewFailure.malformedDocument }
            block = try SnappyDecoder.decode(payload.dropLast(4), maximum: maximumDecoded, context: context)
            let expected = payload.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let actual = block.withUnsafeBufferPointer { UInt32(zlib.crc32(0, $0.baseAddress, uInt($0.count))) }
            guard expected == actual else { throw PreviewFailure.malformedDocument }
        case .unsupported:
            return
        }
        var decoder = AvroValueDecoder(block: block, schema: schema, context: context,
                                       workAllowance: block.count * 4 + 100_000)
        for _ in 0..<count {
            guard !table.isFull else { return }
            guard case .record(let fields) = try decoder.value(root) else { throw PreviewFailure.malformedDocument }
            table.append(fields.map { cell($0.value) })
        }
    }

    // MARK: Cells

    private static func cell(_ value: AvroValue) -> DataCell {
        switch value {
        case .null: return .null
        case .boolean(let flag): return .text(flag ? "true" : "false")
        case .integer(let number): return .text(String(number))
        case .float(let number): return .text(number.description)
        case .double(let number): return .text(number.description)
        case .string(let text), .symbol(let text): return .text(text)
        case .binary(let count): return .binary(byteCount: count)
        case .array, .map, .record:
            let text = compactText(value)
            return containsSecretKey(value) ? .segments([(text, true)]) : .text(text)
        }
    }

    /// A JSON-like rendering of a nested value, for the one table cell that holds it.
    static func compactText(_ value: AvroValue) -> String {
        switch value {
        case .null: return "null"
        case .boolean(let flag): return flag ? "true" : "false"
        case .integer(let number): return String(number)
        case .float(let number): return number.description
        case .double(let number): return number.description
        case .string(let text): return quoted(text)
        case .symbol(let text): return text
        case .binary(let count): return "bytes[\(count)]"
        case .array(let items, let total):
            return "[" + (items.map(compactText) + (total > items.count ? ["…"] : [])).joined(separator: ", ") + "]"
        case .map(let entries, let total):
            return "{" + (entries.map { quoted($0.key) + ": " + compactText($0.value) }
                          + (total > entries.count ? ["…"] : [])).joined(separator: ", ") + "}"
        case .record(let fields):
            return "{" + fields.map { quoted($0.name) + ": " + compactText($0.value) }.joined(separator: ", ") + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func containsSecretKey(_ value: AvroValue) -> Bool {
        switch value {
        case .array(let items, _): return items.contains(where: containsSecretKey)
        case .map(let entries, _):
            return entries.contains { SecretFieldPolicy.isSensitive($0.key) || containsSecretKey($0.value) }
        case .record(let fields):
            return fields.contains { SecretFieldPolicy.isSensitive($0.name) || containsSecretKey($0.value) }
        default: return false
        }
    }

    // MARK: Presentation

    private static func document(header: Header, schema: AvroSchema, scan: Scan,
                                 context: RequestContext) throws -> ParsedTextDocument {
        var members: [(String, SummaryValue)] = [
            ("dataFormat", .string("Avro")),
            ("codec", .string(DataTable.clip(header.codec, to: 32).0)),
            ("recordCount", .integer(scan.recordCount)),
            ("blockCount", .integer(scan.blockCount))
        ]
        if scan.partial { members.append(("partial", .boolean(true))) }
        var budget = 300
        members.append(("schema", describe(schema.root, fieldName: nil, schema: schema, budget: &budget, depth: 1)))
        if !header.metadata.isEmpty {
            members.append(("metadata", .array(header.metadata.map { pair in
                .object([("key", .string(DataTable.clip(pair.key, to: 200).0)),
                         ("value", .string(DataTable.clip(pair.value, to: 300).0,
                                           sensitive: SecretFieldPolicy.isSensitive(pair.key)))])
            })))
        }
        if let table = scan.table, !table.rows.isEmpty { members.append((DataSummaryKeys.table, table.summary)) }
        let root = try schema.resolve(schema.root)
        let facts = root.kind == .record ? PresentationFacts([
            .grid(rows: scan.recordCount, columns: root.fields.count, rowsAreLowerBound: scan.partial)
        ]) : .none
        return try DataDocument.make(members, context: context, facts: facts)
    }

    /// The schema as a bounded tree. Names are Avro identifiers; type words are the specification's
    /// own, so none of this is translated.
    private static func describe(_ node: AvroSchemaNode, fieldName: String?, schema: AvroSchema,
                                 budget: inout Int, depth: Int) -> SummaryValue {
        budget -= 1
        var members: [(String, SummaryValue)] = []
        if let fieldName { members.append(("name", .string(DataTable.clip(fieldName, to: 200).0))) }
        members.append(("kind", .string(node.kind.rawValue)))
        if let name = node.name { members.append(("typeName", .string(DataTable.clip(name, to: 200).0))) }
        if let logical = node.logicalType { members.append(("logicalType", .string(logical))) }
        if budget <= 0 || depth > 8 {
            if !node.fields.isEmpty || !node.children.isEmpty { members.append(("partial", .boolean(true))) }
            return .object(members)
        }
        switch node.kind {
        case .record:
            var fields: [SummaryValue] = []
            for field in node.fields {
                guard budget > 0 else { members.append(("partial", .boolean(true))); break }
                fields.append(describe(field.node, fieldName: field.name, schema: schema, budget: &budget, depth: depth + 1))
            }
            members.append(("fields", .array(fields)))
        case .enumeration:
            members.append(("symbols", .array(node.symbols.prefix(30).map { .string(DataTable.clip($0, to: 100).0) })))
        case .fixed:
            members.append(("size", .integer(node.size)))
        case .array:
            members.append(("items", describe(node.children[0], fieldName: nil, schema: schema, budget: &budget, depth: depth + 1)))
        case .map:
            members.append(("values", describe(node.children[0], fieldName: nil, schema: schema, budget: &budget, depth: depth + 1)))
        case .union:
            var branches: [SummaryValue] = []
            for branch in node.children {
                guard budget > 0 else { members.append(("partial", .boolean(true))); break }
                branches.append(describe(branch, fieldName: nil, schema: schema, budget: &budget, depth: depth + 1))
            }
            members.append(("branches", .array(branches)))
        default:
            break
        }
        return .object(members)
    }
}

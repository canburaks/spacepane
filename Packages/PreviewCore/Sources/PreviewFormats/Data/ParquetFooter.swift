import Foundation
import PreviewContracts

/// The parts of a Parquet `FileMetaData` that the preview shows, decoded from the Thrift compact
/// footer. Field numbers follow the public `parquet.thrift` definition. Only bounded prefixes of
/// the lists are retained; totals are counted while the rest is skipped.
struct ParquetFooter {
    struct SchemaElement {
        var name = ""
        var physicalType: Int?
        var typeLength: Int?
        var repetition: Int?
        var childCount = 0
        var convertedType: Int?
        var scale: Int?
        var precision: Int?
        var logicalType: String?
    }

    struct ColumnChunk {
        var path: [String] = []
        var physicalType: Int?
        var encodings: [Int] = []
        var codec: Int?
        var valueCount: Int64?
        var uncompressedBytes: Int64?
        var compressedBytes: Int64?
        var nullCount: Int64?
        /// Where the chunk's first data page and optional dictionary page begin (absolute file offsets).
        var dataPageOffset: Int64?
        var dictionaryPageOffset: Int64?
    }

    struct RowGroup {
        var chunks: [ColumnChunk] = []
        var chunkCount = 0
        var uncompressedBytes: Int64?
        var compressedBytes: Int64?
        var rows: Int64?
    }

    struct Limits {
        static let schemaElements = 20_000
        static let rowGroups = 6
        static let chunksPerGroup = 30
        static let keyValues = 50
        static let pathComponents = 64
        static let encodingsPerChunk = 12
    }

    var version: Int?
    var rowCount: Int64?
    var createdBy: String?
    var schema: [SchemaElement] = []
    /// Elements declared by the footer, which can exceed `schema` when the list was cut.
    var schemaElementCount = 0
    var rowGroups: [RowGroup] = []
    var rowGroupCount = 0
    var keyValues: [(key: String, value: String?)] = []
    var keyValueCount = 0

    static func decode(_ footer: [UInt8], context: RequestContext) throws -> ParquetFooter {
        var reader = ThriftCompactReader(bytes: footer, context: context)
        var result = ParquetFooter()
        try reader.structure(depth: 1) { id, type, reader in
            switch (id, type) {
            case (1, .i32): result.version = Int(try reader.zigzag32())
            case (2, .list): try result.decodeSchema(&reader)
            case (3, .i64): result.rowCount = try reader.zigzag64()
            case (4, .list): try result.decodeRowGroups(&reader)
            case (5, .list): try result.decodeKeyValues(&reader)
            case (6, .binary): result.createdBy = try reader.string(maximumBytes: 512)
            default: return false
            }
            return true
        }
        // The footer must hold exactly one struct; trailing bytes mean a wrong length prefix.
        guard reader.remaining == 0 else { throw PreviewFailure.malformedDocument }
        guard result.version != nil, result.rowCount != nil, result.schemaElementCount > 0 else {
            throw PreviewFailure.malformedDocument
        }
        return result
    }

    // MARK: Schema

    private mutating func decodeSchema(_ reader: inout ThriftCompactReader) throws {
        let (element, count) = try reader.listHeader()
        guard element == .structure else { throw PreviewFailure.malformedDocument }
        schemaElementCount = count
        schema.reserveCapacity(min(count, Limits.schemaElements))
        for index in 0..<count {
            if index >= Limits.schemaElements {
                try reader.skip(.structure, depth: 2, inCollection: true)
                continue
            }
            var item = SchemaElement()
            try reader.structure(depth: 2) { id, type, reader in
                switch (id, type) {
                case (1, .i32): item.physicalType = Int(try reader.zigzag32())
                case (2, .i32): item.typeLength = Int(try reader.zigzag32())
                case (3, .i32): item.repetition = Int(try reader.zigzag32())
                case (4, .binary): item.name = try reader.string(maximumBytes: 256)
                case (5, .i32): item.childCount = max(0, Int(try reader.zigzag32()))
                case (6, .i32): item.convertedType = Int(try reader.zigzag32())
                case (7, .i32): item.scale = Int(try reader.zigzag32())
                case (8, .i32): item.precision = Int(try reader.zigzag32())
                case (10, .structure): item.logicalType = try Self.decodeLogicalType(&reader)
                default: return false
                }
                return true
            }
            schema.append(item)
        }
    }

    /// `LogicalType` is a Thrift union: exactly one member names the annotation.
    private static func decodeLogicalType(_ reader: inout ThriftCompactReader) throws -> String? {
        var name: String?
        try reader.structure(depth: 3) { id, type, reader in
            guard type == .structure else { return false }
            switch id {
            case 5:
                var scale: Int32?, precision: Int32?
                try reader.structure(depth: 4) { field, type, reader in
                    switch (field, type) {
                    case (1, .i32): scale = try reader.zigzag32()
                    case (2, .i32): precision = try reader.zigzag32()
                    default: return false
                    }
                    return true
                }
                name = "DECIMAL(\(precision ?? 0), \(scale ?? 0))"
            case 7, 8:
                var unit = ""
                var adjusted: Bool?
                try reader.structure(depth: 4) { field, type, reader in
                    switch (field, type) {
                    case (1, .booleanTrue): adjusted = true
                    case (1, .booleanFalse): adjusted = false
                    case (2, .structure):
                        // `TimeUnit` is a union of empty structs; the member number names the unit.
                        try reader.structure(depth: 5) { unitField, unitType, _ in
                            if unitType == .structure { unit = ["MILLIS", "MICROS", "NANOS"][safe: unitField - 1] ?? "" }
                            return false
                        }
                    default: return false
                    }
                    return true
                }
                name = "\(id == 7 ? "TIME" : "TIMESTAMP")(\(unit)\(adjusted == true ? ", UTC" : ""))"
            case 10:
                var width: UInt8?
                var signed: Bool?
                try reader.structure(depth: 4) { field, type, reader in
                    switch (field, type) {
                    case (1, .byte): width = try reader.byte()
                    case (2, .booleanTrue): signed = true
                    case (2, .booleanFalse): signed = false
                    default: return false
                    }
                    return true
                }
                name = "INTEGER(\(width.map(String.init) ?? "?"), \(signed == false ? "unsigned" : "signed"))"
            default:
                // Annotations without parameters are empty structs.
                guard let label = simpleLogicalTypes[id] else { return false }
                name = label
                try reader.structure(depth: 4) { _, _, _ in false }
            }
            return true
        }
        return name
    }

    private static let simpleLogicalTypes: [Int: String] = [
        1: "STRING", 2: "MAP", 3: "LIST", 4: "ENUM", 6: "DATE", 11: "UNKNOWN",
        12: "JSON", 13: "BSON", 14: "UUID", 15: "FLOAT16"
    ]

    // MARK: Row groups

    private mutating func decodeRowGroups(_ reader: inout ThriftCompactReader) throws {
        let (element, count) = try reader.listHeader()
        guard element == .structure else { throw PreviewFailure.malformedDocument }
        rowGroupCount = count
        for index in 0..<count {
            guard index < Limits.rowGroups else {
                try reader.skip(.structure, depth: 2, inCollection: true)
                continue
            }
            var group = RowGroup()
            try reader.structure(depth: 2) { id, type, reader in
                switch (id, type) {
                case (1, .list):
                    let (chunkElement, chunkTotal) = try reader.listHeader()
                    guard chunkElement == .structure else { throw PreviewFailure.malformedDocument }
                    group.chunkCount = chunkTotal
                    for chunkIndex in 0..<chunkTotal {
                        guard chunkIndex < Limits.chunksPerGroup else {
                            try reader.skip(.structure, depth: 3, inCollection: true)
                            continue
                        }
                        group.chunks.append(try Self.decodeColumnChunk(&reader))
                    }
                case (2, .i64): group.uncompressedBytes = try reader.zigzag64()
                case (3, .i64): group.rows = try reader.zigzag64()
                case (6, .i64): group.compressedBytes = try reader.zigzag64()
                default: return false
                }
                return true
            }
            rowGroups.append(group)
        }
    }

    private static func decodeColumnChunk(_ reader: inout ThriftCompactReader) throws -> ColumnChunk {
        var chunk = ColumnChunk()
        try reader.structure(depth: 3) { id, type, reader in
            // Field 3 is `meta_data`; plaintext-footer encrypted files carry it elsewhere, so a
            // chunk can legitimately lack it and is then shown without details.
            guard id == 3, type == .structure else { return false }
            try reader.structure(depth: 4) { field, type, reader in
                switch (field, type) {
                case (1, .i32): chunk.physicalType = Int(try reader.zigzag32())
                case (2, .list):
                    let (element, count) = try reader.listHeader()
                    guard element == .i32 else { throw PreviewFailure.malformedDocument }
                    for index in 0..<count {
                        let value = Int(try reader.zigzag32())
                        if index < Limits.encodingsPerChunk { chunk.encodings.append(value) }
                    }
                case (3, .list):
                    let (element, count) = try reader.listHeader()
                    guard element == .binary else { throw PreviewFailure.malformedDocument }
                    for index in 0..<count {
                        let part = try reader.string(maximumBytes: 128)
                        if index < Limits.pathComponents { chunk.path.append(part) }
                    }
                case (4, .i32): chunk.codec = Int(try reader.zigzag32())
                case (5, .i64): chunk.valueCount = try reader.zigzag64()
                case (6, .i64): chunk.uncompressedBytes = try reader.zigzag64()
                case (7, .i64): chunk.compressedBytes = try reader.zigzag64()
                case (9, .i64): chunk.dataPageOffset = try reader.zigzag64()
                case (11, .i64): chunk.dictionaryPageOffset = try reader.zigzag64()
                case (12, .structure):
                    try reader.structure(depth: 5) { statistic, type, reader in
                        guard statistic == 3, type == .i64 else { return false }
                        chunk.nullCount = try reader.zigzag64()
                        return true
                    }
                default: return false
                }
                return true
            }
            return true
        }
        return chunk
    }

    // MARK: Key/value metadata

    private mutating func decodeKeyValues(_ reader: inout ThriftCompactReader) throws {
        let (element, count) = try reader.listHeader()
        guard element == .structure else { throw PreviewFailure.malformedDocument }
        keyValueCount = count
        for index in 0..<count {
            guard index < Limits.keyValues else {
                try reader.skip(.structure, depth: 2, inCollection: true)
                continue
            }
            var key = ""
            var value: String?
            try reader.structure(depth: 2) { id, type, reader in
                switch (id, type) {
                case (1, .binary): key = try reader.string(maximumBytes: 256)
                case (2, .binary): value = try reader.string(maximumBytes: 1_024)
                default: return false
                }
                return true
            }
            keyValues.append((key, value))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

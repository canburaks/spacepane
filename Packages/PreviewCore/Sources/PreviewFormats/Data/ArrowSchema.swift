import Foundation
import PreviewContracts

/// One field of an Arrow schema, reduced to what the preview shows.
struct ArrowField {
    var name: String
    var type: String
    var nullable: Bool
    var children: [ArrowField] = []
}

struct ArrowSchemaInfo {
    var fields: [ArrowField] = []
    var metadata: [(key: String, value: String?)] = []
    var metadataCount = 0
}

/// Decodes the Arrow `Schema` table (field names, types, nullability, dictionary encodings and
/// nested children, plus custom metadata) from a bounded FlatBuffers buffer. Slot numbers follow
/// the public `Schema.fbs`; a union's type tag occupies the slot before its table. Walks are
/// limited by depth and by a total field count, which also defeats shared-subtree buffers.
enum ArrowSchemaDecoder {
    static let maximumFields = 5_000
    static let maximumDepth = 16
    static let maximumMetadata = 50

    static func decode(_ schema: FlatTable, context: RequestContext) throws -> ArrowSchemaInfo {
        var info = ArrowSchemaInfo()
        var visited = 0
        if let vector = try schema.vector(1, elementSize: 4) {
            for index in 0..<vector.count {
                if index.isMultiple(of: 64) { try context.checkpoint() }
                let table = try schema.vectorTable(at: index, in: vector)
                info.fields.append(try field(table, depth: 1, visited: &visited, context: context))
            }
        }
        (info.metadata, info.metadataCount) = try keyValues(schema, slot: 2)
        return info
    }

    static func keyValues(_ table: FlatTable, slot: Int) throws -> ([(key: String, value: String?)], Int) {
        guard let vector = try table.vector(slot, elementSize: 4) else { return ([], 0) }
        var result: [(key: String, value: String?)] = []
        for index in 0..<min(vector.count, maximumMetadata) {
            let pair = try table.vectorTable(at: index, in: vector)
            result.append((try pair.string(0, maximumBytes: 256) ?? "", try pair.string(1, maximumBytes: 1_024)))
        }
        return (result, vector.count)
    }

    private static func field(_ table: FlatTable, depth: Int, visited: inout Int,
                              context: RequestContext) throws -> ArrowField {
        guard depth <= maximumDepth else { throw PreviewFailure.structureTooDeep }
        visited += 1
        guard visited <= maximumFields else { throw PreviewFailure.tooManyNodes }
        if visited.isMultiple(of: 128) { try context.checkpoint() }
        var type = try describe(tag: table.uint8(2), table: try table.table(3))
        if let dictionary = try table.table(4) {
            let indices = try dictionary.table(1).map { try describe(tag: 2, table: $0) } ?? "int32"
            type = "dictionary<values=\(type), indices=\(indices)>"
        }
        var result = ArrowField(name: try table.string(0) ?? "", type: type, nullable: try table.bool(1))
        if let vector = try table.vector(5, elementSize: 4) {
            for index in 0..<vector.count {
                result.children.append(try field(try table.vectorTable(at: index, in: vector),
                                                 depth: depth + 1, visited: &visited, context: context))
            }
        }
        return result
    }

    private static let timeUnits = ["s", "ms", "us", "ns"]

    private static func unit(_ table: FlatTable?, slot: Int, default fallback: Int16) throws -> String {
        let value = Int(try table?.int16(slot, default: fallback) ?? fallback)
        return timeUnits.indices.contains(value) ? timeUnits[value] : "?"
    }

    /// Arrow's usual spelling of a type, as shown by the reference implementations.
    static func describe(tag: UInt8, table: FlatTable?) throws -> String {
        switch tag {
        case 1: return "null"
        case 2:
            let width = try table?.int32(0) ?? 0
            let signed = try table?.bool(1) ?? false
            return (signed ? "int" : "uint") + String(width)
        case 3:
            switch try table?.int16(0) ?? 0 {
            case 0: return "float16"
            case 1: return "float32"
            case 2: return "float64"
            default: return "float?"
            }
        case 4: return "binary"
        case 5: return "utf8"
        case 6: return "bool"
        case 7:
            let width = try table?.int32(2, default: 128) ?? 128
            return "decimal\(width)(\(try table?.int32(0) ?? 0), \(try table?.int32(1) ?? 0))"
        case 8:
            let dateUnit = try table?.int16(0, default: 1) ?? 1
            return dateUnit == 0 ? "date32[day]" : "date64[ms]"
        case 9:
            let width = try table?.int32(1, default: 32) ?? 32
            return "time\(width)[\(try unit(table, slot: 0, default: 1))]"
        case 10:
            let zone = try table?.string(1, maximumBytes: 64)
            return "timestamp[\(try unit(table, slot: 0, default: 0))\(zone.map { ", tz=" + $0 } ?? "")]"
        case 11:
            let names = ["year_month", "day_time", "month_day_nano"]
            let value = Int(try table?.int16(0) ?? 0)
            return "interval[\(names.indices.contains(value) ? names[value] : "?")]"
        case 12: return "list"
        case 13: return "struct"
        case 14:
            let mode = try table?.int16(0) ?? 0
            return "union[\(mode == 0 ? "sparse" : "dense")]"
        case 15: return "fixed_size_binary[\(try table?.int32(0) ?? 0)]"
        case 16: return "fixed_size_list[\(try table?.int32(0) ?? 0)]"
        case 17: return "map"
        case 18: return "duration[\(try unit(table, slot: 0, default: 1))]"
        case 19: return "large_binary"
        case 20: return "large_utf8"
        case 21: return "large_list"
        case 22: return "run_end_encoded"
        case 23: return "binary_view"
        case 24: return "string_view"
        case 25: return "list_view"
        case 26: return "large_list_view"
        default: return "type#\(tag)"
        }
    }
}

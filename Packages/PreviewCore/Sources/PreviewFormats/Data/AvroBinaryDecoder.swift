import Foundation
import PreviewContracts

/// Thrown by `AvroBinaryReader` when the buffer ends inside a value. The header scan treats it as
/// "read more bytes"; anywhere else it means a truncated or corrupt block.
struct AvroUnderflow: Error {}

/// A decoded Avro value reduced to what the preview shows. Binary content (`bytes`, `fixed`) is
/// reduced to its length, strings are clipped, and collections keep a bounded prefix.
indirect enum AvroValue {
    case null
    case boolean(Bool)
    case integer(Int64)
    case float(Float)
    case double(Double)
    case string(String)
    case symbol(String)
    case binary(byteCount: Int)
    case array([AvroValue], total: Int)
    case map([(key: String, value: AvroValue)], total: Int)
    case record([(name: String, value: AvroValue)])
}

/// A bounded reader of the Avro binary encoding (zig-zag variable-length integers, little-endian
/// floats, length-prefixed strings and bytes). Every length is checked against the bytes that
/// remain before use, so a corrupt length can neither over-read nor allocate.
struct AvroBinaryReader {
    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - position }

    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw AvroUnderflow() }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func long() throws -> Int64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            let next = try byte()
            if index == 9, next > 1 { throw PreviewFailure.malformedDocument }
            value |= UInt64(next & 0x7F) << UInt64(index * 7)
            if next & 0x80 == 0 { return Int64(bitPattern: value >> 1) ^ -Int64(bitPattern: value & 1) }
        }
        throw PreviewFailure.malformedDocument
    }

    /// A non-negative length that fits in the bytes still to come.
    mutating func length() throws -> Int {
        let value = try long()
        guard value >= 0 else { throw PreviewFailure.malformedDocument }
        guard value <= Int64(remaining) else {
            // A length beyond the buffer is truncation while scanning a header, corruption elsewhere.
            throw AvroUnderflow()
        }
        return Int(value)
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw AvroUnderflow() }
        defer { position += count }
        return bytes[position..<(position + count)]
    }

    mutating func float() throws -> Float {
        let raw = try take(4)
        return Float(bitPattern: raw.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) })
    }

    mutating func double() throws -> Double {
        let raw = try take(8)
        return Double(bitPattern: raw.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) })
    }

    /// A string clipped to `maximumBytes`; the rest is consumed. Invalid UTF-8 becomes U+FFFD.
    mutating func string(maximumBytes: Int) throws -> String {
        let count = try length()
        var kept = Array(try take(count).prefix(maximumBytes))
        if kept.count < count { Self.trimIncompleteScalar(&kept) }
        return String(decoding: kept, as: UTF8.self)
    }

    private static func trimIncompleteScalar(_ bytes: inout [UInt8]) {
        var index = bytes.count - 1
        var continuation = 0
        while index >= 0, bytes[index] & 0xC0 == 0x80, continuation < 3 {
            index -= 1
            continuation += 1
        }
        guard index >= 0 else { return }
        let lead = bytes[index]
        let expected = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        if expected > continuation + 1 { bytes.removeSubrange(index...) }
    }
}

/// Decodes values of one schema from one decompressed block. Work, nesting and retained
/// collection sizes are bounded, so a block cannot cost more than its own byte length plus a fixed
/// allowance, even for schemas whose values occupy no bytes (null, empty records).
struct AvroValueDecoder {
    static let maximumDepth = 24
    static let retainedItems = 16
    static let retainedStringBytes = 512

    private var reader: AvroBinaryReader
    private let schema: AvroSchema
    private let context: RequestContext
    private var remainingWork: Int

    init(block: [UInt8], schema: AvroSchema, context: RequestContext, workAllowance: Int) {
        reader = AvroBinaryReader(block)
        self.schema = schema
        self.context = context
        remainingWork = workAllowance
    }

    var isAtEnd: Bool { reader.remaining == 0 }

    mutating func value(_ node: AvroSchemaNode, depth: Int = 1) throws -> AvroValue {
        guard depth <= Self.maximumDepth else { throw PreviewFailure.structureTooDeep }
        remainingWork -= 1
        guard remainingWork >= 0 else { throw PreviewFailure.tooManyNodes }
        if remainingWork.isMultiple(of: 1_024) { try context.checkpoint() }
        let node = try schema.resolve(node)
        do {
            switch node.kind {
            case .null: return .null
            case .boolean:
                let raw = try reader.byte()
                guard raw <= 1 else { throw PreviewFailure.malformedDocument }
                return .boolean(raw == 1)
            case .int:
                let raw = try reader.long()
                guard let narrowed = Int32(exactly: raw) else { throw PreviewFailure.malformedDocument }
                return .integer(Int64(narrowed))
            case .long: return .integer(try reader.long())
            case .float: return .float(try reader.float())
            case .double: return .double(try reader.double())
            case .bytes: return .binary(byteCount: try reader.take(try reader.length()).count)
            case .string: return .string(try reader.string(maximumBytes: Self.retainedStringBytes))
            case .fixed: return .binary(byteCount: try reader.take(node.size).count)
            case .enumeration:
                let index = try reader.long()
                guard index >= 0, index < Int64(node.symbols.count) else { throw PreviewFailure.malformedDocument }
                return .symbol(node.symbols[Int(index)])
            case .union:
                let index = try reader.long()
                guard index >= 0, index < Int64(node.children.count) else { throw PreviewFailure.malformedDocument }
                return try value(node.children[Int(index)], depth: depth + 1)
            case .record:
                var fields: [(name: String, value: AvroValue)] = []
                for field in node.fields { fields.append((field.name, try value(field.node, depth: depth + 1))) }
                return .record(fields)
            case .array:
                var kept: [AvroValue] = []
                var total = 0
                while let count = try nextBlockCount(total: total) {
                    for _ in 0..<count {
                        let item = try value(node.children[0], depth: depth + 1)
                        if kept.count < Self.retainedItems { kept.append(item) }
                    }
                    total += count
                }
                return .array(kept, total: total)
            case .map:
                var kept: [(key: String, value: AvroValue)] = []
                var total = 0
                while let count = try nextBlockCount(total: total) {
                    for _ in 0..<count {
                        let key = try reader.string(maximumBytes: 256)
                        let item = try value(node.children[0], depth: depth + 1)
                        if kept.count < Self.retainedItems { kept.append((key, item)) }
                    }
                    total += count
                }
                return .map(kept, total: total)
            case .reference: throw PreviewFailure.malformedDocument
            }
        } catch is AvroUnderflow {
            // Inside a block the whole payload is present, so running out of bytes is corruption.
            throw PreviewFailure.malformedDocument
        }
    }

    /// The item count of the next array or map block, or nil at the terminating empty block. A
    /// negative count is followed by the block's byte size, which is not needed here.
    private mutating func nextBlockCount(total: Int) throws -> Int? {
        var count = try reader.long()
        if count == 0 { return nil }
        if count < 0 {
            guard count != Int64.min else { throw PreviewFailure.malformedDocument }
            count = -count
            _ = try reader.long()
        }
        guard count <= 1_000_000, total + Int(count) <= 1_000_000 else { throw PreviewFailure.tooManyNodes }
        return Int(count)
    }
}

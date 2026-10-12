import Foundation
import PreviewContracts

/// A bounded, cancellable reader for the Apache Thrift compact protocol, written from the public
/// protocol description. It decodes only the shapes that the Parquet footer uses and skips every
/// other field, so an unknown or future field can never change what is displayed.
///
/// Every length is checked against the bytes that remain before anything is allocated or read,
/// nesting is capped, and a varint is at most ten bytes. Failures are `malformedDocument`
/// (truncation, bad lengths, overlong varints) or `structureTooDeep`.
struct ThriftCompactReader {
    enum WireType: UInt8 {
        case stop = 0, booleanTrue = 1, booleanFalse = 2, byte = 3, i16 = 4, i32 = 5, i64 = 6
        case double = 7, binary = 8, list = 9, set = 10, map = 11, structure = 12
    }

    static let maximumDepth = 24

    private let bytes: [UInt8]
    private let context: RequestContext
    private(set) var position = 0
    private var checkpointPosition = 0

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
    }

    var remaining: Int { bytes.count - position }

    // MARK: Primitives

    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func varint() throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<10 {
            let next = try byte()
            // The tenth byte may contribute only the single remaining bit of a 64-bit value.
            if index == 9, next > 1 { throw PreviewFailure.malformedDocument }
            value |= UInt64(next & 0x7F) << UInt64(index * 7)
            if next & 0x80 == 0 { return value }
        }
        throw PreviewFailure.malformedDocument
    }

    mutating func zigzag64() throws -> Int64 {
        let raw = try varint()
        return Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1)
    }

    mutating func zigzag32() throws -> Int32 {
        let value = try zigzag64()
        guard let narrowed = Int32(exactly: value) else { throw PreviewFailure.malformedDocument }
        return narrowed
    }

    /// Length-prefixed bytes, validated against the remaining input before they are copied.
    /// At most `maximumBytes` are kept; the rest are skipped.
    mutating func binary(maximumBytes: Int) throws -> (bytes: ArraySlice<UInt8>, clipped: Bool) {
        let length = try varint()
        guard length <= UInt64(remaining) else { throw PreviewFailure.malformedDocument }
        let count = Int(length)
        let kept = min(count, maximumBytes)
        let slice = bytes[position..<(position + kept)]
        position += count
        return (slice, kept < count)
    }

    /// A UTF-8 string clipped at a character boundary; invalid sequences become U+FFFD.
    mutating func string(maximumBytes: Int = 512) throws -> String {
        let (slice, clipped) = try binary(maximumBytes: maximumBytes)
        var kept = Array(slice)
        if clipped { Self.trimIncompleteScalar(&kept) }
        return String(decoding: kept, as: UTF8.self)
    }

    mutating func double() throws -> Double {
        guard remaining >= 8 else { throw PreviewFailure.malformedDocument }
        var bits: UInt64 = 0
        for index in 0..<8 { bits |= UInt64(bytes[position + index]) << UInt64(index * 8) }
        position += 8
        return Double(bitPattern: bits)
    }

    // MARK: Containers

    /// The element type and count of a list or set.
    mutating func listHeader() throws -> (element: WireType, count: Int) {
        let header = try byte()
        guard let element = WireType(rawValue: header & 0x0F), element != .stop else { throw PreviewFailure.malformedDocument }
        var count = Int(header >> 4)
        if count == 15 {
            let large = try varint()
            guard large <= UInt64(remaining) else { throw PreviewFailure.malformedDocument }
            count = Int(large)
        }
        // Every element occupies at least one byte (a struct has its stop byte, a boolean its own
        // byte), so a count beyond the remaining bytes is corrupt, not merely large.
        guard count <= remaining else { throw PreviewFailure.malformedDocument }
        return (element, count)
    }

    /// Visits the fields of a struct. `body` returns true when it consumed the field's value; a
    /// field it declines is skipped by type.
    mutating func structure(depth: Int,
                            _ body: (_ id: Int, _ type: WireType, _ reader: inout ThriftCompactReader) throws -> Bool) throws {
        guard depth <= Self.maximumDepth else { throw PreviewFailure.structureTooDeep }
        var lastID = 0
        while true {
            try tick()
            let header = try byte()
            if header == 0 { return }
            guard let type = WireType(rawValue: header & 0x0F), type != .stop else { throw PreviewFailure.malformedDocument }
            let delta = Int(header >> 4)
            if delta == 0 {
                // A long-form field identifier is a zigzag-encoded 16-bit integer.
                let identifier = try zigzag64()
                guard (0...Int64(Int16.max)).contains(identifier) else { throw PreviewFailure.malformedDocument }
                lastID = Int(identifier)
            } else {
                lastID += delta
            }
            let handled = try body(lastID, type, &self)
            if !handled { try skip(type, depth: depth + 1, inCollection: false) }
        }
    }

    /// Skips one value. A boolean field carries its value in the type nibble; a boolean inside a
    /// list or set occupies one byte.
    mutating func skip(_ type: WireType, depth: Int, inCollection: Bool) throws {
        guard depth <= Self.maximumDepth else { throw PreviewFailure.structureTooDeep }
        try tick()
        switch type {
        case .stop: throw PreviewFailure.malformedDocument
        case .booleanTrue, .booleanFalse: if inCollection { _ = try byte() }
        case .byte: _ = try byte()
        case .i16, .i32, .i64: _ = try varint()
        case .double: guard remaining >= 8 else { throw PreviewFailure.malformedDocument }; position += 8
        case .binary: _ = try binary(maximumBytes: 0)
        case .list, .set:
            let (element, count) = try listHeader()
            for _ in 0..<count { try skip(element, depth: depth + 1, inCollection: true) }
        case .map:
            let count = try varint()
            guard count <= UInt64(remaining) else { throw PreviewFailure.malformedDocument }
            if count > 0 {
                let types = try byte()
                guard let key = WireType(rawValue: types >> 4), let value = WireType(rawValue: types & 0x0F),
                      key != .stop, value != .stop else { throw PreviewFailure.malformedDocument }
                for _ in 0..<Int(count) {
                    try skip(key, depth: depth + 1, inCollection: true)
                    try skip(value, depth: depth + 1, inCollection: true)
                }
            }
        case .structure:
            try structure(depth: depth) { _, _, _ in false }
        }
    }

    private mutating func tick() throws {
        if position - checkpointPosition >= 1_024 {
            try context.checkpoint()
            checkpointPosition = position
        }
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

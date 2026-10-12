import Foundation
import PreviewContracts

/// A minimal, bounds-checked FlatBuffers reader, written from the public format description, for
/// the few Arrow IPC tables the preview reads. Every offset is validated against the buffer before
/// it is followed; a table whose vtable or field lies outside the buffer is `malformedDocument`.
///
/// FlatBuffers offsets can alias or point backwards, so a hostile buffer could describe a cycle or
/// an exponentially shared tree. The reader therefore only hands out typed accessors; callers walk
/// with an explicit depth limit and a shared node counter (`FlatBufferWalk`).
struct FlatBuffer {
    let bytes: [UInt8]

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func u8(at position: Int) throws -> UInt8 {
        guard position >= 0, position < bytes.count else { throw PreviewFailure.malformedDocument }
        return bytes[position]
    }

    func u16(at position: Int) throws -> UInt16 {
        guard position >= 0, position + 2 <= bytes.count else { throw PreviewFailure.malformedDocument }
        return UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8
    }

    func u32(at position: Int) throws -> UInt32 {
        guard position >= 0, position + 4 <= bytes.count else { throw PreviewFailure.malformedDocument }
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[position + $1]) << UInt32($1 * 8) }
    }

    func u64(at position: Int) throws -> UInt64 {
        guard position >= 0, position + 8 <= bytes.count else { throw PreviewFailure.malformedDocument }
        return (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[position + $1]) << UInt64($1 * 8) }
    }

    /// The table the buffer's leading offset names.
    func rootTable() throws -> FlatTable {
        try table(at: Int(try u32(at: 0)))
    }

    func table(at position: Int) throws -> FlatTable {
        // The table starts with a signed offset back to its vtable.
        let relative = Int(Int32(bitPattern: try u32(at: position)))
        let vtable = position - relative
        guard vtable >= 0, vtable + 4 <= bytes.count else { throw PreviewFailure.malformedDocument }
        let vtableLength = Int(try u16(at: vtable))
        guard vtableLength >= 4, vtableLength % 2 == 0, vtable + vtableLength <= bytes.count else {
            throw PreviewFailure.malformedDocument
        }
        return FlatTable(buffer: self, position: position, vtable: vtable, vtableLength: vtableLength)
    }
}

struct FlatTable {
    let buffer: FlatBuffer
    let position: Int
    let vtable: Int
    let vtableLength: Int

    /// Absolute position of a field's data, or nil when the table omits it.
    func field(_ slot: Int) throws -> Int? {
        let entry = 4 + slot * 2
        guard entry + 2 <= vtableLength else { return nil }
        let offset = Int(try buffer.u16(at: vtable + entry))
        return offset == 0 ? nil : position + offset
    }

    func int16(_ slot: Int, default fallback: Int16 = 0) throws -> Int16 {
        guard let at = try field(slot) else { return fallback }
        return Int16(bitPattern: try buffer.u16(at: at))
    }

    func int32(_ slot: Int, default fallback: Int32 = 0) throws -> Int32 {
        guard let at = try field(slot) else { return fallback }
        return Int32(bitPattern: try buffer.u32(at: at))
    }

    func int64(_ slot: Int, default fallback: Int64 = 0) throws -> Int64 {
        guard let at = try field(slot) else { return fallback }
        return Int64(bitPattern: try buffer.u64(at: at))
    }

    func uint8(_ slot: Int, default fallback: UInt8 = 0) throws -> UInt8 {
        guard let at = try field(slot) else { return fallback }
        return try buffer.u8(at: at)
    }

    func bool(_ slot: Int, default fallback: Bool = false) throws -> Bool {
        try uint8(slot, default: fallback ? 1 : 0) != 0
    }

    /// A table referenced by an unsigned offset stored in the field.
    func table(_ slot: Int) throws -> FlatTable? {
        guard let at = try field(slot) else { return nil }
        return try buffer.table(at: at + Int(try buffer.u32(at: at)))
    }

    /// A string clipped to `maximumBytes`; invalid UTF-8 becomes U+FFFD.
    func string(_ slot: Int, maximumBytes: Int = 256) throws -> String? {
        guard let at = try field(slot) else { return nil }
        let start = at + Int(try buffer.u32(at: at))
        let length = Int(try buffer.u32(at: start))
        guard start + 4 + length <= buffer.bytes.count else { throw PreviewFailure.malformedDocument }
        var kept = Array(buffer.bytes[(start + 4)..<(start + 4 + min(length, maximumBytes))])
        if kept.count < length { Self.trimIncompleteScalar(&kept) }
        return String(decoding: kept, as: UTF8.self)
    }

    /// The element count and absolute start of a vector field.
    func vector(_ slot: Int, elementSize: Int) throws -> (start: Int, count: Int)? {
        guard let at = try field(slot) else { return nil }
        let start = at + Int(try buffer.u32(at: at))
        let count = Int(try buffer.u32(at: start))
        guard elementSize > 0, count <= (buffer.bytes.count - start - 4) / elementSize else {
            throw PreviewFailure.malformedDocument
        }
        return (start + 4, count)
    }

    /// The tables of a vector of table offsets, by index, so callers can bound how many they open.
    func vectorTable(at index: Int, in vector: (start: Int, count: Int)) throws -> FlatTable {
        guard index >= 0, index < vector.count else { throw PreviewFailure.malformedDocument }
        let at = vector.start + index * 4
        return try buffer.table(at: at + Int(try buffer.u32(at: at)))
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

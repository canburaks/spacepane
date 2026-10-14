import Foundation

/// Synthetic GGUF files assembled byte by byte. Nothing here is a real model; names and values are made up.
/// The tensor sizes below are written out independently of the production type table on purpose, so a
/// wrong constant in either place fails a test.
enum GGUFFixtures {
    /// A GGUF metadata value.
    indirect enum Value {
        case u8(UInt8), i8(Int8), u16(UInt16), i16(Int16), u32(UInt32), i32(Int32), f32(Float), bool(Bool)
        case string(String), u64(UInt64), i64(Int64), f64(Double)
        case strings([String])
        /// An array of fixed-width numbers: its element type, its count and `count * width` zero bytes.
        case zeros(type: UInt32, count: Int)
        /// An array whose header says one thing and whose bytes may say another.
        case rawArray(type: UInt32, count: UInt64, payload: [UInt8])
        case nested([Value])
    }

    struct Tensor {
        var name: String
        var dimensions: [UInt64]
        var type: UInt32
        var offset: UInt64
    }

    struct Built {
        var data: Data
        /// Offset of the first byte after the last tensor info.
        var headerEnd: Int
        /// Offset where tensor data starts after alignment padding.
        var dataStart: Int
    }

    static let magic: [UInt8] = [0x47, 0x47, 0x55, 0x46]

    /// Bytes of a tensor with these dimensions, from first principles for the types the tests use.
    static func byteCount(type: UInt32, dimensions: [UInt64]) -> UInt64 {
        let elements = dimensions.reduce(1, *)
        switch type {
        case 0: return elements * 4
        case 1, 30: return elements * 2
        case 2: return elements / 32 * 18
        case 8: return elements / 32 * 34
        case 12: return elements / 256 * 144
        case 14: return elements / 256 * 210
        default: preconditionFailure("fixture has no size for type \(type)")
        }
    }

    /// A tensor placed right after the previous ones, each starting on the alignment.
    static func laidOut(_ specs: [(String, [UInt64], UInt32)], alignment: UInt64 = 32) -> [Tensor] {
        var offset: UInt64 = 0
        return specs.map { name, dimensions, type in
            defer {
                let end = offset + byteCount(type: type, dimensions: dimensions)
                offset = (end + alignment - 1) / alignment * alignment
            }
            return Tensor(name: name, dimensions: dimensions, type: type, offset: offset)
        }
    }

    static func total(_ tensors: [Tensor], alignment: UInt64 = 32) -> Int {
        guard let last = tensors.max(by: { $0.offset < $1.offset }) else { return 0 }
        return Int(last.offset + byteCount(type: last.type, dimensions: last.dimensions))
    }

    /// Assembles a file. `dataBytes` of zeros follow the padding; `nil` writes exactly the bytes the
    /// tensors need, so the file is complete.
    static func build(version: UInt32 = 3, bigEndian: Bool = false, metadata: [(String, Value)] = [],
                      tensors: [Tensor] = [], alignment: Int = 32, dataBytes: Int? = nil,
                      declaredTensorCount: UInt64? = nil, declaredMetadataCount: UInt64? = nil) -> Built {
        var writer = Writer(bigEndian: bigEndian)
        writer.bytes(magic)
        writer.u32(version)
        writer.u64(declaredTensorCount ?? UInt64(tensors.count))
        writer.u64(declaredMetadataCount ?? UInt64(metadata.count))
        for (key, value) in metadata {
            writer.string(key)
            writer.typeAndValue(value)
        }
        for tensor in tensors {
            writer.string(tensor.name)
            writer.u32(UInt32(tensor.dimensions.count))
            for dimension in tensor.dimensions { writer.u64(dimension) }
            writer.u32(tensor.type)
            writer.u64(tensor.offset)
        }
        let headerEnd = writer.output.count
        let padded = (headerEnd + alignment - 1) / alignment * alignment
        writer.bytes([UInt8](repeating: 0, count: padded - headerEnd))
        writer.bytes([UInt8](repeating: 0, count: dataBytes ?? total(tensors, alignment: UInt64(alignment))))
        return Built(data: Data(writer.output), headerEnd: headerEnd, dataStart: padded)
    }

    /// A small, ordinary Llama-style model file: eight metadata entries and two tensors.
    static func ordinary(bigEndian: Bool = false, version: UInt32 = 3) -> Built {
        let tensors = laidOut([("token_embd.weight", [64, 4], 0), ("blk.0.attn_q.weight", [64, 64], 8)])
        return build(version: version, bigEndian: bigEndian, metadata: [
            ("general.architecture", .string("llama")), ("general.name", .string("Synthetic Test Model")),
            ("llama.context_length", .u32(4096)), ("tokenizer.ggml.model", .string("llama")),
            ("tokenizer.ggml.tokens", .strings(["<s>", "</s>", "a", "b"])),
            ("general.alignment", .u32(32)), ("general.file_type", .u32(7)), ("llama.block_count", .u32(2))
        ], tensors: tensors)
    }

    struct Writer {
        var output: [UInt8] = []
        let bigEndian: Bool

        mutating func bytes(_ values: [UInt8]) { output += values }
        mutating func integer(_ value: UInt64, width: Int) {
            let ordered = (0..<width).map { UInt8(truncatingIfNeeded: value >> UInt64(8 * $0)) }
            output += bigEndian ? ordered.reversed() : ordered
        }
        mutating func u32(_ value: UInt32) { integer(UInt64(value), width: 4) }
        mutating func u64(_ value: UInt64) { integer(value, width: 8) }
        mutating func string(_ text: String) {
            u64(UInt64(text.utf8.count))
            output += Array(text.utf8)
        }

        mutating func typeAndValue(_ value: Value) {
            u32(Self.typeCode(value))
            body(value)
        }

        static func typeCode(_ value: Value) -> UInt32 {
            switch value {
            case .u8: 0
            case .i8: 1
            case .u16: 2
            case .i16: 3
            case .u32: 4
            case .i32: 5
            case .f32: 6
            case .bool: 7
            case .string: 8
            case .strings, .zeros, .rawArray, .nested: 9
            case .u64: 10
            case .i64: 11
            case .f64: 12
            }
        }

        mutating func body(_ value: Value) {
            switch value {
            case .u8(let number): integer(UInt64(number), width: 1)
            case .i8(let number): integer(UInt64(bitPattern: Int64(number)), width: 1)
            case .u16(let number): integer(UInt64(number), width: 2)
            case .i16(let number): integer(UInt64(bitPattern: Int64(number)), width: 2)
            case .u32(let number): integer(UInt64(number), width: 4)
            case .i32(let number): integer(UInt64(bitPattern: Int64(number)), width: 4)
            case .f32(let number): integer(UInt64(number.bitPattern), width: 4)
            case .bool(let flag): integer(flag ? 1 : 0, width: 1)
            case .string(let text): string(text)
            case .u64(let number): u64(number)
            case .i64(let number): integer(UInt64(bitPattern: number), width: 8)
            case .f64(let number): u64(number.bitPattern)
            case .strings(let items):
                u32(8)
                u64(UInt64(items.count))
                for item in items { string(item) }
            case .zeros(let type, let count):
                u32(type)
                u64(UInt64(count))
                output += [UInt8](repeating: 0, count: count * Self.width(type))
            case .rawArray(let type, let count, let payload):
                u32(type)
                u64(count)
                output += payload
            case .nested(let items):
                u32(9)
                u64(UInt64(items.count))
                for item in items { body(item) }
            }
        }

        static func width(_ type: UInt32) -> Int {
            switch type {
            case 0, 1, 7: 1
            case 2, 3: 2
            case 4, 5, 6: 4
            default: 8
            }
        }
    }
}

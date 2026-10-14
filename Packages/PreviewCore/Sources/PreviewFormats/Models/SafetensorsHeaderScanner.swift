import Foundation
import PreviewContracts

/// One tensor descriptor from a safetensors header.
struct SafetensorsTensor {
    let name: String
    let dtype: String
    let shape: [UInt64]
    /// Byte range inside the data buffer that follows the header; `end` is exclusive.
    let begin: UInt64
    let end: UInt64
}

struct SafetensorsHeader {
    var tensors: [SafetensorsTensor] = []
    /// Entries of `__metadata__`, up to `SafetensorsHeaderScanner.keptMetadataEntries`, in file order.
    var metadata: [(key: String, value: String)] = []
    var metadataCount = 0
}

/// A strict scanner for the one JSON shape a safetensors header may have: an object holding an optional
/// `__metadata__` map of strings and, for every other key, a tensor descriptor with `dtype`, `shape` and
/// `data_offsets`. It builds only that structure, refuses duplicate keys and ill-formed strings, limits
/// nesting to four levels and the tensor count to 200,000, and calls the request's checkpoint every 1,024
/// entries and every 64 KiB of header it consumes. It never evaluates anything and keeps no JSON tree.
struct SafetensorsHeaderScanner {
    static let maximumTensors = 200_000
    static let maximumDepth = 4
    static let maximumShapeRank = 64
    static let keptMetadataEntries = 64
    private static let checkpointBytes = 65_536
    private static let metadataKey = Array("__metadata__".utf8)
    private static let dtypeKey = Array("dtype".utf8)
    private static let shapeKey = Array("shape".utf8)
    private static let offsetsKey = Array("data_offsets".utf8)

    private let bytes: [UInt8]
    private let context: RequestContext
    private var position = 0
    private var lastCheckpoint = 0

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
    }

    mutating func scan() throws -> SafetensorsHeader {
        try context.checkpoint()
        guard bytes.first == UInt8(ascii: "{") else { throw PreviewFailure.malformedDocument }
        position = 1
        var header = SafetensorsHeader()
        var seen = Set<[UInt8]>()
        try skipWhitespace()
        if consume("}") { return try finish(header) }
        while true {
            let key = try string()
            guard seen.insert(key).inserted else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            guard consume(":") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            if key == Self.metadataKey {
                try metadata(into: &header)
            } else {
                guard header.tensors.count < Self.maximumTensors else { throw PreviewFailure.tooManyNodes }
                if header.tensors.count.isMultiple(of: 1_024) { try context.checkpoint() }
                header.tensors.append(try tensor(named: String(decoding: key, as: UTF8.self)))
            }
            try skipWhitespace()
            if consume("}") { return try finish(header) }
            guard consume(",") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
        }
    }

    private mutating func finish(_ header: SafetensorsHeader) throws -> SafetensorsHeader {
        try skipWhitespace()
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        return header
    }

    // MARK: Objects

    private mutating func metadata(into header: inout SafetensorsHeader) throws {
        guard consume("{") else { throw PreviewFailure.malformedDocument }
        var seen = Set<[UInt8]>()
        try skipWhitespace()
        if consume("}") { return }
        while true {
            let key = try string()
            guard seen.insert(key).inserted else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            guard consume(":") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            let value = try string()
            header.metadataCount += 1
            if header.metadata.count < Self.keptMetadataEntries {
                header.metadata.append((String(decoding: key, as: UTF8.self), String(decoding: value, as: UTF8.self)))
            }
            try skipWhitespace()
            if consume("}") { return }
            guard consume(",") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
        }
    }

    private mutating func tensor(named name: String) throws -> SafetensorsTensor {
        guard consume("{") else { throw PreviewFailure.malformedDocument }
        var dtype: String?
        var shape: [UInt64]?
        var offsets: [UInt64]?
        var seen = Set<[UInt8]>()
        try skipWhitespace()
        if consume("}") { throw PreviewFailure.malformedDocument }
        while true {
            let key = try string()
            guard seen.insert(key).inserted else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            guard consume(":") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            if key == Self.dtypeKey {
                dtype = String(decoding: try string(), as: UTF8.self)
            } else if key == Self.shapeKey {
                shape = try numbers(limit: Self.maximumShapeRank, overflow: .tooManyNodes)
            } else if key == Self.offsetsKey {
                offsets = try numbers(limit: 2, overflow: .malformedDocument)
            } else {
                try skipValue(depth: 3)
            }
            try skipWhitespace()
            if consume("}") { break }
            guard consume(",") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
        }
        guard let dtype, let shape, let offsets, offsets.count == 2, offsets[0] <= offsets[1] else {
            throw PreviewFailure.malformedDocument
        }
        return SafetensorsTensor(name: name, dtype: dtype, shape: shape, begin: offsets[0], end: offsets[1])
    }

    /// An array of non-negative integers that fit a signed 64-bit integer.
    private mutating func numbers(limit: Int, overflow: PreviewFailure) throws -> [UInt64] {
        guard consume("[") else { throw PreviewFailure.malformedDocument }
        var values: [UInt64] = []
        try skipWhitespace()
        if consume("]") { return values }
        while true {
            guard values.count < limit else { throw overflow }
            values.append(try unsignedInteger())
            try skipWhitespace()
            if consume("]") { return values }
            guard consume(",") else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
        }
    }

    private mutating func unsignedInteger() throws -> UInt64 {
        var digits = 0
        var value: UInt64 = 0
        while position < bytes.count, (48...57).contains(bytes[position]) {
            if digits == 1, value == 0 { throw PreviewFailure.malformedDocument } // leading zero
            let (scaled, overflow) = value.multipliedReportingOverflow(by: 10)
            let (sum, added) = scaled.addingReportingOverflow(UInt64(bytes[position] - 48))
            guard !overflow, !added, sum <= UInt64(Int64.max) else { throw PreviewFailure.malformedDocument }
            value = sum
            digits += 1
            position += 1
        }
        guard digits > 0 else { throw PreviewFailure.malformedDocument }
        // A fraction, exponent or sign makes it a number the format does not allow here.
        if position < bytes.count, [UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E")].contains(bytes[position]) {
            throw PreviewFailure.malformedDocument
        }
        return value
    }

    // MARK: Values that are only skipped

    /// `depth` is the nesting level a container at this position would have.
    private mutating func skipValue(depth: Int) throws {
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        switch bytes[position] {
        case UInt8(ascii: "{"):
            guard depth <= Self.maximumDepth else { throw PreviewFailure.structureTooDeep }
            position += 1
            try skipWhitespace()
            if consume("}") { return }
            while true {
                _ = try string()
                try skipWhitespace()
                guard consume(":") else { throw PreviewFailure.malformedDocument }
                try skipWhitespace()
                try skipValue(depth: depth + 1)
                try skipWhitespace()
                if consume("}") { return }
                guard consume(",") else { throw PreviewFailure.malformedDocument }
                try skipWhitespace()
            }
        case UInt8(ascii: "["):
            guard depth <= Self.maximumDepth else { throw PreviewFailure.structureTooDeep }
            position += 1
            try skipWhitespace()
            if consume("]") { return }
            while true {
                try skipValue(depth: depth + 1)
                try skipWhitespace()
                if consume("]") { return }
                guard consume(",") else { throw PreviewFailure.malformedDocument }
                try skipWhitespace()
            }
        case UInt8(ascii: "\""): _ = try string()
        case UInt8(ascii: "t"): try literal("true")
        case UInt8(ascii: "f"): try literal("false")
        case UInt8(ascii: "n"): try literal("null")
        default: try skipNumber()
        }
    }

    private mutating func literal(_ word: String) throws {
        let expected = Array(word.utf8)
        guard bytes.count - position >= expected.count, Array(bytes[position..<(position + expected.count)]) == expected else {
            throw PreviewFailure.malformedDocument
        }
        position += expected.count
    }

    private mutating func skipNumber() throws {
        _ = consume("-")
        if !consume("0") {
            guard position < bytes.count, (49...57).contains(bytes[position]) else { throw PreviewFailure.malformedDocument }
            skipDigits()
        }
        if consume(".") {
            guard position < bytes.count, (48...57).contains(bytes[position]) else { throw PreviewFailure.malformedDocument }
            skipDigits()
        }
        if consume("e") || consume("E") {
            if !consume("+") { _ = consume("-") }
            guard position < bytes.count, (48...57).contains(bytes[position]) else { throw PreviewFailure.malformedDocument }
            skipDigits()
        }
    }

    private mutating func skipDigits() {
        while position < bytes.count, (48...57).contains(bytes[position]) { position += 1 }
    }

    // MARK: Strings

    /// The decoded UTF-8 bytes of a JSON string. Control characters, bad escapes, unpaired surrogates and
    /// invalid UTF-8 are refused.
    private mutating func string() throws -> [UInt8] {
        guard consume("\"") else { throw PreviewFailure.malformedDocument }
        var decoded: [UInt8] = []
        var isASCII = true
        while position < bytes.count {
            try tick()
            let byte = bytes[position]
            position += 1
            switch byte {
            case UInt8(ascii: "\""):
                if !isASCII, String(bytes: decoded, encoding: .utf8) == nil { throw PreviewFailure.malformedDocument }
                return decoded
            case 0..<0x20: throw PreviewFailure.malformedDocument
            case UInt8(ascii: "\\"): try escape(into: &decoded)
            default:
                if byte >= 0x80 { isASCII = false }
                decoded.append(byte)
            }
        }
        throw PreviewFailure.malformedDocument
    }

    private mutating func escape(into decoded: inout [UInt8]) throws {
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        let code = bytes[position]
        position += 1
        switch code {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): decoded.append(code)
        case UInt8(ascii: "b"): decoded.append(8)
        case UInt8(ascii: "f"): decoded.append(12)
        case UInt8(ascii: "n"): decoded.append(10)
        case UInt8(ascii: "r"): decoded.append(13)
        case UInt8(ascii: "t"): decoded.append(9)
        case UInt8(ascii: "u"):
            var value = UInt32(try hexUnit())
            if (0xD800...0xDBFF).contains(value) {
                guard consume("\\"), consume("u") else { throw PreviewFailure.malformedDocument }
                let low = UInt32(try hexUnit())
                guard (0xDC00...0xDFFF).contains(low) else { throw PreviewFailure.malformedDocument }
                value = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
            } else if (0xDC00...0xDFFF).contains(value) {
                throw PreviewFailure.malformedDocument
            }
            guard let scalar = Unicode.Scalar(value) else { throw PreviewFailure.malformedDocument }
            decoded.append(contentsOf: Array(String(Character(scalar)).utf8))
        default: throw PreviewFailure.malformedDocument
        }
    }

    private mutating func hexUnit() throws -> UInt16 {
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard position < bytes.count else { throw PreviewFailure.malformedDocument }
            let digit: UInt16
            switch bytes[position] {
            case 48...57: digit = UInt16(bytes[position] - 48)
            case 65...70: digit = UInt16(bytes[position] - 55)
            case 97...102: digit = UInt16(bytes[position] - 87)
            default: throw PreviewFailure.malformedDocument
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    // MARK: Lexical helpers

    private mutating func consume(_ character: Unicode.Scalar) -> Bool {
        guard position < bytes.count, bytes[position] == UInt8(ascii: character) else { return false }
        position += 1
        return true
    }

    private mutating func skipWhitespace() throws {
        while position < bytes.count, Self.isWhitespace(bytes[position]) {
            position += 1
            try tick()
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }

    private mutating func tick() throws {
        guard position - lastCheckpoint >= Self.checkpointBytes else { return }
        lastCheckpoint = position
        try context.checkpoint()
    }
}

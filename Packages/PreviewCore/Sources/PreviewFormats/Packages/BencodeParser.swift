import Foundation
import PreviewContracts

/// A parsed bencode value. Strings are byte ranges into the source so large `pieces` hashes are never
/// copied, and a dictionary entry remembers the exact byte range of its value, which a torrent's
/// info-hash is computed over.
indirect enum BencodeValue: Equatable {
    case integer(Int64)
    case string(Range<Int>)
    case list([BencodeValue])
    case dictionary([BencodeEntry])

    func entry(_ key: String) -> BencodeEntry? {
        guard case .dictionary(let entries) = self else { return nil }
        return entries.first { $0.key == key }
    }
}

struct BencodeEntry: Equatable {
    let key: String
    let value: BencodeValue
    /// Exact bytes of the encoded value within the source, for hashing.
    let valueRange: Range<Int>
}

/// A strict, bounded bencode reader (BEP 3): `i<integer>e`, `<length>:<bytes>`, `l...e` and `d...e`.
///
/// Integers must be canonical (no leading zeros, no negative zero) and fit `Int64`; lengths are checked
/// against the remaining input before use; nesting depth and node count are capped; duplicate dictionary
/// keys and trailing data other than whitespace are rejected. Nothing is interpreted or fetched.
struct BencodeParser {
    let bytes: [UInt8]
    let context: RequestContext
    let maximumDepth: Int
    let maximumNodes: Int
    private var position = 0
    private var nodes = 0

    init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
        maximumDepth = min(context.budget.maxJSONDepth, 32)
        maximumNodes = 250_000
    }

    /// Parses exactly one root value.
    mutating func parseDocument() throws -> BencodeValue {
        let value = try parseValue(depth: 0)
        while position < bytes.count, [0x0A, 0x0D, 0x20, 0x09].contains(bytes[position]) { position += 1 }
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        return value
    }

    func text(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }

    private mutating func parseValue(depth: Int) throws -> BencodeValue {
        nodes += 1
        if nodes.isMultiple(of: 1_024) { try context.checkpoint() }
        guard nodes <= maximumNodes else { throw PreviewFailure.tooManyNodes }
        guard depth <= maximumDepth else { throw PreviewFailure.structureTooDeep }
        guard position < bytes.count else { throw PreviewFailure.malformedDocument }
        switch bytes[position] {
        case UInt8(ascii: "i"): return .integer(try parseInteger())
        case UInt8(ascii: "l"):
            position += 1
            var items: [BencodeValue] = []
            while true {
                guard position < bytes.count else { throw PreviewFailure.malformedDocument }
                if bytes[position] == UInt8(ascii: "e") { position += 1; return .list(items) }
                items.append(try parseValue(depth: depth + 1))
            }
        case UInt8(ascii: "d"):
            position += 1
            var entries: [BencodeEntry] = []
            var keys = Set<[UInt8]>()
            while true {
                guard position < bytes.count else { throw PreviewFailure.malformedDocument }
                if bytes[position] == UInt8(ascii: "e") { position += 1; return .dictionary(entries) }
                // Keys are byte strings. A key that is not valid UTF-8 can never match a name this reader looks up.
                guard bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "9") else { throw PreviewFailure.malformedDocument }
                let keyRange = try parseString()
                guard keys.insert(Array(bytes[keyRange])).inserted else { throw PreviewFailure.malformedDocument }
                let start = position
                let value = try parseValue(depth: depth + 1)
                entries.append(BencodeEntry(key: String(decoding: bytes[keyRange], as: UTF8.self), value: value, valueRange: start..<position))
            }
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return .string(try parseString())
        default: throw PreviewFailure.malformedDocument
        }
    }

    private mutating func parseInteger() throws -> Int64 {
        position += 1 // i
        let start = position
        if position < bytes.count, bytes[position] == UInt8(ascii: "-") { position += 1 }
        let digitsStart = position
        while position < bytes.count, bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "9") { position += 1 }
        let digits = position - digitsStart
        guard digits > 0, digits <= 18, position < bytes.count, bytes[position] == UInt8(ascii: "e") else { throw PreviewFailure.malformedDocument }
        let negative = digitsStart > start
        // Canonical form: no leading zero unless the number is exactly zero, and no "-0".
        if bytes[digitsStart] == UInt8(ascii: "0"), digits > 1 || negative { throw PreviewFailure.malformedDocument }
        guard let value = Int64(String(decoding: bytes[start..<position], as: UTF8.self)) else { throw PreviewFailure.malformedDocument }
        position += 1 // e
        return value
    }

    private mutating func parseString() throws -> Range<Int> {
        let start = position
        while position < bytes.count, bytes[position] >= UInt8(ascii: "0"), bytes[position] <= UInt8(ascii: "9") { position += 1 }
        let digits = position - start
        guard digits > 0, digits <= 10, position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw PreviewFailure.malformedDocument }
        if bytes[start] == UInt8(ascii: "0"), digits > 1 { throw PreviewFailure.malformedDocument }
        guard let length = Int(String(decoding: bytes[start..<position], as: UTF8.self)) else { throw PreviewFailure.malformedDocument }
        position += 1 // :
        guard length <= bytes.count - position else { throw PreviewFailure.malformedDocument }
        defer { position += length }
        return position..<(position + length)
    }
}

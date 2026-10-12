import Foundation
import PreviewContracts

/// A decoder for the raw Snappy block format, written from the public format description.
///
/// A block starts with the uncompressed length as a varint, followed by elements: a literal run
/// (tag type 0) or a copy of earlier output with a 1-, 2- or 4-byte offset (tag types 1, 2, 3).
/// The declared length is checked against `maximum` before any output is allocated, every literal
/// and copy is checked against the input and the output produced so far, and a block that
/// produces anything but its declared length is malformed. Overlapping copies repeat bytes, as
/// the format requires. The caller owns any framing around the block.
enum SnappyDecoder {
    static func decode(_ input: some Collection<UInt8>, maximum: Int, context: RequestContext) throws -> [UInt8] {
        try context.checkpoint()
        let bytes = Array(input)
        var position = 0
        var length: UInt64 = 0
        for index in 0..<5 {
            guard position < bytes.count else { throw PreviewFailure.malformedDocument }
            let byte = bytes[position]
            position += 1
            length |= UInt64(byte & 0x7F) << UInt64(index * 7)
            if byte & 0x80 == 0 { break }
            // A fifth continuation byte would exceed 32 bits.
            if index == 4 { throw PreviewFailure.malformedDocument }
        }
        guard length <= UInt64(maximum) else { throw PreviewFailure.outputTooLarge }
        let expected = Int(length)
        var output: [UInt8] = []
        // Snappy cannot expand more than about 21 to 1, so a short input never reserves the declared size.
        output.reserveCapacity(min(expected, bytes.count * 24))
        var elements = 0
        while output.count < expected {
            elements += 1
            if elements.isMultiple(of: 4_096) { try context.checkpoint() }
            guard position < bytes.count else { throw PreviewFailure.malformedDocument }
            let tag = bytes[position]
            position += 1
            switch tag & 0x03 {
            case 0:
                var literal = Int(tag >> 2)
                if literal >= 60 {
                    // 60...63 mean the length follows in one to four little-endian bytes.
                    let extra = literal - 59
                    guard position + extra <= bytes.count else { throw PreviewFailure.malformedDocument }
                    literal = 0
                    for offset in 0..<extra { literal |= Int(bytes[position + offset]) << (offset * 8) }
                    position += extra
                }
                literal += 1
                guard literal <= bytes.count - position, literal <= expected - output.count else {
                    throw PreviewFailure.malformedDocument
                }
                output.append(contentsOf: bytes[position..<(position + literal)])
                position += literal
            default:
                let copyLength: Int
                let offset: Int
                switch tag & 0x03 {
                case 1:
                    guard position < bytes.count else { throw PreviewFailure.malformedDocument }
                    copyLength = 4 + Int((tag >> 2) & 0x07)
                    offset = Int(tag >> 5) << 8 | Int(bytes[position])
                    position += 1
                case 2:
                    guard position + 2 <= bytes.count else { throw PreviewFailure.malformedDocument }
                    copyLength = 1 + Int(tag >> 2)
                    offset = Int(bytes[position]) | Int(bytes[position + 1]) << 8
                    position += 2
                default:
                    guard position + 4 <= bytes.count else { throw PreviewFailure.malformedDocument }
                    copyLength = 1 + Int(tag >> 2)
                    offset = (0..<4).reduce(0) { $0 | Int(bytes[position + $1]) << ($1 * 8) }
                    position += 4
                }
                guard offset > 0, offset <= output.count, copyLength <= expected - output.count else {
                    throw PreviewFailure.malformedDocument
                }
                // Byte by byte: a copy may overlap the bytes it is producing.
                var source = output.count - offset
                for _ in 0..<copyLength {
                    output.append(output[source])
                    source += 1
                }
            }
        }
        guard position == bytes.count else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        return output
    }
}

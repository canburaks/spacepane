import Foundation
import PreviewContracts

/// Limits checked before any decoder allocation. They bound untrusted headers; they are not a
/// promise to preempt a blocking call, but the decoder checks the request deadline regularly.
struct LZMALimits {
    /// Largest dictionary a stream may declare. The decoder keeps the whole bounded output as its
    /// window, so this value never sizes an allocation: it only limits how far a match may reach.
    var maximumDictionaryBytes = 67_108_864
    /// Largest output the caller will accept; the output buffer is allocated at the declared size.
    var maximumOutputBytes: Int
}

/// Raw LZMA decoder for 7z coder streams, written from the public LZMA format description
/// (the LZMA SDK specification is in the public domain). Input and output are in memory, the output
/// size comes from the container, and cancellation is checked as symbols are decoded.
enum LZMADecoder {
    /// `properties` is the 5-byte 7z coder property block: lc/lp/pb byte, then the little-endian dictionary size.
    static func decode(_ input: [UInt8], properties: [UInt8], outputSize: Int, limits: LZMALimits,
                       context: RequestContext) throws -> [UInt8] {
        try context.checkpoint()
        guard properties.count == 5, properties[0] < 9 * 5 * 5 else { throw PreviewFailure.malformedDocument }
        let dictionary = properties[1...4].reversed().reduce(0) { ($0 << 8) | Int($1) }
        guard dictionary <= limits.maximumDictionaryBytes else { throw PreviewFailure.inputTooLarge }
        guard outputSize >= 0, outputSize <= limits.maximumOutputBytes else { throw PreviewFailure.outputTooLarge }
        var engine = LZMAEngine(outputSize: outputSize, dictionarySize: max(dictionary, 4_096))
        try engine.setProperties(properties[0])
        engine.resetState()
        engine.resetDictionary()
        guard !input.isEmpty else { throw PreviewFailure.malformedDocument }
        var coder = try LZMARangeDecoder(input: input, start: 0, end: input.count)
        // A stream may end with an end marker after exactly `outputSize` bytes; it is not required
        // and is not read. A marker before that point means the stream is shorter than declared.
        if try engine.decode(&coder, until: outputSize, context: context) { throw PreviewFailure.malformedDocument }
        return engine.output
    }
}

/// Binary range decoder from the LZMA specification. Reading past the declared input fails
/// instead of returning zeros, so a truncated stream cannot decode to plausible data.
struct LZMARangeDecoder {
    private let input: [UInt8]
    private(set) var position: Int
    private let end: Int
    private var range: UInt32 = 0xFFFF_FFFF
    private var code: UInt32 = 0

    init(input: [UInt8], start: Int, end: Int) throws {
        guard start >= 0, end <= input.count, end - start >= 5, input[start] == 0 else { throw PreviewFailure.malformedDocument }
        self.input = input
        self.end = end
        position = start + 5
        for index in 1...4 { code = (code << 8) | UInt32(input[start + index]) }
        guard code != range else { throw PreviewFailure.malformedDocument }
    }

    /// A finished chunk leaves the code register at zero.
    var isFinished: Bool { code == 0 }

    private mutating func normalize() throws {
        if range < 0x0100_0000 {
            guard position < end else { throw PreviewFailure.malformedDocument }
            range <<= 8
            code = (code << 8) | UInt32(input[position])
            position += 1
        }
    }

    mutating func bit(_ probabilities: inout [UInt16], _ index: Int) throws -> Int {
        let probability = UInt32(probabilities[index])
        let bound = (range >> 11) &* probability
        let result: Int
        if code < bound {
            range = bound
            probabilities[index] = UInt16(probability + ((2_048 - probability) >> 5))
            result = 0
        } else {
            range &-= bound
            code &-= bound
            probabilities[index] = UInt16(probability - (probability >> 5))
            result = 1
        }
        try normalize()
        return result
    }

    mutating func directBits(_ count: Int) throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<count {
            range >>= 1
            code &-= range
            let mask = 0 &- (code >> 31)
            code &+= range & mask
            guard code != range else { throw PreviewFailure.malformedDocument }
            try normalize()
            result = (result << 1) &+ mask &+ 1
        }
        return result
    }
}

/// Probability model, match history and output window shared by LZMA and every LZMA2 chunk.
struct LZMAEngine {
    // Offsets into one flat probability array. Sizes follow the specification's model.
    private static let isMatch = 0                              // 12 states x 16 position states
    private static let isRep = isMatch + 192                    // 12
    private static let isRepG0 = isRep + 12
    private static let isRepG1 = isRepG0 + 12
    private static let isRepG2 = isRepG1 + 12
    private static let isRep0Long = isRepG2 + 12                // 12 x 16
    private static let positionSlot = isRep0Long + 192          // 4 length states x 64
    private static let specialPosition = positionSlot + 256     // 115 reverse-coded distance bits
    private static let align = specialPosition + 115            // 16
    private static let lengthCoder = align + 16                 // choice, choice2, low 16x8, mid 16x8, high 256
    private static let repeatLengthCoder = lengthCoder + 514
    private static let literal = repeatLengthCoder + 514        // 0x300 per literal context

    private(set) var output: [UInt8]
    private(set) var outputCount = 0
    private let dictionarySize: Int
    /// Index of the first byte of the current dictionary; matches may not reach before it.
    private var dictionaryStart = 0
    private var literalContextBits = 0
    private var literalPositionBits = 0
    private var positionBits = 0
    private var probabilities: [UInt16] = []
    private var state = 0
    private var rep0 = 0, rep1 = 0, rep2 = 0, rep3 = 0
    private var hasProperties = false

    init(outputSize: Int, dictionarySize: Int) {
        output = [UInt8](repeating: 0, count: outputSize)
        self.dictionarySize = dictionarySize
    }

    /// Decodes the lc/lp/pb byte and allocates the literal model (at most 0x300 << 12 entries).
    mutating func setProperties(_ byte: UInt8) throws {
        guard byte < 9 * 5 * 5 else { throw PreviewFailure.malformedDocument }
        literalContextBits = Int(byte) % 9
        literalPositionBits = (Int(byte) / 9) % 5
        positionBits = Int(byte) / 45
        probabilities = [UInt16](repeating: 1_024, count: Self.literal + (0x300 << (literalContextBits + literalPositionBits)))
        hasProperties = true
    }

    mutating func resetState() {
        for index in probabilities.indices { probabilities[index] = 1_024 }
        state = 0
        rep0 = 0; rep1 = 0; rep2 = 0; rep3 = 0
    }

    mutating func resetDictionary() { dictionaryStart = outputCount }

    /// Appends an uncompressed LZMA2 chunk to the window.
    mutating func append(_ bytes: ArraySlice<UInt8>) throws {
        guard bytes.count <= output.count - outputCount else { throw PreviewFailure.malformedDocument }
        for byte in bytes { output[outputCount] = byte; outputCount += 1 }
    }

    /// Decodes until `target` bytes of output exist. Returns true when an end marker was reached first.
    mutating func decode(_ coder: inout LZMARangeDecoder, until target: Int, context: RequestContext) throws -> Bool {
        guard hasProperties else { throw PreviewFailure.malformedDocument }
        guard target <= output.count else { throw PreviewFailure.outputTooLarge }
        var symbols = 0
        while outputCount < target {
            symbols &+= 1
            if symbols & 0xFFF == 0 { try context.checkpoint() }
            let processed = outputCount - dictionaryStart
            let positionState = processed & ((1 << positionBits) - 1)
            if try coder.bit(&probabilities, Self.isMatch + (state << 4) + positionState) == 0 {
                try decodeLiteral(&coder, processed: processed)
                continue
            }
            var length: Int
            if try coder.bit(&probabilities, Self.isRep + state) != 0 {
                guard processed > 0 else { throw PreviewFailure.malformedDocument }
                if try coder.bit(&probabilities, Self.isRepG0 + state) == 0 {
                    if try coder.bit(&probabilities, Self.isRep0Long + (state << 4) + positionState) == 0 {
                        guard rep0 < processed else { throw PreviewFailure.malformedDocument }
                        state = state < 7 ? 9 : 11
                        output[outputCount] = output[outputCount - rep0 - 1]
                        outputCount += 1
                        continue
                    }
                } else {
                    let distance: Int
                    if try coder.bit(&probabilities, Self.isRepG1 + state) == 0 {
                        distance = rep1
                    } else {
                        if try coder.bit(&probabilities, Self.isRepG2 + state) == 0 {
                            distance = rep2
                        } else {
                            distance = rep3
                            rep3 = rep2
                        }
                        rep2 = rep1
                    }
                    rep1 = rep0
                    rep0 = distance
                }
                length = try decodeLength(&coder, base: Self.repeatLengthCoder, positionState: positionState)
                state = state < 7 ? 8 : 11
            } else {
                rep3 = rep2; rep2 = rep1; rep1 = rep0
                length = try decodeLength(&coder, base: Self.lengthCoder, positionState: positionState)
                state = state < 7 ? 7 : 10
                let distance = try decodeDistance(&coder, lengthState: min(length, 3))
                if distance == 0xFFFF_FFFF { return true }
                rep0 = distance
            }
            length += 2
            guard rep0 < processed, rep0 < dictionarySize else { throw PreviewFailure.malformedDocument }
            guard length <= target - outputCount else { throw PreviewFailure.malformedDocument }
            // Byte-wise forward copy: an overlapping match intentionally re-reads what it just wrote.
            for _ in 0..<length {
                output[outputCount] = output[outputCount - rep0 - 1]
                outputCount += 1
            }
        }
        return false
    }

    private mutating func decodeLiteral(_ coder: inout LZMARangeDecoder, processed: Int) throws {
        let previous = processed > 0 ? Int(output[outputCount - 1]) : 0
        let context = ((processed & ((1 << literalPositionBits) - 1)) << literalContextBits) + (previous >> (8 - literalContextBits))
        let base = Self.literal + 0x300 * context
        var symbol = 1
        if state >= 7 {
            guard rep0 < processed else { throw PreviewFailure.malformedDocument }
            var matchByte = Int(output[outputCount - rep0 - 1])
            repeat {
                let matchBit = (matchByte >> 7) & 1
                matchByte <<= 1
                let bit = try coder.bit(&probabilities, base + ((1 + matchBit) << 8) + symbol)
                symbol = (symbol << 1) | bit
                if matchBit != bit { break }
            } while symbol < 0x100
        }
        while symbol < 0x100 { symbol = (symbol << 1) | (try coder.bit(&probabilities, base + symbol)) }
        output[outputCount] = UInt8(truncatingIfNeeded: symbol)
        outputCount += 1
        state = state < 4 ? 0 : (state < 10 ? state - 3 : state - 6)
    }

    private mutating func decodeLength(_ coder: inout LZMARangeDecoder, base: Int, positionState: Int) throws -> Int {
        if try coder.bit(&probabilities, base) == 0 {
            return try bitTree(&coder, base: base + 2 + positionState * 8, bits: 3)
        }
        if try coder.bit(&probabilities, base + 1) == 0 {
            return 8 + (try bitTree(&coder, base: base + 130 + positionState * 8, bits: 3))
        }
        return 16 + (try bitTree(&coder, base: base + 258, bits: 8))
    }

    private mutating func decodeDistance(_ coder: inout LZMARangeDecoder, lengthState: Int) throws -> Int {
        let slot = try bitTree(&coder, base: Self.positionSlot + lengthState * 64, bits: 6)
        if slot < 4 { return slot }
        let directBits = (slot >> 1) - 1
        var distance = (2 | (slot & 1)) << directBits
        if slot < 14 {
            distance += try reverseBitTree(&coder, base: Self.specialPosition + distance - slot, bits: directBits)
        } else {
            distance += Int(try coder.directBits(directBits - 4)) << 4
            distance += try reverseBitTree(&coder, base: Self.align, bits: 4)
        }
        return distance
    }

    private mutating func bitTree(_ coder: inout LZMARangeDecoder, base: Int, bits: Int) throws -> Int {
        var node = 1
        for _ in 0..<bits { node = (node << 1) + (try coder.bit(&probabilities, base + node)) }
        return node - (1 << bits)
    }

    private mutating func reverseBitTree(_ coder: inout LZMARangeDecoder, base: Int, bits: Int) throws -> Int {
        var node = 1
        var result = 0
        for index in 0..<bits {
            let bit = try coder.bit(&probabilities, base + node)
            node = (node << 1) + bit
            result |= bit << index
        }
        return result
    }
}

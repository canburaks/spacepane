import Foundation
import PreviewContracts

/// LZMA2 decoder for 7z coder streams: a sequence of chunks, each either stored or LZMA-coded,
/// with explicit dictionary, state and property resets. Written from the public format description.
enum LZMA2Decoder {
    /// `dictionaryProperty` is the single 7z coder property byte. Value 40 means "4 GiB - 1".
    static func decode(_ input: [UInt8], dictionaryProperty: UInt8, outputSize: Int, limits: LZMALimits,
                       context: RequestContext) throws -> [UInt8] {
        try context.checkpoint()
        guard dictionaryProperty <= 40 else { throw PreviewFailure.malformedDocument }
        let dictionary = dictionaryProperty == 40 ? 0xFFFF_FFFF
            : (2 | Int(dictionaryProperty & 1)) << (Int(dictionaryProperty) / 2 + 11)
        guard dictionary <= limits.maximumDictionaryBytes else { throw PreviewFailure.inputTooLarge }
        guard outputSize >= 0, outputSize <= limits.maximumOutputBytes else { throw PreviewFailure.outputTooLarge }
        var engine = LZMAEngine(outputSize: outputSize, dictionarySize: dictionary)
        var position = 0
        var needsDictionaryReset = true
        var needsProperties = true
        while true {
            try context.checkpoint()
            // A complete output ends the stream even if the closing zero byte was not stored.
            if engine.outputCount == outputSize, position == input.count { break }
            guard position < input.count else { throw PreviewFailure.malformedDocument }
            let control = input[position]
            position += 1
            if control == 0 { break }
            if control == 1 || control == 2 {
                guard input.count - position >= 2 else { throw PreviewFailure.malformedDocument }
                let size = (Int(input[position]) << 8 | Int(input[position + 1])) + 1
                position += 2
                if control == 1 {
                    engine.resetDictionary()
                    needsDictionaryReset = false
                    needsProperties = true
                } else {
                    guard !needsDictionaryReset else { throw PreviewFailure.malformedDocument }
                }
                guard size <= input.count - position else { throw PreviewFailure.malformedDocument }
                try engine.append(input[position..<(position + size)])
                position += size
                continue
            }
            guard control >= 0x80, input.count - position >= 4 else { throw PreviewFailure.malformedDocument }
            let unpacked = ((Int(control & 0x1F) << 16) | Int(input[position]) << 8 | Int(input[position + 1])) + 1
            let packed = (Int(input[position + 2]) << 8 | Int(input[position + 3])) + 1
            position += 4
            let reset = (control >> 5) & 3
            if reset == 3 {
                engine.resetDictionary()
                needsDictionaryReset = false
            } else {
                guard !needsDictionaryReset else { throw PreviewFailure.malformedDocument }
            }
            if reset >= 2 {
                guard position < input.count else { throw PreviewFailure.malformedDocument }
                let properties = input[position]
                position += 1
                // LZMA2 restricts lc + lp to four.
                guard properties < 9 * 5 * 5, Int(properties) % 9 + (Int(properties) / 9) % 5 <= 4 else {
                    throw PreviewFailure.malformedDocument
                }
                try engine.setProperties(properties)
                needsProperties = false
            } else {
                guard !needsProperties else { throw PreviewFailure.malformedDocument }
            }
            if reset >= 1 { engine.resetState() }
            guard unpacked <= outputSize - engine.outputCount, packed <= input.count - position else {
                throw PreviewFailure.malformedDocument
            }
            var coder = try LZMARangeDecoder(input: input, start: position, end: position + packed)
            // An end marker is not allowed inside LZMA2; the chunk must fill its stated size and
            // consume exactly its stated compressed bytes.
            guard try !engine.decode(&coder, until: engine.outputCount + unpacked, context: context),
                  coder.position == position + packed, coder.isFinished else { throw PreviewFailure.malformedDocument }
            position += packed
        }
        guard engine.outputCount == outputSize else { throw PreviewFailure.malformedDocument }
        return engine.output
    }
}

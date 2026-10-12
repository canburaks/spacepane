import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private let lzmaContext = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
private let limits = LZMALimits(maximumOutputBytes: 1 << 20)

private func properties(_ vector: LZMAVector) -> [UInt8] {
    [UInt8((vector.pb * 5 + vector.lp) * 9 + vector.lc)] + ArchiveFixtures.le(UInt64(vector.dictionary), 4)
}

@Suite("LZMA and LZMA2 decoding")
struct LZMADecoderTests {
    @Test(arguments: ArchiveTestVectors.lzma1.map(\.name))
    func rawLZMAStreamsMatchLiblzmaOutput(name: String) throws {
        let vector = try #require(ArchiveTestVectors.lzma1.first { $0.name == name })
        let output = try LZMADecoder.decode([UInt8](vector.compressed), properties: properties(vector),
                                            outputSize: vector.plain.count, limits: limits, context: lzmaContext)
        #expect(Data(output) == vector.plain)
    }

    @Test(arguments: ArchiveTestVectors.lzma2.map(\.name))
    func rawLZMA2StreamsMatchLiblzmaOutput(name: String) throws {
        let vector = try #require(ArchiveTestVectors.lzma2.first { $0.name == name })
        let output = try LZMA2Decoder.decode([UInt8](vector.compressed), dictionaryProperty: vector.property,
                                             outputSize: vector.plain.count, limits: limits, context: lzmaContext)
        #expect(Data(output) == vector.plain)
    }

    @Test func truncatedStreamsFailInsteadOfDecodingToZeros() throws {
        for vector in ArchiveTestVectors.lzma1 {
            let half = [UInt8](vector.compressed.prefix(vector.compressed.count / 2))
            #expect(throws: PreviewFailure.malformedDocument, "\(vector.name)") {
                try LZMADecoder.decode(half, properties: properties(vector), outputSize: vector.plain.count, limits: limits, context: lzmaContext)
            }
        }
        for vector in ArchiveTestVectors.lzma2 {
            let half = [UInt8](vector.compressed.prefix(vector.compressed.count / 2))
            #expect(throws: PreviewFailure.malformedDocument, "\(vector.name)") {
                try LZMA2Decoder.decode(half, dictionaryProperty: vector.property, outputSize: vector.plain.count, limits: limits, context: lzmaContext)
            }
        }
    }

    @Test func everySingleByteCorruptionFailsCleanlyOrDecodesToTheDeclaredSize() {
        for vector in ArchiveTestVectors.lzma1 where vector.compressed.count < 400 {
            let bytes = [UInt8](vector.compressed)
            for index in bytes.indices {
                var copy = bytes
                copy[index] ^= 0xA5
                do {
                    let output = try LZMADecoder.decode(copy, properties: properties(vector), outputSize: vector.plain.count, limits: limits, context: lzmaContext)
                    #expect(output.count == vector.plain.count)
                } catch let failure as PreviewFailure {
                    #expect(failure == .malformedDocument, "\(vector.name) byte \(index): \(failure)")
                } catch { Issue.record("Unexpected error \(error)") }
            }
        }
        for vector in ArchiveTestVectors.lzma2 where vector.compressed.count < 400 {
            let bytes = [UInt8](vector.compressed)
            for index in bytes.indices {
                var copy = bytes
                copy[index] ^= 0xA5
                do {
                    let output = try LZMA2Decoder.decode(copy, dictionaryProperty: vector.property, outputSize: vector.plain.count, limits: limits, context: lzmaContext)
                    #expect(output.count == vector.plain.count)
                } catch let failure as PreviewFailure {
                    #expect(failure == .malformedDocument, "\(vector.name) byte \(index): \(failure)")
                } catch { Issue.record("Unexpected error \(error)") }
            }
        }
    }

    @Test func dictionaryAndOutputLimitsApplyBeforeAllocation() throws {
        let vector = ArchiveTestVectors.lzma1[0]
        let huge = [UInt8(0x5D)] + ArchiveFixtures.le(128 << 20, 4)
        #expect(throws: PreviewFailure.inputTooLarge) {
            try LZMADecoder.decode([UInt8](vector.compressed), properties: huge, outputSize: 100, limits: limits, context: lzmaContext)
        }
        // The limit is configurable and exact: 64 MiB passes, one byte more does not.
        let exact = [UInt8(0x5D)] + ArchiveFixtures.le(64 << 20, 4)
        #expect(throws: PreviewFailure.malformedDocument) { // accepted by the limit, then fails on the bytes themselves
            try LZMADecoder.decode([1, 2, 3, 4, 5, 6], properties: exact, outputSize: 10, limits: limits, context: lzmaContext)
        }
        let over = [UInt8(0x5D)] + ArchiveFixtures.le((64 << 20) + 1, 4)
        #expect(throws: PreviewFailure.inputTooLarge) {
            try LZMADecoder.decode([0, 0, 0, 0, 0, 0], properties: over, outputSize: 10, limits: limits, context: lzmaContext)
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try LZMADecoder.decode([UInt8](vector.compressed), properties: properties(vector), outputSize: (1 << 20) + 1, limits: limits, context: lzmaContext)
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try LZMA2Decoder.decode([0], dictionaryProperty: 16, outputSize: Int.max, limits: limits, context: lzmaContext)
        }
        // LZMA2 property 40 is the 4 GiB marker; 30 is 128 MiB; 28 is exactly 64 MiB and accepted.
        for property: UInt8 in [30, 40] {
            #expect(throws: PreviewFailure.inputTooLarge) {
                try LZMA2Decoder.decode([0], dictionaryProperty: property, outputSize: 0, limits: limits, context: lzmaContext)
            }
        }
        #expect(try LZMA2Decoder.decode([0], dictionaryProperty: 28, outputSize: 0, limits: limits, context: lzmaContext).isEmpty)
        #expect(throws: PreviewFailure.malformedDocument) {
            try LZMA2Decoder.decode([0], dictionaryProperty: 41, outputSize: 0, limits: limits, context: lzmaContext)
        }
    }

    @Test func invalidPropertyBlocksAreRejected() {
        for bad in [[UInt8](), [0x5D, 0, 0, 0], [225, 0, 0, 1, 0], [0x5D, 0, 0, 1, 0, 0]] as [[UInt8]] {
            #expect(throws: PreviewFailure.malformedDocument) {
                try LZMADecoder.decode([0, 0, 0, 0, 0], properties: bad, outputSize: 1, limits: limits, context: lzmaContext)
            }
        }
    }

    @Test func lzma2ValidatesChunkControlBytesAndResets() throws {
        // A stored chunk with a dictionary reset, then the end marker.
        #expect(try LZMA2Decoder.decode([0x01, 0x00, 0x00, 0x41, 0x00], dictionaryProperty: 16, outputSize: 1, limits: limits, context: lzmaContext) == [0x41])
        // Missing the first dictionary reset, an unknown control value, a stored chunk longer than the input,
        // an LZMA chunk without properties, lc + lp above four, and output shorter than declared.
        let bad: [[UInt8]] = [[0x02, 0x00, 0x00, 0x41, 0x00], [0x03, 0x00], [0x01, 0x00, 0x09, 0x41, 0x00],
                              [0x80, 0x00, 0x00, 0x00, 0x04, 0, 0, 0, 0, 0, 0], [0xE0, 0x00, 0x00, 0x00, 0x04, 225 - 1, 0, 0, 0, 0, 0],
                              [0x01, 0x00, 0x00, 0x41, 0x00]]
        for (index, stream) in bad.enumerated() {
            #expect(throws: PreviewFailure.malformedDocument, "stream \(index)") {
                try LZMA2Decoder.decode(stream, dictionaryProperty: 16, outputSize: index == 5 ? 2 : 1, limits: limits, context: lzmaContext)
            }
        }
    }

    @Test func honorsDeadlineAndCancellation() async {
        let vector = ArchiveTestVectors.lzma1[0]
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try LZMADecoder.decode([UInt8](vector.compressed), properties: properties(vector), outputSize: vector.plain.count,
                                   limits: limits, context: RequestContext(budget: .init(maxMilliseconds: 0)))
        }
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try LZMA2Decoder.decode([UInt8](ArchiveTestVectors.lzma2[0].compressed), dictionaryProperty: ArchiveTestVectors.lzma2[0].property,
                                            outputSize: ArchiveTestVectors.lzma2[0].plain.count, limits: limits, context: lzmaContext)
                return false
            } catch is CancellationError { return true } catch { return false }
        }
        #expect(await cancelled.value)
    }
}

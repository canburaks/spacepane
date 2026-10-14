import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("GGUF byte reader")
struct GGUFByteReaderTests {
    private static func budget(input: Int = 16_777_216) -> PreviewBudget { PreviewBudget(maxInputBytes: input, maxMilliseconds: 30_000) }

    private func reader(_ bytes: [UInt8], budget: PreviewBudget = Self.budget()) -> GGUFByteReader {
        GGUFByteReader(source: DataByteSource(Data(bytes)), context: RequestContext(budget: budget))
    }

    @Test func integersFollowTheByteOrder() throws {
        var little = reader([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
        #expect(try little.uint8() == 0x01)
        #expect(try little.integer(width: 2) == 0x0302)
        #expect(try little.integer(width: 3) == 0x060504)
        #expect(try little.uint64() == 0x0E0D_0C0B_0A09_0807)
        var big = reader([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
        big.useBigEndian()
        #expect(try big.uint8() == 0x01)
        #expect(try big.integer(width: 2) == 0x0203)
        #expect(try big.integer(width: 3) == 0x040506)
        #expect(try big.uint64() == 0x0708_090A_0B0C_0D0E)
        #expect(big.position == 14 && big.remaining == 1)
    }

    @Test func readingPastTheEndIsATruncatedFile() throws {
        var short = reader([1, 2, 3])
        #expect(throws: PreviewFailure.malformedDocument) { try short.uint32() }
        #expect(throws: PreviewFailure.malformedDocument) { try short.skip(4) }
        #expect(try short.bytes(3) == [1, 2, 3])
        #expect(throws: PreviewFailure.malformedDocument) { try short.uint8() }
    }

    @Test func aSkipFetchesNothingAndAReadAfterItStartsAtTheNewPosition() throws {
        var bytes = [UInt8](repeating: 0, count: 10_000_000)
        bytes[5_000_004] = 0xAB
        let source = CountingSource(Data(bytes))
        var reader = GGUFByteReader(source: source, context: RequestContext(budget: Self.budget()))
        _ = try reader.uint32()
        try reader.skip(5_000_000)
        #expect(reader.position == 5_000_004)
        #expect(try reader.uint8() == 0xAB)
        #expect(source.bytesRequested <= 2 * GGUFByteReader.firstWindow)
        #expect(source.reads == 2)
    }

    @Test func windowsGrowWhileReadingForwardAndStopAtOneMebibyte() throws {
        let source = CountingSource(Data(count: 6_000_000))
        var reader = GGUFByteReader(source: source, context: RequestContext(budget: Self.budget()))
        while reader.remaining >= 8 { _ = try reader.uint64() }
        #expect(source.reads >= 6 && source.reads <= 10)
        #expect(source.bytesRequested <= 6_000_000)
    }

    @Test func theBudgetBoundsEveryByteFetched() throws {
        let source = CountingSource(Data(count: 1_000_000))
        var reader = GGUFByteReader(source: source, context: RequestContext(budget: Self.budget(input: 100_000)))
        #expect(throws: GGUFByteReader.BudgetExhausted.self) {
            for _ in 0..<1_000_000 { _ = try reader.uint64() }
        }
        #expect(source.bytesRequested == 100_000)
    }

    @Test func aFileSmallerThanTheFirstWindowIsReadOnce() throws {
        let source = CountingSource(Data(count: 1_000))
        var reader = GGUFByteReader(source: source, context: RequestContext(budget: Self.budget()))
        _ = try reader.bytes(1_000)
        #expect(source.reads == 1 && source.bytesRequested == 1_000)
    }
}

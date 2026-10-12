import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func number(_ value: UInt64) -> [UInt8] { ArchiveFixtures.sevenZipNumber(value) }

/// Concatenates byte runs; a variadic call keeps each literal's type explicit instead of chaining `+`.
private func bytes(_ parts: [UInt8]...) -> [UInt8] { parts.flatMap { $0 } }

private func list(_ header: [UInt8], budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> ParsedTextDocument {
    let data = Data(ArchiveFixtures.sevenZipContainer(body: [], nextHeader: header))
    return try SevenZipListingAdapter().parse(DataByteSource(data), context: RequestContext(budget: budget))
}

/// `Header`, `MainStreamsInfo`, then a `PackInfo` that declares `declaredCount` pack streams and carries `properties`.
private func headerWithPackInfo(declaredCount: UInt64, properties: [UInt8]) -> [UInt8] {
    bytes([0x01, 0x04, 0x06], number(0), number(declaredCount), properties, [0x00, 0x00, 0x00])
}

/// A `size` property of `count` one-byte sizes.
private func packSizes(_ count: Int) -> [UInt8] {
    bytes([0x09], (0..<count).flatMap { _ in number(1) })
}

/// A `crc` property: an all-defined byte or a bit vector, then four bytes for each digest present.
private func digests(allDefined: Bool, bits: [Bool] = [], present: Int) -> [UInt8] {
    let vector: [UInt8] = allDefined ? [] : ArchiveFixtures.bitVector(bits)
    return bytes([0x0A, allDefined ? 1 : 0], vector, [UInt8](repeating: 0xAB, count: present * 4))
}

/// A header with `packStreams` pack streams and `folders` folders of one copy coder each, and no files.
private func headerWithFolders(_ folders: Int, packStreams: Int) -> [UInt8] {
    let folder: [UInt8] = [0x01, 0x01, 0x00]   // one coder with a one-byte method id: the copy method
    let info = bytes([0x06], number(0), number(UInt64(packStreams)), packSizes(packStreams), [0x00],
                     [0x07, 0x0B], number(UInt64(folders)), [0x00], (0..<folders).flatMap { _ in folder },
                     [0x0C], (0..<folders).flatMap { _ in number(1) }, [0x00])
    // End of StreamsInfo, then a FilesInfo that declares no files, then the end of the header.
    return bytes([0x01, 0x04], info, [0x00, 0x05, 0x00, 0x00, 0x00])
}

/// 7z headers declare counts that size arrays. Each count is checked against the bytes that remain and against the
/// entries a listing may show before anything is allocated for it, so a few header bytes cannot ask for megabytes.
@Suite("7z header bounds")
struct SevenZipBoundsTests {
    // MARK: Counts that cannot fit

    @Test(arguments: [UInt64(1) << 40, UInt64.max])
    func anAbsurdPackStreamCountIsMalformed(declared: UInt64) {
        #expect(throws: PreviewFailure.malformedDocument) {
            try list(headerWithPackInfo(declaredCount: declared, properties: packSizes(1)))
        }
    }

    @Test func aPackStreamCountBeyondTheHeaderBytesIsMalformed() {
        #expect(throws: PreviewFailure.malformedDocument) {
            try list(headerWithPackInfo(declaredCount: 50, properties: packSizes(2)))
        }
    }

    @Test func anAbsurdSubstreamCountIsMalformed() {
        let info = bytes([0x06], number(0), number(1), [0x09], number(5_000), [0x00],
                         [0x07, 0x0B], number(1), [0x00], [0x01, 0x01, 0x00], [0x0C], number(5_000), [0x00],
                         [0x08, 0x0D], number(UInt64(1) << 40), [0x00, 0x00])
        #expect(throws: PreviewFailure.malformedDocument) {
            var reader = ArchiveByteReader(info)
            _ = try SevenZipStreamsInfo.parse(&reader, context: RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)))
        }
    }

    @Test func allDefinedDigestsMustFitTheRemainingBytes() throws {
        // 100 digests need 400 bytes; two are present. The count fits the header's byte count (one size byte each).
        #expect(throws: PreviewFailure.malformedDocument) {
            try list(headerWithPackInfo(declaredCount: 100, properties: packSizes(100) + digests(allDefined: true, present: 2)))
        }
        let complete = try list(headerWithPackInfo(declaredCount: 100,
                                                   properties: packSizes(100) + digests(allDefined: true, present: 100)))
        #expect(try listedEntries(complete).isEmpty)
    }

    @Test func aBitVectorPaysOnlyForTheDigestsItMarksAsDefined() throws {
        let bits = [true, false, true] + [Bool](repeating: false, count: 37)
        let complete = try list(headerWithPackInfo(declaredCount: 40,
                                                   properties: packSizes(40) + digests(allDefined: false, bits: bits, present: 2)))
        #expect(try listedEntries(complete).isEmpty)
        #expect(throws: PreviewFailure.malformedDocument) {
            try list(headerWithPackInfo(declaredCount: 40,
                                        properties: packSizes(40) + digests(allDefined: false, bits: bits, present: 1)))
        }
        // No digest is defined: nothing follows the vector, however many entries it covers.
        let none = try list(headerWithPackInfo(declaredCount: 40,
                                               properties: packSizes(40) + digests(allDefined: false, bits: [Bool](repeating: false, count: 40), present: 0)))
        #expect(try listedEntries(none).isEmpty)
    }

    // MARK: The entry limit

    /// Each folder costs several allocations, so a header may not declare more of them than a listing may show.
    @Test func moreFoldersOrPackStreamsThanTheEntryLimitAreRefusedAsTooMany() throws {
        let budget = PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)
        #expect(try listedEntries(list(headerWithFolders(40, packStreams: 40), budget: budget)).isEmpty)
        #expect(throws: PreviewFailure.tooManyNodes) { try list(headerWithFolders(100, packStreams: 1), budget: budget) }
        #expect(throws: PreviewFailure.tooManyNodes) { try list(headerWithFolders(1, packStreams: 100), budget: budget) }
        // The same header fits the default budget.
        #expect(try listedEntries(list(headerWithFolders(100, packStreams: 100))).isEmpty)
    }

    /// A solid archive with more files than the limit still lists its first entries: only the stored sizes are bounded.
    @Test func aSolidArchiveWithMoreFilesThanTheLimitStillListsItsFirstEntries() throws {
        let members = (0..<100).map { ArchiveFixtures.Member("file\($0).txt", "x") }
        let data = ArchiveFixtures.sevenZip(members)
        let budget = PreviewBudget(maxJSONNodes: 40 + 3 * ArchiveListing.nodesPerEntry, maxMilliseconds: 30_000)
        let document = try SevenZipListingAdapter().parse(DataByteSource(data), context: RequestContext(budget: budget))
        let object = try listingObject(document)
        #expect(object["partial"] as? Bool == true)
        let entries = try listedEntries(document)
        #expect(entries.count == 3)
        #expect(entries.map { $0["path"] as? String } == ["file0.txt", "file1.txt", "file2.txt"])
        #expect(entries.allSatisfy { $0["bytes"] as? Int == 1 })
    }

    @Test func storedStreamSizesStopAtTheEntryLimitWhileEveryCountStaysExact() throws {
        let streams = 200
        // One pack stream and one copy folder of 5,000 bytes whose substreams are 200 files of ten bytes, the last
        // taking the rest; then the end of SubStreamsInfo and the end of StreamsInfo.
        let info = bytes([0x06], number(0), number(1), [0x09], number(5_000), [0x00],
                         [0x07, 0x0B], number(1), [0x00], [0x01, 0x01, 0x00], [0x0C], number(5_000), [0x00],
                         [0x08, 0x0D], number(UInt64(streams)), [0x09], (1..<streams).flatMap { _ in number(10) },
                         [0x00, 0x00])
        func parse(_ budget: PreviewBudget) throws -> SevenZipStreamsInfo {
            var reader = ArchiveByteReader(info)
            return try SevenZipStreamsInfo.parse(&reader, context: RequestContext(budget: budget))
        }
        let unlimited = try parse(PreviewBudget(maxMilliseconds: 30_000))
        #expect(unlimited.streamCounts == [streams])
        #expect(unlimited.streamSizes.count == streams)
        #expect(unlimited.streamSizes.last == 5_000 - UInt64(10 * (streams - 1)))
        let limited = try parse(PreviewBudget(maxJSONNodes: 73, maxMilliseconds: 30_000))
        #expect(limited.streamCounts == [streams])
        #expect(limited.streamSizes.count == 73)
        #expect(limited.streamSizes == Array(unlimited.streamSizes.prefix(73)))
    }
}

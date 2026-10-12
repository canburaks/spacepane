import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private let sevenZipContext = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
private func list(_ data: Data, budget: PreviewBudget? = nil) throws -> ParsedTextDocument {
    try SevenZipListingAdapter().parse(DataByteSource(data), context: budget.map { RequestContext(budget: $0) } ?? sevenZipContext)
}
private let vectorPaths = ["Example", "Example/readme.txt", "Example/data/values.json", "Example/notes.md"]

@Suite("7z listing")
struct SevenZipListingTests {
    @Test func listsAPlainHeaderWithSizesDatesAndSolidFlag() throws {
        let document = try list(ArchiveFixtures.sevenZip())
        let object = try listingObject(document)
        #expect(object["archiveFormat"] as? String == "7Z")
        #expect(object["partial"] as? Bool == false)
        #expect(object["solid"] as? Bool == true)
        let entries = try listedEntries(document)
        #expect(entries.map { $0["path"] as? String } == ["Example", "Example/readme.txt", "Example/日本語.txt"])
        #expect(entries.map { $0["type"] as? String } == ["directory", "file", "file"])
        #expect(entries[1]["bytes"] as? Int == 26)
        #expect(entries[2]["bytes"] as? Int == 13)
        #expect(entries.allSatisfy { $0["modified"] as? String == ArchiveFixtures.modifiedISO })
        #expect(document.syntax == .json)
    }

    @Test func listsHeadersCompressedWithLZMAAndLZMA2() throws {
        for (name, archive) in [("LZMA", ArchiveTestVectors.sevenZipLZMAHeader), ("LZMA2", ArchiveTestVectors.sevenZipLZMA2Header),
                                ("plain", ArchiveTestVectors.sevenZipPlainHeader)] {
            let document = try list(archive)
            #expect(try listedPaths(document) == vectorPaths, "\(name) header")
            #expect(try listedEntries(document)[1]["bytes"] as? Int == 27, "\(name) header")
        }
    }

    @Test func neverReadsMemberDataOnlyTheStartHeaderAndHeader() throws {
        let payload = String(repeating: "PAYLOAD-MUST-NOT-BE-READ ", count: 400)
        let data = ArchiveFixtures.sevenZip([Member("big.bin", payload), Member("small.txt", "tiny")])
        let marker = try #require(data.range(of: Data("PAYLOAD-MUST-NOT-BE-READ".utf8)))
        let source = RecordingSource(data)
        #expect(try listedPaths(SevenZipListingAdapter().parse(source, context: sevenZipContext)) == ["big.bin", "small.txt"])
        #expect(!source.touches(marker.lowerBound..<(marker.lowerBound + payload.utf8.count)))
    }

    @Test func encryptedHeadersAreReportedNotListed() {
        #expect(throws: PreviewFailure.encryptedContent) { try list(ArchiveTestVectors.sevenZipEncryptedHeader) }
    }

    @Test func aesFoldersMarkTheirMembersEncrypted() throws {
        var options = ArchiveFixtures.SevenZipOptions()
        options.folderCoder = [0x06, 0xF1, 0x07, 0x01]
        let entries = try listedEntries(list(ArchiveFixtures.sevenZip([Member.directory("d"), Member("a.bin", "x"), Member("empty.txt", "")], options: options)))
        #expect(entries[0]["encrypted"] == nil)
        #expect(entries[1]["encrypted"] as? Bool == true)
        #expect(entries[2]["encrypted"] == nil)
    }

    @Test func distinguishesEmptyFilesDirectoriesAntiItemsAndSymlinks() throws {
        var options = ArchiveFixtures.SevenZipOptions()
        options.anti = ["deleted.txt"]
        let members = [Member.directory("dir"), Member("empty.txt", ""), Member("deleted.txt", ""), Member("link", "t", symlink: true), Member("data.bin", "abc")]
        let entries = try listedEntries(list(ArchiveFixtures.sevenZip(members, options: options)))
        #expect(entries.map { $0["path"] as? String } == ["dir", "empty.txt", "link", "data.bin"])
        #expect(entries.map { $0["type"] as? String } == ["directory", "file", "symlink", "file"])
        #expect(entries[1]["bytes"] as? Int == 0)
        // The directory attribute also marks a directory that has a stream-less entry flagged as a file.
        var attributes = ArchiveFixtures.SevenZipOptions()
        attributes.attributes = ["folder-by-attribute": 0x10]
        let flagged = try listedEntries(list(ArchiveFixtures.sevenZip([Member("folder-by-attribute", "")], options: attributes)))
        #expect(flagged[0]["type"] as? String == "directory")
    }

    @Test func emptyArchivesAndMissingTimesAreListedWithoutError() throws {
        let empty = Data(ArchiveFixtures.sevenZipContainer(body: [], nextHeader: []))
        #expect(try listedEntries(list(empty)).isEmpty)
        // A header that states zero files needs no name table.
        let zeroFiles = Data(ArchiveFixtures.sevenZipContainer(body: [], nextHeader: [0x01, 0x05, 0x00, 0x00, 0x00]))
        #expect(try listedEntries(list(zeroFiles)).isEmpty)
        var options = ArchiveFixtures.SevenZipOptions()
        options.omitTimes = true
        #expect(try listedEntries(list(ArchiveFixtures.sevenZip([Member("a.txt", "x")], options: options)))[0]["modified"] == nil)
    }

    @Test func rejectsCorruptStartHeaderHeaderCRCAndTruncation() throws {
        let valid = ArchiveFixtures.sevenZip()
        var startCRC = valid
        startCRC[8] ^= 0xFF
        #expect(throws: PreviewFailure.malformedDocument) { try list(startCRC) }
        var nextCRC = valid
        nextCRC[nextCRC.count - 3] ^= 0x01
        #expect(throws: PreviewFailure.malformedDocument) { try list(nextCRC) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(valid.count - 5)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(20)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(4)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(Data("this is not a 7z archive at all, it is text".utf8)) }
        var version = valid
        // A major version other than 0 is unsupported; the start-header CRC does not cover the version bytes.
        version[6] = 9
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(version) }
    }

    @Test func selfExtractingStubsAreUnsupported() {
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(Data([0x4D, 0x5A, 0x90, 0x00]) + Data(repeating: 0, count: 100) + ArchiveFixtures.sevenZip()) }
    }

    @Test func compressedHeaderFailuresAreTypedAndNothingCrashes() throws {
        let body = [UInt8](repeating: 0, count: 10)
        func archive(coder: [UInt8], unpack: UInt64) -> Data {
            Data(ArchiveFixtures.sevenZipContainer(body: body, nextHeader: ArchiveFixtures.sevenZipEncodedHeader(
                packedPosition: 0, packedSize: body.count, coder: coder, unpackSize: unpack)))
        }
        // Coders other than Copy, LZMA and LZMA2 are unsupported for header streams.
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(archive(coder: [0x03, 0x04, 0x02, 0x02], unpack: 100)) }
        // The declared dictionary and the declared output are checked before anything is allocated.
        #expect(throws: PreviewFailure.inputTooLarge) { try list(archive(coder: ArchiveFixtures.lzmaCoder(dictionary: 128 << 20), unpack: 100)) }
        #expect(throws: PreviewFailure.outputTooLarge) { try list(archive(coder: ArchiveFixtures.lzmaCoder(dictionary: 1 << 20), unpack: 4 << 30)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try list(archive(coder: ArchiveFixtures.lzma2Coder(property: 40), unpack: 100)) }
        // A packed stream that lies outside the file.
        let outside = Data(ArchiveFixtures.sevenZipContainer(body: body, nextHeader: ArchiveFixtures.sevenZipEncodedHeader(
            packedPosition: 0, packedSize: 1000, coder: ArchiveFixtures.lzmaCoder(dictionary: 1 << 20), unpackSize: 100)))
        #expect(throws: PreviewFailure.malformedDocument) { try list(outside) }
        // Garbage that is not an LZMA stream: first range-coder byte must be zero.
        let junk = Data(ArchiveFixtures.sevenZipContainer(body: [1, 2, 3, 4, 5, 6, 7, 8], nextHeader: ArchiveFixtures.sevenZipEncodedHeader(
            packedPosition: 0, packedSize: 8, coder: ArchiveFixtures.lzmaCoder(dictionary: 1 << 20), unpackSize: 100)))
        #expect(throws: PreviewFailure.malformedDocument) { try list(junk) }
    }

    @Test func everySingleByteCorruptionOfACompressedHeaderIsRejectedOrHarmless() throws {
        for archive in [ArchiveTestVectors.sevenZipLZMAHeader, ArchiveTestVectors.sevenZipLZMA2Header] {
            let bytes = [UInt8](archive)
            let nextOffset = bytes[12..<20].reversed().reduce(0) { ($0 << 8) | Int($1) }
            for index in 32..<(32 + nextOffset) {
                var copy = bytes
                copy[index] ^= 0x5A
                do { _ = try list(Data(copy)) } catch let failure as PreviewFailure {
                    #expect([.malformedDocument, .unsupportedFormat, .inputTooLarge, .outputTooLarge].contains(failure), "offset \(index): \(failure)")
                }
            }
        }
    }

    @Test func honorsEntryNodeAndInputBudgets() throws {
        let many = (0..<40).map { Member("file\($0).txt", "x") }
        let data = ArchiveFixtures.sevenZip(many)
        let limited = try listingObject(list(data, budget: PreviewBudget(maxJSONNodes: 40 + 3 * ArchiveListing.nodesPerEntry, maxMilliseconds: 30_000)))
        #expect(limited["partial"] as? Bool == true)
        #expect(limited["listedEntries"] as? Int == 3)
        #expect(throws: PreviewFailure.inputTooLarge) { try list(data, budget: PreviewBudget(maxInputBytes: 64, maxMilliseconds: 30_000)) }
    }

    @Test func secretLikeEntryNamesAreMarkedSensitive() throws {
        let document = try list(ArchiveFixtures.sevenZip([Member("config/password=synthetic-secret-value.txt", "x")]))
        let bytes = Array(document.text.utf8)
        #expect(document.sensitiveRanges.contains { String(decoding: bytes[$0.utf8Range], as: UTF8.self).contains("synthetic-secret-value") })
    }

    @Test func checksCancellationAndDeadlineBeforeSourceAccess() async {
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try SevenZipListingAdapter().parse(RecordingSource(ArchiveFixtures.sevenZip()), context: .init(budget: .standard)); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try SevenZipListingAdapter().parse(RecordingSource(ArchiveFixtures.sevenZip()), context: .init(budget: .init(maxMilliseconds: 0)))
        }
    }
}

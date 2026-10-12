import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

typealias Member = ArchiveFixtures.Member

/// The listing is JSON; tests inspect it structurally instead of by substring where order matters.
func listingObject(_ document: ParsedTextDocument) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
}
func listedEntries(_ document: ParsedTextDocument) throws -> [[String: Any]] {
    try #require(try listingObject(document)["entries"] as? [[String: Any]])
}
func listedPaths(_ document: ParsedTextDocument) throws -> [String] {
    try listedEntries(document).compactMap { $0["path"] as? String }
}

private let archiveContext = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
private func list(_ data: Data, budget: PreviewBudget? = nil) throws -> ParsedTextDocument {
    try RARListingAdapter().parse(DataByteSource(data), context: budget.map { RequestContext(budget: $0) } ?? archiveContext)
}

@Suite("RAR 5 listing")
struct RAR5ListingTests {
    @Test func listsStoredEntriesWithKindSizeAndModifiedDate() throws {
        let document = try list(ArchiveFixtures.rar5())
        let object = try listingObject(document)
        #expect(object["archiveFormat"] as? String == "RAR5")
        #expect(object["partial"] as? Bool == false)
        #expect(object["listedEntries"] as? Int == 3)
        let entries = try listedEntries(document)
        #expect(entries.map { $0["path"] as? String } == ["Example", "Example/readme.txt", "Example/日本語.txt"])
        #expect(entries.map { $0["type"] as? String } == ["directory", "file", "file"])
        #expect(entries[1]["bytes"] as? Int == 26)
        #expect(entries.allSatisfy { $0["modified"] as? String == ArchiveFixtures.modifiedISO })
        #expect(entries.allSatisfy { $0["encrypted"] == nil })
        #expect(document.syntax == .json)
        #expect(document.usesStructuredPrivacy)
    }

    @Test func reportsArchiveFlags() throws {
        var options = ArchiveFixtures.RAR5Options()
        options.solid = true; options.locked = true; options.recovery = true
        let flagged = try listingObject(list(ArchiveFixtures.rar5(options: options)))
        #expect(flagged["solid"] as? Bool == true)
        #expect(flagged["locked"] as? Bool == true)
        #expect(flagged["recoveryRecord"] as? Bool == true)
        #expect(flagged["multiVolume"] as? Bool == false)
        #expect(flagged["volumeNumber"] == nil)
        options = .init()
        options.volume = 0
        let first = try listingObject(list(ArchiveFixtures.rar5(options: options)))
        #expect(first["multiVolume"] as? Bool == true)
        #expect(first["volumeNumber"] as? Int == 1)
        options.volume = 2
        let third = try listingObject(list(ArchiveFixtures.rar5(options: options)))
        #expect(third["volumeNumber"] as? Int == 3)
    }

    @Test func marksEncryptedMembersAndSymlinksWithoutReadingTargets() throws {
        let members = [Member("secret.bin", "x", encrypted: true), Member("link", "", symlink: true), Member("plain.txt", "y")]
        let entries = try listedEntries(list(ArchiveFixtures.rar5(members)))
        #expect(entries[0]["encrypted"] as? Bool == true)
        #expect(entries[1]["type"] as? String == "symlink")
        #expect(entries[2]["encrypted"] == nil)
        #expect(!String(decoding: try JSONSerialization.data(withJSONObject: entries), as: UTF8.self).contains("target"))
    }

    @Test func archiveEncryptionHeaderIsReportedNotListed() {
        var options = ArchiveFixtures.RAR5Options()
        options.encryptedHeaders = true
        #expect(throws: PreviewFailure.encryptedContent) { try list(ArchiveFixtures.rar5(options: options)) }
    }

    @Test func serviceBlocksAreSkippedWithTheirDataAreas() throws {
        var options = ArchiveFixtures.RAR5Options()
        options.serviceBlock = true
        #expect(try listedPaths(list(ArchiveFixtures.rar5(options: options))).count == 3)
    }

    @Test func timeRecordsSupplyDatesWhenTheHeaderHasNone() throws {
        let windows = (UInt64(ArchiveFixtures.modified) + 11_644_473_600) * 10_000_000
        var blocks: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
        blocks += ArchiveFixtures.rar5Block(type: 1, fields: ArchiveFixtures.vint(0))
        blocks += ArchiveFixtures.rar5File(Member("w.txt", "a"), timeRecord: .windows(windows))
        blocks += ArchiveFixtures.rar5File(Member("u.txt", "a"), timeRecord: .unix(ArchiveFixtures.modified))
        blocks += ArchiveFixtures.rar5File(Member("n.txt", "a"), timeRecord: .unixNanoseconds)
        blocks += ArchiveFixtures.rar5Block(type: 5, fields: ArchiveFixtures.vint(0))
        let entries = try listedEntries(list(Data(blocks)))
        #expect(entries[0]["modified"] as? String == ArchiveFixtures.modifiedISO)
        #expect(entries[1]["modified"] as? String == ArchiveFixtures.modifiedISO)
        // The nanosecond variant is deliberately not decoded.
        #expect(entries[2]["modified"] == nil)
    }

    @Test func unknownUnpackedSizeIsReportedAsNull() throws {
        var blocks: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
        blocks += ArchiveFixtures.rar5Block(type: 1, fields: ArchiveFixtures.vint(0))
        blocks += ArchiveFixtures.rar5File(Member("stream.bin", "abc"), unknownSize: true)
        blocks += ArchiveFixtures.rar5Block(type: 5, fields: ArchiveFixtures.vint(0))
        #expect(try listedEntries(list(Data(blocks)))[0]["bytes"] is NSNull)
    }

    @Test func neverReadsMemberDataAreas() throws {
        let payload = String(repeating: "PAYLOAD-MUST-NOT-BE-READ ", count: 400)
        let data = ArchiveFixtures.rar5([Member("big.bin", payload), Member("after.txt", "tiny")])
        let marker = try #require(data.range(of: Data("PAYLOAD-MUST-NOT-BE-READ".utf8)))
        let source = RecordingSource(data)
        let document = try RARListingAdapter().parse(source, context: archiveContext)
        #expect(try listedPaths(document) == ["big.bin", "after.txt"])
        #expect(!source.touches(marker.lowerBound..<(marker.lowerBound + payload.utf8.count)))
        #expect(!document.text.contains("PAYLOAD"))
    }

    @Test func missingEndBlockIsReportedAsPartial() throws {
        var options = ArchiveFixtures.RAR5Options()
        options.endBlock = false
        let object = try listingObject(list(ArchiveFixtures.rar5(options: options)))
        #expect(object["partial"] as? Bool == true)
        #expect(object["listedEntries"] as? Int == 3)
    }

    @Test func rejectsCorruptedHeadersTruncationAndBadVariableIntegers() throws {
        let valid = ArchiveFixtures.rar5()
        // Flip a byte inside the first file header's name: the header CRC must catch it.
        var corrupt = valid
        let name = try #require(corrupt.range(of: Data("Example".utf8)))
        corrupt[name.lowerBound] ^= 1
        #expect(throws: PreviewFailure.malformedDocument) { try list(corrupt) }
        // Cut inside the last file's data area and inside a header.
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(valid.count - 12)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(12)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(10)) }
        // A header-size field longer than three bytes, and an eleven-byte variable integer.
        var long = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) + Data(repeating: 0, count: 4)
        long += Data([0x80, 0x80, 0x80, 0x01, 0x01, 0x00])
        #expect(throws: PreviewFailure.malformedDocument) { try list(long) }
        // A main header whose archive-flags vint never terminates within ten bytes, with a valid CRC.
        let body: [UInt8] = [1, 0] + [UInt8](repeating: 0xFF, count: 11)
        let size = ArchiveFixtures.vint(UInt64(body.count))
        let bad = ArchiveFixtures.le(UInt64(ArchiveFixtures.crc32(size + body)), 4) + size + body
        #expect(throws: PreviewFailure.malformedDocument) {
            try list(Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00] + bad))
        }
    }

    @Test func listsAndFlagsPathTraversalAndAbsolutePaths() throws {
        // Like ZIP and TAR, listing never extracts: unsafe names are shown and reported as risks (decision 012).
        for name in ["../escape.txt", "/etc/passwd", "C:/windows"] {
            let document = try list(ArchiveFixtures.rar5([Member(name)]))
            #expect(document.text.contains("\"unsafePath\""), "\(name)")
        }
    }

    @Test func recognizesUnsupportedLayoutsExplicitly() {
        let signature = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
        // A self-extracting executable stub in front of the archive.
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(Data([0x4D, 0x5A, 0x90, 0x00]) + Data(repeating: 0, count: 80) + signature) }
        // RAR 1.4 and a volume whose first block is not the main header.
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(Data([0x52, 0x45, 0x7E, 0x5E, 0, 0, 0, 0])) }
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(signature + Data(ArchiveFixtures.rar5File(Member("orphan.bin", "x")))) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(Data("not a rar archive".utf8)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(Data()) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(signature) }
    }

    @Test func honorsEntryNodeAndInputBudgets() throws {
        let many = (0..<30).map { Member("file\($0).txt", "x") }
        let data = ArchiveFixtures.rar5(many)
        // 40 reserved nodes plus room for two entries.
        let limited = try listingObject(list(data, budget: PreviewBudget(maxJSONNodes: 40 + 2 * ArchiveListing.nodesPerEntry, maxMilliseconds: 30_000)))
        #expect(limited["partial"] as? Bool == true)
        #expect(limited["listedEntries"] as? Int == 2)
        // Reads are charged: with a small input budget the walk stops with a partial listing.
        let small = try listingObject(list(data, budget: PreviewBudget(maxInputBytes: 400, maxMilliseconds: 30_000)))
        #expect(small["partial"] as? Bool == true)
        #expect((small["listedEntries"] as? Int ?? 0) > 0)
        #expect(throws: PreviewFailure.inputTooLarge) { try list(data, budget: PreviewBudget(maxInputBytes: 12, maxMilliseconds: 30_000)) }
    }

    @Test func secretLikeEntryNamesAreMarkedSensitive() throws {
        let document = try list(ArchiveFixtures.rar5([Member("config/password=synthetic-secret-value.txt")]))
        let bytes = Array(document.text.utf8)
        #expect(document.sensitiveRanges.contains { String(decoding: bytes[$0.utf8Range], as: UTF8.self).contains("synthetic-secret-value") })
    }

    @Test func checksCancellationAndDeadlineBeforeSourceAccess() async {
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try RARListingAdapter().parse(RecordingSource(ArchiveFixtures.rar5()), context: .init(budget: .standard)); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try RARListingAdapter().parse(RecordingSource(ArchiveFixtures.rar5()), context: .init(budget: .init(maxMilliseconds: 0)))
        }
    }
}

@Suite("RAR 4 listing")
struct RAR4ListingTests {
    @Test func listsStoredEntriesWithKindSizeAndDosDate() throws {
        var options = ArchiveFixtures.RAR4Options()
        options.hostOS = 3
        let document = try list(ArchiveFixtures.rar4(options: options))
        let object = try listingObject(document)
        #expect(object["archiveFormat"] as? String == "RAR4")
        let entries = try listedEntries(document)
        #expect(entries.map { $0["path"] as? String } == ["Example", "Example/readme.txt", "Example/日本語.txt"])
        #expect(entries.map { $0["type"] as? String } == ["directory", "file", "file"])
        #expect(entries[1]["bytes"] as? Int == 26)
        #expect(entries.allSatisfy { $0["modified"] as? String == ArchiveFixtures.modifiedISO })
    }

    @Test func reportsArchiveFlags() throws {
        var options = ArchiveFixtures.RAR4Options()
        options.solid = true; options.locked = true; options.recovery = true; options.volume = true
        let object = try listingObject(list(ArchiveFixtures.rar4(options: options)))
        #expect(object["solid"] as? Bool == true)
        #expect(object["locked"] as? Bool == true)
        #expect(object["recoveryRecord"] as? Bool == true)
        #expect(object["multiVolume"] as? Bool == true)
        #expect(object["volumeNumber"] == nil)
    }

    @Test func decodesUnicodeNamesAndWindowsSeparators() throws {
        var options = ArchiveFixtures.RAR4Options()
        options.unicodeNames = true
        let unicode = try listedPaths(list(ArchiveFixtures.rar4([Member("日本語/ファイル.txt", "x"), Member("ascii.txt", "y")], options: options)))
        #expect(unicode == ["日本語/ファイル.txt", "ascii.txt"])
        // Windows-hosted archives store backslashes; Unix-hosted ones keep them as ordinary characters.
        var windows = ArchiveFixtures.RAR4Options()
        windows.hostOS = 2
        #expect(try listedPaths(list(ArchiveFixtures.rar4([Member("dir\\inner.txt", "x")], options: windows))) == ["dir/inner.txt"])
    }

    @Test func fallsBackToUTF8ThenCodePage437ForByteNames() throws {
        func archive(_ name: [UInt8]) -> Data {
            var data = [UInt8](ArchiveFixtures.rar4([]))
            data.removeLast(7)
            data += ArchiveFixtures.rar4File(Member("x", "a"), nameBytes: name) + [0xC4, 0x3D, 0x7B, 0x00, 0x40, 0x07, 0x00]
            return Data(data)
        }
        #expect(try listedPaths(list(archive(Array("café.txt".utf8)))) == ["café.txt"])
        #expect(try listedPaths(list(archive([0x80, 0x2E, 0x74]))) == ["Ç.t"])
    }

    @Test func marksEncryptedMembersAndSymlinks() throws {
        var options = ArchiveFixtures.RAR4Options()
        options.hostOS = 3
        let entries = try listedEntries(list(ArchiveFixtures.rar4([Member("locked.bin", "x", encrypted: true), Member("link", "", symlink: true)], options: options)))
        #expect(entries[0]["encrypted"] as? Bool == true)
        #expect(entries[1]["type"] as? String == "symlink")
    }

    @Test func encryptedHeadersAreReportedNotListed() {
        var options = ArchiveFixtures.RAR4Options()
        options.encryptedHeaders = true
        #expect(throws: PreviewFailure.encryptedContent) { try list(ArchiveFixtures.rar4(options: options)) }
    }

    @Test func skipsServiceAndOldStyleBlocksAndHonorsHighSizeWords() throws {
        var options = ArchiveFixtures.RAR4Options()
        options.highSizes = true
        var data = [UInt8](ArchiveFixtures.rar4([], options: options))
        data.removeLast(7)
        data += ArchiveFixtures.rar4File(Member("a.txt", "first"), options: options)
        // Sub-block (new-style comment) with its own data area, and an old-style block with ADD_SIZE.
        data += ArchiveFixtures.rar4File(Member("CMT", "service data"), options: options, blockType: 0x7A)
        data += ArchiveFixtures.rar4Block(type: 0x75, flags: 0x8000, body: ArchiveFixtures.le(4, 4)) + Array("skip".utf8)
        data += ArchiveFixtures.rar4File(Member("b.txt", "second"), options: options)
        data += [0xC4, 0x3D, 0x7B, 0x00, 0x40, 0x07, 0x00]
        let document = try list(Data(data))
        #expect(try listedPaths(document) == ["a.txt", "b.txt"])
        #expect(try listedEntries(document)[1]["bytes"] as? Int == 6)
    }

    @Test func neverReadsMemberDataAreas() throws {
        let payload = String(repeating: "PAYLOAD-MUST-NOT-BE-READ ", count: 400)
        let data = ArchiveFixtures.rar4([Member("big.bin", payload), Member("after.txt", "tiny")])
        let marker = try #require(data.range(of: Data("PAYLOAD-MUST-NOT-BE-READ".utf8)))
        let source = RecordingSource(data)
        #expect(try listedPaths(RARListingAdapter().parse(source, context: archiveContext)) == ["big.bin", "after.txt"])
        #expect(!source.touches(marker.lowerBound..<(marker.lowerBound + payload.utf8.count)))
    }

    @Test func rejectsCorruptedHeadersTruncationAndTraversal() throws {
        let valid = ArchiveFixtures.rar4()
        var corrupt = valid
        let name = try #require(corrupt.range(of: Data("Example".utf8)))
        corrupt[name.lowerBound] ^= 1
        #expect(throws: PreviewFailure.malformedDocument) { try list(corrupt) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(valid.count - 12)) }
        #expect(throws: PreviewFailure.malformedDocument) { try list(valid.prefix(12)) }
        #expect(try list(ArchiveFixtures.rar4([Member("../escape.txt")])).text.contains("\"unsafePath\""))
    }

    @Test func recognizesUnsupportedLayoutsAndMissingEndBlocks() throws {
        // A later volume that starts with a file block instead of the main header.
        let orphan = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) + Data(ArchiveFixtures.rar4File(Member("orphan.bin", "x")))
        #expect(throws: PreviewFailure.unsupportedFormat) { try list(orphan) }
        var options = ArchiveFixtures.RAR4Options()
        options.endBlock = false
        #expect(try listingObject(list(ArchiveFixtures.rar4(options: options)))["partial"] as? Bool == true)
    }

    @Test func honorsEntryAndInputBudgets() throws {
        let data = ArchiveFixtures.rar4((0..<30).map { Member("file\($0).txt", "x") })
        let limited = try listingObject(list(data, budget: PreviewBudget(maxJSONNodes: 40 + 3 * ArchiveListing.nodesPerEntry, maxMilliseconds: 30_000)))
        #expect(limited["partial"] as? Bool == true)
        #expect(limited["listedEntries"] as? Int == 3)
        let small = try listingObject(list(data, budget: PreviewBudget(maxInputBytes: 300, maxMilliseconds: 30_000)))
        #expect(small["partial"] as? Bool == true)
    }
}

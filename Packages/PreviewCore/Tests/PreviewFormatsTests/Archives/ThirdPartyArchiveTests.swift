import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private let thirdPartyContext = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
private let expectedPaths = ["src", "src/docs", "src/docs/deep", "src/docs/deep/data.bin", "src/docs/deep/empty.txt",
                             "src/docs/notes.md", "src/hello.txt"]

/// py7zr wrote these archives, so they check the reader against a writer this repository does not control.
@Suite("7z archives written by py7zr")
struct ThirdPartyArchiveTests {
    private func list(_ data: Data) throws -> ParsedTextDocument {
        try SevenZipListingAdapter().parse(DataByteSource(data), context: thirdPartyContext)
    }

    @Test(arguments: [("lzma members", ThirdPartyArchiveVectors.lzmaMembers), ("bzip2 members", ThirdPartyArchiveVectors.bzip2Members)])
    func listsNamesKindsAndSizes(label: String, archive: Data) throws {
        let entries = try listedEntries(list(archive))
        #expect(entries.compactMap { $0["path"] as? String } == expectedPaths, "\(label)")
        #expect(entries.compactMap { $0["type"] as? String } == ["directory", "directory", "directory", "file", "file", "file", "file"])
        #expect(entries.compactMap { $0["bytes"] as? Int } == [0, 0, 0, 1024, 0, 408, 240])
        #expect(entries[6]["modified"] as? String == ArchiveFixtures.modifiedISO)
        #expect(entries.allSatisfy { $0["encrypted"] == nil })
        #expect(try listingObject(list(archive))["solid"] as? Bool == true)
    }

    @Test func memberEncryptionIsFlaggedPerEntryWhileNamesRemainListed() throws {
        let entries = try listedEntries(list(ThirdPartyArchiveVectors.encryptedMembers))
        #expect(entries.compactMap { $0["path"] as? String } == expectedPaths)
        #expect(entries.filter { $0["type"] as? String == "file" }.allSatisfy { $0["encrypted"] as? Bool == true })
        #expect(entries.filter { $0["type"] as? String == "directory" }.allSatisfy { $0["encrypted"] == nil })
    }

    @Test func headerEncryptionIsReportedInsteadOfListed() {
        #expect(throws: PreviewFailure.encryptedContent) { try list(ThirdPartyArchiveVectors.encryptedHeader) }
    }
}

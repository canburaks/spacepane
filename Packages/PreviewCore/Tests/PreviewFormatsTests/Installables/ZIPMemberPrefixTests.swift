import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport
@testable import PreviewFormats

@Suite("ZIP member prefixes")
struct ZIPMemberPrefixTests {
    private typealias Fixtures = InstallFixtures


    private func archive(_ members: [(path: String, data: Data)], deflate: Bool) throws -> (ZIPArchive, RecordingByteSource) {
        let source = RecordingByteSource(Fixtures.zip(members, deflate: deflate))
        return (try ZIPArchiveReader.read(source, context: Fixtures.context), source)
    }

    @Test(arguments: [false, true])
    func readsOnlyTheRequestedStartOfALargeMember(deflate: Bool) throws {
        let content = Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: $0 / 7) })
        let (archive, source) = try archive([("big.bin", content)], deflate: deflate)
        let entry = try #require(archive.entry(at: "big.bin"))
        let readsBefore = source.reads.count
        let prefix = try ZIPMemberPrefix.read(entry, from: source, maximumBytes: 1_024, context: Fixtures.context)
        #expect(prefix == content.prefix(1_024))
        let read = source.reads.dropFirst(readsBefore).reduce(0) { $0 + $1.count }
        #expect(read == ZIPMemberPrefix.compressedReadSize(of: entry, maximumBytes: 1_024))
        #expect(read <= 5_300)
    }

    @Test func aMemberShorterThanTheRequestIsReadWhole() throws {
        let (archive, source) = try archive([("small.txt", Data("short".utf8))], deflate: true)
        let entry = try #require(archive.entry(at: "small.txt"))
        #expect(try ZIPMemberPrefix.read(entry, from: source, maximumBytes: 1_024, context: Fixtures.context) == Data("short".utf8))
    }

    @Test func aDamagedOrTruncatedStreamGivesWhatDecodedAndNeverFails() throws {
        let content = Data(String(repeating: "abcdefghij", count: 5_000).utf8)
        let (archive, source) = try archive([("x.txt", content)], deflate: true)
        let entry = try #require(archive.entry(at: "x.txt"))
        let cut = ZIPEntry(path: entry.path, kind: "file", flags: 0, method: 8, crc32: entry.crc32,
                           compressedSize: entry.compressedSize / 2, uncompressedSize: entry.uncompressedSize,
                           payloadOffset: entry.payloadOffset, versionMadeBy: 3, externalAttributes: 0, modified: nil)
        let partial = try ZIPMemberPrefix.read(cut, from: source, maximumBytes: 40_000, context: Fixtures.context)
        #expect(partial.count <= 40_000 && content.starts(with: partial))
        let garbage = RecordingByteSource(Data(repeating: 0xFF, count: 600))
        let damaged = ZIPEntry(path: "g", kind: "file", flags: 0, method: 8, crc32: 0, compressedSize: 500,
                               uncompressedSize: 5_000, payloadOffset: 10, versionMadeBy: 3, externalAttributes: 0, modified: nil)
        #expect(try ZIPMemberPrefix.read(damaged, from: garbage, maximumBytes: 1_024, context: Fixtures.context).isEmpty)
    }

    @Test func otherMethodsEncryptedMembersAndFoldersGiveNothingAndReadNothing() throws {
        let source = RecordingByteSource(Data(repeating: 0, count: 600))
        func entry(kind: String = "file", method: UInt64 = 8, flags: UInt64 = 0, size: Int = 100) -> ZIPEntry {
            ZIPEntry(path: "m", kind: kind, flags: flags, method: method, crc32: 0, compressedSize: size,
                     uncompressedSize: size, payloadOffset: 0, versionMadeBy: 3, externalAttributes: 0, modified: nil)
        }
        for candidate in [entry(method: 12), entry(method: 93), entry(flags: 1), entry(kind: "directory"),
                          entry(kind: "symlink"), entry(size: 0)] {
            #expect(try ZIPMemberPrefix.read(candidate, from: source, maximumBytes: 1_024, context: Fixtures.context).isEmpty)
        }
        #expect(source.reads.isEmpty)
    }
}

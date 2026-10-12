import Foundation
import CryptoKit
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Torrent summaries")
struct TorrentAdapterTests {
    private let context = PackageTestSupport.context
    private func summary(_ data: Data, context: RequestContext = PackageTestSupport.context) throws -> ([String: Any], ParsedTextDocument) {
        let document = try TorrentAdapter().parse(FileBytes(data: data), context: context)
        return (PackageTestSupport.object(document), document)
    }

    @Test func singleFileTorrentReportsItsFacts() throws {
        let fixture = PackageFixtures.torrent(isPrivate: true)
        let (summary, _) = try summary(fixture.data)
        #expect(summary["name"] as? String == "Synthetic Data")
        #expect(summary["layout"] as? String == "singleFile")
        #expect(summary["fileCount"] as? Int == 1)
        #expect(summary["totalBytes"] as? Int == 4_096)
        #expect(summary["pieceLength"] as? Int == 1_024)
        #expect(summary["pieceCount"] as? Int == 4)
        #expect(summary["private"] as? Bool == true)
        #expect(summary["created"] as? String == "2023-11-14T22:13:20Z")
        #expect(summary["createdBy"] as? String == "Synthetic Tool 1.0")
        #expect(summary["comment"] as? String == "Synthetic comment")
        #expect(summary["archiveFormat"] as? String == "BitTorrent")
        let entries = PackageTestSupport.entries(summary)
        #expect(entries.count == 1 && entries[0]["path"] as? String == "Synthetic Data" && entries[0]["bytes"] as? Int == 4_096)
    }

    @Test func infoHashIsTheSHA1OfTheExactInfoBytes() throws {
        let fixture = PackageFixtures.torrent()
        let (summary, _) = try summary(fixture.data)
        let expected = Data(Insecure.SHA1.hash(data: fixture.info)).hexadecimal().lowercased()
        #expect(summary["infoHash"] as? String == expected)
        #expect(summary["infoHashV2"] == nil)
    }

    @Test func versionTwoTorrentsAlsoReportTheSHA256Hash() throws {
        let fixture = PackageFixtures.torrent(extraInfo: [("meta version", .integer(2))])
        let (summary, _) = try summary(fixture.data)
        #expect(summary["infoHashV2"] as? String == Data(SHA256.hash(data: fixture.info)).hexadecimal().lowercased())
        #expect((summary["infoHash"] as? String)?.count == 40)
    }

    @Test func multiFileTorrentListsFilesUnderTheTorrentName() throws {
        let fixture = PackageFixtures.torrent(name: "Album", files: [(["disc 1", "a.flac"], 3_000), (["b.txt"], 200)])
        let (summary, _) = try summary(fixture.data)
        #expect(summary["layout"] as? String == "multipleFiles")
        #expect(summary["fileCount"] as? Int == 2)
        #expect(summary["totalBytes"] as? Int == 3_200)
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String } == ["Album/disc 1/a.flac", "Album/b.txt"])
    }

    @Test func paddingFilesAreNotListed() throws {
        let padded = PackageFixtures.Bencode.dictionary([("length", .integer(512)), ("attr", .text("p")), ("path", .list([.text(".pad"), .text("512")]))])
        let real = PackageFixtures.Bencode.dictionary([("length", .integer(100)), ("path", .list([.text("real.bin")]))])
        let info = PackageFixtures.Bencode.dictionary([("name", .text("Padded")), ("piece length", .integer(1_024)),
                                                       ("pieces", .bytes(Data(repeating: 1, count: 20))), ("files", .list([real, padded]))])
        let data = PackageFixtures.Bencode.dictionary([("info", info)]).encoded
        let (summary, _) = try summary(data)
        #expect(summary["fileCount"] as? Int == 1)
        #expect(summary["totalBytes"] as? Int == 100)
    }

    @Test func versionTwoFileTreesAreFlattened() throws {
        let leaf = { (length: Int) in PackageFixtures.Bencode.dictionary([("", .dictionary([("length", .integer(length))]))]) }
        let tree = PackageFixtures.Bencode.dictionary([("docs", .dictionary([("a.txt", leaf(10)), ("b.txt", leaf(20))])), ("readme", leaf(5))])
        let info = PackageFixtures.Bencode.dictionary([("name", .text("Tree")), ("piece length", .integer(16_384)),
                                                       ("meta version", .integer(2)), ("file tree", tree)])
        let (summary, _) = try summary(PackageFixtures.Bencode.dictionary([("info", info)]).encoded)
        #expect(summary["fileCount"] as? Int == 3)
        #expect(summary["totalBytes"] as? Int == 35)
        #expect(Set(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String }) == ["Tree/docs/a.txt", "Tree/docs/b.txt", "Tree/readme"])
        #expect(summary["infoHash"] == nil)
        #expect(summary["infoHashV2"] != nil)
    }

    @Test func trackersAreReducedToSchemeHostAndPort() throws {
        let fixture = PackageFixtures.torrent(
            announce: "udp://tracker.example.test:6969/announce?passkey=\(PackageFixtures.secret)",
            announceList: [["https://user:pass@secure.example.test/a/b?c=d", "udp://tracker.example.test:6969/other"], ["http://[2001:db8::1]:8080/x", "ftp://ignored.example.test/x", "not a url"]],
            webSeeds: ["https://seed.example.test/files/?token=\(PackageFixtures.secret)"])
        let (summary, document) = try summary(fixture.data)
        #expect(summary["trackers"] as? [String] == ["udp://tracker.example.test:6969", "https://secure.example.test", "http://[2001:db8::1]:8080"])
        #expect(summary["webSeeds"] as? Int == 1)
        for text in [document.text, PackageTestSupport.concealedText(document)] {
            #expect(!text.contains(PackageFixtures.secret) && !text.contains("passkey") && !text.contains("user:pass") && !text.contains("/announce"))
        }
    }

    @Test func credentialLookingFreeTextIsConcealed() throws {
        for comment in ["passkey=abc", "see https://tracker.example.test/get?x=1", "https://u@example.test/", "my password is hunter2", "api_key: \(PackageFixtures.secret)"] {
            let fixture = PackageFixtures.torrent(comment: comment, createdBy: comment)
            let (_, document) = try summary(fixture.data)
            let visible = PackageTestSupport.concealedText(document)
            #expect(!visible.contains(comment), "Comment should be concealed: \(comment)")
            #expect(document.sensitiveRanges.count >= 2)
        }
        let (_, ordinary) = try summary(PackageFixtures.torrent(comment: "Ordinary note").data)
        #expect(PackageTestSupport.concealedText(ordinary).contains("Ordinary note"))
    }

    @Test func nonUTF8NamesUseTheUTF8Variant() throws {
        let fixture = PackageFixtures.torrent(name: "legacy", extraInfo: [("name.utf-8", .text("Ünïcode 日本語"))])
        let (summary, _) = try summary(fixture.data)
        #expect(summary["name"] as? String == "Ünïcode 日本語")
    }

    @Test func unsafeEntryPathsAreSkippedAndFlaggedPartial() throws {
        let fixture = PackageFixtures.torrent(name: "Root", files: [(["..", "escape.txt"], 1), (["ok.txt"], 2)])
        let (summary, _) = try summary(fixture.data)
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String } == ["Root/ok.txt"])
        #expect(summary["partial"] as? Bool == true)
        #expect(summary["fileCount"] as? Int == 2)
    }

    @Test func listingIsBoundedByTheBudgetAndFlaggedPartial() throws {
        let files = (0..<5_000).map { (["file-\($0).bin"], 1) }
        let fixture = PackageFixtures.torrent(name: "Many", files: files)
        let (summary, _) = try summary(fixture.data, context: RequestContext(budget: PreviewBudget(maxInputBytes: 4_194_304, maxMilliseconds: 30_000)))
        #expect(summary["fileCount"] as? Int == 5_000)
        #expect(PackageTestSupport.entries(summary).count == PackageSummary.listingCapacity(PackageTestSupport.context))
        #expect(summary["partial"] as? Bool == true)
    }

    @Test func missingPieceTableDoesNotInventAPieceCount() throws {
        let info = PackageFixtures.Bencode.dictionary([("name", .text("NoPieces")), ("length", .integer(10)), ("piece length", .integer(16))])
        let (summary, _) = try summary(PackageFixtures.Bencode.dictionary([("info", info)]).encoded)
        #expect(summary["pieceCount"] == nil && summary["infoHash"] == nil)
    }

    @Test func malformedTorrentsFailClosed() {
        let valid = PackageFixtures.torrent().data
        let samples: [Data] = [
            Data(), Data("not bencode".utf8), Data("i42e".utf8), Data("le".utf8), Data("de".utf8),
            valid.dropLast(), valid + Data("x".utf8), Data(valid.prefix(valid.count / 2)),
            Data("d4:infod4:name3:abcee".utf8),                                  // no files or length
            Data("d4:infod4:name3:abc6:lengthi-1eee".utf8),                       // negative length
            Data("d4:infod4:name3:abc6:lengthi01eee".utf8),                       // leading zero
            Data("d4:infod4:name3:abc6:lengthi-0eee".utf8),                       // negative zero
            Data("d4:infod4:name3:abc6:lengthi99999999999999999999eee".utf8),     // beyond Int64
            Data("d4:infod4:name99:abce6:lengthi1eee".utf8),                      // string longer than the input
            Data("d4:infod4:name3:abc4:name3:xyz6:lengthi1eee".utf8),             // duplicate key
            Data("d4:infod4:name3:abc6:lengthi1e6:pieces5:abcdeee".utf8)          // pieces not a multiple of 20
        ]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try TorrentAdapter().parse(FileBytes(data: data), context: PackageTestSupport.context) }
        }
    }

    @Test func nestingDepthAndNodeCountAreBounded() {
        let deep = Data(String(repeating: "l", count: 200).utf8) + Data(String(repeating: "e", count: 200).utf8)
        #expect(throws: PreviewFailure.structureTooDeep) { try TorrentAdapter().parse(FileBytes(data: deep), context: PackageTestSupport.context) }
        let wide = Data("d4:infod4:name1:a6:lengthi1e5:extral".utf8) + Data(String(repeating: "i1e", count: 260_000).utf8) + Data("eee".utf8)
        #expect(throws: PreviewFailure.tooManyNodes) {
            try TorrentAdapter().parse(FileBytes(data: wide), context: RequestContext(budget: PreviewBudget(maxInputBytes: 4_194_304, maxMilliseconds: 30_000)))
        }
    }

    @Test func totalSizeOverflowIsRejected() {
        let fixture = PackageFixtures.torrent(name: "Big", files: [(["a"], Int(Int64.max)), (["b"], 10)])
        #expect(throws: PreviewFailure.malformedDocument) { try TorrentAdapter().parse(FileBytes(data: fixture.data), context: PackageTestSupport.context) }
    }

    @Test func cancelledRequestsNeverParse() async {
        let data = PackageFixtures.torrent().data
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try TorrentAdapter().parse(FileBytes(data: data), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport
@testable import PreviewFormats

@Suite("Add-on archive helpers")
struct AddOnArchiveTests {
    private var context: RequestContext { RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)) }
    private typealias Member = AddOnFixtures.Member

    private func open(_ members: [Member]) throws -> (AddOnArchive, RecordingByteSource) {
        let source = RecordingByteSource(AddOnFixtures.zip(members))
        return (try AddOnArchive(source: source, context: context), source)
    }

    private func counts(_ tally: AddOnHiddenTally) -> [PreviewFindingKind: Int] {
        Dictionary(uniqueKeysWithValues: tally.findings.map { ($0.kind, $0.count) })
    }

    private static let zeroWidth = "\u{200B}"

    // MARK: Manifest

    @Test func manifestIsReadAsTolerantJSON() throws {
        let text = "\u{FEFF}// a comment\n{ \"name\": \"demo\", /* inline */ \"list\": [1, 2,], \"nested\": {\"flag\": true}, }"
        let (archive, _) = try open([Member("manifest.json", text: text)])
        let root = try archive.manifest(at: "manifest.json")
        #expect(root.text("name") == "demo")
        #expect(root.at("nested")?.flag("flag") == true)
        #expect(root.member("list")?.value.elements?.count == 2)
    }

    @Test func aMissingOrUnusableManifestFailsTheSummary() throws {
        let samples: [Data] = [Data("[1, 2]".utf8), Data("not json".utf8), Data(), Data([0x7B, 0xFF, 0x7D]), Data("{\"a\": 1".utf8)]
        for data in samples {
            let (archive, _) = try open([Member("manifest.json", data)])
            #expect(throws: PreviewFailure.malformedDocument) { try archive.manifest(at: "manifest.json") }
        }
        let (other, _) = try open([Member("sub/manifest.json", text: "{}")])
        #expect(throws: PreviewFailure.malformedDocument) { try other.manifest(at: "manifest.json") }
    }

    @Test func anOversizedManifestIsRefusedBeforeItsPayloadIsRead() throws {
        let big = Data("{\"description\": \"".utf8) + Data(repeating: 0x61, count: AddOnLimits.manifestBytes) + Data("\"}".utf8)
        let (archive, source) = try open([Member("manifest.json", big)])
        let opened = source.reads.count
        #expect(throws: PreviewFailure.inputTooLarge) { try archive.manifest(at: "manifest.json") }
        #expect(source.reads.count == opened, "no payload byte is read")
    }

    // MARK: Prefix reads

    @Test func aStoredMemberIsReadUpToTheLimit() throws {
        let data = Data((0..<1_000).map { UInt8($0 % 251) })
        let (archive, source) = try open([Member("a.bin", data)])
        let entry = try #require(archive.archive.entry(at: "a.bin"))
        let before = source.reads.count
        #expect(try archive.prefix(of: entry, limit: 100) == data.prefix(100))
        #expect(source.reads.dropFirst(before).map(\.count) == [100])
        #expect(try archive.prefix(of: entry, limit: 5_000) == data)
    }

    @Test func aDeflatedMemberIsInflatedOnlyAsFarAsTheLimitNeeds() throws {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        let noise = Data((0..<2_000_000).map { _ -> UInt8 in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        })
        let (archive, source) = try open([Member("big.js", noise, deflated: true)])
        let entry = try #require(archive.archive.entry(at: "big.js"))
        #expect(entry.method == 8 && entry.compressedSize > 1_900_000)
        let before = source.reads.count
        let head = try archive.prefix(of: entry, limit: 100_000)
        #expect(head == noise.prefix(100_000))
        let payload = entry.payloadOffset..<(entry.payloadOffset + entry.compressedSize)
        let read = source.reads.dropFirst(before).filter { $0.overlaps(payload) }.reduce(0) { $0 + $1.count }
        #expect(read > 0 && read <= 100_000 + 2 * 65_536, "read \(read) payload bytes")
    }

    @Test func aHighlyCompressedMemberYieldsItsPrefixFromAFewBytes() throws {
        let zeros = Data(repeating: 0, count: 4_000_000)
        let (archive, _) = try open([Member("zeros.js", zeros, deflated: true)])
        let entry = try #require(archive.archive.entry(at: "zeros.js"))
        #expect(try archive.prefix(of: entry, limit: 262_144) == zeros.prefix(262_144))
    }

    @Test func unreadableMembersReadAsEmpty() throws {
        let (archive, _) = try open([Member("dir/", Data()), Member("empty.js", Data())])
        for entry in archive.archive.entries { #expect(try archive.prefix(of: entry, limit: 10).isEmpty) }
    }

    // MARK: Native code

    @Test func nativeMembersAreFoundByNameAndByContent() throws {
        let (archive, _) = try open([
            Member("lib/addon.node", Data("not really".utf8)), Member("bin/helper", AddOnFixtures.machO),
            Member("bin/tool", AddOnFixtures.elf, deflated: true), Member("src/index.js", text: "console.log(1)\n"),
            Member("README.md", text: "# readme"), Member("data/blob.bin", Data(repeating: 7, count: 200)),
            Member("tiny", Data([0xCF, 0xFA, 0xED, 0xFE])), Member("dir/", Data())
        ])
        #expect(Set(try archive.nativeMembers()) == ["lib/addon.node", "bin/helper", "bin/tool"])
    }

    @Test func plainSuffixesAreNotProbedAndOrdinaryFilesAreNotNative() throws {
        let (archive, source) = try open([
            Member("logo.png", AddOnFixtures.machO), Member("notes.txt", text: String(repeating: "MZ is only text. ", count: 20)),
            Member("a.class", Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 65]) + Data(repeating: 0, count: 40))
        ])
        let opened = source.reads.count
        #expect(try archive.nativeMembers().isEmpty)
        #expect(source.reads.dropFirst(opened).count == 1, "only the class file is probed")
    }

    @Test func contentProbesAreBounded() throws {
        var members = (0..<AddOnLimits.contentProbes).map { Member("file-\($0).dat", Data(repeating: 1, count: 32)) }
        members += [Member("late.dat", AddOnFixtures.machO), Member("late.dylib", Data("named".utf8))]
        let (archive, _) = try open(members)
        #expect(try archive.nativeMembers() == ["late.dylib"])
    }

    // MARK: Invisible characters in scripts

    @Test func invisibleCharactersInAScriptAreCounted() throws {
        let code = "const a = 1;\(Self.zeroWidth)\(Self.zeroWidth) // \u{202E}reversed\n"
        let (archive, _) = try open([Member("extension/main.js", text: code, deflated: true)])
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: [], to: &tally)
        #expect(counts(tally) == [.hiddenZeroWidth: 2, .hiddenBidirectionalControls: 1])
        #expect(tally.findings.allSatisfy { $0.lines.isEmpty && $0.detail == .none })
    }

    @Test func aByteOrderMarkAndOrdinaryTextAreSilent() throws {
        let (archive, _) = try open([Member("a.js", Data([0xEF, 0xBB, 0xBF]) + Data("let x = 'caf\u{E9} \u{1F600}';\n".utf8)),
                                     Member("b.py", text: "print('hello')\n")])
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: [], to: &tally)
        #expect(tally.findings.isEmpty)
    }

    @Test func onlyTheLeadingBytesOfALargeScriptAreScanned() throws {
        let filler = String(repeating: "x", count: AddOnLimits.scriptMemberBytes + 10)
        let (archive, _) = try open([Member("late.js", text: filler + Self.zeroWidth, deflated: true),
                                     Member("early.js", text: Self.zeroWidth + filler, deflated: true)])
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: ["late.js"], to: &tally)
        #expect(counts(tally) == [.hiddenZeroWidth: 1])
    }

    @Test func theDeclaredEntryPointIsScannedBeforeTheMemberLimit() throws {
        var members = (0..<(AddOnLimits.scriptMembers + 5)).map { Member(String(format: "m%02d.js", $0), text: "let a = 1;\n") }
        members.append(Member("zz/entry.js", text: "let b = \(Self.zeroWidth)1;\n"))
        let (archive, _) = try open(members)
        var preferred = AddOnHiddenTally()
        try archive.addScriptText(preferred: ["zz/entry.js"], to: &preferred)
        #expect(counts(preferred) == [.hiddenZeroWidth: 1])
        var unpreferred = AddOnHiddenTally()
        try archive.addScriptText(preferred: [], to: &unpreferred)
        #expect(unpreferred.findings.isEmpty, "the entry sorts after the twenty shallower scripts")
    }

    @Test func extensionlessEntryPointsGetTheirJavaScriptSuffix() throws {
        let (archive, _) = try open([Member("out/extension.js", text: Self.zeroWidth + "x")])
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: ["out/extension"], to: &tally)
        #expect(counts(tally) == [.hiddenZeroWidth: 1])
    }

    @Test func dependenciesAndDeclarationFilesRankLast() throws {
        var members = (0..<AddOnLimits.scriptMembers).map { Member("src/s\($0).js", text: "let a;\n") }
        members += [Member("node_modules/dep/index.js", text: Self.zeroWidth), Member("types/x.d.ts", text: Self.zeroWidth)]
        let (archive, _) = try open(members)
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: [], to: &tally)
        #expect(tally.findings.isEmpty)
    }

    @Test func allScriptsTogetherAreReadToTheTotalLimit() throws {
        let block = String(repeating: "y", count: AddOnLimits.scriptMemberBytes)
        var members = (0..<8).map { Member("s\($0).js", text: block) }
        members.append(Member("s9.js", text: Self.zeroWidth + block))
        let (archive, source) = try open(members)
        let opened = source.reads.count
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: [], to: &tally)
        #expect(tally.findings.isEmpty, "eight members use the whole 2 MiB")
        let last = try #require(archive.archive.entry(at: "s9.js"))
        let payload = last.payloadOffset..<(last.payloadOffset + last.compressedSize)
        #expect(!source.reads.dropFirst(opened).contains { $0.overlaps(payload) })
    }

    @Test func aCorruptDeflateStreamDoesNotStopTheScan() throws {
        var bytes = AddOnFixtures.zip([Member("bad.js", text: String(repeating: "q", count: 500), deflated: true), Member("ok.js", text: Self.zeroWidth)])
        // Corrupt the start of the first member's deflate stream (its payload follows the 30-byte header and the 6-byte name).
        bytes[36] = 0xFF
        bytes[37] = 0xFF
        let archive = try AddOnArchive(source: RecordingByteSource(bytes), context: context)
        var tally = AddOnHiddenTally()
        try archive.addScriptText(preferred: [], to: &tally)
        #expect(counts(tally) == [.hiddenZeroWidth: 1])
    }
}

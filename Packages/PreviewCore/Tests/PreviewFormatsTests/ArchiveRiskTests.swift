import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

// MARK: Fixtures

private struct ZIPMember {
    var path: String
    var payload = Data("x".utf8)
    /// Uncompressed size written to both headers; defaults to the payload size.
    var declaredSize: UInt64?
    var method: UInt64 = 0
    var flags: UInt64 = 0x800
    /// Unix mode, file type bits included, written to the external attributes.
    var mode: UInt64?
    /// Version-made-by host: 3 is Unix, 0 is MS-DOS.
    var host: UInt64 = 3
}

private func zipArchive(_ members: [ZIPMember]) -> Data {
    var data = Data()
    var central = Data()
    for member in members {
        let name = Data(member.path.utf8)
        let stored = UInt64(member.payload.count)
        let declared = member.declaredSize ?? stored
        let offset = data.count
        data += little(0x04034b50, width: 4) + little(20, width: 2) + little(member.flags, width: 2) + little(member.method, width: 2)
        data += Data(repeating: 0, count: 8) + little(stored, width: 4) + little(declared, width: 4)
        data += little(UInt64(name.count), width: 2) + little(0, width: 2) + name + member.payload
        central += little(0x02014b50, width: 4) + little(member.host << 8 | 20, width: 2) + little(20, width: 2)
        central += little(member.flags, width: 2) + little(member.method, width: 2) + Data(repeating: 0, count: 8)
        central += little(stored, width: 4) + little(declared, width: 4) + little(UInt64(name.count), width: 2)
        central += Data(repeating: 0, count: 8) // extra, comment, disk and internal attributes
        central += little((member.mode ?? 0) << 16, width: 4) + little(UInt64(offset), width: 4) + name
    }
    let start = data.count
    data += central
    data += little(0x06054b50, width: 4) + Data(repeating: 0, count: 4)
    data += little(UInt64(members.count), width: 2) + little(UInt64(members.count), width: 2)
    data += little(UInt64(central.count), width: 4) + little(UInt64(start), width: 4) + little(0, width: 2)
    return data
}

private struct TARMember {
    var path: String
    var type: UInt8 = 48
    var mode = 0o644
    var link = ""
    var payload = Data()
}

private func tarArchive(_ members: [TARMember]) -> Data {
    var data = Data()
    for member in members {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ string: String, at offset: Int, count: Int) {
            for (index, byte) in string.utf8.prefix(count).enumerated() { header[offset + index] = byte }
        }
        put(member.path, at: 0, count: 100)
        put(String(format: "%07o", member.mode) + "\0", at: 100, count: 8)
        put(String(format: "%011o", member.payload.count) + "\0", at: 124, count: 12)
        header[156] = member.type
        put(member.link, at: 157, count: 100)
        put("ustar\0", at: 257, count: 6)
        for index in 148..<156 { header[index] = 32 }
        let checksum = header.reduce(0) { $0 + Int($1) }
        put(String(format: "%06o", checksum) + "\0 ", at: 148, count: 8)
        data += Data(header) + member.payload + Data(repeating: 0, count: (512 - member.payload.count % 512) % 512)
    }
    return data + Data(repeating: 0, count: 1024)
}

/// One PAX extended-header record: its decimal length counts itself.
private func paxRecord(_ key: String, _ value: String) -> Data {
    let body = " \(key)=\(value)\n"
    var length = body.utf8.count
    while String(length).utf8.count + body.utf8.count != length { length = String(length).utf8.count + body.utf8.count }
    return Data("\(length)\(body)".utf8)
}

private final class RiskRecordingSource: PreviewByteSource {
    struct Read: Sendable, Equatable { let offset: Int64; let count: Int }
    let data: Data
    private let failAfter: Int?
    private let log = Mutex<[Read]>([])
    var byteCount: Int64 { Int64(data.count) }
    var reads: [Read] { log.withLock { $0 } }
    /// `failAfter` reads succeed; every later read reports an exhausted budget.
    init(_ data: Data, failAfter: Int? = nil) { self.data = data; self.failAfter = failAfter }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        try log.withLock { reads in
            if let failAfter, reads.count >= failAfter { throw PreviewFailure.inputTooLarge }
            reads.append(Read(offset: offset, count: count))
        }
        guard offset >= 0, count >= 0, offset <= byteCount, Int64(count) <= byteCount - offset else { throw PreviewFailure.malformedDocument }
        return data.subdata(in: Int(offset)..<(Int(offset) + count))
    }
}

// MARK: Summary helpers

private func entryRisks(_ document: ParsedTextDocument) throws -> [(path: String, risks: [String])] {
    let root = try #require(JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
    let entries = try #require(root["entries"] as? [[String: Any]])
    return try entries.map { entry in
        (try #require(entry["path"] as? String), entry["risks"] as? [String] ?? [])
    }
}

private func risksByPath(_ document: ParsedTextDocument) throws -> [String: [String]] {
    Dictionary(try entryRisks(document).map { ($0.path, $0.risks) }) { first, _ in first }
}

private func counts(_ document: ParsedTextDocument) -> [PreviewFindingKind: Int] {
    Dictionary(uniqueKeysWithValues: document.findings.map { ($0.kind, $0.count) })
}

// MARK: Analyzer rules

private func entry(_ path: String, kind: ContainerEntryKind = .file, size: Int? = nil, stored: Int? = nil,
                   mode: UInt32? = nil, target: String? = nil, encrypted: Bool = false) -> ContainerEntry {
    ContainerEntry(path: path, kind: kind, size: size, storedSize: stored, mode: mode, linkTarget: target, isEncrypted: encrypted)
}

private func analyze(_ entries: [ContainerEntry]) throws -> ArchiveRiskReport {
    try ArchiveRiskAnalyzer.analyze(entries, context: containerContext)
}

private func risks(_ single: ContainerEntry) throws -> [ArchiveEntryRisk] { try analyze([single]).entryRisks[0] }

@Suite("Archive risk analyzer")
struct ArchiveRiskAnalyzerTests {
    @Test func unsafePathsAreAbsoluteDriveLetterOrParentTraversalAfterTreatingBackslashAsSeparator() throws {
        for path in ["../x", "a/../x", "a/b/..", "/abs", "\\abs", "C:\\x", "c:/x", "a\\..\\b", "..\\x"] {
            #expect(try risks(entry(path)).contains(.unsafePath), "\(path)")
        }
        for path in ["a..b.txt", "a/b..", "..hidden", "...", "dir/..a/b", "file:name", "1:x", "x/./y", "日本語.txt", "C", "a/b/"] {
            #expect(try !risks(entry(path)).contains(.unsafePath), "\(path)")
        }
    }

    @Test func hiddenComponentsAndMacMetadataAreSeparateAndMetadataIsNotHidden() throws {
        for path in [".github/workflows/ci.yml", "a/.hidden/b", ".DS_Store", "dir/.env", "..hidden", ".config/"] {
            #expect(try risks(entry(path)) == [.hidden], "\(path)")
        }
        for path in ["report.pdf", ".", "./a", "a/.", "a/b/", "a/.."] {
            #expect(try !risks(entry(path)).contains(.hidden), "\(path)")
        }
        #expect(try risks(entry("__MACOSX/._report.pdf")) == [.macMetadata])
        #expect(try risks(entry("__MACOSX/", kind: .directory)) == [.macMetadata])
        #expect(try risks(entry("docs/__MACOSX/x")).isEmpty)
        #expect(try risks(entry("__MACOSXX/x")).isEmpty)
    }

    @Test func executablesAreThingsThatRunOnOpenOrInstallNotOrdinarySource() throws {
        for name in ["setup.exe", "SETUP.EXE", "a.pkg", "a.mpkg", "run.command", "x.tool", "x.scpt", "x.scptd", "x.applescript",
                     "x.workflow", "x.action", "x.terminal", "x.jar", "x.msi", "x.bat", "x.cmd", "x.com", "x.scr", "x.ps1",
                     "x.vbs", "x.wsf", "dir/Tool.App", "dir/Tool.app/"] {
            #expect(try risks(entry(name)).contains(.executable), "\(name)")
        }
        for name in ["run.sh", "tool.py", "app.js", "readme.txt", "exe", ".exe", "setup.exe.txt", "archive.tar.gz", "app"] {
            #expect(try !risks(entry(name)).contains(.executable), "\(name)")
        }
    }

    @Test func executeBitsFlagOnlyRegularFilesWithAKnownMode() throws {
        #expect(try risks(entry("bin/tool", mode: 0o100755)) == [.executable])
        #expect(try risks(entry("bin/tool", mode: 0o100100)) == [.executable])
        #expect(try risks(entry("bin/tool", mode: 0o100644)).isEmpty)
        #expect(try risks(entry("bin/tool", mode: nil)).isEmpty)
        #expect(try risks(entry("bin", kind: .directory, mode: 0o40755)).isEmpty)
        #expect(try risks(entry("dev/null", kind: .special, mode: 0o20755)).isEmpty)
        #expect(try risks(entry("ok", kind: .symlink, mode: 0o120777, target: "tool")) == [])
    }

    @Test func aBundleCountsOnceOnItsDirectoryEntryOrItsFirstListedMember() throws {
        let members = [entry("Foo.app/Contents/MacOS/Foo", mode: 0o100755), entry("Foo.app/Contents/Resources/run.command", mode: 0o100755),
                       entry("Foo.app/Contents/", kind: .directory, mode: 0o40755)]
        let directory = entry("Foo.app/", kind: .directory, mode: 0o40755)
        for ordered in [[directory] + members, members + [directory]] {
            let report = try analyze(ordered)
            let flagged = report.entryRisks.indices.filter { report.entryRisks[$0].contains(.executable) }
            #expect(flagged.map { ordered[$0].path } == ["Foo.app/"])
        }
        let withoutDirectory = try analyze([entry("Foo.app/Contents/Info.plist"), entry("Foo.app/Contents/MacOS/Foo", mode: 0o100755)])
        #expect(withoutDirectory.entryRisks.map { $0.contains(.executable) } == [true, false])
        let nested = try analyze([entry("Foo.app/Frameworks/A.app/Contents/x"), entry("Foo.app/Frameworks/B.app/Contents/y", mode: 0o100755)])
        #expect(nested.entryRisks.map { $0.contains(.executable) } == [true, false])
        let separate = try analyze([entry("A.app/x"), entry("B.app/y"), entry("apps/C.app/z"), entry("apps/C.app/w")])
        #expect(separate.entryRisks.map { $0.contains(.executable) } == [true, true, true, false])
        #expect(separate.findings.first { $0.kind == .archiveExecutables }?.count == 3)
    }

    @Test func disguisedNamesPutAnExecutableExtensionAfterADocumentOrMediaOne() throws {
        for name in ["invoice.pdf.app", "photo.jpg   .command", "invoice.pdf     .app", "a.TXT.exe", "dir/report.docx.scr",
                     "movie.mp4\u{00A0}\u{00A0}.bat", "invoice.pdf.app/"] {
            #expect(try risks(entry(name)) == [.executable, .disguisedName], "\(name)")
        }
        for name in ["report.pdf", "archive.tar.gz", "notes.app", "readme.exe.txt", ".pdf.app", "setup.exe", "pdf.app", "a.sh.exe"] {
            #expect(try !risks(entry(name)).contains(.disguisedName), "\(name)")
        }
        // A bundle is judged by the name its folder shows, even when only a member is listed.
        let bundle = try analyze([entry("invoice.pdf.app/Contents/Info.plist")])
        #expect(bundle.entryRisks[0] == [.executable, .disguisedName])
    }

    @Test func directionalCharactersAreFlaggedAnywhereInThePath() throws {
        let values: [UInt32] = [0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069]
        let scalars = values.compactMap { Unicode.Scalar($0) }
        #expect(scalars.count == 12)
        for scalar in scalars {
            #expect(try risks(entry("dir/fi\(scalar)le.txt")) == [.directionalName], "U+\(String(scalar.value, radix: 16))")
        }
        #expect(try risks(entry("invoice\u{202E}fdp.exe")) == [.executable, .directionalName])
        for name in ["日本語.txt", "ملف.txt", "שלום.txt", "a\u{200B}b.txt", "a\u{2065}b", "a\u{202F}b", "a\u{2070}b"] {
            #expect(try !risks(entry(name)).contains(.directionalName), "\(name)")
        }
    }

    @Test func nestedArchivesAndDiskImagesAreFlaggedByFinalExtensionOnly() throws {
        for name in ["a.zip", "b.TAR.GZ", "c.dmg", "d.tgz", "e.bz2", "f.tbz", "g.tbz2", "h.xz", "i.txz", "j.zst", "k.7z", "l.rar",
                     "m.xip", "n.iso", "o.sparseimage", "p.cpio", "q.pax", "r.gz", "s.tar"] {
            #expect(try risks(entry(name)) == [.nested], "\(name)")
        }
        #expect(try risks(entry("d.sparsebundle/", kind: .directory)) == [.nested])
        for name in ["e.txt", "zip", ".zip", "zip.txt", "gz.txt", "d.sparsebundle"] {
            #expect(try !risks(entry(name)).contains(.nested), "\(name)")
        }
        // A folder that merely has an archive's name is not an archive; its members are checked on their own.
        #expect(try risks(entry("x.zip/", kind: .directory)).isEmpty)
        #expect(try risks(entry("d.sparsebundle/bands/0")).isEmpty)
    }

    @Test func highCompressionNeedsOneMebibyteAndAHundredToOneAndKeepsTheLargestRatio() throws {
        let mebibyte = 1_048_576
        #expect(try risks(entry("a", size: mebibyte, stored: 10_485)) == [.highCompression])
        #expect(try risks(entry("a", size: mebibyte, stored: 10_486)).isEmpty)
        #expect(try risks(entry("a", size: mebibyte - 1, stored: 1)).isEmpty)
        #expect(try risks(entry("a", size: mebibyte * 50, stored: 0)).isEmpty)
        #expect(try risks(entry("a", size: mebibyte * 50, stored: nil)).isEmpty)
        #expect(try risks(entry("a/", kind: .directory, size: mebibyte * 50, stored: 1)).isEmpty)
        let report = try analyze([entry("a", size: 5 * mebibyte, stored: 1_000), entry("b", size: mebibyte, stored: 100),
                                  entry("c", size: mebibyte, stored: mebibyte / 2)])
        #expect(report.entryRisks.map(\.isEmpty) == [false, false, true])
        let finding = try #require(report.findings.first { $0.kind == .archiveHighCompression })
        #expect(finding.count == 2)
        #expect(finding.detail == .compressionRatio(10_485)) // 1 MiB / 100 B, the larger, rounded down
        #expect(try #require(analyze([entry("a", size: 5 * mebibyte, stored: 1_000)]).findings.first).detail == .compressionRatio(5_242))
    }

    @Test func largeExpansionTotalsDeclaredFileSizesWithoutOverflow() throws {
        let gibibyte = 1 << 30
        func total(_ sizes: [Int]) throws -> PreviewFinding? {
            try analyze(sizes.map { entry("f\($0)", size: $0) }).findings.first { $0.kind == .archiveLargeExpansion }
        }
        #expect(try total([gibibyte])?.detail == .expandedBytes(Int64(gibibyte)))
        #expect(try total([gibibyte - 1]) == nil)
        #expect(try total([600 << 20, 600 << 20])?.detail == .expandedBytes(Int64(1_200 << 20)))
        #expect(try total([400 << 20, 400 << 20]) == nil)
        #expect(try total([Int.max, Int.max])?.detail == .expandedBytes(.max))
        // Directories and links do not count towards the extracted size.
        let others = try analyze([entry("d/", kind: .directory, size: gibibyte), entry("l", kind: .symlink, size: gibibyte, target: "x")])
        #expect(others.findings.allSatisfy { $0.kind != .archiveLargeExpansion })
        let finding = try #require(try total([gibibyte]))
        #expect(finding.count == 1)
        #expect(finding.severity == PreviewFindingKind.archiveLargeExpansion.defaultSeverity)
    }

    @Test func symbolicLinksResolveFromTheirOwnDirectory() throws {
        func risk(_ path: String, _ target: String?) throws -> [ArchiveEntryRisk] {
            try risks(entry(path, kind: .symlink, target: target))
        }
        #expect(try risk("docs/link", "../../etc") == [.linkEscape])
        #expect(try risk("link", "../x") == [.linkEscape])
        #expect(try risk("a/link", "b/../../..") == [.linkEscape])
        #expect(try risk("a/link", "../..") == [.linkEscape])
        #expect(try risk("a/link", "/etc/passwd") == [.linkEscape])
        #expect(try risk("a/link", "\\share") == [.linkEscape])
        #expect(try risk("a/link", "C:\\Windows") == [.linkEscape])
        #expect(try risk("a/link", "..\\..\\x") == [.linkEscape])
        for clean in ["sibling", "./sibling", "../top", "b/../c", "..", "sub/deeper/file", ".", "x//y"] {
            #expect(try risk("a/link", clean).isEmpty, "\(clean)")
        }
        #expect(try risk("a/b/link", "../../top").isEmpty)
        #expect(try risk("a/b/link", "../../../x") == [.linkEscape])
        #expect(try risk("a/link", nil) == [.link])
        #expect(try risk("a/link", "") == [.link])
    }

    @Test func hardLinksNameArchiveMembersFromTheRoot() throws {
        func risk(_ path: String, _ target: String?) throws -> [ArchiveEntryRisk] {
            try risks(entry(path, kind: .hardlink, target: target))
        }
        #expect(try risk("docs/h", "docs/original").isEmpty)
        #expect(try risk("docs/h", "original").isEmpty)
        #expect(try risk("docs/h", "../original") == [.linkEscape])
        #expect(try risk("docs/h", "/etc/passwd") == [.linkEscape])
        #expect(try risk("docs/h", nil) == [.link])
    }

    @Test func caseCollisionsCompareFoldedCanonicalNamesAndFlagEveryMember() throws {
        func flagged(_ paths: [String], kinds: [ContainerEntryKind]? = nil) throws -> [Bool] {
            let entries = paths.enumerated().map { entry($1, kind: kinds?[$0] ?? .file) }
            return try analyze(entries).entryRisks.map { $0.contains(.caseCollision) }
        }
        #expect(try flagged(["A.txt", "a.txt", "b.txt"]) == [true, true, false])
        #expect(try flagged(["Dir/readme", "other", "DIR/README"]) == [true, false, true])
        #expect(try flagged(["Readme", "README", "readme"]) == [true, true, true])
        // Precomposed and decomposed spellings differ in code units but name the same file on APFS.
        #expect(try flagged(["caf\u{E9}.txt", "cafe\u{301}.txt"]) == [true, true])
        #expect(try flagged(["CAF\u{C9}.txt", "cafe\u{301}.txt"]) == [true, true])
        #expect(try flagged(["Foo/", "foo"], kinds: [.directory, .file]) == [true, true])
        #expect(try flagged(["same.txt", "same.txt", "unique"]) == [false, false, false])
        #expect(try flagged(["a.txt", "b.txt", "c/a.txt"]) == [false, false, false])
        #expect(try flagged(["a/b", "a\\B"]) == [true, true])
    }

    @Test func encryptedFactBecomesTheRisk() throws {
        #expect(try risks(entry("secret.txt", encrypted: true)) == [.encrypted])
        #expect(try risks(entry("plain.txt")).isEmpty)
    }

    @Test func risksAreOrderedByDeclarationAndFindingsCountEntriesAndCarryNoNames() throws {
        let report = try analyze([
            entry("../invoice.pdf.app/", kind: .directory, mode: 0o40755),
            entry("evil\u{202E}fdp.zip", encrypted: true),
            entry(".hidden"), entry("clean.txt")
        ])
        #expect(report.entryRisks[0] == [.unsafePath, .executable, .disguisedName])
        #expect(report.entryRisks[1] == [.directionalName, .encrypted, .nested])
        #expect(report.entryRisks[2] == [.hidden])
        #expect(report.entryRisks[3].isEmpty)
        #expect(report.annotatesEntries)
        let byKind = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.kind, $0) })
        #expect(Set(byKind.keys) == [.archiveUnsafePath, .archiveExecutables, .archiveDisguisedName, .archiveDirectionalName,
                                     .archiveEncrypted, .archiveNested, .archiveHiddenEntries])
        #expect(byKind.values.allSatisfy { $0.count == 1 && $0.lines.isEmpty && $0.detail == .none })
        #expect(byKind.values.allSatisfy { $0.severity == $0.kind.defaultSeverity })
        let clean = try analyze([entry("a.txt"), entry("dir/", kind: .directory), entry("dir/b.txt", size: 10, stored: 10)])
        #expect(clean.findings.isEmpty)
        #expect(!clean.annotatesEntries)
    }

    @Test func everyPerEntryRiskMapsToItsOwnFindingKind() {
        let kinds = ArchiveEntryRisk.allCases.map(\.findingKind)
        #expect(Set(kinds).count == ArchiveEntryRisk.allCases.count)
        #expect(kinds.map(\.rawValue) == [
            "archive.unsafePath", "archive.linkEscape", "archive.links", "archive.executables",
            "archive.disguisedName", "archive.directionalName", "archive.encrypted", "archive.nested",
            "archive.highCompression", "archive.hiddenEntries", "archive.caseCollisions", "archive.macMetadata",
            "listing.hiddenCharacters"
        ])
    }

    @Test func analysisIsBoundedAtTheEntryLimitAndStaysLinear() throws {
        let limit = 10_000
        let colliding = (0..<limit).map { entry($0.isMultiple(of: 2) ? "dir/File\($0 / 2)" : "DIR/file\($0 / 2)") }
        let report = try analyze(colliding)
        #expect(report.entryRisks.count == limit)
        #expect(report.entryRisks.allSatisfy { $0 == [.caseCollision] })
        #expect(report.findings.first?.count == limit)
        #expect(throws: PreviewFailure.tooManyNodes) { try analyze(colliding + [entry("one-more")]) }
        // A smaller node budget lowers the limit the same way it does for the adapters.
        let small = RequestContext(budget: PreviewBudget(maxJSONNodes: 100))
        #expect(throws: PreviewFailure.tooManyNodes) {
            try ArchiveRiskAnalyzer.analyze((0...100).map { entry("f\($0)") }, context: small)
        }
        #expect(try ArchiveRiskAnalyzer.analyze((0..<100).map { entry("f\($0)") }, context: small).entryRisks.count == 100)
    }

    @Test func analysisCooperatesWithCancellation() async throws {
        let entries = (0..<2_000).map { entry("dir/file\($0).txt") }
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            do { _ = try ArchiveRiskAnalyzer.analyze(entries, context: RequestContext(budget: .standard)); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        task.cancel()
        #expect(await task.value)
    }
}

// MARK: Listings

@Suite("Archive risk listings")
struct ArchiveRiskListingTests {
    @Test func cleanArchivesKeepTheirExactSummaryAndHaveNoFindings() throws {
        let zip = try ZIPListingAdapter().parse(FileBytes(data: zipFixture()), context: containerContext)
        #expect(zip.text == """
        {
          "archiveFormat": "ZIP",
          "listedEntries": 1,
          "partial": false,
          "entries": [
            {
              "path": "nested/日本語.txt",
              "type": "file",
              "bytes": 16
            }
          ]
        }
        """)
        #expect(zip.findings.isEmpty)
        let tar = try TARListingAdapter().parse(FileBytes(data: tarFixture()), context: containerContext)
        #expect(tar.text == """
        {
          "archiveFormat": "TAR",
          "listedEntries": 1,
          "partial": false,
          "entries": [
            {
              "path": "safe.txt",
              "type": "file",
              "bytes": 14
            }
          ]
        }
        """)
        #expect(tar.findings.isEmpty)
        let xip = try XIPListingAdapter().parse(FileBytes(data: xipFixture()), context: containerContext)
        #expect(!xip.text.contains("risks"))
        #expect(xip.findings.isEmpty)
        let gzip = try GZIPPreviewAdapter().parse(FileBytes(data: compressFixture(tarFixture(), gzip: true)), context: containerContext)
        #expect(gzip.text == tar.text)
        #expect(gzip.findings.isEmpty)
    }

    @Test func zipReportsEveryRuleOnTheEntriesThatCarryIt() throws {
        let unixFile: UInt64 = 0o100755
        let members: [ZIPMember] = [
            ZIPMember(path: "docs/report.pdf"), ZIPMember(path: "a..b.txt"),
            ZIPMember(path: "../escape.txt"), ZIPMember(path: "/abs.txt"), ZIPMember(path: "C:\\win.txt"),
            ZIPMember(path: ".github/ci.yml"), ZIPMember(path: "__MACOSX/._x"),
            ZIPMember(path: "Foo.app/", payload: Data(), mode: 0o40755),
            ZIPMember(path: "Foo.app/Contents/MacOS/Foo", mode: unixFile),
            ZIPMember(path: "run.sh", mode: unixFile), ZIPMember(path: "win.sh", mode: unixFile, host: 0),
            ZIPMember(path: "darwin.sh", mode: unixFile, host: 19), ZIPMember(path: "plain.sh", mode: 0o100644),
            ZIPMember(path: "photo.jpg   .command"), ZIPMember(path: "evil\u{202E}fdp.exe"),
            ZIPMember(path: "A.txt"), ZIPMember(path: "a.txt"),
            ZIPMember(path: "nested.zip"), ZIPMember(path: "disk.dmg")
        ]
        let document = try ZIPListingAdapter().parse(FileBytes(data: zipArchive(members)), context: containerContext)
        let expected: [String: [String]] = [
            "docs/report.pdf": [], "a..b.txt": [],
            "../escape.txt": ["unsafePath"], "/abs.txt": ["unsafePath"], "C:\\win.txt": ["unsafePath"],
            ".github/ci.yml": ["hidden"], "__MACOSX/._x": ["macMetadata"],
            "Foo.app/": ["executable"], "Foo.app/Contents/MacOS/Foo": [],
            "run.sh": ["executable"], "win.sh": [], "darwin.sh": ["executable"], "plain.sh": [],
            "photo.jpg   .command": ["executable", "disguisedName"], "evil\u{202E}fdp.exe": ["executable", "directionalName"],
            "A.txt": ["caseCollision"], "a.txt": ["caseCollision"],
            "nested.zip": ["nested"], "disk.dmg": ["nested"]
        ]
        #expect(try risksByPath(document) == expected)
        #expect(counts(document) == [.archiveUnsafePath: 3, .archiveHiddenEntries: 1, .archiveMacMetadata: 1, .archiveExecutables: 5,
                                     .archiveDisguisedName: 1, .archiveDirectionalName: 1, .archiveCaseCollisions: 2, .archiveNested: 2])
        #expect(document.findings.allSatisfy { $0.lines.isEmpty && $0.detail == .none })
        #expect(document.text.contains("\"path\": \"../escape.txt\""))
        // The listing is the position of every finding, so the document stays a JSON summary.
        #expect(document.syntax == .json)
        #expect(document.usesStructuredPrivacy)
    }

    @Test func zipListsEncryptedMembersAndStillRejectsCentralDirectoryEncryption() throws {
        for flags: UInt64 in [0x801, 0x840, 0x841] {
            let document = try ZIPListingAdapter().parse(FileBytes(data: zipArchive([ZIPMember(path: "secret.txt", flags: flags)])), context: containerContext)
            #expect(try risksByPath(document) == ["secret.txt": ["encrypted"]], "flags \(flags)")
            #expect(document.findings.map(\.kind) == [.archiveEncrypted])
        }
        for zip64 in [false, true] {
            let document = try ZIPListingAdapter().parse(FileBytes(data: zipFixture(path: "../x", encrypted: true, zip64: zip64)), context: containerContext)
            #expect(try risksByPath(document) == ["../x": ["unsafePath", "encrypted"]])
            #expect(document.text.contains(zip64 ? "ZIP64" : "\"ZIP\""))
        }
        // Bit 13 masks the directory itself, in any record.
        let masked = zipArchive([ZIPMember(path: "ok.txt"), ZIPMember(path: "masked.txt", flags: 0x2800)])
        #expect(throws: PreviewFailure.unsupportedFormat) { try ZIPListingAdapter().parse(FileBytes(data: masked), context: containerContext) }
        #expect(throws: PreviewFailure.unsupportedFormat) {
            try ZIPListingAdapter().parse(FileBytes(data: zipArchive([ZIPMember(path: "masked.txt", flags: 0x2801)])), context: containerContext)
        }
    }

    @Test func namesThatCannotBeShownAsInertTextStillFailTheArchive() {
        for path in ["a\u{0}b", "a\nb", "tab\there", "bell\u{7}", "", "\u{1F}"] {
            #expect(throws: PreviewFailure.malformedDocument, "\(path.debugDescription)") {
                try ZIPListingAdapter().parse(FileBytes(data: zipArchive([ZIPMember(path: path)])), context: containerContext)
            }
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try TARListingAdapter().parse(FileBytes(data: tarArchive([TARMember(path: "a\nb")])), context: containerContext)
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try XIPListingAdapter().parse(FileBytes(data: xipFixture(path: "a\u{1}b")), context: containerContext)
        }
    }

    @Test func zipStructuralChecksStillApplyToRiskyEntries() throws {
        var overlapping = zipArchive([ZIPMember(path: "../a", payload: Data(repeating: 1, count: 40)),
                                      ZIPMember(path: "../a", payload: Data(repeating: 2, count: 40))])
        let end = overlapping.count - 22
        let directoryStart = Int(overlapping[end + 16]) | Int(overlapping[end + 17]) << 8
        // Point the second record's local-header offset (byte 42 of a central record) at the first member.
        let secondRecord = directoryStart + 46 + "../a".utf8.count
        overlapping.replaceSubrange((secondRecord + 42)..<(secondRecord + 46), with: little(0, width: 4))
        #expect(throws: PreviewFailure.malformedDocument) { try ZIPListingAdapter().parse(FileBytes(data: overlapping), context: containerContext) }
        var mismatch = zipArchive([ZIPMember(path: "/abs", flags: 0x801)])
        mismatch[6] = 0x00 // local flags no longer match the central directory
        #expect(throws: PreviewFailure.malformedDocument) { try ZIPListingAdapter().parse(FileBytes(data: mismatch), context: containerContext) }
    }

    @Test func zipReadsOnlyStoredUnencryptedSymbolicLinkTargets() throws {
        let link: UInt64 = 0o120777
        let members: [ZIPMember] = [
            ZIPMember(path: "inside", payload: Data("docs/report.pdf".utf8), mode: link),
            ZIPMember(path: "docs/up", payload: Data("../../etc".utf8), mode: link),
            ZIPMember(path: "absolute", payload: Data("/etc/passwd".utf8), mode: link),
            ZIPMember(path: "deflated", payload: Data("../../etc".utf8), method: 8, mode: link),
            ZIPMember(path: "encrypted", payload: Data("../../etc".utf8), flags: 0x801, mode: link),
            ZIPMember(path: "oversized", payload: Data(repeating: 97, count: 4_097), mode: link),
            ZIPMember(path: "binary", payload: Data([97, 0, 98]), mode: link),
            ZIPMember(path: "empty", payload: Data(), mode: link),
            ZIPMember(path: "limit", payload: Data(repeating: 97, count: 4_096), mode: link)
        ]
        let document = try ZIPListingAdapter().parse(FileBytes(data: zipArchive(members)), context: containerContext)
        #expect(try risksByPath(document) == [
            "inside": [], "docs/up": ["linkEscape"], "absolute": ["linkEscape"], "deflated": ["link"],
            "encrypted": ["link", "encrypted"], "oversized": ["link"], "binary": ["link"], "empty": ["link"], "limit": []
        ])
        #expect(document.text.contains("\"type\": \"symlink\""))
        #expect(counts(document)[.archiveLinks] == 5)
        // Targets are never displayed.
        #expect(!document.text.contains("/etc/passwd"))
    }

    @Test func zipTargetReadsAreBoundedAndNeverFailTheListing() throws {
        let link: UInt64 = 0o120777
        let members = (0..<40).map { ZIPMember(path: "link\($0)", payload: Data(repeating: 97, count: 4_000), mode: link) }
        let data = zipArchive(members)
        let document = try ZIPListingAdapter().parse(FileBytes(data: data), context: containerContext)
        // 65,536 bytes of targets: sixteen 4,000-byte payloads fit, the rest are reported as plain links.
        #expect(counts(document)[.archiveLinks] == 24)
        #expect(try entryRisks(document).prefix(16).allSatisfy { $0.risks.isEmpty })

        // The target pass runs last. An exhausted read budget there leaves links unread rather than failing.
        let probe = RiskRecordingSource(zipArchive([ZIPMember(path: "l", payload: Data("x".utf8), mode: link), ZIPMember(path: "f")]))
        _ = try ZIPListingAdapter().parse(probe, context: containerContext)
        let structuralReads = probe.reads.count - 1
        let starved = RiskRecordingSource(probe.data, failAfter: structuralReads)
        let starvedDocument = try ZIPListingAdapter().parse(starved, context: containerContext)
        #expect(try risksByPath(starvedDocument) == ["l": ["link"], "f": []])
    }

    @Test func zipNeverReadsRegularFilePayloads() throws {
        let secret = Data("SYNTHETIC-PAYLOAD-NEVER-READ".utf8)
        let data = zipArchive([ZIPMember(path: "a.txt", payload: secret), ZIPMember(path: "link", payload: Data("sibling".utf8), mode: 0o120777)])
        let source = RiskRecordingSource(data)
        let document = try ZIPListingAdapter().parse(source, context: containerContext)
        let payload = 30 + "a.txt".utf8.count
        let range = Int64(payload)..<Int64(payload + secret.count)
        // The first read is the end-of-archive scan, which small archives satisfy from their last bytes.
        #expect(source.reads.dropFirst().allSatisfy { read in
            let end = read.offset + Int64(read.count)
            return end <= range.lowerBound || read.offset >= range.upperBound
        })
        #expect(source.reads.contains { $0.count == "sibling".utf8.count })
        #expect(!document.text.contains("SYNTHETIC-PAYLOAD"))
        #expect(try risksByPath(document) == ["a.txt": [], "link": []])
    }

    @Test func zipHighCompressionAndLargeExpansionUseDeclaredSizesWithoutDecompressing() throws {
        let junk = Data((0..<1_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let members = [
            ZIPMember(path: "bomb.bin", payload: junk, declaredSize: 10 * 1_048_576, method: 8),
            ZIPMember(path: "boundary.bin", payload: Data(repeating: 1, count: 10_485), declaredSize: 1_048_576, method: 8),
            ZIPMember(path: "below.bin", payload: Data(repeating: 1, count: 10_486), declaredSize: 1_048_576, method: 8),
            ZIPMember(path: "small.bin", payload: Data([1]), declaredSize: 1_048_575, method: 8),
            ZIPMember(path: "ordinary.txt")
        ]
        let document = try ZIPListingAdapter().parse(FileBytes(data: zipArchive(members)), context: containerContext)
        #expect(try risksByPath(document) == ["bomb.bin": ["highCompression"], "boundary.bin": ["highCompression"],
                                              "below.bin": [], "small.bin": [], "ordinary.txt": []])
        let finding = try #require(document.findings.first { $0.kind == .archiveHighCompression })
        #expect(finding.count == 2)
        #expect(finding.detail == .compressionRatio(10 * 1_048_576 / 1_000))
        #expect(document.findings.allSatisfy { $0.kind != .archiveLargeExpansion })

        func expansion(_ sizes: [UInt64]) throws -> PreviewFinding? {
            let members = sizes.enumerated().map { ZIPMember(path: "f\($0)", payload: Data([1]), declaredSize: $1, method: 8) }
            let document = try ZIPListingAdapter().parse(FileBytes(data: zipArchive(members)), context: containerContext)
            return document.findings.first { $0.kind == .archiveLargeExpansion }
        }
        #expect(try expansion([600 << 20, 600 << 20])?.detail == .expandedBytes(Int64(1_200 << 20)))
        #expect(try expansion([1 << 30])?.detail == .expandedBytes(1 << 30))
        #expect(try expansion([(1 << 30) - 1]) == nil)
        #expect(try expansion([400 << 20, 400 << 20]) == nil)
    }

    @Test func tarReportsModesLinkTargetsAndTraversal() throws {
        let members = [
            TARMember(path: "docs/", type: 53, mode: 0o755),
            TARMember(path: "docs/escape-link", type: 50, link: "../../etc"),
            TARMember(path: "docs/inside-link", type: 50, link: "sibling"),
            TARMember(path: "docs/absolute-link", type: 50, link: "/etc/passwd"),
            TARMember(path: "docs/unreadable-link", type: 50, link: ""),
            TARMember(path: "docs/hard-ok", type: 49, link: "docs/inside-link"),
            TARMember(path: "docs/hard-escape", type: 49, link: "../outside"),
            TARMember(path: "bin/tool", mode: 0o755), TARMember(path: "bin/data", mode: 0o644),
            TARMember(path: "../../escape.txt"), TARMember(path: ".hidden"), TARMember(path: "__MACOSX/._x"),
            TARMember(path: "Setup.pkg"), TARMember(path: "dev/zero", type: 51, mode: 0o755)
        ]
        let document = try TARListingAdapter().parse(FileBytes(data: tarArchive(members)), context: containerContext)
        #expect(try risksByPath(document) == [
            "docs/": [], "docs/escape-link": ["linkEscape"], "docs/inside-link": [], "docs/absolute-link": ["linkEscape"],
            "docs/unreadable-link": ["link"], "docs/hard-ok": [], "docs/hard-escape": ["linkEscape"],
            "bin/tool": ["executable"], "bin/data": [], "../../escape.txt": ["unsafePath"], ".hidden": ["hidden"],
            "__MACOSX/._x": ["macMetadata"], "Setup.pkg": ["executable"], "dev/zero": []
        ])
        #expect(counts(document) == [.archiveLinkEscape: 3, .archiveLinks: 1, .archiveExecutables: 2, .archiveUnsafePath: 1,
                                     .archiveHiddenEntries: 1, .archiveMacMetadata: 1])
        // The random-access reader and the in-memory reader share one analysis.
        let streamed = try TARListingAdapter().parse(DataByteSource(tarArchive(members)), context: containerContext)
        #expect(streamed.text == document.text)
        #expect(streamed.findings == document.findings)
    }

    @Test func tarLinkTargetsPreferPAXThenGNULongLinkThenTheHeader() throws {
        let members = [
            TARMember(path: "pax", type: 120, payload: paxRecord("linkpath", "/etc/passwd")),
            TARMember(path: "a/pax-link", type: 50, link: "sibling"),
            TARMember(path: "long", type: 75, payload: Data("../../../elsewhere\0".utf8)),
            TARMember(path: "a/gnu-link", type: 50, link: "sibling"),
            TARMember(path: "pax-path", type: 120, payload: paxRecord("path", "../../renamed.txt")),
            TARMember(path: "plain.txt"),
            TARMember(path: "a/header-link", type: 50, link: "sibling")
        ]
        let document = try TARListingAdapter().parse(FileBytes(data: tarArchive(members)), context: containerContext)
        #expect(try risksByPath(document) == [
            "a/pax-link": ["linkEscape"], "a/gnu-link": ["linkEscape"], "../../renamed.txt": ["unsafePath"], "a/header-link": []
        ])
    }

    @Test func gzipWrappedTARGetsTheSameAnalysis() throws {
        let tar = tarArchive([TARMember(path: "../escape"), TARMember(path: "tool", mode: 0o755),
                              TARMember(path: "l", type: 50, link: "../x"), TARMember(path: "a.zip")])
        let direct = try TARListingAdapter().parse(FileBytes(data: tar), context: containerContext)
        let wrapped = try GZIPPreviewAdapter().parse(FileBytes(data: compressFixture(tar, gzip: true)), context: containerContext)
        #expect(wrapped.text == direct.text)
        #expect(wrapped.findings == direct.findings)
        #expect(Set(wrapped.findings.map(\.kind)) == [.archiveUnsafePath, .archiveExecutables, .archiveLinkEscape, .archiveNested])
        // Ordinary gzip text is untouched.
        let text = try GZIPPreviewAdapter().parse(FileBytes(data: compressFixture(Data("plain ../text".utf8), gzip: true)), context: containerContext)
        #expect(text.text == "plain ../text")
        #expect(text.findings.isEmpty)
    }

    @Test func xipReportsModesAndSymbolicLinkTargetsFromTheDecodedListing() throws {
        let cpio = cpioArchive([
            ("./Foo.app", 0o40755, Data()),
            ("./Foo.app/Contents/MacOS/Foo", 0o100755, Data()),
            ("./escape", 0o120777, Data("../../x".utf8)),
            ("./inside", 0o120777, Data("Foo.app".utf8)),
            ("./unreadable", 0o120777, Data()),
            ("./.hidden", 0o100644, Data("data".utf8)),
            ("./tool", 0o100755, Data()),
            ("./data", 0o100644, Data()),
            ("./pipe", 0o10755, Data())
        ])
        let document = try XIPListingAdapter().parse(FileBytes(data: xipContainer(cpio: cpio)), context: containerContext)
        #expect(try risksByPath(document) == [
            "./Foo.app": ["executable"], "./Foo.app/Contents/MacOS/Foo": [], "./escape": ["linkEscape"], "./inside": [],
            "./unreadable": ["link"], "./.hidden": ["hidden"], "./tool": ["executable"], "./data": [], "./pipe": []
        ])
        #expect(counts(document) == [.archiveExecutables: 2, .archiveLinkEscape: 1, .archiveLinks: 1, .archiveHiddenEntries: 1])
        #expect(document.text.contains("\"signatureVerified\": false"))
    }

    @Test func annotationsDegradeToTheExactListingWhenTheyAloneExceedTheBudget() throws {
        // 120 hidden files: the plain listing fits, the risk arrays do not.
        let data = zipArchive((0..<120).map { ZIPMember(path: ".f\($0)") })
        let annotated = try ZIPListingAdapter().parse(FileBytes(data: data), context: containerContext)
        #expect(try entryRisks(annotated).allSatisfy { $0.risks == ["hidden"] })
        // Each plain entry costs 7 nodes, and the listing reserves 64 for its root fields (ListingBudget).
        let nodes = PreviewBudget(maxJSONNodes: 120 * 7 + 64, maxMilliseconds: 30_000)
        let degraded = try ZIPListingAdapter().parse(FileBytes(data: data), context: RequestContext(budget: nodes))
        #expect(try entryRisks(degraded).count == 120)
        #expect(!degraded.text.contains("risks"))
        #expect(!degraded.text.contains("\"partial\": true"))
        // The totals are still reported, so the risk is not lost.
        #expect(counts(degraded) == [.archiveHiddenEntries: 120])
        // A budget too small for every plain entry lists the first ones and says so instead of failing
        // (decision 014); the totals then cover the listed entries.
        let tiny = PreviewBudget(maxOutputUTF8Bytes: degraded.text.utf8.count - 1, maxMilliseconds: 30_000)
        let partial = try ZIPListingAdapter().parse(FileBytes(data: data), context: RequestContext(budget: tiny))
        #expect(partial.text.contains("\"partial\": true"))
        #expect(try entryRisks(partial).count < 120)
    }
}

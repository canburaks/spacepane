import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func q150NameContext(_ budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) -> RequestContext {
    RequestContext(budget: budget)
}

private func q150NameEntry(_ path: String) -> ContainerEntry { ContainerEntry(path: path, kind: .file, size: 1) }

private func q150NameObject(_ document: ParsedTextDocument) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
}

private func q150NameEntries(_ document: ParsedTextDocument) throws -> [[String: Any]] {
    try #require(q150NameObject(document)["entries"] as? [[String: Any]])
}

private func q150NameFixture(_ names: [String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    for name in names { try Data("synthetic content".utf8).write(to: directory.appendingPathComponent(name)) }
    return directory
}

@Suite("Q150 listing name risks")
struct Q150ListingNameRiskTests {
    @Test func hiddenNameRiskCountsEntriesAndNeverCarriesNamesOrTagPayloads() throws {
        let names = ["many\u{200B}\u{200B}\u{2060}.txt", "tag\u{E0070}\u{E0061}\u{E0073}\u{E0073}.txt",
                     "stray\u{180B}.txt", "controls\u{FFF9}\u{1D173}\u{13430}.txt", "blank\u{2800}\u{2800}.txt"]
        let report = try ArchiveRiskAnalyzer.analyze(names.map(q150NameEntry), context: q150NameContext())
        #expect(report.entryRisks.allSatisfy { $0.map(\.rawValue) == ["hiddenCharacters"] })
        let finding = try #require(report.findings.first { $0.kind.rawValue == "listing.hiddenCharacters" })
        #expect(finding.count == names.count && finding.severity == .caution && finding.lines.isEmpty && finding.detail == .none)
    }

    @Test func filenameMarksRetainDirectionalRiskWithoutPretendingTheyAreHiddenPayloads() throws {
        for mark in ["\u{061C}", "\u{200E}", "\u{200F}"] {
            let report = try ArchiveRiskAnalyzer.analyze([q150NameEntry("שלום\(mark).txt")], context: q150NameContext())
            #expect(report.entryRisks == [[.directionalName]])
            #expect(report.findings.map(\.kind) == [.archiveDirectionalName])
        }
        let mixed = try ArchiveRiskAnalyzer.analyze([q150NameEntry("invoice\u{202E}\u{200B}.txt")], context: q150NameContext())
        #expect(Set(mixed.entryRisks[0].map(\.rawValue)) == ["directionalName", "hiddenCharacters"])
    }

    @Test func legitimateNameContextsAndCleanListingsRemainExact() throws {
        let names = ["שלום.txt", "\u{182C}\u{180F}.txt", "emoji👩‍💻.txt", "क्\u{200D}ष.txt", "⠁\u{2800}⠃.txt", "icon\u{E0A0}.txt"]
        let report = try ArchiveRiskAnalyzer.analyze(names.map(q150NameEntry), context: q150NameContext())
        #expect(report.entryRisks.allSatisfy(\.isEmpty) && report.findings.isEmpty)
        let clean = try listingDocument(format: "ZIP", entries: names.map(q150NameEntry), context: q150NameContext(), assessRisks: true)
        let unchanged = try listingDocument(format: "ZIP", entries: names.map(q150NameEntry), context: q150NameContext())
        #expect(clean.text.utf8.elementsEqual(unchanged.text.utf8))
        #expect(try q150NameEntries(clean).compactMap { $0["path"] as? String }.map { Array($0.utf8) } == names.map { Array($0.utf8) })
    }

    @Test func archiveDisguiseComparisonIgnoresFormattingOnlyInsideTheComparisonStem() throws {
        for name in ["invoice.p\u{200B}df.app", "invoice.pdf\u{2800}.command", "invoice.p\u{061C}df.exe"] {
            let report = try ArchiveRiskAnalyzer.analyze([q150NameEntry(name)], context: q150NameContext())
            #expect(report.entryRisks[0].contains(.executable) && report.entryRisks[0].contains(.disguisedName))
            let document = try listingDocument(format: "ZIP", entries: [q150NameEntry(name)], context: q150NameContext(), assessRisks: true)
            #expect(try q150NameEntries(document).first?["path"] as? String == name)
        }
        // A changed final suffix does not become a real executable suffix through normalization.
        let report = try ArchiveRiskAnalyzer.analyze([q150NameEntry("invoice.pdf.a\u{200B}pp")], context: q150NameContext())
        #expect(!report.entryRisks[0].contains(.executable) && !report.entryRisks[0].contains(.disguisedName))
        #expect(report.entryRisks[0].map(\.rawValue) == ["hiddenCharacters"])
    }

    @Test func foldersAssessNamesWithoutApplyingArchiveExecutableOrLinkRules() throws {
        let names = ["invisible\u{200B}.txt", "שלום\u{200F}.txt", "Fake.app", "nested.zip", ".hidden"]
        let directory = try q150NameFixture(names)
        defer { try? FileManager.default.removeItem(at: directory) }
        let external = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("external synthetic content".utf8).write(to: external)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape"), withDestinationURL: external)
        let before = try Dictionary(uniqueKeysWithValues: names.map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
        let document = try FolderSummaryAdapter().parse(url: directory, context: q150NameContext())
        let entries = try q150NameEntries(document)
        #expect(Set(entries.compactMap { $0["path"] as? String }) == Set(names.filter { !$0.hasPrefix(".") } + ["escape"]))
        let risks = Dictionary(uniqueKeysWithValues: entries.map { ($0["path"] as! String, $0["risks"] as? [String] ?? []) })
        #expect(risks["invisible\u{200B}.txt"] == ["hiddenCharacters"])
        #expect(risks["שלום\u{200F}.txt"] == ["directionalName"])
        #expect(risks["Fake.app"] == [] && risks["nested.zip"] == [] && risks["escape"] == [])
        #expect(Set(document.findings.map { $0.kind.rawValue }) == ["listing.hiddenCharacters", "archive.directionalName"])
        #expect(document.findings.allSatisfy { $0.count == 1 && $0.lines.isEmpty && $0.detail == .none })
        for (name, data) in before { #expect(try Data(contentsOf: directory.appendingPathComponent(name)) == data) }
        #expect(try Data(contentsOf: external) == Data("external synthetic content".utf8))
        #expect(try q150NameObject(document)["hiddenEntries"] as? Int == 1)
    }

    @Test func hiddenNameAnnotationsDegradeWithoutLosingTheCountOrCleanListing() throws {
        let entries = (0..<120).map { q150NameEntry("file\($0)\u{200B}.txt") }
        let budget = PreviewBudget(maxJSONNodes: 120 * 7 + 64, maxMilliseconds: 30_000)
        let plain = try listingDocument(format: "ZIP", entries: entries, context: q150NameContext(budget))
        let analyzed = try listingDocument(format: "ZIP", entries: entries, context: q150NameContext(budget), assessRisks: true)
        #expect(!analyzed.text.contains("\"risks\""))
        #expect(analyzed.text.utf8.elementsEqual(plain.text.utf8))
        let finding = try #require(analyzed.findings.first { $0.kind.rawValue == "listing.hiddenCharacters" })
        #expect(finding.count == 120 && finding.lines.isEmpty && finding.detail == .none)
    }

    @Test func archiveNameAssessmentPreservesEntryBudgetsAndCancellation() async {
        #expect(throws: PreviewFailure.tooManyNodes) {
            try ArchiveRiskAnalyzer.analyze([q150NameEntry("x\u{200B}"), q150NameEntry("y\u{200B}")],
                context: q150NameContext(PreviewBudget(maxJSONNodes: 1, maxMilliseconds: 30_000)))
        }
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try ArchiveRiskAnalyzer.analyze([q150NameEntry("x\u{200B}")], context: q150NameContext()); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await task.value)
    }
}

import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Archive risk labels")
struct ArchiveRiskLabelsTests {
    private let english = Locale(identifier: "en_US")

    /// The summary an archive listing writes, with the second entry clean.
    private let summaryJSON = """
    {"archiveFormat":"ZIP","listedEntries":2,"partial":false,"entries":[\
    {"path":"../x.exe","type":"file","bytes":4,"risks":["unsafePath","executable","futureRisk"]},\
    {"path":"unsafePath","type":"file","bytes":1}]}
    """

    private func localized(_ json: String, format: FormatID = .zip) throws -> [SafeOutlineNode] {
        SafeSchemaLabels.localize(try #require(SafeStructuredText.json(json)), formatID: format, locale: english)
    }

    @Test func riskFieldAndEachCodeAreLocalizedWhileUnknownCodesAndPathsStayExact() throws {
        let entries = try #require(try localized(summaryJSON).first?.children.last)
        #expect(entries.name == PreviewStrings.text(.summaryEntries))
        let risky = try #require(entries.children.first)
        #expect(risky.children.map(\.name) == [PreviewStrings.text(.summaryPath), PreviewStrings.text(.summaryType),
                                                PreviewStrings.text(.summaryBytes), PreviewStrings.text(.summaryRisks)])
        #expect(risky.children[0].value == "../x.exe")
        let risks = risky.children[3]
        #expect(risks.name == "Check")
        #expect(risks.children.map(\.value) == [PreviewStrings.text(.archiveRiskUnsafePath), PreviewStrings.text(.archiveRiskExecutable), "futureRisk"])
        #expect(risks.children.map(\.value).prefix(2) == ["Outside destination folder", "App, installer, script or program"])
        // Array positions stay as they are: only the values are wording.
        #expect(risks.children.map(\.name) == ["[0]", "[1]", "[2]"])
    }

    @Test func aPathThatSpellsARiskCodeIsNotTranslated() throws {
        let entries = try #require(try localized(summaryJSON).first?.children.last)
        let clean = entries.children[1]
        #expect(clean.children[0].value == "unsafePath")
        #expect(clean.children.map(\.name).contains(PreviewStrings.text(.summaryRisks)) == false)
    }

    @Test func entriesWithRisksAreMarkedAsIssuesAndCleanOnesAreNot() throws {
        let entries = try #require(try localized(summaryJSON).first?.children.last)
        #expect(entries.children.map(\.isIssue) == [true, false])
        #expect(!entries.isIssue)
        // An entry whose risk list is empty is not an issue.
        let emptyList = try localized(#"{"entries":[{"path":"a","type":"file","bytes":1,"risks":[]}]}"#)
        #expect(emptyList[0].children[0].children[0].isIssue == false)
    }

    @Test func everyRiskHasDistinctNonEmptyWordingThatIsNotTheRawCode() throws {
        let codes = ArchiveEntryRisk.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        let json = "{\"entries\":[{\"path\":\"a\",\"type\":\"file\",\"bytes\":1,\"risks\":[\(codes)]}]}"
        let values = try localized(json)[0].children[0].children[0].children[3].children.map(\.value)
        #expect(values.count == ArchiveEntryRisk.allCases.count)
        #expect(Set(values).count == values.count)
        for (risk, value) in zip(ArchiveEntryRisk.allCases, values) {
            #expect(!value.isEmpty, "\(risk)")
            #expect(value != risk.rawValue, "\(risk)")
            #expect(!value.hasPrefix("archive.risk."), "\(risk)")
        }
    }

    @Test func otherListingsKeepTheirExactShape() throws {
        // A database or user JSON document that merely has matching keys stays untouched.
        for format: FormatID in [.sqlite, .json] {
            let roots = try localized(summaryJSON, format: format)
            let entries = try #require(roots.first?.children.last)
            #expect(entries.name == "entries")
            #expect(entries.children[0].children.last?.children.map(\.value) == ["unsafePath", "executable", "futureRisk"])
            #expect(entries.children.allSatisfy { !$0.isIssue })
        }
        // Folders localize name checks only in the adapter-owned entries[].risks[] shape.
        let folderJSON = #"{"entries":[{"path":"a","type":"file","bytes":1,"risks":["hiddenCharacters"]},{"path":"b","type":"file","bytes":1}],"custom":{"risks":["hiddenCharacters"]}}"#
        let folder = try localized(folderJSON, format: .folder)
        let entries = try #require(folder[0].children.first { $0.name == PreviewStrings.text(.summaryEntries) })
        #expect(entries.children.map(\.isIssue) == [true, false])
        #expect(entries.children[0].children.last?.children.map(\.value) == [PreviewStrings.text(.listingRiskHiddenCharacters)])
        let custom = try #require(folder[0].children.first { $0.name == "custom" })
        #expect(custom.children[0].children.map(\.value) == ["hiddenCharacters"])
        #expect(!custom.isIssue && custom.children.allSatisfy { !$0.isIssue })
    }

    @Test func summaryModeShowsTheLocalizedCheckRowsForAnArchivePresentation() throws {
        let presentation = TextPresentation(formatID: .zip, text: summaryJSON, lineCount: 1, byteCount: summaryJSON.utf8.count,
                                            encoding: .utf8, redactionCount: 0, syntax: .json)
        let modes = SafePreviewModes(presentation, locale: english)
        // Listings open in the Files table (decision 014); Summary keeps the localized check rows.
        #expect(modes.initialMode(for: .zip) == .files)
        #expect(modes.available.contains(.summary))
        let entry = try #require(modes.summary?.first?.children.last?.children.first)
        let check = try #require(entry.children.first { $0.name == "Check" })
        #expect(check.children.first?.value == "Outside destination folder")
        #expect(entry.isIssue)
    }
}

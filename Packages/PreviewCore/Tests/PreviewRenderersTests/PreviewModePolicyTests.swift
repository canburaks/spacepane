import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Preview mode policy")
struct PreviewModePolicyTests {
    private let locale = Locale(identifier: "en_US")

    private func modes() -> SafePreviewModes {
        SafePreviewModes(TextPresentation(formatID: .plainText, text: "safe", lineCount: 1,
                                          byteCount: 4, encoding: .utf8, redactionCount: 0), locale: locale)
    }

    private func table() -> SafeTable {
        SafeTable(columns: ["name"], rows: [["safe"]], truncation: [])
    }

    private func allModes() throws -> SafePreviewModes {
        var result = modes()
        result.outline = []
        result.records = []
        result.summary = []
        result.markdown = SafeMarkdownDocument(text: "One\nTwo", decorations: [], headings: [
            MarkupHeading(level: 1, title: "One", range: NSRange(location: 0, length: 3)),
            MarkupHeading(level: 2, title: "Two", range: NSRange(location: 4, length: 3))
        ])
        result.table = table()
        result.profile = LazyDataProfile(source: table(), locale: locale)
        result.cues = []
        result.references = SafeBibliography(entries: [])
        result.diagram = try #require(SafeDiagram.parse(mermaid: "flowchart LR\nA --> B"))
        result.files = table()
        result.tree = SafeListingTree(roots: [], nodeCount: 0, isPartial: false, usesUTC: false, entryOrder: [])
        result.images = [PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .cover),
                         PreviewImage(data: Data([2]), pixelWidth: 1, pixelHeight: 1, role: .icon)]
        result.plot = SafePlot(paths: [], points: [], simplified: false)
        result.sampleRows = table()
        result.invisibles = SafeInvisibleText(text: "safe", markerRanges: [])
        return result
    }

    @Test func everyModeKeepsItsTypedTitle() {
        let titles: [(NativePreviewMode, PreviewStrings.Key)] = [
            (.source, .previewModeSource), (.outline, .previewModeOutline), (.records, .previewModeRecords),
            (.rendered, .previewModeRendered), (.summary, .previewModeSummary), (.table, .previewModeTable),
            (.profile, .previewModeProfile), (.cues, .previewModeCues), (.invisibles, .previewModeInvisibles),
            (.contents, .previewModeContents), (.diagram, .previewModeDiagram), (.pages, .previewModePages),
            (.files, .previewModeFiles), (.tree, .previewModeTree), (.references, .markupModeReferences),
            (.plot, .previewModePlot), (.rows, .summaryRows), (.icon, .previewModeIcon)
        ]
        for (mode, title) in titles { #expect(mode.title == title) }
    }

    @Test func allAvailableModesKeepTheirEstablishedOrderWithoutComputingProfile() throws {
        let result = try allModes()
        let profile = try #require(result.profile)
        #expect(result.available == [.source, .outline, .records, .summary, .rendered, .table, .profile,
                                     .cues, .contents, .references, .diagram, .files, .tree, .pages,
                                     .plot, .rows, .icon, .invisibles])
        #expect(!profile.isComputed)
    }

    @Test func availabilityDependsOnTheDerivedCapabilityAndKeepsIconsSeparateFromPages() {
        var result = modes()
        #expect(result.available == [.source])
        result.markdown = SafeMarkdownDocument(text: "One", decorations: [], headings: [
            MarkupHeading(level: 1, title: "One", range: NSRange(location: 0, length: 3))
        ])
        result.images = [PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .icon)]
        #expect(result.available == [.source, .rendered, .icon])
        result.markdown?.headings.append(MarkupHeading(level: 2, title: "Two", range: NSRange(location: 0, length: 3)))
        result.images.append(PreviewImage(data: Data([2]), pixelWidth: 1, pixelHeight: 1, role: .cover))
        #expect(result.available == [.source, .rendered, .contents, .pages, .icon])
    }

    @Test func initialModeKeepsTheExistingCrossFamilyPrecedence() throws {
        var result = try allModes()
        #expect(result.initialMode(for: .markdown) == .rendered)
        #expect(result.initialMode(for: .mermaid) == .diagram)
        #expect(result.initialMode(for: .iosApp) == .summary)
        #expect(result.initialMode(for: .zip) == .files)
        result.summary = nil
        #expect(result.initialMode(for: .iosApp) == .files)
        result.files = nil
        #expect(result.initialMode(for: .comicBook) == .pages)
        #expect(result.initialMode(for: .epub) == .rendered)
        #expect(result.initialMode(for: .parquet) == .rows)
        #expect(result.initialMode(for: .geoJSON) == .rows)
        result.sampleRows = nil
        #expect(result.initialMode(for: .geoJSON) == .plot)
        result.plot = nil
        #expect(result.initialMode(for: .geoJSON) == .table)
        result.summary = []
        #expect(result.initialMode(for: .applicationBundle) == .summary)
        // The table fallback still precedes the notebook's Rendered fallback.
        #expect(result.initialMode(for: .jupyterNotebook) == .table)
        result.table = nil
        #expect(result.initialMode(for: .jupyterNotebook) == .rendered)
        #expect(result.initialMode(for: .plainText) == .source)
    }

    @Test func missingPrimaryCapabilitiesFallBackToSourceWithoutUsingDiagnosticModes() throws {
        var result = modes()
        result.invisibles = SafeInvisibleText(text: "safe", markerRanges: [])
        result.profile = LazyDataProfile(source: table(), locale: locale)
        for format in [FormatID.markdown, .mermaid, .comicBook, .epub, .parquet, .geoJSON,
                       .applicationBundle, .jupyterNotebook, .plainText] {
            #expect(result.initialMode(for: format) == .source)
        }
        #expect(result.available == [.source, .profile, .invisibles])
        #expect(try #require(result.profile).isComputed == false)
    }
}

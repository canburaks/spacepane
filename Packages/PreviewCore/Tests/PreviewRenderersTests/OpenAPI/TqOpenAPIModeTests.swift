import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The Endpoints mode in the mode policy, the registry and its view, and the limits-strip notices (tier 1 item 5,
/// workstream tq-openapi). The mode is offered beside the JSON modes and is never the initial mode.
@Suite("OpenAPI endpoints mode policy")
struct TqOpenAPIModePolicyTests {
    private let locale = Locale(identifier: "en_US")
    private let spec = #"{"openapi": "3.0.3", "paths": {"/pets": {"get": {"summary": "List"}}}}"#

    private func jsonModes(_ text: String) -> SafePreviewModes {
        SafePreviewModes(TextPresentation(formatID: .json, text: text, lineCount: 1, byteCount: text.utf8.count,
                                          encoding: .utf8, redactionCount: 0, syntax: .json), locale: locale)
    }

    private func endpoints(_ json: String) throws -> OpenAPIEndpointList {
        let root = try #require(SafeStructuredText.json(json)?.first)
        return try #require(OpenAPIEndpointList.derive(from: root))
    }

    @Test func theEndpointListIsTypedAsEndpointsAndAPlainTableWithTheSameTitlesIsNot() throws {
        // The table view chooses the endpoint layout from this typed value, never from localized column titles.
        let list = try endpoints(spec)
        #expect(list.table.layout == .endpoints)
        let lookalike = SafeTable(columns: list.table.columns, rows: [["GET", "/pets", "List", ""]], truncation: [])
        #expect(lookalike.layout == .standard && lookalike != list.table)
    }

    @Test func theEndpointsModeKeepsItsTypedTitle() {
        #expect(NativePreviewMode.endpoints.title == .previewModeEndpoints)
    }

    @Test func aRecognizedSpecificationOffersEndpointsAfterTheOutline() {
        let modes = jsonModes(spec)
        #expect(modes.available == [.source, .outline, .endpoints])
        #expect(jsonModes(#"{"paths": {"/pets": {"get": {}}}}"#).available == [.source, .outline])
    }

    @Test func endpointsSitsAfterCuesAndBeforeTheInvisiblesDiagnostic() throws {
        var modes = SafePreviewModes(TextPresentation(formatID: .plainText, text: "safe", lineCount: 1,
                                                      byteCount: 4, encoding: .utf8, redactionCount: 0), locale: locale)
        modes.cues = []
        modes.endpoints = try endpoints(spec)
        modes.invisibles = SafeInvisibleText(text: "safe", markerRanges: [])
        #expect(modes.available == [.source, .cues, .endpoints, .invisibles])
    }

    @Test func endpointsIsNeverTheInitialModeOfAJSONDocument() {
        let modes = jsonModes(spec)
        #expect(modes.initialMode(for: .json) == .source)
        #expect(modes.initialMode(for: FormatID(rawValue: "data.json")) == .source)
    }
}

@Suite("OpenAPI endpoints notices")
struct TqOpenAPIEndpointNoticeTests {
    private let locale = Locale(identifier: "en_US")

    private func modes(endpoints: OpenAPIEndpointList?) -> SafePreviewModes {
        var modes = SafePreviewModes(TextPresentation(formatID: .json, text: "{}", lineCount: 1, byteCount: 2,
                                                      encoding: .utf8, redactionCount: 0, syntax: .json), locale: locale)
        modes.endpoints = endpoints
        return modes
    }

    private func derive(_ json: String) throws -> OpenAPIEndpointList {
        let root = try #require(SafeStructuredText.json(json)?.first)
        return try #require(OpenAPIEndpointList.derive(from: root))
    }

    @Test func theRowCapIsAGroupedLimitWithTheShownAndTotalCounts() throws {
        let list = try derive(TqOpenAPIFixtures.cappedSpec(paths: OpenAPIEndpointList.maximumRows + 1))
        let notices = OpenAPIEndpointNotices.notices(modes: modes(endpoints: list), mode: .endpoints, locale: locale)
        #expect(notices == [PresentationNotice(kind: .limit, text: "Showing the first 5,000 rows of 5,001.")])
    }

    @Test func unresolvedReferencesAreCountedInASingularAndPluralSentence() throws {
        let one = try derive(#"{"openapi": "3.0.3", "paths": {"/c": {"$ref": "other.yaml"}}}"#)
        let two = try derive(#"{"openapi": "3.0.3", "paths": {"/c": {"$ref": "a.yaml"}, "/d": {"$ref": "b.yaml"}}}"#)
        #expect(OpenAPIEndpointNotices.notices(modes: modes(endpoints: one), mode: .endpoints, locale: locale)
            == [PresentationNotice(kind: .limit, text: "1 path item refers to another file or an unknown location and is not listed.")])
        #expect(OpenAPIEndpointNotices.notices(modes: modes(endpoints: two), mode: .endpoints, locale: locale)
            == [PresentationNotice(kind: .limit, text: "2 path items refer to other files or unknown locations and are not listed.")])
    }

    @Test func noticesBelongToTheEndpointsModeAndNothingIsSaidWithoutLimits() throws {
        let list = try derive(#"{"openapi": "3.0.3", "paths": {"/c": {"$ref": "other.yaml"}}}"#)
        #expect(OpenAPIEndpointNotices.notices(modes: modes(endpoints: list), mode: .outline, locale: locale).isEmpty)
        let clean = try derive(#"{"openapi": "3.0.3", "paths": {"/a": {"get": {}}}}"#)
        #expect(OpenAPIEndpointNotices.notices(modes: modes(endpoints: clean), mode: .endpoints, locale: locale).isEmpty)
        #expect(OpenAPIEndpointNotices.notices(modes: modes(endpoints: nil), mode: .endpoints, locale: locale).isEmpty)
    }
}

@Suite("OpenAPI endpoints view", .serialized)
@MainActor
struct TqOpenAPIEndpointViewTests {
    private let locale = Locale(identifier: "en_US")

    private var style: SafeModeStyle {
        SafeModeStyle(typography: .init(), palette: .init(theme: .system, isDark: false, increasedContrast: false),
                      syntaxStyle: .init(), locale: locale)
    }

    private func modes(_ text: String) -> SafePreviewModes {
        SafePreviewModes(TextPresentation(formatID: .json, text: text, lineCount: 1, byteCount: text.utf8.count,
                                          encoding: .utf8, redactionCount: 0, syntax: .json), locale: locale)
    }

    @Test func theRegistryMakesTheEndpointsViewWhichHostsItsOwnTable() {
        #expect(SafeModeViewRegistry.makeView(for: .endpoints) is NativeEndpointsPreviewView)
    }

    @Test func displayShowsOneRowPerOperationAndClearEmptiesIt() {
        let view = NativeEndpointsPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let spec = #"{"openapi": "3.0.3", "paths": {"/a": {"get": {}, "put": {}}, "/b": {"post": {"summary": "Make"}}}}"#
        view.display(modes(spec), mode: .endpoints, style: style)
        #expect(view.table.tableView.numberOfRows == 3)
        #expect(view.table.tableView.numberOfColumns == 4)
        view.clear()
        #expect(view.table.tableView.numberOfRows == 0)
    }

    @Test func displayIgnoresAnyModeOtherThanEndpoints() {
        let view = NativeEndpointsPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        view.display(modes(#"{"openapi": "3.0.3", "paths": {"/a": {"get": {}}}}"#), mode: .outline, style: style)
        #expect(view.table.tableView.numberOfRows == 0)
    }
}

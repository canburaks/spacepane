import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// When the Contents rail is offered and how wide it is (decision 027, Q-74). Rules over values: no layout is needed.
@Suite("Q74 Contents rail policy")
@MainActor
struct Q74ContentsRailPolicyTests {
    private let english = Locale(identifier: "en")
    private var low: CGFloat { ContentsRailPolicy.minimumHostWidth - ContentsRailPolicy.hysteresis }
    private var high: CGFloat { ContentsRailPolicy.minimumHostWidth + ContentsRailPolicy.hysteresis }

    @Test func aHostBecomesWideAboveTheBandAndNarrowBelowItAndKeepsItsStateInside() {
        #expect(!ContentsRailPolicy.isWide(forWidth: high - 1, previous: false))
        #expect(ContentsRailPolicy.isWide(forWidth: high, previous: false))
        #expect(ContentsRailPolicy.isWide(forWidth: low, previous: true))
        #expect(!ContentsRailPolicy.isWide(forWidth: low - 1, previous: true))
        // Inside the band either state holds, so a drag across the threshold never flickers the rail.
        let middle = ContentsRailPolicy.minimumHostWidth
        #expect(ContentsRailPolicy.isWide(forWidth: middle, previous: true))
        #expect(!ContentsRailPolicy.isWide(forWidth: middle, previous: false))
    }

    @Test func aHostWithNoWidthYetKeepsTheStateItHas() {
        #expect(ContentsRailPolicy.isWide(forWidth: 0, previous: true))
        #expect(!ContentsRailPolicy.isWide(forWidth: 0, previous: false))
    }

    @Test func onlyTheRenderedModeOfAWideHostWithEnoughHeadingsOffersTheRail() {
        #expect(ContentsRailPolicy.offers(mode: .rendered, headingCount: 2, isWide: true))
        #expect(!ContentsRailPolicy.offers(mode: .rendered, headingCount: 1, isWide: true))
        #expect(!ContentsRailPolicy.offers(mode: .rendered, headingCount: 0, isWide: true))
        #expect(!ContentsRailPolicy.offers(mode: .rendered, headingCount: 9, isWide: false))
        // Heading ranges belong to the rendered text; every other mode keeps its own view.
        for mode in [NativePreviewMode.source, .contents, .outline, .invisibles, .references, .table] {
            #expect(!ContentsRailPolicy.offers(mode: mode, headingCount: 9, isWide: true), "\(mode)")
        }
    }

    @Test func theRailIsOfferedExactlyWhenTheContentsModeIsForAWideRenderedDocument() throws {
        for count in 0...3 {
            let text = (0..<count).map { "## Heading \($0)\n\nText of the section.\n\n" }.joined()
            let presentation = TextPresentation(
                formatID: .markdown, text: text, lineCount: max(1, text.components(separatedBy: "\n").count),
                byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .markdown)
            let modes = SafePreviewModes(presentation, locale: english)
            let headings = modes.markdown?.headings.count ?? 0
            #expect(headings == count, "headings for \(count)")
            #expect(ContentsRailPolicy.offers(mode: .rendered, headingCount: headings, isWide: true)
                    == modes.available.contains(.contents), "count \(count)")
        }
    }

    @Test func theRailsWidthFollowsItsState() {
        #expect(ContentsRailPolicy.width(offered: false, collapsed: false) == 0)
        #expect(ContentsRailPolicy.width(offered: false, collapsed: true) == 0)
        #expect(ContentsRailPolicy.width(offered: true, collapsed: false) == ContentsRailPolicy.expandedWidth)
        #expect(ContentsRailPolicy.width(offered: true, collapsed: true) == ContentsRailPolicy.collapsedWidth)
        #expect(ContentsRailPolicy.collapsedWidth < ContentsRailPolicy.expandedWidth)
    }

    @Test func theProvisionalThresholdLeavesARegularDensityColumnBesideTheRail() {
        // These hold whatever the measured widths turn out to be; if the compact threshold moves, revisit the rail's.
        let narrowestWide = low
        #expect(PreviewChrome.density(forWidth: narrowestWide, previous: .regular) == .regular)
        let column = narrowestWide - ContentsRailPolicy.expandedWidth
        #expect(column >= PreviewChrome.compactWidth + PreviewChrome.compactHysteresis)
        #expect(ContentsRailPolicy.hysteresis >= PreviewChrome.compactHysteresis)
    }
}

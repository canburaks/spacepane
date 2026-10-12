import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// One representative finding per kind, with the detail its wording needs.
private func sample(_ kind: PreviewFindingKind) -> PreviewFinding {
    switch kind {
    case .notebookOutOfOrder: PreviewFinding(kind: kind, count: 2, detail: .executionSequence([5, 2, 9]))
    case .notebookErrorOutputs, .notebookUnexecutedCells: PreviewFinding(kind: kind, count: 2, detail: .cells([3, 7]))
    case .archiveHighCompression: PreviewFinding(kind: kind, count: 1, detail: .compressionRatio(1_200))
    case .archiveLargeExpansion: PreviewFinding(kind: kind, count: 1, detail: .expandedBytes(12_400_000_000))
    case .secretSyncedFolder: PreviewFinding(kind: kind, count: 1, detail: .syncProvider(.dropbox))
    case .hiddenUnicodeTags: PreviewFinding(kind: kind, count: 4, lines: [2], detail: .decodedText("hi"))
    default: PreviewFinding(kind: kind, count: 3, lines: [2, 7])
    }
}

private func presentation(_ findings: [PreviewFinding], text: String = "alpha\npassword=••••\n",
                          redactions: Int = 0, format: FormatID = .plainText) -> TextPresentation {
    TextPresentation(formatID: format, text: text, lineCount: 2, byteCount: text.utf8.count, encoding: .utf8,
                     redactionCount: redactions, syntax: format == .markdown ? .markdown : .plain, findings: PreviewFindings.normalized(findings))
}

@Suite("Findings wording and banner", .serialized)
@MainActor
struct FindingsBannerTests {
    private let english = Locale(identifier: "en_US")

    @Test func everyKindHasResolvedWordingWithoutRawKeysOrPlaceholders() {
        for kind in PreviewFindingKind.allCases {
            let message = FindingText.message(for: sample(kind), locale: english)
            #expect(!message.isEmpty, "\(kind)")
            #expect(!message.contains("finding."), "\(kind)")
            #expect(!message.contains("%"), "\(kind)")
        }
        #expect(FindingText.message(for: sample(.notebookOutOfOrder), locale: english) == "Cells ran out of order: 5 → 2 → 9.")
        #expect(FindingText.message(for: sample(.archiveHighCompression), locale: english).contains("1,200"))
        #expect(FindingText.message(for: sample(.secretSyncedFolder), locale: english).contains("Dropbox"))
        let unknown = PreviewFinding(kind: .secretSyncedFolder, count: 1)
        #expect(FindingText.message(for: unknown, locale: english).contains(PreviewStrings.text(.findingProviderOther)))
    }

    @Test func detailsListLocalizedPositionsAndBoundTheList() {
        #expect(FindingText.detail(for: PreviewFinding(kind: .hiddenZeroWidth, count: 3, lines: [3, 7, 12]), locale: english)
                == "Lines: 3, 7, 12")
        let many = PreviewFinding(kind: .hiddenZeroWidth, count: 20, lines: Array(1...10))
        #expect(FindingText.detail(for: many, locale: english) == "Lines: 1, 2, 3, 4, 5, 6, 7, 8 and 2 more")
        #expect(FindingText.detail(for: sample(.notebookErrorOutputs), locale: english) == "Cells: 3, 7")
        let manyCells = PreviewFinding(kind: .notebookUnexecutedCells, count: 40, detail: .cells(Array(1...40)))
        #expect(FindingText.detail(for: manyCells, locale: english) == "Cells: 1, 2, 3, 4, 5, 6, 7, 8 and 32 more")
        #expect(FindingText.detail(for: PreviewFinding(kind: .archiveNested, count: 1), locale: english) == nil)
        // Decoded hidden text is shown verbatim, never interpreted.
        let decoded = PreviewFinding(kind: .hiddenUnicodeTags, count: 1, lines: [1], detail: .decodedText("<script>"))
        #expect(FindingText.detail(for: decoded, locale: english)?.contains("<script>") == true)
        let thousands = PreviewFinding(kind: .hiddenZeroWidth, count: 1, lines: [12_345])
        #expect(FindingText.detail(for: thousands, locale: Locale(identifier: "de_DE"))?.contains("12.345") == true)
    }

    @Test func bannerShowsOneAccessibleRowPerFindingMostSeriousFirst() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        view.display(.ready(presentation([PreviewFinding(kind: .secretAPIKey, count: 1, lines: [2]),
                                          PreviewFinding(kind: .hiddenBidirectionalControls, count: 2, lines: [1])])),
                     locale: english)
        let banner = view.findingsBanner
        #expect(!banner.isHidden)
        #expect(!banner.isExpanded && banner.detailScrollView.isHidden)
        #expect(banner.summaryLabel.stringValue == "2 findings to review.")
        banner.setExpanded(true)
        view.layoutSubtreeIfNeeded()
        #expect(banner.rowLabels.count == 2)
        let first = try #require(banner.rowLabels.first)
        #expect(first.accessibilityLabel()?.hasPrefix(PreviewStrings.text(.findingSeverityWarning)) == true)
        #expect(banner.detailLabels.first?.stringValue.contains("Lines: 1") == true)
        #expect(banner.accessibilityLabel() == PreviewStrings.text(.findingBannerLabel))
        #expect(!banner.offersConcealedCopy)
    }

    @Test func bannerKeepsEveryBoundedFindingInsideItsDisclosure() {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let findings = PreviewFindingKind.allCases.prefix(9).map { PreviewFinding(kind: $0, count: 1) }
        view.display(.ready(presentation(findings)), locale: english)
        #expect(!view.findingsBanner.isExpanded && view.findingsBanner.detailScrollView.isHidden)
        view.findingsBanner.setExpanded(true)
        view.layoutSubtreeIfNeeded()
        #expect(view.findingsBanner.rowLabels.count == findings.count)
        #expect(!view.findingsBanner.rowLabels.contains { $0.stringValue.contains("More findings") })
    }

    @Test func bannerCollapsesWithoutFindingsAndClearsForEveryNonContentOutcome() {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        view.display(.ready(presentation([])), locale: english)
        #expect(view.findingsBanner.isHidden)
        #expect(!view.findingsBanner.hasContent)
        for outcome: PreviewOutcome in [.disabledByUser(.plainText), .unavailable(.malformedDocument), .cancelled] {
            view.display(.ready(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1)])), locale: english)
            #expect(!view.findingsBanner.isHidden)
            view.display(outcome, locale: english)
            #expect(view.findingsBanner.isHidden, "\(outcome)")
            #expect(view.findingsBanner.rowLabels.isEmpty)
        }
        view.display(.ready(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1)])), locale: english)
        view.showLoading()
        #expect(view.findingsBanner.isHidden)
    }

    @Test func copyConcealedTextWritesOnlyTheConcealedPresentationToTheGivenPasteboard() {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.concealedTextPasteboard = pasteboard
        let text = "user=demo\npassword=••••\n"
        view.display(.ready(presentation([], text: text, redactions: 1, format: .markdown)), locale: english)
        #expect(view.findingsBanner.offersConcealedCopy)
        #expect(!view.findingsBanner.isHidden)
        #expect(view.findingsBanner.copyActionButton.title == "Copy Concealed Text")
        view.findingsBanner.copyActionButton.performClick(nil)
        #expect(pasteboard.string(forType: .string) == text)
    }

    @Test func copyConcealedTextDoesNothingWithoutConcealment() {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("unchanged", forType: .string)
        view.concealedTextPasteboard = pasteboard
        view.display(.ready(presentation([PreviewFinding(kind: .hiddenZeroWidth, count: 1)])), locale: english)
        #expect(!view.findingsBanner.offersConcealedCopy)
        view.copyConcealedText()
        #expect(pasteboard.string(forType: .string) == "unchanged")
    }
}

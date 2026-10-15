import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Typed notices (decision 027, Q-51 groundwork): every notice says whether it is a limit (shown in the slot at the
/// bottom), a fallback (shown below the mode control) or provenance (shown in the information panel).
/// `PresentationNotices.lines` keeps its old shape.
@Suite("Chrome notices", .serialized)
@MainActor
struct ChromeNoticeTests {
    private let english = Locale(identifier: "en")

    private func presentation(_ text: String = "safe", format: FormatID = .plainText, syntax: TextSyntax = .plain,
                              redactions: Int = 0, truncatedSourceBytes: Int? = nil, isReformatted: Bool = false,
                              sourceRecordCount: Int? = nil) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
                         redactionCount: redactions, syntax: syntax, sourceRecordCount: sourceRecordCount,
                         truncatedSourceBytes: truncatedSourceBytes, isReformatted: isReformatted)
    }

    // MARK: The families

    @Test func aPartialReadIsALimitWithBothSizes() {
        let partial = presentation(truncatedSourceBytes: 3_000_000)
        let notices = PresentationNotices.notices(for: partial, locale: english)
        #expect(notices.map(\.kind) == [.limit])
        let shown = Int64(partial.byteCount).formatted(.byteCount(style: .file).locale(english))
        let whole = Int64(3_000_000).formatted(.byteCount(style: .file).locale(english))
        #expect(notices.first?.text == PreviewStrings.format(.codeNoticeTruncated, arguments: [shown, whole], locale: english))
    }

    @Test func aReformattedViewIsProvenanceAndKeepsItsPlaceAfterTheLimit() {
        let reformatted = presentation(isReformatted: true)
        let alone = PresentationNotices.notices(for: reformatted, locale: english)
        #expect(alone.map(\.kind) == [.provenance] && alone.first?.text == PreviewStrings.text(.codeNoticeReformatted))
        let both = PresentationNotices.notices(for: presentation(truncatedSourceBytes: 3_000_000, isReformatted: true),
                                               locale: english)
        #expect(both.map(\.kind) == [.limit, .provenance])
    }

    @Test func signaturesAndCertificatesAreProvenanceAndOnlyForTheirFormats() {
        for format in [FormatID.applicationBundle, .iosApp, .installerPackage, .provisioningProfile] {
            let notices = PresentationNotices.notices(for: presentation("{}", format: format), locale: english)
            #expect(notices.map(\.kind) == [.provenance], "\(format.rawValue)")
            #expect(notices.first?.text == PreviewStrings.text(.packageNoticeSignature), "\(format.rawValue)")
        }
        let certificate = PresentationNotices.notices(for: presentation("{}", format: .certificate), locale: english)
        #expect(certificate.map(\.kind) == [.provenance] && certificate.first?.text == PreviewStrings.text(.packageNoticeCertificate))
        #expect(PresentationNotices.notices(for: presentation("{}", format: .json), locale: english).isEmpty)
    }

    @Test func aPageLimitAndAPartialOrProtectedBookAreLimits() {
        let pages = PresentationNotices.notices(for: presentation("x", syntax: .drawio, sourceRecordCount: 3), locale: english)
        #expect(pages.map(\.kind) == [.limit])
        #expect(pages.first?.text == PreviewStrings.format(.diagramDrawioPage, arguments: [Int64(3)], locale: english))
        let partial = PresentationNotices.notices(
            for: presentation("---\npartial: true\n---\nBody", format: .epub, syntax: .markdown), locale: english)
        #expect(partial.map(\.kind) == [.limit] && partial.first?.text == PreviewStrings.text(.ebooksNoticePartialText))
        let protected = PresentationNotices.notices(
            for: presentation("---\ndrm: true\n---\nBody", format: .epub, syntax: .markdown), locale: english)
        #expect(protected.map(\.kind) == [.limit] && protected.first?.text == PreviewStrings.text(.ebooksNoticeDRM))
    }

    // MARK: The shim and the wrapper

    @Test func theLinesShimIsTheTypedWordingInTheSameOrder() {
        for sample in [presentation(),
                       presentation(truncatedSourceBytes: 3_000_000, isReformatted: true),
                       presentation("{}", format: .applicationBundle),
                       presentation("x", syntax: .drawio, sourceRecordCount: 2)] {
            let typed = PresentationNotices.notices(for: sample, locale: english)
            #expect(PresentationNotices.lines(for: sample, locale: english) == typed.map(\.text))
        }
    }

    @Test func typedWrapsLinesOfOneKindInOrder() {
        let wrapped = PresentationNotices.typed(["a", "b"], as: .fallback)
        #expect(wrapped == [PresentationNotice(kind: .fallback, text: "a"), PresentationNotice(kind: .fallback, text: "b")])
        #expect(PresentationNotices.typed([], as: .limit).isEmpty)
    }

    // MARK: Where the preview shows them

    private func harness() -> InteractionHarness {
        let host = InteractionHarness()
        host.view.chromeScheduler = ManualChromeScheduler()
        return host
    }

    @Test func limitsGoToTheLimitsSlotAndTheStatusTextKeepsEveryNoticeInItsOrder() {
        let host = harness()
        defer { host.release() }
        let sample = presentation("token = ••••", redactions: 1, truncatedSourceBytes: 4_000_000, isReformatted: true)
        host.view.display(.ready(sample), locale: english)
        let typed = PresentationNotices.notices(for: sample, locale: english)
        let limit = typed.first { $0.kind == .limit }?.text ?? ""
        let reformatted = PreviewStrings.text(.codeNoticeReformatted)
        #expect(!limit.isEmpty)
        #expect(host.view.limitsLabel.stringValue == limit)
        // A formatting note is provenance: the information panel draws it, so the status line holds no note here.
        #expect(host.view.statusLabel.stringValue.isEmpty)
        // The status text keeps every notice in the order its family produced them, whichever slot shows each.
        #expect(host.view.displayedStatus == [limit, reformatted].joined(separator: "\n"))
    }

    @Test func aStructureFallbackIsANoteNotALimit() {
        let host = harness()
        defer { host.release() }
        host.view.display(.ready(presentation("{ not json", format: .json, syntax: .json)), locale: english)
        #expect(host.view.statusLabel.stringValue.contains(PreviewStrings.text(.previewStructureFallback)))
        #expect(host.view.limitsLabel.stringValue.isEmpty)
    }

    @Test func aPresentationWithNoNoticesLeavesBothSlotsEmptyAndHidden() {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(5)))
        #expect(host.view.statusLabel.stringValue.isEmpty && host.view.limitsLabel.stringValue.isEmpty)
        #expect(host.view.limitsLabel.isHidden && host.view.displayedStatus.isEmpty)
    }
}

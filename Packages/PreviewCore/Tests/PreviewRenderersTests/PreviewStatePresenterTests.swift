import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Preview state and notice presentation", .serialized)
struct PreviewStatePresenterTests {
    private let locale = Locale(identifier: "en")

    private func presentation(_ text: String = "safe", redactions: Int = 0,
                              invalidRecords: [Int] = [], images: [PreviewImage] = [],
                              truncatedSourceBytes: Int? = nil, isReformatted: Bool = false) -> TextPresentation {
        TextPresentation(formatID: .plainText, text: text, lineCount: 1, byteCount: text.utf8.count,
                         encoding: .utf8, redactionCount: redactions, invalidRecordLines: invalidRecords,
                         images: images, truncatedSourceBytes: truncatedSourceBytes, isReformatted: isReformatted)
    }

    @Test func everyFailureRetainsItsReviewedCopyWithoutInventedLimitsOrActions() throws {
        for language in CopyFailureContentTests.languages {
            let locale = CopyFailureContentTests.viewLocale(language)
            for failure in CopyFailureContentTests.failures {
                let state = try #require(PreviewStatePresenter.state(for: .unavailable(failure), locale: locale))
                let expected = PreviewFailureCopy.content(for: failure, locale: locale)
                #expect(state.content.kind == .unavailable(failure))
                #expect(state.content.title == expected.title && state.content.body == expected.body)
                #expect(state.content.action == nil && state.announces)
            }
        }
    }

    @Test func unknownOrInvalidBudgetsNeverBorrowTheStandardLimits() throws {
        let unknown = try #require(PreviewStatePresenter.state(for: .unavailable(.tooManyLines), locale: locale))
        let invalid = PreviewBudget(maxJSONDepth: 0, maxTextLines: 4_321)
        let rejected = PreviewStatePresenter.state(for: .unavailable(.tooManyLines), limits: invalid, locale: locale)
        #expect(rejected == unknown)
        #expect(unknown.content.body == PreviewFailureCopy.content(for: .tooManyLines, locale: locale).body)
    }

    @Test func cancelledIsQuietAndDisabledHasNoFinderAction() throws {
        let cancelled = try #require(PreviewStatePresenter.state(for: .cancelled, locale: locale))
        #expect(cancelled.content == .cancelled() && !cancelled.announces)
        let disabled = try #require(PreviewStatePresenter.state(for: .disabledByUser(.json), locale: locale))
        #expect(disabled.content == .content(for: .disabled, locale: locale))
        #expect(disabled.content.action == nil && disabled.announces)
    }

    @Test func anEmptyStateRequiresNoTextPicturesOrOtherContent() throws {
        let empty = try #require(PreviewStatePresenter.state(for: .ready(presentation("")), locale: locale))
        #expect(empty.content == .content(for: .empty, locale: locale) && empty.announces)
        #expect(PreviewStatePresenter.state(for: .ready(presentation(" ")), locale: locale) == nil)
        #expect(PreviewStatePresenter.state(for: .ready(presentation("safe content")), locale: locale) == nil)
        let image = PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .page)
        #expect(PreviewStatePresenter.state(for: .ready(presentation("", images: [image])), locale: locale) == nil)
    }

    @Test func noticesKeepTheirFamilyOrderAndTypedLimitPlacement() {
        let sample = presentation("concealed text", redactions: 1, invalidRecords: [3],
                                  truncatedSourceBytes: 4_000_000, isReformatted: true)
        let notices = PreviewStatePresenter.notices(for: sample, mode: .profile, hasStructureFallback: true,
                                                   markupNotices: ["safe converted-document note"],
                                                   profileNotices: ["safe profile note"], hasRecords: true, locale: locale)
        #expect(notices.map(\.kind) == [.fallback, .provenance, .provenance, .limit, .provenance, .fallback])
        #expect(!notices.contains { $0.text == PreviewStrings.text(.privacyNotice) })
        #expect(notices[0].text == PreviewStrings.text(.previewStructureFallback))
        #expect(notices[1].text == "safe converted-document note" && notices[2].text == "safe profile note")
        #expect(notices[4].text == PreviewStrings.text(.codeNoticeReformatted))
        #expect(notices[5].text == PreviewStrings.format(.previewInvalidRecord, arguments: [Int64(3)], locale: locale))
        #expect(notices.allSatisfy { !$0.text.contains(sample.text) })
    }

    @Test func profileAndInvisiblesNoticesBelongOnlyToTheirSelectedMode() {
        let source = PreviewStatePresenter.notices(for: presentation(), mode: .source, hasStructureFallback: false,
                                                  markupNotices: [], profileNotices: ["unused profile note"],
                                                  hasRecords: false, locale: locale)
        #expect(source.isEmpty)
        let invisibles = PreviewStatePresenter.notices(for: presentation(), mode: .invisibles, hasStructureFallback: false,
                                                      markupNotices: [], profileNotices: ["unused profile note"],
                                                      hasRecords: false, locale: locale)
        #expect(invisibles == [PresentationNotice(kind: .provenance, text: PreviewStrings.text(.previewInvisiblesNote))])
        let profile = PreviewStatePresenter.notices(for: presentation(), mode: .profile, hasStructureFallback: false,
                                                   markupNotices: [], profileNotices: ["safe profile note"],
                                                   hasRecords: false, locale: locale)
        #expect(profile == [PresentationNotice(kind: .provenance, text: "safe profile note")])
    }

    @Test func invalidRecordWarningRequiresAnAvailableRecordsPresentation() {
        let sample = presentation(invalidRecords: [3])
        let withoutRecords = PreviewStatePresenter.notices(for: sample, mode: .source, hasStructureFallback: false,
                                                          markupNotices: [], profileNotices: [],
                                                          hasRecords: false, locale: locale)
        #expect(withoutRecords.isEmpty)
        let withRecords = PreviewStatePresenter.notices(for: sample, mode: .source, hasStructureFallback: false,
                                                       markupNotices: [], profileNotices: [],
                                                       hasRecords: true, locale: locale)
        #expect(withRecords == [PresentationNotice(kind: .fallback,
            text: PreviewStrings.format(.previewInvalidRecord, arguments: [Int64(3)], locale: locale))])
    }

    @MainActor
    @Test func failureStatesHonorTheEffectiveRequestBudget() throws {
        let view = NativePreviewView(frame: .zero)
        let budget = PreviewBudget(maxInputBytes: 262_144, maxOutputUTF8Bytes: 524_288,
                                   maxJSONDepth: 12, maxJSONNodes: 500, maxTextLines: 200,
                                   maxLineUTF8Bytes: 8_192, maxMilliseconds: 4_000)
        for failure in CopyFailureContentTests.limitFailures {
            view.display(PreviewResult(outcome: .unavailable(failure), effectiveBudget: budget), locale: locale)
            let content = try #require(view.stateContent)
            let expected = PreviewFailureCopy.content(for: failure, locale: locale,
                                                      limits: PreviewLimitsSummary(budget: budget))
            #expect(content.kind == .unavailable(failure))
            #expect(content.title == expected.title)
            #expect(content.body == expected.body, "\(failure): the result's family budget reaches the state")
        }
    }
}

import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en")

/// The states that have no content (decision 027, Q-35): one centered view with a symbol or a delayed spinner, a title
/// and a body, announced once, and no action in the Finder extension.
@Suite("Chrome states", .serialized)
@MainActor
struct ChromeStateViewTests {
    private func makeStateView() -> (view: NativeStateView, scheduler: ManualChromeScheduler) {
        let scheduler = ManualChromeScheduler()
        let view = NativeStateView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
        view.scheduler = scheduler
        view.locale = english
        return (view, scheduler)
    }

    private func harness() -> (host: InteractionHarness, scheduler: ManualChromeScheduler) {
        let host = InteractionHarness()
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        return (host, scheduler)
    }

    private func spoken(_ content: NativeStateContent) -> String {
        [content.title, content.body].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    // MARK: The view

    @Test func everyKindShowsItsTitleAndBodyAndOnlyLoadingSpins() {
        let kinds: [NativeStateContent.Kind] = [.loading, .empty, .unavailable(.missingFile), .disabled,
                                                .settingsUnavailable, .configurationUnavailable]
        for kind in kinds {
            let (view, _) = makeStateView()
            let content = NativeStateContent.content(for: kind, locale: english)
            #expect(!content.title.isEmpty, "\(kind)")
            view.show(content, palette: chromeTestPalette())
            view.layoutSubtreeIfNeeded()
            #expect(view.isRevealed && !view.isHidden, "\(kind)")
            #expect(view.titleText == content.title && view.bodyText == content.body, "\(kind)")
            let isLoading = kind == .loading
            #expect(view.isSpinnerRunning == isLoading, "\(kind)")
            if !isLoading { #expect(!content.body.isEmpty, "\(kind)") }
            #expect(!view.isActionVisible, "\(kind)")
        }
    }

    @Test func aStateIsOneAccessibilityElementWithTheTitleAndBodyAsOneSentence() {
        let (view, _) = makeStateView()
        let content = NativeStateContent.content(for: .unavailable(.missingFile), locale: english)
        view.show(content, palette: chromeTestPalette())
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityLabel() == spoken(content))
        #expect(view.accessibilityChildren()?.isEmpty == true)
        // Nothing inside it is another element: no label, symbol, spinner or stack.
        let exposed = descendants(of: NSView.self, in: view).filter { !$0.isHidden && $0.isAccessibilityElement() }
        #expect(exposed.isEmpty)
        // A loading state is the same single element, with the spinner not exposed.
        let (loading, _) = makeStateView()
        loading.show(NativeStateContent.content(for: .loading, locale: english), palette: chromeTestPalette())
        #expect(loading.isSpinnerRunning)
        #expect(descendants(of: NSView.self, in: loading).filter { !$0.isHidden && $0.isAccessibilityElement() }.isEmpty)
    }

    @Test func anActionIsTheOnlyOtherElementAndIsReportedToOnAction() throws {
        let (view, _) = makeStateView()
        var received: [StateAction] = []
        view.onAction = { received.append($0) }
        let content = NativeStateContent(kind: .disabled, title: "Title", body: "Body", action: .openFile)
        view.show(content, palette: chromeTestPalette())
        #expect(view.isActionVisible && view.actionTitle == PreviewStrings.text(.openFile))
        #expect(view.accessibilityChildren()?.count == 1)
        let button = try #require(descendants(of: NSButton.self, in: view).first)
        button.performClick(nil)
        #expect(received == [.openFile])
        // The other actions have titles of their own, and a state without an action offers none.
        view.show(NativeStateContent(kind: .disabled, title: "Title", body: "Body", action: .enableFormat(.json)),
                  palette: chromeTestPalette())
        #expect(view.isActionVisible && !view.actionTitle.isEmpty && view.actionTitle != PreviewStrings.text(.openFile))
        view.show(NativeStateContent(kind: .empty, title: "Title", body: "Body", action: .showSource),
                  palette: chromeTestPalette())
        #expect(view.isActionVisible && !view.actionTitle.isEmpty)
        view.show(NativeStateContent(kind: .empty, title: "Title", body: "Body"), palette: chromeTestPalette())
        #expect(!view.isActionVisible && view.accessibilityChildren()?.isEmpty == true)
    }

    @Test func theSameContentAgainOnlyRestylesAndClearHidesTheView() {
        let (view, scheduler) = makeStateView()
        let content = NativeStateContent.content(for: .empty, locale: english)
        view.show(content, palette: chromeTestPalette())
        view.show(content, palette: chromeTestPalette())
        #expect(view.isRevealed && view.content == content && scheduler.scheduled.isEmpty)
        view.clear()
        #expect(view.content == nil && !view.isRevealed && view.isHidden && !view.isSpinnerRunning)
    }

    // MARK: The delayed spinner

    @Test func aLoadingStateStaysInvisibleUntilItsGracePeriodHasPassed() {
        let (view, scheduler) = makeStateView()
        view.showLoading(generation: UUID(), after: PreviewChrome.spinnerDelay)
        #expect(view.content?.kind == .loading)
        #expect(!view.isRevealed && view.isHidden && !view.isSpinnerRunning)
        #expect(scheduler.waiting.count == 1 && scheduler.waiting.first?.delay == PreviewChrome.spinnerDelay)
        var revealed: [NativeStateContent] = []
        view.onReveal = { revealed.append($0) }
        scheduler.runWaiting()
        #expect(view.isRevealed && !view.isHidden && view.isSpinnerRunning)
        #expect(revealed == [NativeStateContent.content(for: .loading, locale: english)])
        #expect(view.titleText == NativeStateContent.content(for: .loading, locale: english).title)
    }

    @Test func contentThatArrivesFirstCancelsTheSpinner() {
        let (view, scheduler) = makeStateView()
        view.showLoading(generation: UUID(), after: PreviewChrome.spinnerDelay)
        let pending = scheduler.waiting
        #expect(pending.count == 1)
        view.show(NativeStateContent.content(for: .empty, locale: english), palette: chromeTestPalette())
        #expect(scheduler.waiting.isEmpty)
        // Even a timer that fires late does nothing to the state that replaced the loading state.
        pending.first?.runIgnoringCancellation()
        #expect(view.content?.kind == .empty && !view.isSpinnerRunning)
        view.showLoading(generation: UUID(), after: PreviewChrome.spinnerDelay)
        view.clear()
        scheduler.runWaiting()
        #expect(view.content == nil && !view.isRevealed && view.isHidden)
    }

    @Test func aTimerFromAnOlderGenerationCannotRevealAReplacement() {
        let (view, scheduler) = makeStateView()
        view.showLoading(generation: UUID(), after: PreviewChrome.spinnerDelay)
        let older = scheduler.scheduled[0]
        view.showLoading(generation: UUID(), after: PreviewChrome.spinnerDelay)
        #expect(older.isCancelled && scheduler.waiting.count == 1)
        older.runIgnoringCancellation()
        #expect(!view.isRevealed)
        scheduler.runWaiting()
        #expect(view.isRevealed)
    }

    // MARK: In the preview

    @Test func aLoadingStateIsAnnouncedOnlyWhenItAppears() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.view.showLoading()
        let loading = NativeStateContent.content(for: .loading, locale: host.view.presentationLocale)
        #expect(host.view.stateContent == loading)
        #expect(!host.view.stateView.isRevealed && host.view.stateView.isHidden)
        #expect(host.view.displayedStatus == loading.title)
        #expect(host.announcements.texts.isEmpty)
        #expect(scheduler.waiting.count == 1 && scheduler.waiting.first?.delay == PreviewChrome.spinnerDelay)
        scheduler.runWaiting()
        #expect(host.view.stateView.isRevealed && !host.view.stateView.isHidden && host.view.stateView.isSpinnerRunning)
        #expect(host.announcements.texts == [spoken(loading)])
    }

    @Test func aPreviewThatArrivesFirstCancelsTheLoadingState() {
        let (host, scheduler) = harness()
        defer { host.release() }
        host.view.showLoading()
        host.show(plainPresentation("hello"))
        #expect(scheduler.waiting.isEmpty && host.view.stateContent == nil && host.view.stateView.isHidden)
        scheduler.runWaiting()
        #expect(host.announcements.texts.isEmpty && host.view.stateView.content == nil)
        #expect(host.view.textView.string == "hello" && !host.view.scrollView.isHidden)
    }

    @Test func eachStateIsAnnouncedOnceWhenItAppearsAndNotWhenItRepeats() {
        let (host, _) = harness()
        defer { host.release() }
        let locale = host.view.presentationLocale
        host.view.display(.unavailable(.missingFile))
        let missing = spoken(NativeStateContent.content(for: .unavailable(.missingFile), locale: locale))
        #expect(host.announcements.texts == [missing])
        // The same state again, as a live reload of a file that is still missing would send it: not a second time.
        host.view.display(.unavailable(.missingFile))
        #expect(host.announcements.texts == [missing])
        host.view.display(.disabledByUser(.json))
        let disabled = spoken(NativeStateContent.content(for: .disabled, locale: locale))
        #expect(host.announcements.texts == [missing, disabled])
        host.view.showSettingsUnavailable()
        host.view.showSettingsConfigurationUnavailable()
        #expect(host.announcements.texts == [missing, disabled,
                                              spoken(NativeStateContent.content(for: .settingsUnavailable, locale: locale)),
                                              spoken(NativeStateContent.content(for: .configurationUnavailable, locale: locale))])
        // A cancelled request is not news.
        host.view.display(.cancelled)
        #expect(host.announcements.texts.count == 4)
        #expect(host.view.stateContent?.title == PreviewStrings.text(.cancelled))
    }

    @Test func aStateShowsItsTitleAndBodyAsTheStatusAndNamesNobody() {
        let (host, _) = harness()
        defer { host.release() }
        host.view.providerName = "Acme Preview"
        host.show(plainPresentation("safe"))
        #expect(!host.view.infoBadge.isHidden)
        host.view.display(.unavailable(.missingFile))
        let content = NativeStateContent.content(for: .unavailable(.missingFile), locale: host.view.presentationLocale)
        #expect(host.view.displayedStatus == content.title + "\n" + content.body)
        #expect(host.view.infoBadge.isHidden && host.view.statusLabel.stringValue.isEmpty)
        #expect(!host.view.displayedStatus.contains("Acme Preview"))
    }

    @Test func aZeroByteFileShowsTheEmptyStateInsteadOfABlankPane() {
        let (host, _) = harness()
        defer { host.release() }
        let locale = host.view.presentationLocale
        let empty = NativeStateContent.content(for: .empty, locale: locale)
        let formats: [(FormatID, TextSyntax)] = [(.plainText, .plain), (.json, .json), (.csv, .commaSeparated)]
        for (format, syntax) in formats {
            host.show(plainPresentation("", format: format, syntax: syntax), resetsContentState: true)
            #expect(host.view.stateContent == empty, "\(format.rawValue)")
            #expect(host.view.stateView.isRevealed && !host.view.stateView.isHidden, "\(format.rawValue)")
            #expect(host.view.scrollView.isHidden && host.view.textView.isHidden && host.view.infoBadge.isHidden,
                    "\(format.rawValue)")
            #expect(host.view.modeControl.isHidden, "\(format.rawValue)")
        }
        #expect(host.announcements.texts == [spoken(empty)])
        // Text arrives: the state goes away and the preview is back.
        host.show(plainPresentation("now there is text"), resetsContentState: true)
        #expect(host.view.stateContent == nil && host.view.stateView.isHidden && !host.view.scrollView.isHidden)
        #expect(host.view.textView.string == "now there is text" && !host.view.infoBadge.isHidden)
        // A folder summary has no bytes of its own but has text to show, so it is not empty.
        host.show(plainPresentation(#"{"members":[]}"#, format: .folder, syntax: .json), resetsContentState: true)
        #expect(host.view.stateContent == nil)
    }

    @Test func onlyAPresentationWithNothingToShowIsEmpty() {
        #expect(NativeStateContent.isEmpty(plainPresentation("")))
        #expect(!NativeStateContent.isEmpty(plainPresentation(" ")))
        #expect(!NativeStateContent.isEmpty(plainPresentation("\n")))
        let page = PreviewImage(data: Data([1]), pixelWidth: 1, pixelHeight: 1, role: .page)
        let withPicture = TextPresentation(formatID: .comicBook, text: "", lineCount: 1, byteCount: 0, encoding: .utf8,
                                           redactionCount: 0, images: [page])
        #expect(!NativeStateContent.isEmpty(withPicture))
    }

    @Test func aStateReplacesContentAndContentReplacesTheState() {
        let (host, _) = harness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(10)))
        #expect(!host.view.scrollView.isHidden && host.view.stateView.isHidden && host.view.hasDisplayableContent)
        host.view.display(.unavailable(.missingFile))
        #expect(host.view.textView.string.isEmpty && host.view.scrollView.isHidden && !host.view.stateView.isHidden)
        #expect(host.view.copyAllText == nil && !host.view.hasDisplayableContent)
        host.show(plainPresentation(numberedLines(10)))
        #expect(!host.view.scrollView.isHidden && host.view.stateView.isHidden && host.view.stateContent == nil)
        #expect(host.view.textView.string == numberedLines(10) && host.view.hasDisplayableContent)
    }
}

import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Records the actual notification path and the visible hierarchy at the instant it is published. Speech is
/// recorded separately by InteractionHarness, so these tests never post to the user's accessibility session.
@MainActor
private final class ChromeLayoutRecorder {
    struct Post {
        let element: NSView
        let notification: NSAccessibility.Notification
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any]
        let mode: NativePreviewMode
        let modes: [NativePreviewMode]
        let state: NativeStateContent.Kind?
        let stateIsVisible: Bool
        let sourceIsVisible: Bool
        let outlineIsVisible: Bool
    }

    private(set) var posts: [Post] = []
    var layouts: [Post] { posts.filter { $0.notification == .layoutChanged } }

    init(view: NativePreviewView) {
        view.announcer.notificationHandler = { [weak self, weak view] element, notification, userInfo in
            guard let self, let view else { return }
            posts.append(Post(element: element, notification: notification, userInfo: userInfo,
                              mode: view.selectedMode, modes: view.displayedModes,
                              state: view.stateContent?.kind,
                              stateIsVisible: view.stateView.isRevealed && !view.stateView.isHidden,
                              sourceIsVisible: !view.textView.isHidden && !view.scrollView.isHidden,
                              outlineIsVisible: !view.outlineView.isHidden))
        }
    }

    func reset() { posts.removeAll() }
}

/// Q54: a labelled mode control and one structural notification after an actual visible transition. No clock
/// sleeps, source values or notification payload strings are needed to prove that the final hierarchy is ready.
@Suite("Chrome accessibility transitions", .serialized)
@MainActor
struct ChromeAccessibilityTransitionTests {
    private let english = Locale(identifier: "en")
    private let chord: NSEvent.ModifierFlags = [.option, .command]
    private let json = #"{"items":[1,2]}"#

    private func expectLayouts(_ recorder: ChromeLayoutRecorder, from view: NativePreviewView, count: Int) {
        #expect(recorder.layouts.count == count)
        #expect(recorder.posts.count == count, "The speech handler must not swallow structural events or add speech posts")
        for post in recorder.layouts {
            #expect(post.element === view)
            #expect(post.userInfo.isEmpty, "A layout notification carries no file content, source values or announcement text")
        }
    }

    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        view.modeControl.selectedSegment = try #require(view.displayedModes.firstIndex(of: mode))
        #expect(view.modeControl.sendAction(view.modeControl.action, to: view.modeControl.target))
        view.layoutSubtreeIfNeeded()
    }

    @Test func theModeControlLabelUsesOwnedUILanguageResourcesAndSurvivesReuse() {
        let key = PreviewStrings.Key.previewModeControlLabel
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        #expect(PreviewStrings.text(key, languagePreferences: ["en"]) == "View mode")
        for language in languages {
            let value = PreviewStrings.text(key, languagePreferences: [language])
            #expect(!value.isEmpty && value != key.rawValue, "\(language)")
            #expect(value != PreviewStrings.text(.resourceUnavailable), "\(language)")
        }
        let host = InteractionHarness()
        defer { host.release() }
        #expect(host.view.modeControl.accessibilityLabel() == PreviewStrings.text(key))
        host.show(plainPresentation(json, format: .json, syntax: .json))
        #expect(!host.view.modeControl.isHidden)
        #expect(host.view.modeControl.accessibilityLabel() == PreviewStrings.text(key))
        // Presentation locale formats numbers; it must not select a different UI language.
        host.view.display(.ready(plainPresentation(json, format: .json, syntax: .json)), locale: Locale(identifier: "tr_TR"))
        #expect(host.view.modeControl.accessibilityLabel() == PreviewStrings.text(key))
        host.view.display(.unavailable(.missingFile))
        host.show(plainPresentation(json, format: .json, syntax: .json))
        #expect(host.view.modeControl.accessibilityLabel() == PreviewStrings.text(key))
    }

    @Test func aSegmentChangePublishesTheFinalModeOnceAndARepeatedSelectionDoesNothing() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let recorder = ChromeLayoutRecorder(view: host.view)
        host.show(plainPresentation(json, format: .json, syntax: .json))
        expectLayouts(recorder, from: host.view, count: 1)
        recorder.reset()

        try select(.outline, in: host.view)
        expectLayouts(recorder, from: host.view, count: 1)
        let outline = try #require(recorder.layouts.first)
        #expect(outline.mode == .outline && outline.outlineIsVisible && !outline.sourceIsVisible)
        #expect(outline.state == nil && !outline.stateIsVisible)
        try select(.outline, in: host.view)
        expectLayouts(recorder, from: host.view, count: 1)
        try select(.source, in: host.view)
        expectLayouts(recorder, from: host.view, count: 2)
        let source = try #require(recorder.layouts.last)
        #expect(source.mode == .source && source.sourceIsVisible && !source.outlineIsVisible)
        #expect(host.announcements.texts.isEmpty, "The focused native control already names its selection")
    }

    @Test func aModeChordAndAContentsLinkPublishOnceWithoutDuplicatingTheirSpeech() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let recorder = ChromeLayoutRecorder(view: host.view)
        host.show(plainPresentation("# Alpha\n\ntext\n\n## Beta\n\nmore text", format: .markdown, syntax: .markdown))
        recorder.reset()
        #expect(host.window.makeFirstResponder(host.textView))
        #expect(host.press("1", chord))
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(recorder.layouts.first?.mode == .source && recorder.layouts.first?.sourceIsVisible == true)
        #expect(host.announcements.texts == [PreviewStrings.text(.previewModeSource)])
        #expect(host.press("1", chord))
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(host.announcements.texts.count == 1)

        try select(.contents, in: host.view)
        recorder.reset()
        host.announcements.texts.removeAll()
        let contents = try #require(host.view.contentView(for: .contents) as? any SafeModeContentView)
        contents.navigate?(.rendered, NSRange(location: 0, length: 5))
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(recorder.layouts.first?.mode == .rendered && recorder.layouts.first?.sourceIsVisible == true)
        #expect(host.announcements.texts == [PreviewStrings.text(.previewModeRendered)])
        #expect((host.textView.string as NSString).substring(with: host.textView.selectedRange()) == "Alpha")
        #expect(host.window.firstResponder === host.textView)
    }

    @Test func visibleStateChangesAndRecoveryPublishAfterTheNewHierarchyIsInstalled() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let recorder = ChromeLayoutRecorder(view: host.view)
        let states: [(PreviewOutcome, NativeStateContent.Kind)] = [
            (.unavailable(.missingFile), .unavailable(.missingFile)),
            (.disabledByUser(.json), .disabled),
            (.ready(plainPresentation("")), .empty)
        ]
        for (index, item) in states.enumerated() {
            host.view.display(item.0, locale: english)
            expectLayouts(recorder, from: host.view, count: index + 1)
            let post = try #require(recorder.layouts.last)
            #expect(post.state == item.1 && post.stateIsVisible && !post.sourceIsVisible && !post.outlineIsVisible)
            host.view.display(item.0, locale: english)
            expectLayouts(recorder, from: host.view, count: index + 1)
        }
        host.view.showSettingsUnavailable()
        host.view.showSettingsUnavailable()
        expectLayouts(recorder, from: host.view, count: 4)
        #expect(recorder.layouts.last?.state == .settingsUnavailable)
        host.view.showSettingsConfigurationUnavailable()
        expectLayouts(recorder, from: host.view, count: 5)
        #expect(recorder.layouts.last?.state == .configurationUnavailable)
        host.show(plainPresentation("ready"))
        expectLayouts(recorder, from: host.view, count: 6)
        let ready = try #require(recorder.layouts.last)
        #expect(ready.state == nil && !ready.stateIsVisible && ready.sourceIsVisible)
        #expect(host.textView.string == "ready")
    }

    @Test func loadingPublishesOnlyWhenTheGracePeriodRevealsItAndRecoveryPublishesOnce() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        let recorder = ChromeLayoutRecorder(view: host.view)
        host.view.showLoading()
        host.view.showLoading()
        expectLayouts(recorder, from: host.view, count: 0)
        #expect(!host.view.stateView.isRevealed && scheduler.waiting.count == 1)
        let pending = try #require(scheduler.waiting.first)
        #expect(pending.delay == PreviewChrome.spinnerDelay)
        scheduler.runWaiting()
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(recorder.layouts.first?.state == .loading && recorder.layouts.first?.stateIsVisible == true)
        #expect(host.announcements.texts.count == 1)
        host.view.showLoading()
        scheduler.runWaiting()
        expectLayouts(recorder, from: host.view, count: 1)
        host.show(plainPresentation("ready"))
        expectLayouts(recorder, from: host.view, count: 2)
        #expect(recorder.layouts.last?.state == nil && recorder.layouts.last?.sourceIsVisible == true)
        pending.runIgnoringCancellation()
        expectLayouts(recorder, from: host.view, count: 2)
        #expect(host.announcements.texts.count == 1)
    }

    @Test func cancelledLoadingGraceAndLateTimersCannotPublishAHiddenOrStaleState() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        let recorder = ChromeLayoutRecorder(view: host.view)
        let presentation = plainPresentation("ready")
        host.show(presentation)
        recorder.reset()
        host.view.showLoading()
        let pending = try #require(scheduler.waiting.first)
        host.show(presentation)
        expectLayouts(recorder, from: host.view, count: 0)
        pending.runIgnoringCancellation()
        expectLayouts(recorder, from: host.view, count: 0)
        #expect(host.view.stateContent == nil && host.view.stateView.isHidden)

        host.view.showLoading()
        let replaced = try #require(scheduler.waiting.first)
        host.view.display(.unavailable(.missingFile))
        expectLayouts(recorder, from: host.view, count: 1)
        replaced.runIgnoringCancellation()
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(recorder.layouts.first?.state == .unavailable(.missingFile))
        #expect(host.announcements.texts.count == 1)
    }

    @Test func cancellationChangesVisibleStructureWithoutSpeakingAndDoesNotRepeat() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let recorder = ChromeLayoutRecorder(view: host.view)
        host.show(plainPresentation("ready"))
        recorder.reset()
        host.view.display(.cancelled)
        expectLayouts(recorder, from: host.view, count: 1)
        let cancelled = try #require(recorder.layouts.first)
        #expect(cancelled.state == NativeStateContent.cancelled().kind && cancelled.stateIsVisible)
        #expect(!cancelled.sourceIsVisible && host.announcements.texts.isEmpty)
        host.view.display(.cancelled)
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(host.announcements.texts.isEmpty)
    }

    @Test func changingOfferedModesPublishesTheNewControlEvenWhenTheSelectedModeStaysSource() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let recorder = ChromeLayoutRecorder(view: host.view)
        host.show(plainPresentation("words"))
        #expect(host.view.modeControl.isHidden)
        recorder.reset()
        host.show(plainPresentation(json, format: .json, syntax: .json), resetsContentState: true)
        expectLayouts(recorder, from: host.view, count: 1)
        let post = try #require(recorder.layouts.first)
        #expect(post.mode == .source && post.modes == [.source, .outline])
        #expect(!host.view.modeControl.isHidden && post.sourceIsVisible)
        host.show(plainPresentation(#"{"items":[3,4]}"#, format: .json, syntax: .json))
        expectLayouts(recorder, from: host.view, count: 1)
        #expect(host.announcements.texts.isEmpty)
    }

    @Test func liveReloadRestyleAndResizeDoNotPublishUnchangedStructure() {
        let host = InteractionHarness()
        defer { host.release() }
        let recorder = ChromeLayoutRecorder(view: host.view)
        host.show(plainPresentation(json, format: .json, syntax: .json))
        recorder.reset()
        host.show(plainPresentation(json, format: .json, syntax: .json))
        host.view.display(.ready(plainPresentation(#"{"items":[3,4]}"#, format: .json, syntax: .json)),
                          typography: .init(fontSize: 20, showsLineNumbers: true), theme: .dark)
        host.view.setFrameSize(NSSize(width: 580, height: 400))
        host.view.layoutSubtreeIfNeeded()
        expectLayouts(recorder, from: host.view, count: 0)
        #expect(host.announcements.texts.isEmpty && host.view.selectedMode == .source)
    }
}

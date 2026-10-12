import AppKit
import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Uses the existing provisional density constants. This is off-screen AppKit proof, not Finder measurement.
@Suite("Q55 compact chrome integration", .serialized)
@MainActor
struct Q55CompactChromeTests {
    private let english = Locale(identifier: "en_US")
    private var low: CGFloat { PreviewChrome.compactWidth - PreviewChrome.compactHysteresis }
    private var high: CGFloat { PreviewChrome.compactWidth + PreviewChrome.compactHysteresis }
    private let json = #"{"items":[1,2,3],"name":"safe"}"#

    @Test func compactChoosesTheMenuBeforeFirstLayoutAndKeepsTheFactsInOneRow() throws {
        let host = InteractionHarness(width: low - 1)
        defer { host.release() }
        host.view.display(.ready(plainPresentation(json, format: .json, syntax: .json)), locale: english,
            resetsContentState: true)
        #expect(host.view.density == .compact)
        #expect(host.view.visibleModeControl === host.view.modePullDown)
        #expect(host.view.modeControl.isHidden && !host.view.modePullDown.isHidden)
        host.view.layoutSubtreeIfNeeded()
        let menu = try #require(host.view.modePullDown.menu)
        #expect(menu.items.filter { $0.action != nil }.map(\.title) == host.view.displayedModes.map {
            PreviewStrings.text($0.title)
        })
        #expect(host.view.displayedFacts.count == 2)
        let row = host.view.headerGuide.frame
        let facts = host.view.convert(host.view.factsLabel.bounds, from: host.view.factsLabel)
        let modes = host.view.convert(host.view.modePullDown.bounds, from: host.view.modePullDown)
        #expect(row.height > 0 && row.height <= PreviewChrome.headerHeight)
        #expect(facts.minY >= row.minY && facts.maxY <= row.maxY)
        #expect(modes.minY >= row.minY && modes.maxY <= row.maxY)
        #expect(facts.maxX <= modes.minX)
        #expect(!host.view.hasAmbiguousLayout && !host.view.modePullDown.hasAmbiguousLayout)
        #expect(host.view.navigationOrderViews.contains { $0 === host.view.modePullDown })
        #expect(!host.view.navigationOrderViews.contains { $0 === host.view.modeControl })
        let order = host.view.navigationOrderViews
        let controlIndex = try #require(order.firstIndex { $0 === host.view.modePullDown })
        let contentIndex = try #require(order.firstIndex { $0 === host.view.scrollView })
        #expect(controlIndex < contentIndex)
    }

    @Test func menuAndKeyboardReachTheSameModesAndResizeDoesNotReselect() throws {
        let host = InteractionHarness(width: low - 1)
        defer { host.release() }
        show(plainPresentation(json, format: .json, syntax: .json), in: host.view)
        let offered = host.view.displayedModes
        let outlineIndex = try #require(offered.firstIndex(of: .outline))
        let menu = try #require(host.view.modePullDown.menu)
        menu.performActionForItem(at: outlineIndex + 1)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.selectedMode == .outline && !host.view.outlineView.isHidden)
        #expect(host.view.modePullDown.accessibilityValue() as? String == PreviewStrings.text(.previewModeOutline))
        #expect(host.view.modeControl.selectedSegment == outlineIndex)
        host.announcements.texts.removeAll()
        #expect(host.press("1", [.option, .command]))
        #expect(host.view.selectedMode == offered[0] && !host.textView.isHidden)
        #expect(host.view.modePullDown.menu?.items.filter { $0.state == .on }.map(\.tag) == [0])
        #expect(host.announcements.texts == [PreviewStrings.text(.previewModeSource)])
        host.announcements.texts.removeAll()
        resize(host.view, to: high)
        #expect(host.view.visibleModeControl === host.view.modeControl && host.view.modePullDown.isHidden)
        #expect(host.view.displayedModes == offered && host.view.selectedMode == .source)
        #expect(host.announcements.texts.isEmpty)
        host.view.modeControl.selectedSegment = outlineIndex
        #expect(host.view.modeControl.sendAction(host.view.modeControl.action, to: host.view.modeControl.target))
        resize(host.view, to: low - 1)
        #expect(host.view.selectedMode == .outline && host.view.displayedModes == offered)
        #expect(host.view.modePullDown.menu?.items.filter { $0.state == .on }.map(\.tag) == [outlineIndex])
    }

    @Test func gutterHidesOnResizeAndReturnsWithoutChangingPreferenceSelectionOrSafeText() {
        let host = InteractionHarness(width: high + 30)
        defer { host.release() }
        let safe = numberedLines(100)
        let typography = PreviewTypography(showsLineNumbers: true)
        show(plainPresentation(safe), in: host.view, typography: typography)
        let gutter = host.view.lineNumberGutter
        let text = host.textView
        #expect(!gutter.isHidden && gutter.bounds.width > 0)
        text.setSelectedRange(NSRange(location: 12, length: 8))
        let selection = text.selectedRange()
        host.view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 160))
        let origin = host.view.scrollView.contentView.bounds.origin
        let font = text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        resize(host.view, to: low - 1)
        #expect(gutter.isHidden && gutter.bounds.width == 0)
        #expect(text.string == safe && text.selectedRange() == selection)
        #expect(host.view.scrollView.contentView.bounds.origin == origin)
        #expect(!host.view.navigationOrderViews.contains { $0 === gutter })
        #expect(host.view.displayedFacts.count == 2)
        resize(host.view, to: high)
        #expect(!gutter.isHidden && gutter.bounds.width == gutter.requiredWidth)
        #expect(text.string == safe && text.selectedRange() == selection)
        #expect(host.view.scrollView.contentView.bounds.origin == origin)
        #expect((text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == font)
        host.view.forcedDensity = .compact
        show(plainPresentation(safe), in: host.view, typography: typography)
        #expect(gutter.isHidden && gutter.bounds.width == 0, "Restyling must honor compact density")
        host.view.forcedDensity = .regular
        host.view.layoutSubtreeIfNeeded()
        #expect(!gutter.isHidden)
        show(plainPresentation(safe), in: host.view, typography: PreviewTypography(showsLineNumbers: false))
        resize(host.view, to: high + 50)
        #expect(gutter.isHidden && gutter.bounds.width == 0, "Density must never turn on a disabled preference")
    }

    @Test func densityDoesNotReparseSourceOrComputeProfileAndForcedSamplesStayRegular() {
        let recorder = Q55StageRecorder()
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: high + 30, height: 420),
            stageObserver: recorder.observer)
        let csv = plainPresentation("name,value\na,1\nb,2\n", format: .csv, syntax: .commaSeparated)
        show(csv, in: view)
        #expect(!view.dataProfileIsComputed)
        let offered = view.displayedModes
        let selected = view.selectedMode
        recorder.reset()
        resize(view, to: low - 1)
        resize(view, to: PreviewChrome.compactWidth)
        #expect(view.density == .compact && view.visibleModeControl === view.modePullDown)
        resize(view, to: high)
        #expect(view.density == .regular && view.visibleModeControl === view.modeControl)
        #expect(!view.dataProfileIsComputed && view.displayedModes == offered && view.selectedMode == selected)
        for stage in [PreviewMeasurementStage.modes, .tokens, .lineIndex, .storage] {
            #expect(recorder.counts(for: stage).isEmpty, "Density must only change native chrome and text geometry")
        }
        view.forcedDensity = .regular
        resize(view, to: low - 30)
        #expect(view.density == .regular && view.visibleModeControl === view.modeControl)
        #expect(!view.modeControl.isHidden && view.modePullDown.isHidden && !view.dataProfileIsComputed)
    }

    @Test func changingDensityPreservesContentFocusAndLeavesNoHiddenControlFocused() throws {
        let host = InteractionHarness(width: high + 30)
        defer { host.release() }
        show(plainPresentation(json, format: .json, syntax: .json), in: host.view)
        #expect(host.window.makeFirstResponder(host.textView))
        #expect(host.window.firstResponder === host.textView)
        resize(host.view, to: low - 1)
        #expect(host.window.firstResponder === host.textView)
        #expect(host.window.makeFirstResponder(host.view.modePullDown))
        #expect(host.window.firstResponder === host.view.modePullDown)
        resize(host.view, to: high)
        #expect(host.window.firstResponder === host.view.modeControl)
        #expect(host.window.firstResponder !== host.view.modePullDown)
        resize(host.view, to: low - 1)
        #expect(host.window.firstResponder === host.view.modePullDown)
        host.view.showLoading()
        #expect(host.view.visibleModeControl == nil)
        #expect(host.window.firstResponder !== host.view.modePullDown)
        #expect(host.window.firstResponder !== host.view.modeControl)
    }

    @Test func aSingleModeAndNoContentClearBothControlsAndTheirMetadata() {
        let host = InteractionHarness(width: low - 1)
        defer { host.release() }
        show(plainPresentation(json, format: .json, syntax: .json), in: host.view)
        show(plainPresentation("one safe mode"), in: host.view)
        #expect(host.view.visibleModeControl == nil)
        #expect(host.view.modePullDown.isHidden && host.view.modeControl.isHidden)
        show(plainPresentation(json, format: .json, syntax: .json), in: host.view)
        host.view.showLoading()
        #expect(host.view.visibleModeControl == nil && host.view.modePullDown.menu == nil)
        #expect(((host.view.modePullDown.accessibilityValue() as? String) ?? "").isEmpty)
        #expect(!host.view.navigationOrderViews.contains { $0 === host.view.modePullDown || $0 === host.view.modeControl })
    }

    private func show(_ presentation: TextPresentation, in view: NativePreviewView, typography: PreviewTypography = .init()) {
        view.display(.ready(presentation), typography: typography, locale: english, resetsContentState: true)
        view.layoutSubtreeIfNeeded()
    }

    private func resize(_ view: NativePreviewView, to width: CGFloat) {
        view.setFrameSize(NSSize(width: width, height: 420))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }
}

private final class Q55StageRecorder: Sendable {
    private let values = Mutex<[PreviewStageObservation]>([])
    var observer: PreviewStageObserver {
        PreviewStageObserver { [self] observation in values.withLock { $0.append(observation) } }
    }
    func reset() { values.withLock { $0.removeAll(keepingCapacity: true) } }
    func counts(for stage: PreviewMeasurementStage) -> [Int] {
        values.withLock { $0.filter { $0.stage == stage }.map(\.count) }
    }
}

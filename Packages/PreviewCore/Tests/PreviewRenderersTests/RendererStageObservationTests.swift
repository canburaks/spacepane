import AppKit
import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewRenderers

private final class RendererStageRecorder: Sendable {
    private let values = Mutex<[PreviewStageObservation]>([])

    var observer: PreviewStageObserver {
        PreviewStageObserver { [self] value in values.withLock { $0.append(value) } }
    }

    func snapshot() -> [PreviewStageObservation] { values.withLock { $0 } }
    func reset() { values.withLock { $0.removeAll(keepingCapacity: true) } }
    func counts(for stage: PreviewMeasurementStage) -> [Int] {
        snapshot().filter { $0.stage == stage }.map(\.count)
    }
}

@MainActor
private final class RendererLayoutPassCounter: NSObject, @preconcurrency NSLayoutManagerDelegate {
    private(set) var completedPasses = 0

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?,
                       atEnd layoutFinishedFlag: Bool) {
        if layoutFinishedFlag { completedPasses += 1 }
    }
}

@Suite("Optional renderer stage observation", .serialized)
@MainActor
struct RendererStageObservationTests {
    private let frame = NSRect(x: 0, y: 0, width: 600, height: 300)

    private func value(_ source: String, format: FormatID = .plainText, syntax: TextSyntax = .plain) -> TextPresentation {
        .init(formatID: format, text: source, lineCount: 2, byteCount: 128, encoding: .utf8,
              redactionCount: 0, syntax: syntax)
    }

    private func show(_ source: String, in view: NativePreviewView, syntax: TextSyntax = .plain,
                      typography: PreviewTypography = .init(), theme: PreviewTheme = .system) {
        view.display(.ready(value(source, syntax: syntax)), typography: typography, theme: theme)
        view.layoutSubtreeIfNeeded()
    }

    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        view.modeControl.selectedSegment = try #require(view.displayedModes.firstIndex(of: mode))
        #expect(view.modeControl.sendAction(view.modeControl.action, to: view.modeControl.target))
        view.layoutSubtreeIfNeeded()
    }

    @Test func anInitialSourceGenerationMeasuresOnlyActualWorkWithItsOwnCounts() throws {
        let recorder = RendererStageRecorder()
        let view = NativePreviewView(frame: frame, stageObserver: recorder.observer)
        let source = #"{"a":1}"#
        let before = ContinuousClock.now
        show(source, in: view, syntax: .json)
        let after = ContinuousClock.now

        // This fixture offers Source and Outline, has two syntax tokens and one logical line. Storage and
        // styling count UTF-16 units; layout counts glyphs in the actual TextKit stack, not the source's bytes.
        #expect(view.displayedModes == [.source, .outline] && view.selectedMode == .source)
        #expect(recorder.counts(for: .modes) == [2])
        #expect(recorder.counts(for: .tokens) == [2])
        #expect(recorder.counts(for: .lineIndex) == [1])
        #expect(recorder.counts(for: .storage) == [7])
        #expect(recorder.counts(for: .styling) == [7])
        #expect(recorder.counts(for: .layout) == [try #require(view.textView.layoutManager).numberOfGlyphs])
        #expect(Set(recorder.snapshot().map(\.stage)) == [.modes, .tokens, .lineIndex, .storage, .styling, .layout])
        #expect(recorder.snapshot().allSatisfy {
            $0.duration >= .zero && $0.startedAt >= before && $0.startedAt.advanced(by: $0.duration) <= after
        })
    }

    @Test func repeatedContentAndAppearanceRestyleDoNotRebuildTheGeneration() throws {
        let recorder = RendererStageRecorder()
        let view = NativePreviewView(frame: frame, stageObserver: recorder.observer)
        let source = "safe words\nsecond line"
        show(source, in: view)
        recorder.reset()

        show(source, in: view)
        for stage in [PreviewMeasurementStage.modes, .tokens, .lineIndex, .storage] {
            #expect(recorder.counts(for: stage).isEmpty)
        }
        #expect(recorder.counts(for: .styling) == [source.utf16.count])
        #expect(recorder.counts(for: .layout) == [try #require(view.textView.layoutManager).numberOfGlyphs])
        recorder.reset()

        let manager = try #require(view.textView.layoutManager)
        try #require(manager.delegate == nil)
        let layoutCounter = RendererLayoutPassCounter()
        manager.delegate = layoutCounter
        defer { manager.delegate = nil }
        show(source, in: view, typography: .init(fontSize: 20, showsLineNumbers: true), theme: .dark)
        for stage in [PreviewMeasurementStage.modes, .tokens, .lineIndex, .storage] {
            #expect(recorder.counts(for: stage).isEmpty)
        }
        #expect(recorder.counts(for: .styling) == [source.utf16.count])
        // This also activates a gutter whose width changes the existing viewport. Preserve and count that work
        // rather than imposing the one-pass guarantee of the separate initial-layout and cached-layout cases.
        // An ordinary host follows the same pre-measurement path and independently checks the pass count.
        let ordinary = NativePreviewView(frame: frame)
        show(source, in: ordinary)
        show(source, in: ordinary)
        let ordinaryManager = try #require(ordinary.textView.layoutManager)
        try #require(ordinaryManager.delegate == nil)
        let ordinaryCounter = RendererLayoutPassCounter()
        ordinaryManager.delegate = ordinaryCounter
        defer { ordinaryManager.delegate = nil }
        show(source, in: ordinary, typography: .init(fontSize: 20, showsLineNumbers: true), theme: .dark)
        #expect(layoutCounter.completedPasses > 0)
        #expect(layoutCounter.completedPasses == ordinaryCounter.completedPasses)

        let observedLayoutCounts = recorder.counts(for: .layout)
        let expectedLayoutCounts = Array(repeating: manager.numberOfGlyphs, count: layoutCounter.completedPasses)
        #expect(observedLayoutCounts == expectedLayoutCounts,
                "Completed TextKit passes: \(layoutCounter.completedPasses); viewport: \(view.scrollView.contentSize)")
        #expect(view.textView.string.utf16.elementsEqual(source.utf16))
    }

    @Test func anExactUnicodeReplacementGetsOneFreshGenerationWithCurrentCounts() throws {
        let recorder = RendererStageRecorder()
        let view = NativePreviewView(frame: frame, stageObserver: recorder.observer)
        let composed = "safe caf\u{00e9}\nsecond"
        let decomposed = "safe cafe\u{0301}\nsecond"
        #expect(composed == decomposed && !composed.utf16.elementsEqual(decomposed.utf16))
        show(composed, in: view)
        let storage = try #require(view.textView.textStorage)
        recorder.reset()

        show(decomposed, in: view)
        #expect(recorder.counts(for: .modes) == [1])
        #expect(recorder.counts(for: .tokens) == [0])
        #expect(recorder.counts(for: .lineIndex) == [2])
        #expect(recorder.counts(for: .storage) == [decomposed.utf16.count])
        #expect(recorder.counts(for: .styling) == [decomposed.utf16.count])
        #expect(recorder.counts(for: .layout) == [try #require(view.textView.layoutManager).numberOfGlyphs])
        #expect(view.textView.textStorage === storage && storage.string.utf16.elementsEqual(decomposed.utf16))
    }

    @Test func cachedLayoutDoesNotPublishAnotherMeasurement() {
        let recorder = RendererStageRecorder()
        let view = NativePreviewView(frame: frame, stageObserver: recorder.observer)
        show("safe words\nsecond line", in: view)
        #expect(recorder.counts(for: .layout).count == 1)
        recorder.reset()

        // Invoke the facade's layout path itself, rather than merely relying on no pending AppKit invalidation.
        view.layout()
        view.layout()
        view.layoutSubtreeIfNeeded()
        #expect(recorder.snapshot().isEmpty)
    }

    @Test func hiddenReplacementClearsOldStorageWithoutMaterializingOrStylingNewSource() throws {
        let recorder = RendererStageRecorder()
        let view = NativePreviewView(frame: frame, stageObserver: recorder.observer)
        let old = #"{"entries":[{"path":"safe-old","type":"file"}]}"#
        let new = #"{"entries":[{"path":"safe-new","type":"file"}]}"#
        view.display(.ready(value(old, format: .folder, syntax: .json)))
        try select(.source, in: view)
        #expect(view.textView.string == old)
        try select(.files, in: view)
        recorder.reset()

        view.display(.ready(value(new, format: .folder, syntax: .json)), resetsContentState: true)
        view.layoutSubtreeIfNeeded()
        #expect(view.textView.isHiddenOrHasHiddenAncestor && view.textView.string.isEmpty)
        #expect(recorder.counts(for: .modes) == [view.displayedModes.count])
        #expect(recorder.counts(for: .lineIndex) == [0])
        #expect(recorder.counts(for: .storage) == [0])
        for stage in [PreviewMeasurementStage.tokens, .styling, .layout] {
            #expect(recorder.counts(for: stage).isEmpty)
        }
        recorder.reset()

        try select(.source, in: view)
        #expect(recorder.counts(for: .modes).isEmpty)
        #expect(recorder.counts(for: .lineIndex) == [1])
        #expect(recorder.counts(for: .storage) == [new.utf16.count])
        #expect(recorder.counts(for: .tokens).count == 1)
        #expect(recorder.counts(for: .styling) == [new.utf16.count])
        #expect(!recorder.counts(for: .layout).isEmpty)
        #expect(view.textView.string.utf16.elementsEqual(new.utf16))
    }

    @Test func nilAndMeasuredHostsKeepTheSameSafeTextStylingAndReadingState() throws {
        let recorder = RendererStageRecorder()
        let measured = NativePreviewView(frame: frame, stageObserver: recorder.observer)
        let ordinary = NativePreviewView(frame: frame, stageObserver: nil)
        let source = "safe cafe\u{0301} text\nsecond line"
        for view in [measured, ordinary] {
            show(source, in: view, typography: .init(showsLineNumbers: true))
            view.textView.setSelectedRange(NSRange(location: 5, length: 5))
            show(source, in: view, typography: .init(fontSize: 18, showsLineNumbers: true), theme: .dark)
        }
        #expect(measured.textView.string.utf16.elementsEqual(ordinary.textView.string.utf16))
        #expect(measured.textView.selectedRange() == ordinary.textView.selectedRange())
        #expect(measured.displayedModes == ordinary.displayedModes && measured.selectedMode == ordinary.selectedMode)
        #expect(measured.lineNumberGutter.lineIndex == ordinary.lineNumberGutter.lineIndex)
        let measuredStorage = try #require(measured.textView.textStorage)
        let ordinaryStorage = try #require(ordinary.textView.textStorage)
        #expect(measuredStorage.isEqual(to: ordinaryStorage))
        #expect(measured.textView.frame.size == ordinary.textView.frame.size)
    }
}

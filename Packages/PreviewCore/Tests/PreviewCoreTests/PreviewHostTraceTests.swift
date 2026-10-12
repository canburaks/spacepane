import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Privacy-safe host lifecycle telemetry")
struct PreviewHostTraceTests {
    @Test func typedLifecycleEndsOnceAndContainsOnlyDiagnosticValues() {
        let events = Mutex<[PreviewHostEvent]>([])
        let trace = PreviewHostTrace(surface: .preview, geometry: .init(width: 640, height: 480),
                                     record: { event in events.withLock { $0.append(event) } })
        trace.settings(.loaded)
        trace.finish(.ready, geometry: .init(width: 800, height: 600))
        trace.finish(.cancelled)
        trace.settings(.unavailable)
        let recorded = events.withLock { $0 }
        #expect(recorded.count == 3)
        #expect(recorded[0].phase == .started && recorded[0].surface == .preview)
        #expect(recorded[0].geometry == .init(width: 640, height: 480))
        #expect(recorded[1].settings == .loaded)
        #expect(recorded[2].phase == .finished && recorded[2].outcome == .ready)
        #expect(recorded[2].geometry == .init(width: 800, height: 600))
        #expect(recorded[2].elapsedMilliseconds >= 0)
        #expect(Set(recorded.map(\.requestID)).count == 1)
    }

    @Test func concurrentCompletionStillRecordsOneTerminalEvent() async {
        let events = Mutex<[PreviewHostEvent]>([])
        let trace = PreviewHostTrace(surface: .thumbnail, record: { event in events.withLock { $0.append(event) } })
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<64 { group.addTask { trace.finish(.cancelled) } }
        }
        #expect(events.withLock { $0.filter { $0.phase == .finished }.count } == 1)
    }

    @Test func geometryRejectsNonFiniteAndOutOfRangeValues() {
        #expect(PreviewHostGeometry(width: .nan, height: 480) == nil)
        #expect(PreviewHostGeometry(width: 640, height: .infinity) == nil)
        #expect(PreviewHostGeometry(width: -1, height: 480) == nil)
        #expect(PreviewHostGeometry(width: 100_000_000, height: 480) == nil)
        #expect(PreviewHostGeometry(width: 640.25, height: 480.75)?.width == 640)
    }

    @Test func outcomesDoNotRetainSourceOrErrorDescriptions() {
        let source = TextPresentation(formatID: .plainText, text: "synthetic-source-canary", lineCount: 1,
                                      byteCount: 23, encoding: .utf8, redactionCount: 0)
        #expect(PreviewHostOutcome(.ready(source)) == .ready)
        #expect(PreviewHostOutcome(.disabledByUser(.plainText)) == .disabled)
        #expect(PreviewHostOutcome(.unavailable(.deadlineExceeded)) == .timedOut)
        #expect(PreviewHostOutcome(.unavailable(.unreadableFile)) == .unavailable)
        #expect(PreviewHostOutcome(.cancelled) == .cancelled)
    }
}

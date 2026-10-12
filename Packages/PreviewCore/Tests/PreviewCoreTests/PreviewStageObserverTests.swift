import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore

private final class StageReadProbe: PreviewFileReading, Sendable {
    let reads = Mutex(0)
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.withLock { $0 += 1 }
        return FileBytes(data: Data("ordinary synthetic text".utf8))
    }
}

private struct StageTextAdapter: BinaryFormatAdapter {
    func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: String(decoding: input.data, as: UTF8.self))
    }
}

@Suite("Optional pipeline stage observation")
struct PreviewStageObserverTests {
    private let url = URL(fileURLWithPath: "/unused/stage.txt")

    private func pipeline(reader: StageReadProbe = StageReadProbe(), observer: PreviewStageObserver? = nil) -> PreviewPipeline {
        PreviewPipeline(registrations: [.init(formatID: .plainText, binaryAdapter: { StageTextAdapter() })],
                        reader: reader, stageObserver: observer)
    }

    @Test func onePipelineExecutionHasOneMonotonicInterval() async throws {
        let observations = Mutex<[PreviewStageObservation]>([])
        let service = pipeline(observer: PreviewStageObserver { value in observations.withLock { $0.append(value) } })
        let before = ContinuousClock.now
        let result = await service.previewResult(url: url)
        let after = ContinuousClock.now
        guard case .ready = result.outcome else { Issue.record("Expected ready text"); return }
        let recorded = observations.withLock { $0 }
        #expect(recorded.count == 1)
        let value = try #require(recorded.first)
        #expect(value.stage == .pipeline)
        #expect(value.count == 1)
        #expect(value.duration >= .zero)
        #expect(value.startedAt >= before)
        #expect(value.startedAt.advanced(by: value.duration) <= after)
    }

    @Test func observingDoesNotChangePolicyContentOrSourceReads() async {
        let observedReads = StageReadProbe(), ordinaryReads = StageReadProbe()
        let observations = Mutex<[PreviewStageObservation]>([])
        let observer = PreviewStageObserver { value in observations.withLock { $0.append(value) } }
        let measured = await pipeline(reader: observedReads, observer: observer).previewResult(url: url)
        let ordinary = await pipeline(reader: ordinaryReads).previewResult(url: url)
        #expect(measured == ordinary)
        #expect(observedReads.reads.withLock { $0 } == 1)
        #expect(ordinaryReads.reads.withLock { $0 } == 1)
        #expect(observations.withLock { $0.count } == 1)
    }

    @Test func earlyPolicyOutcomesAreMeasuredWithoutReading() async {
        let reader = StageReadProbe()
        let observations = Mutex<[PreviewStageObservation]>([])
        let service = pipeline(reader: reader, observer: PreviewStageObserver { value in observations.withLock { $0.append(value) } })
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .plainText)
        #expect(await service.previewResult(url: url, preferences: preferences).outcome == .disabledByUser(.plainText))
        #expect(await service.previewResult(url: url, budget: PreviewBudget(maxInputBytes: -1)).outcome == .unavailable(.invalidBudget))
        #expect(reader.reads.withLock { $0 } == 0)
        let recorded = observations.withLock { $0 }
        #expect(recorded.count == 2)
        #expect(recorded.allSatisfy { $0.stage == .pipeline && $0.count == 1 })
    }

    @Test func legacyOutcomeEntryPointDoesNotDoubleRecord() async {
        let observations = Mutex<[PreviewStageObservation]>([])
        let service = pipeline(observer: PreviewStageObserver { value in observations.withLock { $0.append(value) } })
        _ = await service.preview(url: url)
        #expect(observations.withLock { $0.count } == 1)
    }

    @Test func aCancelledExecutionFinishesItsObservation() async {
        let reader = StageReadProbe()
        let observations = Mutex<[PreviewStageObservation]>([])
        let service = pipeline(reader: reader, observer: PreviewStageObserver { value in observations.withLock { $0.append(value) } })
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await service.previewResult(url: url)
        }
        #expect(await task.value.outcome == .cancelled)
        #expect(reader.reads.withLock { $0 } == 0)
        #expect(observations.withLock { $0.count } == 1)
    }

    @Test func intervalCompletionIsIdempotentAndInvalidCountsAreNotPublished() {
        let observations = Mutex<[PreviewStageObservation]>([])
        let observer = PreviewStageObserver { value in observations.withLock { $0.append(value) } }
        let interval = observer.begin(.layout)
        interval.finish(count: 3)
        interval.finish(count: 99)
        #expect(observations.withLock { $0.map(\.count) } == [3])
        observer.begin(.tokens).finish(count: -1)
        observer.begin(.tokens).finish(count: PreviewStageObservation.maximumCount + 1)
        #expect(observations.withLock { $0.count } == 1)
    }

    @Test func observationRejectsNegativeDurationOrOutOfRangeWorkCount() {
        let start = ContinuousClock.now
        #expect(PreviewStageObservation(stage: .storage, startedAt: start, duration: .nanoseconds(-1), count: 1) == nil)
        #expect(PreviewStageObservation(stage: .storage, startedAt: start, duration: .zero, count: -1) == nil)
        #expect(PreviewStageObservation(stage: .storage, startedAt: start, duration: .zero,
                                       count: PreviewStageObservation.maximumCount + 1) == nil)
        #expect(PreviewStageObservation(stage: .storage, startedAt: start, duration: .zero, count: 0)?.count == 0)
    }
}

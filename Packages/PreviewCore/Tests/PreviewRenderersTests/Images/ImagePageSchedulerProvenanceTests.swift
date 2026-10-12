import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Image scheduler request provenance", .serialized)
@MainActor
struct ImagePageSchedulerProvenanceTests {
    private func request(_ index: Int, side: Int = 200) -> ImagePageScheduler.Request {
        .init(index: index, maximumPixelSize: side,
              image: PreviewImage(data: Data([1, 2, 3]), pixelWidth: 100, pixelHeight: 140, role: .page))
    }

    @Test func observationPrecedesQueueProcessingAndTaskExecution() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        var events: [ImagePageScheduler.SchedulingEvent] = []
        scheduler.observeScheduling = { [weak scheduler] event in
            events.append(event)
            switch event {
            case .wanted:
                #expect(scheduler?.runningCount == 0 && scheduler?.pendingCount == 0)
                #expect(probe.started == 0)
            case .started:
                // Initial callback is synchronous, before the Task can execute the decoder.
                if events.count == 2 { #expect(probe.started == 0) }
            case .cancelRequested, .finished: break
            }
        }
        let first = request(0), second = request(1)
        scheduler.want([first, second])
        try #require(events.count == 2)
        #expect(events.first == .wanted([first, second]))
        if let last = events.last, case .started(_, let actual) = last { #expect(actual == first) }
        else { Issue.record("Initial request did not emit started") }
        await probe.waitForStarted(1)
        probe.open()
        await deliveries.waitForCount(2)
        await probe.waitForFinished(2)
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
    }

    @Test func overlappingIdenticalPayloadsUseTheirOwnGenerationIdentity() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let observed = Mutex<[UUID: Int]>([:])
        let decoded = Mutex<[UUID: Int]>([:])
        let fallbackCalls = Mutex(0)
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: { _, _ in
            fallbackCalls.withLock { $0 += 1 }; return nil
        }, scheduledDecode: { request, generation in
            #expect(observed.withLock { $0[generation] } == request.index)
            decoded.withLock { $0[generation] = request.index }
            return await probe.run()
        })
        scheduler.observeScheduling = { event in
            if case .started(let generation, let request) = event {
                observed.withLock { $0[generation] = request.index }
            }
        }
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want([request(0), request(1)])
        try #require(observed.withLock { $0.count } == 2)
        await probe.waitForStarted(2)
        #expect(observed.withLock { $0.count } == 2)
        #expect(decoded.withLock { $0 } == observed.withLock { $0 })
        #expect(probe.maximumConcurrent == 2 && fallbackCalls.withLock { $0 } == 0)
        probe.open()
        await deliveries.waitForCount(2)
        await probe.waitForFinished(2)
        #expect(deliveries.indices.sorted() == [0, 1])
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
    }

    @Test func sameIndexReplacementRetainsDistinctGenerations() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let observed = Mutex<[UUID: Int]>([:])
        let decoded = Mutex<[UUID: Int]>([:])
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, scheduledDecode: { request, generation in
            #expect(observed.withLock { $0[generation] } == request.maximumPixelSize)
            decoded.withLock { $0[generation] = request.maximumPixelSize }
            return await probe.run()
        })
        scheduler.observeScheduling = { event in
            if case .started(let generation, let request) = event {
                observed.withLock { $0[generation] = request.maximumPixelSize }
            }
        }
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want([request(0)])
        try #require(observed.withLock { $0.count } == 1)
        await probe.waitForStarted(1)
        scheduler.want([request(0, side: 300)])
        #expect(observed.withLock { $0.count } == 1)
        #expect(scheduler.runningCount == 1 && scheduler.pendingCount == 1)
        probe.open()
        await deliveries.waitForCount(1)
        await probe.waitForFinished(2)
        #expect(observed.withLock { $0.count } == 2)
        #expect(observed.withLock { Set($0.values) } == [200, 300])
        #expect(decoded.withLock { $0 } == observed.withLock { $0 })
        #expect(probe.cancelledFinishes == 1 && deliveries.indices == [0])
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
    }

    @Test func wantedObservesOldQueueAndReprioritizationBeforeProcessing() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        var started: [Int] = []
        var wantedQueueCounts: [Int] = []
        scheduler.observeScheduling = { [weak scheduler] event in
            switch event {
            case .wanted: wantedQueueCounts.append(scheduler?.pendingCount ?? -1)
            case .started(_, let request): started.append(request.index)
            case .cancelRequested, .finished: break
            }
        }
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want([request(0), request(1), request(2)])
        try #require(started == [0])
        await probe.waitForStarted(1)
        scheduler.want([request(0), request(2), request(1)])
        #expect(wantedQueueCounts == [0, 2])
        #expect(started == [0])
        probe.open()
        await deliveries.waitForCount(3)
        await probe.waitForFinished(3)
        #expect(started == [0, 2, 1])
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
    }

    @Test func cancelledQueuedRequestNeverEmitsStartedOrContextualDecode() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let started = Mutex<[UUID: Int]>([:])
        let decoded = Mutex<[UUID: Int]>([:])
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, scheduledDecode: { request, generation in
            #expect(started.withLock { $0[generation] } == request.index)
            decoded.withLock { $0[generation] = request.index }
            return await probe.run()
        })
        scheduler.observeScheduling = { event in
            if case .started(let generation, let request) = event { started.withLock { $0[generation] = request.index } }
        }
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want([request(0), request(1), request(2)])
        try #require(started.withLock { $0.count } == 1)
        await probe.waitForStarted(1)
        scheduler.cancel(1)
        probe.open()
        await deliveries.waitForCount(2)
        await probe.waitForFinished(2)
        #expect(started.withLock { Set($0.values) } == [0, 2])
        #expect(decoded.withLock { $0 } == started.withLock { $0 })
        #expect(deliveries.indices == [0, 2])
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
    }

    @Test func nilInstrumentationPreservesNormalDecodeAndDelivery() async {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let normalCalls = Mutex(0)
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: { _, _ in
            normalCalls.withLock { $0 += 1 }
            return await probe.run()
        })
        #expect(scheduler.observeScheduling == nil)
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want([request(0), request(1)])
        await probe.waitForStarted(1)
        probe.open()
        await deliveries.waitForCount(2)
        await probe.waitForFinished(2)
        #expect(normalCalls.withLock { $0 } == 2 && deliveries.indices == [0, 1])
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
    }
}

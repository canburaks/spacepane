import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewRenderers

@MainActor private final class ImageSchedulerLifecycleEvents {
    private(set) var values: [ImagePageScheduler.SchedulingEvent] = []
    private(set) var callbacks: [(index: Int, hasResult: Bool, finishWasObserved: Bool)] = []
    func record(_ event: ImagePageScheduler.SchedulingEvent) { values.append(event) }
    var starts: [(UUID, ImagePageScheduler.Request)] {
        values.compactMap { if case .started(let id, let request) = $0 { return (id, request) }; return nil }
    }
    var cancellations: [(UUID, ImagePageScheduler.Request, ImagePageScheduler.CancellationReason)] {
        values.compactMap { if case .cancelRequested(let id, let request, let reason) = $0 { return (id, request, reason) }; return nil }
    }
    var finishes: [(UUID, ImagePageScheduler.Request, ImagePageScheduler.FinishObservation)] {
        values.compactMap { if case .finished(let id, let request, let facts) = $0 { return (id, request, facts) }; return nil }
    }
    func callback(_ index: Int, hasResult: Bool) {
        callbacks.append((index, hasResult, finishes.last?.1.index == index && finishes.last?.2.callbackWillInvoke == true))
    }
}

@Suite("Image scheduler cancellation and finish evidence", .serialized)
@MainActor
struct ImagePageSchedulerLifecycleTests {
    private func request(_ index: Int, side: Int = 200) -> ImagePageScheduler.Request {
        .init(index: index, maximumPixelSize: side,
              image: PreviewImage(data: Data([1, 2, 3]), pixelWidth: 100, pixelHeight: 140, role: .page))
    }
    // Probes pulse native/injected completion first. Only runnable MainActor bookkeeping remains.
    private func drain(_ scheduler: ImagePageScheduler) async {
        while scheduler.runningCount != 0 || scheduler.pendingCount != 0 { await Task.yield() }
    }

    @Test func changedWantedCancelsOriginalUUIDBeforeStartingReplacement() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let events = ImageSchedulerLifecycleEvents(), deliveries = ImageDeliveryProbe()
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        scheduler.observeScheduling = { events.record($0) }
        scheduler.deliver = { index, value in events.callback(index, hasResult: value != nil); deliveries.record(index) }
        let first = request(0), replacement = request(0, side: 300)
        scheduler.want([first])
        await probe.waitForStarted(1)
        scheduler.want([replacement])
        #expect(events.starts.count == 1 && scheduler.pendingCount == 1)
        #expect(events.cancellations.count == 1)
        if let cancelled = events.cancellations.first {
            #expect(cancelled.0 == events.starts.first?.0 && cancelled.1 == first && cancelled.2 == .wantedChanged)
            #expect(events.values.suffix(2).first == .wanted([replacement]))
        }
        probe.open()
        await deliveries.waitForCount(1)
        await probe.waitForFinished(2)
        await drain(scheduler)
        try #require(events.starts.count == 2 && events.finishes.count == 2)
        let originalID = events.starts[0].0, replacementID = events.starts[1].0
        #expect(originalID != replacementID && events.starts[1].1 == replacement)
        let original = try #require(events.finishes.first { $0.0 == originalID })
        let current = try #require(events.finishes.first { $0.0 == replacementID })
        #expect(original.2 == .init(isCurrent: false, cancelled: true, hasResult: true, callbackWillInvoke: false))
        #expect(current.2 == .init(isCurrent: true, cancelled: false, hasResult: true, callbackWillInvoke: true))
        #expect(events.callbacks.count == 1 && events.callbacks[0].finishWasObserved)
    }

    @Test func removedWantedHasCancellationDecisionAndSuppressesItsResult() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let events = ImageSchedulerLifecycleEvents()
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        scheduler.observeScheduling = { events.record($0) }
        scheduler.deliver = { index, value in events.callback(index, hasResult: value != nil) }
        scheduler.want([request(0)])
        await probe.waitForStarted(1)
        scheduler.want([])
        #expect(events.cancellations.count == 1)
        #expect(events.cancellations.first?.2 == .wantedChanged)
        probe.open()
        await probe.waitForFinished(1)
        await drain(scheduler)
        let finish = try #require(events.finishes.first)
        #expect(finish.2 == .init(isCurrent: false, cancelled: true, hasResult: true, callbackWillInvoke: false))
        #expect(events.callbacks.isEmpty)
    }

    @Test func explicitIndexAndRepeatedCancelAllPreserveEveryDecision() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let events = ImageSchedulerLifecycleEvents()
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        scheduler.observeScheduling = { events.record($0) }
        scheduler.deliver = { index, value in events.callback(index, hasResult: value != nil) }
        scheduler.want([request(0), request(1), request(2)])
        await probe.waitForStarted(2)
        scheduler.cancel(2) // Queued work owns no Task and emits no cancellation decision.
        #expect(events.cancellations.isEmpty)
        scheduler.cancel(0)
        scheduler.cancelAll()
        scheduler.cancelAll() // Running noncooperative work still exists after the first cancelAll.
        #expect(events.cancellations.count == 5)
        #expect(events.cancellations.filter { $0.1.index == 0 && $0.2 == .explicitIndex }.count == 1)
        #expect(events.cancellations.filter { $0.1.index == 0 && $0.2 == .all }.count == 2)
        #expect(events.cancellations.filter { $0.1.index == 1 && $0.2 == .all }.count == 2)
        probe.open()
        await probe.waitForFinished(2)
        await drain(scheduler)
        try #require(events.finishes.count == 2)
        #expect(events.finishes.allSatisfy { !$0.2.isCurrent && $0.2.cancelled && $0.2.hasResult && !$0.2.callbackWillInvoke })
        #expect(events.callbacks.isEmpty && events.starts.count == 2)
    }

    @Test func lateCancellationAfterNativeResultExistsStillSuppressesCallback() async throws {
        let native = NoncooperativeImageDecodeProbe(), returnGate = NoncooperativeImageDecodeProbe()
        native.open()
        defer { returnGate.open() }
        let events = ImageSchedulerLifecycleEvents()
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: { _, _ in
            let result = await native.run()
            // Native work has returned a bitmap; hold the injected wrapper before scheduler.finish.
            _ = await returnGate.run()
            return result
        })
        scheduler.observeScheduling = { events.record($0) }
        scheduler.deliver = { index, value in events.callback(index, hasResult: value != nil) }
        scheduler.want([request(0)])
        await returnGate.waitForStarted(1)
        #expect(native.started == 1 && native.cancelledFinishes == 0)
        scheduler.cancel(0)
        returnGate.open()
        await returnGate.waitForFinished(1)
        await drain(scheduler)
        let finish = try #require(events.finishes.first)
        #expect(events.cancellations.first?.0 == finish.0)
        #expect(finish.2 == .init(isCurrent: false, cancelled: true, hasResult: true, callbackWillInvoke: false))
        #expect(events.callbacks.isEmpty && native.cancelledFinishes == 0)
    }

    @Test func identicalOverlappingPayloadsKeepDeliveryAttachedToCurrentUUID() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let events = ImageSchedulerLifecycleEvents(), deliveries = ImageDeliveryProbe()
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        scheduler.observeScheduling = { events.record($0) }
        scheduler.deliver = { index, value in events.callback(index, hasResult: value != nil); deliveries.record(index) }
        let identical = request(0)
        scheduler.want([identical])
        await probe.waitForStarted(1)
        scheduler.cancel(0)
        scheduler.want([identical])
        await probe.waitForStarted(2)
        probe.open()
        await deliveries.waitForCount(1)
        await probe.waitForFinished(2)
        await drain(scheduler)
        try #require(events.starts.count == 2 && events.finishes.count == 2)
        let originalID = events.starts[0].0, currentID = events.starts[1].0
        #expect(originalID != currentID && events.starts[0].1 == events.starts[1].1)
        let original = try #require(events.finishes.first { $0.0 == originalID })
        let current = try #require(events.finishes.first { $0.0 == currentID })
        #expect(!original.2.isCurrent && original.2.cancelled && !original.2.callbackWillInvoke)
        #expect(current.2.isCurrent && !current.2.cancelled && current.2.callbackWillInvoke)
        #expect(deliveries.indices == [0])
    }

    @Test func nilResultAndNilCallbackAreDifferentFinishFacts() async throws {
        let events = ImageSchedulerLifecycleEvents(), deliveries = ImageDeliveryProbe()
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: { _, _ in nil })
        scheduler.observeScheduling = { events.record($0) }
        scheduler.deliver = { index, value in events.callback(index, hasResult: value != nil); deliveries.record(index) }
        scheduler.want([request(0)])
        await deliveries.waitForCount(1)
        await drain(scheduler)
        let deliveredNil = try #require(events.finishes.first)
        #expect(deliveredNil.2 == .init(isCurrent: true, cancelled: false, hasResult: false, callbackWillInvoke: true))
        #expect(events.callbacks.count == 1 && !events.callbacks[0].hasResult && events.callbacks[0].finishWasObserved)

        let probe = NoncooperativeImageDecodeProbe(), noCallbackEvents = ImageSchedulerLifecycleEvents()
        defer { probe.open() }
        let noCallback = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        noCallback.observeScheduling = { noCallbackEvents.record($0) }
        noCallback.want([request(0)])
        await probe.waitForStarted(1)
        probe.open()
        await probe.waitForFinished(1)
        await drain(noCallback)
        let noConsumer = try #require(noCallbackEvents.finishes.first)
        #expect(noConsumer.2 == .init(isCurrent: true, cancelled: false, hasResult: true, callbackWillInvoke: false))
    }

    @Test func nilObserverPreservesNormalDecodeAndDelivery() async {
        let probe = NoncooperativeImageDecodeProbe(), deliveries = ImageDeliveryProbe()
        defer { probe.open() }
        let calls = Mutex(0)
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: { _, _ in
            calls.withLock { $0 += 1 }; return await probe.run()
        })
        #expect(scheduler.observeScheduling == nil)
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want([request(0), request(1)])
        await probe.waitForStarted(1)
        probe.open()
        await deliveries.waitForCount(2)
        await probe.waitForFinished(2)
        await drain(scheduler)
        #expect(calls.withLock { $0 } == 2 && deliveries.indices == [0, 1])
    }
}

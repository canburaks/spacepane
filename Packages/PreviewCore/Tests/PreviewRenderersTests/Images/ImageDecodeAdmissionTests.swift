import Foundation
import Synchronization
import Testing
@testable import PreviewRenderers

/// Admission transitions are causal barriers; tests never poll or wait for a duration.
final class ImageAdmissionEventProbe: Sendable {
    private struct State {
        var decisions = 0
        var released = 0
        var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    }
    private let state = Mutex(State())
    var released: Int { state.withLock { $0.released } }

    func record(_ event: ImageDecodeAdmission.Event) {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            if event == .queued || event == .willGrant { state.decisions += 1 }
            if event == .released { state.released += 1 }
            let ready = state.waiters.filter { $0.0 <= state.decisions }.map { $0.1 }
            state.waiters.removeAll { $0.0 <= state.decisions }
            return ready
        }
        for continuation in ready { continuation.resume() }
    }

    func waitForDecisions(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.decisions >= count { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}

@Suite("Image decode resource admission", .serialized)
struct ImageDecodeAdmissionTests {
    private func run(_ pixels: Int, admission: ImageDecodeAdmission,
                     probe: NoncooperativeImageDecodeProbe) -> Task<DecodedPageImage?, Never> {
        Task {
            await admission.run(sourcePixelCount: pixels, ifCancelled: Optional<DecodedPageImage>.none) { await probe.run() }
        }
    }

    @Test(arguments: [false, true])
    func defaultAdmissionRunsOneSmallNativeCallUntilItActuallyReturns(cancelFirst: Bool) async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(observe: events.record)
        let firstProbe = NoncooperativeImageDecodeProbe()
        let secondProbe = NoncooperativeImageDecodeProbe()
        defer { firstProbe.open(); secondProbe.open() }
        let first = run(16_000_000, admission: admission, probe: firstProbe)
        await firstProbe.waitForStarted(1)
        let second = run(16_000_000, admission: admission, probe: secondProbe)
        // The second acquire has either queued or reserved a lease; no task-order inference.
        await events.waitForDecisions(2)
        #expect(admission.runningCount == 1 && admission.waitingCount == 1)
        #expect(secondProbe.started == 0 && events.released == 0)
        if cancelFirst { first.cancel() }
        // Cancellation of noncooperative work must not open the capacity for its replacement.
        #expect(admission.runningCount == 1 && admission.waitingCount == 1)
        #expect(secondProbe.started == 0 && events.released == 0)
        firstProbe.open()
        _ = await first.value
        await secondProbe.waitForStarted(1)
        #expect(events.released == 1)
        #expect(admission.runningCount == 1 && admission.waitingCount == 0)
        #expect(firstProbe.cancelledFinishes == (cancelFirst ? 1 : 0))
        secondProbe.open()
        _ = await second.value
        #expect(events.released == 2)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test func twoImagesAtSixteenMegapixelsCanRunWhileAThirdWaits() async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(maximumSmallConcurrent: 2, observe: events.record)
        let probe = NoncooperativeImageDecodeProbe()
        let first = run(16_000_000, admission: admission, probe: probe)
        let second = run(16_000_000, admission: admission, probe: probe)
        await probe.waitForStarted(2)
        let third = run(16_000_000, admission: admission, probe: probe)
        await events.waitForDecisions(3)
        #expect(admission.runningCount == 2 && admission.waitingCount == 1)
        #expect(probe.started == 2)
        probe.open()
        _ = await first.value; _ = await second.value; _ = await third.value
        #expect(probe.maximumConcurrent == 2)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test func aboveSixteenMegapixelsRunsAloneAndKeepsItsLeaseWhenCancelled() async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(observe: events.record)
        let largeProbe = NoncooperativeImageDecodeProbe()
        let smallProbe = NoncooperativeImageDecodeProbe()
        let large = run(16_000_001, admission: admission, probe: largeProbe)
        await largeProbe.waitForStarted(1)
        let small = run(1, admission: admission, probe: smallProbe)
        await events.waitForDecisions(2)
        large.cancel()
        #expect(admission.runningCount == 1 && admission.waitingCount == 1)
        #expect(smallProbe.started == 0)
        largeProbe.open()
        _ = await large.value
        await smallProbe.waitForStarted(1)
        #expect(admission.runningCount == 1)
        smallProbe.open()
        _ = await small.value
        #expect(events.released == 2)
    }

    @Test func aSmallRequestCannotBypassALargeRequestAtTheFrontOfTheQueue() async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(maximumSmallConcurrent: 2, observe: events.record)
        let holders = NoncooperativeImageDecodeProbe()
        let largeProbe = NoncooperativeImageDecodeProbe()
        let laterSmall = NoncooperativeImageDecodeProbe()
        let first = run(1, admission: admission, probe: holders)
        let second = run(1, admission: admission, probe: holders)
        await holders.waitForStarted(2)
        let large = run(40_000_000, admission: admission, probe: largeProbe)
        await events.waitForDecisions(3)
        let small = run(1, admission: admission, probe: laterSmall)
        await events.waitForDecisions(4)
        #expect(admission.runningCount == 2 && admission.waitingCount == 2)
        holders.open()
        _ = await first.value; _ = await second.value
        // Both holders returned after release/pump, so the reserved next lease is observable.
        #expect(admission.runningCount == 1 && admission.waitingCount == 1)
        #expect(laterSmall.started == 0)
        largeProbe.open()
        laterSmall.open()
        _ = await large.value; _ = await small.value
        #expect(events.released == 4)
    }

    @Test func aQueuedCancellationNeverStartsNativeWork() async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(observe: events.record)
        let holderProbe = NoncooperativeImageDecodeProbe()
        let cancelledProbe = NoncooperativeImageDecodeProbe()
        let holder = run(40_000_000, admission: admission, probe: holderProbe)
        await holderProbe.waitForStarted(1)
        let waiting = run(1, admission: admission, probe: cancelledProbe)
        await events.waitForDecisions(2)
        waiting.cancel()
        #expect(await waiting.value == nil)
        #expect(admission.runningCount == 1 && admission.waitingCount == 0)
        #expect(cancelledProbe.started == 0)
        holderProbe.open()
        _ = await holder.value
        #expect(events.released == 1)
    }

    @Test func cancellationBetweenReservationAndGrantReturnsItsSlotExactlyOnce() async {
        let events = ImageAdmissionEventProbe()
        let cancellation = Mutex<(@Sendable () -> Void)?>(nil)
        let admission = ImageDecodeAdmission(observe: { event in
            events.record(event)
            guard event == .willGrant else { return }
            let action = cancellation.withLock { action -> (@Sendable () -> Void)? in
                let result = action; action = nil; return result
            }
            action?()
        })
        let holderProbe = NoncooperativeImageDecodeProbe()
        let cancelledProbe = NoncooperativeImageDecodeProbe()
        let holder = run(40_000_000, admission: admission, probe: holderProbe)
        await holderProbe.waitForStarted(1)
        let waiting = run(1, admission: admission, probe: cancelledProbe)
        await events.waitForDecisions(2)
        cancellation.withLock { $0 = { waiting.cancel() } }
        holderProbe.open()
        _ = await holder.value
        #expect(await waiting.value == nil)
        #expect(cancelledProbe.started == 0)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
        #expect(events.released == 2)
        #expect(await admission.run(sourcePixelCount: 1, ifCancelled: false) { true })
    }

    @Test func cancellationAfterAcquisitionReleasesWithoutStartingWork() async {
        let admission = ImageDecodeAdmission(observe: { event in
            if event == .acquired { withUnsafeCurrentTask { $0?.cancel() } }
        })
        let probe = NoncooperativeImageDecodeProbe()
        let task = run(1, admission: admission, probe: probe)
        #expect(await task.value == nil)
        #expect(probe.started == 0)
        #expect(admission.runningCount == 0)
    }

    @Test func invalidSourceCountsNeverReceiveALease() async {
        let admission = ImageDecodeAdmission()
        for count in [0, -1, 40_000_001, Int.max] {
            #expect(await admission.run(sourcePixelCount: count, ifCancelled: false) { true } == false)
        }
        #expect(admission.runningCount == 0)
    }
}

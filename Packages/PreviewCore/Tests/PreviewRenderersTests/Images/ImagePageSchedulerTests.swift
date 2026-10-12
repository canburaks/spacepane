import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Image page scheduler", .serialized)
@MainActor
struct ImagePageSchedulerTests {
    private func requests(_ indices: [Int]) -> [ImagePageScheduler.Request] {
        indices.map { .init(index: $0, maximumPixelSize: 200, image: PreviewImage(data: Data("p\($0)".utf8), pixelWidth: 100, pixelHeight: 140, role: .page)) }
    }

    @Test func neverRunsMoreDecodesThanTheConcurrencyCap() async throws {
        let probe = NoncooperativeImageDecodeProbe()
        defer { probe.open() }
        let startedPayloads = Mutex<[Data]>([])
        let decode = probe.decode()
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: { image, size in
            startedPayloads.withLock { $0.append(image.data) }
            return await decode(image, size)
        })
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want(requests(Array(0..<10)))
        try #require(scheduler.runningCount == 2 && scheduler.pendingCount == 8)
        await probe.waitForStarted(2)
        #expect(probe.started == 2)
        #expect(probe.maximumConcurrent == 2)
        // The first admitted requests follow queue priority; their completion order is independent.
        #expect(startedPayloads.withLock { $0.map { String(decoding: $0, as: UTF8.self) }.sorted() } == ["p0", "p1"])
        probe.open()
        await deliveries.waitForCount(10)
        await probe.waitForFinished(10)
        #expect(probe.started == 10 && probe.cancelledFinishes == 0)
        #expect(scheduler.runningCount == 0 && scheduler.pendingCount == 0)
        #expect(probe.maximumConcurrent == 2)
        #expect(deliveries.indices.sorted() == Array(0..<10))
    }

    @Test func aReplacedWantedSetCancelsRunningWorkThatIsNoLongerWanted() async {
        let probe = DecodeProbe(gated: true)
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        var delivered: [Int] = []
        scheduler.deliver = { index, _ in delivered.append(index) }
        scheduler.want(requests([0, 1, 2]))
        #expect(await waitUntil { probe.started == 2 })
        scheduler.want(requests([5]))   // 0 and 1 are cancelled; 2 is dropped from the queue.
        #expect(scheduler.runningCount == 2)
        #expect(scheduler.pendingCount == 1)
        probe.open()
        #expect(await waitUntil { delivered == [5] })
        #expect(await waitUntil { probe.finished == probe.started })
        #expect(!delivered.contains(0) && !delivered.contains(1) && !delivered.contains(2))
    }

    @Test func requestsStillWantedKeepRunning() async {
        let probe = DecodeProbe(gated: true)
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        var delivered: [Int] = []
        scheduler.deliver = { index, _ in delivered.append(index) }
        scheduler.want(requests([0, 1]))
        #expect(await waitUntil { probe.started == 2 })
        scheduler.want(requests([1, 2]))
        #expect(probe.started == 2)   // Page 1 was not restarted.
        probe.open()
        #expect(await waitUntil { Set(delivered) == [1, 2] })
    }

    @Test func cancelAllDeliversNothingAndLeavesTheSchedulerReusable() async {
        let probe = DecodeProbe(gated: true)
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        var delivered: [Int] = []
        scheduler.deliver = { index, _ in delivered.append(index) }
        scheduler.want(requests([0, 1, 2, 3]))
        #expect(await waitUntil { probe.started == 2 })
        scheduler.cancelAll()
        #expect(scheduler.runningCount == 2 && scheduler.pendingCount == 0)
        probe.open()
        #expect(await waitUntil { probe.finished == 2 })
        try? await Task.sleep(for: .milliseconds(30))
        #expect(delivered.isEmpty)
        scheduler.want(requests([7]))
        #expect(await waitUntil { delivered == [7] })
    }

    @Test func cancelStopsOnePageOnly() async {
        let probe = DecodeProbe(gated: true)
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        var delivered: [Int] = []
        scheduler.deliver = { index, _ in delivered.append(index) }
        scheduler.want(requests([0, 1, 2]))
        #expect(await waitUntil { probe.started == 2 })
        scheduler.cancel(1)
        scheduler.cancel(2)   // Still queued: removed without ever starting.
        probe.open()
        #expect(await waitUntil { delivered == [0] })
    }

    @Test func aFailedDecodeIsDeliveredAsNil() async {
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: { _, _ in nil })
        var results: [(Int, Bool)] = []
        scheduler.deliver = { index, image in results.append((index, image == nil)) }
        scheduler.want(requests([4]))
        #expect(await waitUntil { results.count == 1 })
        #expect(results[0].0 == 4 && results[0].1)
    }

    @Test func theProductionDecoderBoundsTheDecodedSizeAndAppliesTheRequestedLimit() async throws {
        let png = testPNG(400, 600)
        let image = try #require(await ImagePageDecoder.decode(png, maximumPixelSize: 100))
        #expect(max(image.image.width, image.image.height) <= 100)
        #expect(max(image.image.width, image.image.height) >= 90)
        // A request above 4,096 is clamped, and invalid data yields nil instead of crashing.
        let clamped = try #require(await ImagePageDecoder.decode(png, maximumPixelSize: 100_000))
        #expect(max(clamped.image.width, clamped.image.height) <= 4_096)
        #expect(await ImagePageDecoder.decode(Data("not an image".utf8), maximumPixelSize: 100) == nil)
    }
}

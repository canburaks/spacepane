import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Image page unfinished native work", .serialized)
@MainActor
struct ImagePageUnfinishedWorkTests {
    private func requests(_ indices: [Int]) -> [ImagePageScheduler.Request] {
        indices.map { .init(index: $0, maximumPixelSize: 200, image: PreviewImage(data: Data("page-\($0)".utf8), pixelWidth: 100, pixelHeight: 100, role: .page)) }
    }

    @Test func cancellationKeepsUnfinishedDecodesInsideTheConcurrencyCap() async {
        let probe = NoncooperativeImageDecodeProbe()
        let scheduler = ImagePageScheduler(maximumConcurrent: 2, decode: probe.decode())
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want(requests([0, 1]))
        await probe.waitForStarted(2)
        scheduler.cancelAll()
        #expect(scheduler.runningCount == 2)
        #expect(scheduler.pendingCount == 0)
        scheduler.want(requests([2, 3]))
        #expect(scheduler.runningCount == 2)
        #expect(scheduler.pendingCount == 2)
        probe.open()
        await deliveries.waitForCount(2)
        await probe.waitForFinished(4)
        #expect(deliveries.indices.sorted() == [2, 3])
        #expect(probe.maximumConcurrent == 2)
    }

    @Test func replacementAtTheSameIndexWaitsForItsCancelledPredecessor() async {
        let probe = NoncooperativeImageDecodeProbe()
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        scheduler.want(requests([0]))
        await probe.waitForStarted(1)
        scheduler.cancel(0)
        scheduler.want(requests([0]))
        #expect(scheduler.runningCount == 1)
        #expect(scheduler.pendingCount == 1)
        probe.open()
        await deliveries.waitForCount(1)
        await probe.waitForFinished(2)
        #expect(deliveries.indices == [0])
        #expect(probe.maximumConcurrent == 1)
    }
}

import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Image page native lease lifetime", .serialized)
@MainActor
struct ImagePageLeaseLifetimeTests {
    private func requests(_ indices: [Int], image: PreviewImage) -> [ImagePageScheduler.Request] {
        indices.map { .init(index: $0, maximumPixelSize: 100, image: image) }
    }

    @Test func deallocatingASchedulerCancelsItsWorkButDoesNotReleaseItsNativeLeases() async {
        let events = ImageAdmissionEventProbe()
        let admission = ImageDecodeAdmission(maximumSmallConcurrent: 2, observe: events.record)
        let probe = NoncooperativeImageDecodeProbe()
        let picture = PreviewImage(data: testPNG(4, 4), pixelWidth: 4, pixelHeight: 4, role: .page)
        let decode: ImagePageScheduler.Decode = { image, size in
            await ImagePageDecoder.decode(image, maximumPixelSize: size, admission: admission, nativeDecode: probe.nativeDecode())
        }
        let staleDeliveries = ImageDeliveryProbe()
        var first: ImagePageScheduler? = ImagePageScheduler(decode: decode)
        weak var retired = first
        first?.deliver = { index, _ in staleDeliveries.record(index) }
        first?.want(requests([0, 1], image: picture))
        await probe.waitForStarted(2)
        first = nil
        #expect(retired == nil)
        let nextDeliveries = ImageDeliveryProbe()
        let next = ImagePageScheduler(decode: decode)
        next.deliver = { index, _ in nextDeliveries.record(index) }
        next.want(requests([0, 1], image: picture))
        await events.waitForDecisions(4)
        #expect(admission.runningCount == 2 && admission.waitingCount == 2)
        #expect(probe.started == 2)
        probe.open()
        await nextDeliveries.waitForCount(2)
        await probe.waitForFinished(4)
        #expect(nextDeliveries.indices.sorted() == [0, 1])
        #expect(staleDeliveries.indices.isEmpty)
        #expect(probe.cancelledFinishes == 2)
        #expect(probe.maximumConcurrent == 2)
        #expect(admission.runningCount == 0 && admission.waitingCount == 0)
    }

    @Test func changingTheBytesAtTheSameIndexCreatesANewGeneration() async {
        let probe = NoncooperativeImageDecodeProbe()
        let scheduler = ImagePageScheduler(maximumConcurrent: 1, decode: probe.decode())
        let deliveries = ImageDeliveryProbe()
        scheduler.deliver = { index, _ in deliveries.record(index) }
        let first = PreviewImage(data: Data([1]), pixelWidth: 4, pixelHeight: 4, role: .page)
        let second = PreviewImage(data: Data([2]), pixelWidth: 4, pixelHeight: 4, role: .page)
        scheduler.want(requests([0], image: first))
        await probe.waitForStarted(1)
        scheduler.want(requests([0], image: second))
        #expect(scheduler.runningCount == 1 && scheduler.pendingCount == 1)
        probe.open()
        await deliveries.waitForCount(1)
        await probe.waitForFinished(2)
        #expect(deliveries.indices == [0])
        #expect(probe.cancelledFinishes == 1)
        #expect(probe.maximumConcurrent == 1)
    }
}

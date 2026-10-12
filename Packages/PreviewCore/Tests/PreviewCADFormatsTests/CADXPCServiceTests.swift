import Foundation
import Testing
import Synchronization
import Dispatch
@testable import PreviewCADFormats
import PreviewContracts
import PreviewCore

@Suite("CAD XPC boundary", .serialized)
struct CADXPCServiceTests {
    private func reply(_ service: CADImportService, input: Data = Data([0]), format: String = "iges",
                       requestID: String = UUID().uuidString) async -> (Data?, Int?) {
        await withCheckedContinuation { continuation in
            service.importGeometry(input, format: format, requestID: requestID) { data, status in
                continuation.resume(returning: (data, status?.intValue))
            }
        }
    }

    @Test func rejectsInvalidInputAndInvalidatedConnectionsBeforeImport() async {
        let calls = Mutex(0)
        let service = CADImportService { _, _, _ in calls.withLock { $0 += 1 }; return Data([1]) }
        let invalidID = await reply(service, requestID: "invalid")
        #expect(invalidID.0 == nil && invalidID.1 == 2)
        let invalidFormat = await reply(service, format: "external-path")
        #expect(invalidFormat.0 == nil && invalidFormat.1 == 3)
        let oversized = await reply(service, input: Data(repeating: 0, count: GeometryLimits.maximumInputBytes + 1))
        #expect(oversized.0 == nil && oversized.1 == 4)
        service.cancelAll()
        let invalidated = await reply(service)
        #expect(invalidated.0 == nil && invalidated.1 == 1)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func repliesContainOnlyDataOrOwnedNumericErrors() async {
        let successful = CADImportService { input, _, _ in input }
        let result = await reply(successful, input: Data([0, 1, 2]))
        #expect(result.0 == Data([0, 1, 2]) && result.1 == nil)
        let failures: [(PreviewFailure, Int)] = [(.malformedDocument, 2), (.unsupportedFormat, 3),
            (.inputTooLarge, 4), (.outputTooLarge, 4), (.deadlineExceeded, 5), (.cadImporterUnavailable, 1)]
        for (failure, code) in failures {
            let service = CADImportService { _, _, _ in throw failure }
            let result = await reply(service)
            #expect(result.0 == nil && result.1 == code)
        }
        let oversized = CADImportService { _, _, _ in Data(repeating: 0, count: GeometryLimits.maximumSerializedBytes + 1) }
        let tooLarge = await reply(oversized)
        #expect(tooLarge.0 == nil && tooLarge.1 == 4)
    }

    @Test func completedReplyCanImmediatelyStartAnotherRequestOnTheSameConnection() async {
        let service = CADImportService { input, _, _ in input }
        let result: (Data?, Int?) = await withCheckedContinuation { continuation in
            service.importGeometry(Data([1]), format: "iges", requestID: UUID().uuidString) { first, status in
                #expect(first == Data([1]) && status == nil)
                service.importGeometry(Data([2]), format: "step", requestID: UUID().uuidString) { data, status in
                    continuation.resume(returning: (data, status?.intValue))
                }
            }
        }
        #expect(result.0 == Data([2]) && result.1 == nil)
    }

    @Test func serviceWideGateAllowsTwoRequestsAndDeclinesFurtherWorkWithoutQueuing() async throws {
        let starts = Mutex(0)
        let operation: CADImportService.Operation = { _, _, cancellation in
            let ordinal = starts.withLock { count in count += 1; return count }
            // If the gate regresses, return rather than stranding this test.
            if ordinal > 2 { return Data([3]) }
            while !cancellation.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
            throw CancellationError()
        }
        let first = CADImportService(operation: operation), second = CADImportService(operation: operation)
        let third = CADImportService(operation: operation)
        defer { first.cancelAll(); second.cancelAll(); third.cancelAll() }
        let a = Task { await reply(first) }, b = Task { await reply(second) }
        for _ in 0..<100 {
            if starts.withLock({ $0 }) == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard starts.withLock({ $0 }) == 2 else { Issue.record("Two native imports did not start"); return }
        let rejected = await reply(third)
        #expect(rejected.0 == nil && rejected.1 == 1)
        #expect(starts.withLock { $0 } == 2)
        first.cancelAll(); second.cancelAll()
        let results = [await a.value, await b.value]
        #expect(results.allSatisfy { $0.0 == nil && $0.1 == 6 })
    }

    @Test func explicitCancellationMatchesRequestAndConnectionAcceptsOnlyOneActiveImport() async throws {
        let token = Mutex<CADImportCancellation?>(nil)
        let service = CADImportService { _, _, cancellation in
            token.withLock { $0 = cancellation }
            while !cancellation.isCancelled { Thread.sleep(forTimeInterval: 0.005) }
            throw CancellationError()
        }
        defer { service.cancelAll() }
        let requestID = UUID().uuidString
        let pending = Task { await reply(service, requestID: requestID) }
        for _ in 0..<100 {
            if token.withLock({ $0 != nil }) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let cancellation = try #require(token.withLock { $0 })
        service.cancel(UUID().uuidString)
        #expect(!cancellation.isCancelled)
        let rejected = await reply(service)
        #expect(rejected.0 == nil && rejected.1 == 1)
        service.cancel(requestID)
        let result = await pending.value
        #expect(result.0 == nil && result.1 == 6)
    }

    @Test func clientReplyBoundsDataRejectsMalformedEnvelopesAndIgnoresLateCallbacks() {
        let oversized = CADXPCClient.ReplyState(maximumBytes: 1)
        oversized.receive(data: Data([1, 2]), status: nil)
        guard case .failure(.outputTooLarge) = oversized.result else { Issue.record("Oversized XPC reply accepted"); return }
        for (data, status): (Data?, NSNumber?) in [(nil, nil), (Data([1]), NSNumber(value: 1)), (nil, NSNumber(value: 999))] {
            let state = CADXPCClient.ReplyState(maximumBytes: 8)
            state.receive(data: data, status: status)
            guard case .failure(.malformedDocument) = state.result else { Issue.record("Malformed XPC envelope accepted"); continue }
        }
        let state = CADXPCClient.ReplyState(maximumBytes: 8)
        state.receive(data: Data([7]), status: nil)
        DispatchQueue.concurrentPerform(iterations: 100) { _ in state.complete(.failure(.cadImporterUnavailable)) }
        guard case .success(let data) = state.result else { Issue.record("Late failure replaced successful reply"); return }
        #expect(data == Data([7]))
    }

    @Test func missingXPCConfigurationDoesNotFallBackToDirectWorker() async {
        let pipeline = PreviewPipeline(registrations: CADFormatAdapters.registrations(serviceName: ""), reader: XPCEmptyReader())
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: .iges)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/model.igs"), preferences: preferences)
            == .unavailable(.cadImporterUnavailable))
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/model.step")) == .disabledByUser(.step))
    }

    @Test func serviceCancellationTokenTerminatesNativeChildWithoutCancellingSwiftTask() async throws {
        let cancellation = CADImportCancellation()
        let task = Task.detached {
            try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], input: Data(),
                context: RequestContext(budget: GeometryLimits.requestBudget), isCancelled: { cancellation.isCancelled })
        }
        try await Task.sleep(for: .milliseconds(60))
        cancellation.cancel()
        do { _ = try await task.value; Issue.record("Cancelled service child returned") }
        catch is CancellationError {} catch { Issue.record("Unexpected service cancellation failure") }
    }

    @Test func aRequestThroughARealConnectionIsAnsweredAndEndsTheClientsWait() throws {
        // The anonymous listener keeps the exchange inside this process. It lives in this serialized suite because the
        // service-wide import gate (two slots) is shared with the gate tests above.
        let delegate = XPCLoopbackDelegate(service: CADImportService { input, _, _ in input })
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let data = try CADXPCClient.exchange(over: NSXPCConnection(listenerEndpoint: listener.endpoint), kind: .iges,
                                             input: Data([1, 2, 3]), context: RequestContext(budget: PreviewBudget(maxMilliseconds: 10_000)))
        // The listener holds its delegate weakly; this keeps it alive through the exchange.
        withExtendedLifetime(delegate) {}
        #expect(data == Data([1, 2, 3]))
    }

    @Test func aFailureReportedThroughARealConnectionReachesTheClientAsItsTypedFailure() {
        let delegate = XPCLoopbackDelegate(service: CADImportService { _, _, _ in throw PreviewFailure.unsupportedFormat })
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        #expect(throws: PreviewFailure.unsupportedFormat) {
            try CADXPCClient.exchange(over: NSXPCConnection(listenerEndpoint: listener.endpoint), kind: .step,
                                      input: Data([4]), context: RequestContext(budget: PreviewBudget(maxMilliseconds: 10_000)))
        }
        withExtendedLifetime(delegate) {}
    }

    @Test func aConnectionTheListenerRefusesEndsAsImporterUnavailable() {
        // The shape of a peer-requirement rejection (decision 027, Q-44): the listener declines the connection and the
        // client must report an unavailable importer, not wait for its deadline.
        let delegate = XPCLoopbackDelegate(service: CADImportService { input, _, _ in input }, accepts: false)
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        #expect(throws: PreviewFailure.cadImporterUnavailable) {
            try CADXPCClient.exchange(over: NSXPCConnection(listenerEndpoint: listener.endpoint), kind: .iges,
                                      input: Data([1]), context: RequestContext(budget: PreviewBudget(maxMilliseconds: 10_000)))
        }
        withExtendedLifetime(delegate) {}
    }

    @Test func missingEmbeddedServiceFailsThroughBoundedClient() {
        #expect(throws: PreviewFailure.cadImporterUnavailable) {
            try CADXPCClient.run(serviceName: "invalid.example.cad-test.\(UUID().uuidString)", kind: .iges,
                // Bounded, but generous: a loaded runner can take longer than half a second to report
                // that a service does not exist, and the subject here is the typed failure, not the time.
                input: Data(), context: RequestContext(budget: PreviewBudget(maxMilliseconds: 5_000)))
        }
    }
}

/// Serves `service` over the production interface to every connection it accepts; `accepts: false` declines them all.
private final class XPCLoopbackDelegate: NSObject, NSXPCListenerDelegate {
    private let service: CADImportService
    private let accepts: Bool
    init(service: CADImportService, accepts: Bool = true) {
        self.service = service
        self.accepts = accepts
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard accepts else { return false }
        newConnection.exportedInterface = CADImportService.interface()
        newConnection.exportedObject = service
        newConnection.resume()
        return true
    }
}

private struct XPCEmptyReader: PreviewFileReading {
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: Data()) }
}

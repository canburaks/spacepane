import Foundation
import Dispatch
import Synchronization
import OSLog
import PreviewContracts

/// One synchronous request owns its connection. XPC callbacks only publish an
/// immutable reply through Mutex; they never capture or use the connection.
///
/// The calling thread blocks until a reply is stored instead of polling for it: the first reply, failure or
/// invalidation resumes the wait at once. A blocked synchronous thread cannot observe task cancellation, so the
/// wait also wakes every `cancellationSliceMilliseconds` to look at its own cancellation and deadline. A true
/// continuation with a cancellation handler needs an async caller, but the geometry adapter contract
/// (`GeometryFormatAdapter.parse`) is synchronous; keeping the blocked thread off the cooperative pool is the
/// pipeline worker's job (decision 027, Q-40).
enum CADXPCClient {
    private static let logger = Logger(subsystem: CADLogging.subsystem, category: "XPCClient")

    /// The longest a waiting request goes without checking for cancellation or an expired deadline. A reply
    /// never waits for it. Cancellation is noticed within one slice.
    static let cancellationSliceMilliseconds = 25

    static func run(serviceName: String, kind: CADFileKind, input: Data, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard !serviceName.isEmpty, serviceName.utf8.count <= 255,
              !serviceName.contains("\0"), !serviceName.contains("/") else { throw PreviewFailure.unreadableFile }
        guard input.count <= min(context.budget.maxInputBytes, GeometryLimits.maximumInputBytes) else {
            throw PreviewFailure.inputTooLarge
        }
        return try exchange(over: NSXPCConnection(serviceName: serviceName), kind: kind, input: input, context: context)
    }

    /// One request over `connection`, which this call resumes and always invalidates. The embedded service's
    /// connection comes from `run`; a test passes a connection to an in-process listener.
    static func exchange(over connection: NSXPCConnection, kind: CADFileKind, input: Data,
                         context: RequestContext) throws -> Data {
        let reply = ReplyState(maximumBytes: min(context.budget.maxOutputUTF8Bytes, GeometryLimits.maximumSerializedBytes))
        connection.remoteObjectInterface = CADImportService.interface()
        connection.invalidationHandler = { reply.complete(.failure(.unreadableFile)) }
        connection.interruptionHandler = { reply.complete(.failure(.unreadableFile)) }
        connection.resume()
        let requestID = UUID().uuidString
        var proxy: (any CADImportServiceProtocol)?
        var completed = false
        defer {
            if !completed { proxy?.cancel(requestID) }
            connection.invalidate()
        }
        proxy = connection.remoteObjectProxyWithErrorHandler { error in
            logger.error("cad.xpc.proxyFailed code=\((error as NSError).code, privacy: .public)")
            reply.complete(.failure(.unreadableFile))
        } as? any CADImportServiceProtocol
        guard let proxy else { throw PreviewFailure.unreadableFile }
        logger.debug("cad.xpc.requested")
        proxy.importGeometry(input, format: kind.rawValue, requestID: requestID) { data, status in
            reply.receive(data: data, status: status)
        }
        // Cancellation and the deadline throw from here with `completed` still false, so the defer above
        // tells the service to stop the importer and drops the connection.
        let result = try waitForReply(reply, context: context)
        completed = true
        switch result {
        case .success(let data): return data
        case .failure(let failure): throw failure
        case .cancelled: throw CancellationError()
        }
    }

    /// Blocks the calling thread until a reply is stored, then returns it. Cancellation and the request
    /// deadline are checked before each wait and whenever a slice of `sliceMilliseconds` ends.
    static func waitForReply(_ reply: ReplyState, context: RequestContext,
                             sliceMilliseconds: Int = CADXPCClient.cancellationSliceMilliseconds) throws -> Reply {
        while true {
            try context.checkpoint()
            if let result = reply.result { return result }
            _ = reply.wait(milliseconds: sliceMilliseconds)
        }
    }

    enum Reply: Sendable { case success(Data), failure(PreviewFailure), cancelled }
    final class ReplyState: Sendable {
        private let value = Mutex<Reply?>(nil)
        /// Signalled once, by the call that stores the first reply; `wait` blocks on it.
        private let arrival = DispatchSemaphore(value: 0)
        let maximumBytes: Int
        init(maximumBytes: Int) { self.maximumBytes = maximumBytes }
        var result: Reply? { value.withLock { $0 } }
        /// Stores the first reply and wakes the waiting thread; every later reply is ignored.
        func complete(_ reply: Reply) {
            let isFirst = value.withLock { stored in
                guard stored == nil else { return false }
                stored = reply
                return true
            }
            if isFirst { _ = arrival.signal() }
        }
        /// Blocks until a reply was stored or `milliseconds` have passed. True when a reply woke it, including
        /// one stored before the call; false when the time ran out first. It consumes the one wakeup a reply
        /// produces, so a caller reads `result` and stops waiting once it is set.
        func wait(milliseconds: Int) -> Bool {
            arrival.wait(timeout: .now() + .milliseconds(milliseconds)) == .success
        }
        func receive(data: Data?, status: NSNumber?) {
            if let status {
                guard data == nil, let code = CADImportStatus(rawValue: status.intValue) else {
                    complete(.failure(.malformedDocument)); return
                }
                complete(code == .cancelled ? .cancelled : .failure(code.failure))
            } else if let data {
                complete(data.count <= maximumBytes ? .success(data) : .failure(.outputTooLarge))
            } else { complete(.failure(.malformedDocument)) }
        }
    }
}

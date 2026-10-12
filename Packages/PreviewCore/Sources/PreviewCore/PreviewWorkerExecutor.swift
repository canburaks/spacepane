import Dispatch
import Foundation

/// The serial executor that one preview request owner, a `PreviewPipeline`, runs its blocking reads and
/// parses on (decision 027, Q-40; reviews PF-06, SP-05 and AR-07).
///
/// Swift actors run on the cooperative thread pool unless told otherwise: about one thread per core, sized
/// for code that suspends rather than blocks. A request that reads from a stalled network volume, waits for a
/// native decoder or calls the CAD service blocks its thread without suspending. A few of them (a Finder folder
/// of thumbnails, a slow share) can hold every pool thread, and then nothing else can run, including the
/// timer that is supposed to answer Quick Look. On this executor a blocked request holds one dispatch thread
/// of its own and leaves the pool free.
///
/// - One executor serves one owner. `PreviewPipeline` creates its own by default, so a slow parse in one
///   pipeline never delays another. Pipelines handed the same executor share one serial domain.
/// - The executor changes where the work runs, not how it is controlled. Cancellation and deadlines stay
///   cooperative checkpoints inside the work, and a request queued behind a blocked one still returns
///   `.cancelled` the moment its turn comes, before any file access.
/// - It does not limit how many owners run at once. Each running owner holds one dispatch thread, so a host that
///   starts many pipelines together (the thumbnail service) bounds them itself.
/// - It deliberately does not declare `SerialExecutor` conformance. `DispatchSerialQueue` already conforms (since
///   macOS 14), and forwarding its own `UnownedSerialExecutor` keeps the executor identity the queue's own,
///   with no hand-written `enqueue(_:)` to get wrong.
///
/// The one shape of use is an actor naming the executor as its own, as `PreviewPipeline`'s worker does:
///
///     nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
///
/// The actor keeps the executor alive, because an `UnownedSerialExecutor` does not retain it.
public final class PreviewWorkerExecutor: Sendable {
    private let queue: DispatchSerialQueue

    /// - Parameters:
    ///   - label: the queue's name, shown in crash logs and Instruments. Never carries a path or file name.
    ///   - qos: the priority the work runs at; user-initiated suits a request somebody is waiting for.
    public init(label: String = "PreviewCore.PreviewWorker", qos: DispatchQoS = .userInitiated) {
        queue = DispatchSerialQueue(label: label, qos: qos)
    }

    /// Wraps a queue the caller made and keeps. Tests mark such a queue to learn, from inside a read or a parse,
    /// whether the work ran on it; production code uses `init(label:qos:)`.
    package init(queue: DispatchSerialQueue) {
        self.queue = queue
    }

    /// The executor an actor returns from `unownedExecutor`. It refers to this object's queue and does not retain it.
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }
}

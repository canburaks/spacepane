import Foundation
import PreviewContracts

/// Keeps unfinished work within a local task bound, while the decoder owns process-wide native admission.
/// Cancelled tasks keep their slots until completion; generation identity prevents stale delivery.
@MainActor
final class ImagePageScheduler {
    struct Request: Equatable, Sendable {
        let index: Int
        let maximumPixelSize: Int
        let image: PreviewImage
    }

    typealias Decode = @Sendable (PreviewImage, Int) async -> DecodedPageImage?
    /// Optional internal instrumentation uses the scheduler's existing generation identity.
    /// When supplied, this takes precedence over Decode; nil preserves the normal decode path.
    typealias ScheduledDecode = @Sendable (Request, UUID) async -> DecodedPageImage?
    enum CancellationReason: Equatable, Sendable { case wantedChanged, explicitIndex, all }
    /// Facts at scheduler completion; no image value is retained by observation.
    struct FinishObservation: Equatable, Sendable {
        let isCurrent: Bool
        let cancelled: Bool
        let hasResult: Bool
        let callbackWillInvoke: Bool
    }
    enum SchedulingEvent: Equatable, Sendable {
        case wanted([Request])
        case started(UUID, Request)
        /// A Task.cancel decision, not proof that a native call stopped or observed cancellation.
        case cancelRequested(UUID, Request, CancellationReason)
        /// Observes the decision immediately before the unchanged delivery branch.
        case finished(UUID, Request, FinishObservation)
    }
    static let defaultConcurrency = 2
    private struct Running {
        let request: Request
        let task: Task<Void, Never>
    }
    private let maximumConcurrent: Int
    private let decode: Decode
    private let scheduledDecode: ScheduledDecode?
    private var queue: [Request] = []
    private var running: [UUID: Running] = [:]
    private var wanted: [Int: UUID] = [:]
    var deliver: (@MainActor (Int, DecodedPageImage?) -> Void)?
    /// Read-only, nonreentrant observation; observers must not call scheduler mutation methods.
    /// Wanted fires synchronously before queue processing; started before Task creation.
    /// Cancel decisions follow Task.cancel; finish facts precede the existing delivery branch.
    var observeScheduling: (@MainActor (SchedulingEvent) -> Void)?

    init(maximumConcurrent: Int = ImagePageScheduler.defaultConcurrency,
         decode: @escaping Decode = { image, size in await ImagePageDecoder.decode(image, maximumPixelSize: size) },
         scheduledDecode: ScheduledDecode? = nil) {
        self.maximumConcurrent = max(1, maximumConcurrent)
        self.decode = decode
        self.scheduledDecode = scheduledDecode
    }

    isolated deinit { for record in running.values { record.task.cancel() } }

    var runningCount: Int { running.count }
    var pendingCount: Int { queue.count }

    func want(_ requests: [Request]) {
        observeScheduling?(.wanted(requests))
        let requested = Dictionary(requests.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, generation) in wanted {
            guard let current = running[generation] else { wanted[index] = nil; continue }
            if requested[index] != current.request {
                current.task.cancel()
                observeScheduling?(.cancelRequested(generation, current.request, .wantedChanged))
                wanted[index] = nil
            }
        }
        var seen: Set<Int> = []
        queue = requests.filter { wanted[$0.index] == nil && seen.insert($0.index).inserted }
        pump()
    }

    func cancel(_ index: Int) {
        if let generation = wanted.removeValue(forKey: index), let record = running[generation] {
            record.task.cancel()
            observeScheduling?(.cancelRequested(generation, record.request, .explicitIndex))
        }
        queue.removeAll { $0.index == index }
    }

    func cancelAll() {
        for (generation, record) in running {
            record.task.cancel()
            observeScheduling?(.cancelRequested(generation, record.request, .all))
        }
        wanted = [:]
        queue = []
    }

    private func pump() {
        while running.count < maximumConcurrent, !queue.isEmpty {
            let request = queue.removeFirst()
            let generation = UUID()
            let decode = decode
            let scheduledDecode = scheduledDecode
            observeScheduling?(.started(generation, request))
            let task = Task { [weak self] in
                let result: DecodedPageImage?
                if let scheduledDecode {
                    result = await scheduledDecode(request, generation)
                } else {
                    result = await decode(request.image, request.maximumPixelSize)
                }
                self?.finish(generation, result, cancelled: Task.isCancelled)
            }
            running[generation] = Running(request: request, task: task)
            wanted[request.index] = generation
        }
    }

    private func finish(_ generation: UUID, _ result: DecodedPageImage?, cancelled: Bool) {
        guard let record = running.removeValue(forKey: generation) else { return }
        observeScheduling?(.finished(generation, record.request,
                                     FinishObservation(isCurrent: wanted[record.request.index] == generation,
                                                       cancelled: cancelled, hasResult: result != nil,
                                                       callbackWillInvoke: wanted[record.request.index] == generation && !cancelled && deliver != nil)))
        if wanted[record.request.index] == generation {
            wanted[record.request.index] = nil
            if !cancelled { deliver?(record.request.index, result) }
        }
        pump()
    }
}

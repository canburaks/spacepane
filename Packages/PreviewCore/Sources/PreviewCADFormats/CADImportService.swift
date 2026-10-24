import Foundation
import Dispatch
import Synchronization
import OSLog
import PreviewContracts

/// The Logger subsystem of every CAD log line: the hosting bundle's identifier, so a predicate on the app's bundle
/// identifier (the build script's `--telemetry` mode) finds the lines, and the module name where there is no bundle.
/// Messages carry numeric status only, never a path, a file name or content.
enum CADLogging {
    static let subsystem = Bundle.main.bundleIdentifier ?? "PreviewCADFormats"
}

@objc public protocol CADImportServiceProtocol: NSObjectProtocol {
    func importGeometry(_ input: Data, format: String, requestID: String,
                        withReply: @escaping @Sendable (Data?, NSNumber?) -> Void)
    func cancel(_ requestID: String)
}

/// One object belongs to one accepted connection. Mutable state is guarded by
/// Mutex; parsing runs on a private serial queue and never holds either lock.
public final class CADImportService: NSObject, CADImportServiceProtocol, Sendable {
    private struct State: Sendable {
        var invalidated = false
        var active: (id: String, cancellation: CADImportCancellation)?
    }
    typealias Operation = @Sendable (Data, CADFileKind, CADImportCancellation) throws -> Data
    // Two previews (Finder pane and Space bar) may run together. Further callers
    // are declined without retaining queued file data. This gate spans connections
    // in this service process; it is not a claim of a machine-wide resource cap.
    private static let activeImports = Mutex(0)
    private static let maximumConcurrentImports = 2
    private static let logger = Logger(subsystem: CADLogging.subsystem, category: "XPCService")
    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "PreviewCADFormats.XPCImport", qos: .userInitiated)
    private let operation: Operation

    public convenience override init() {
        self.init(workerURL: CADWorkerProcess.bundledExecutableURL)
    }

    public init(workerURL: URL) {
        operation = { input, kind, cancellation in
            try CADWorkerProcess.run(executable: workerURL, arguments: [kind.rawValue], input: input,
                context: RequestContext(budget: GeometryLimits.requestBudget),
                isCancelled: { cancellation.isCancelled })
        }
        super.init()
    }

    init(operation: @escaping Operation) { self.operation = operation; super.init() }

    public static func interface() -> NSXPCInterface { NSXPCInterface(with: CADImportServiceProtocol.self) }

    public func importGeometry(_ input: Data, format: String, requestID: String,
                               withReply reply: @escaping @Sendable (Data?, NSNumber?) -> Void) {
        guard UUID(uuidString: requestID) != nil else { reply(nil, CADImportStatus.malformed.number); return }
        guard let kind = CADFileKind(rawValue: format) else { reply(nil, CADImportStatus.unsupported.number); return }
        guard input.count <= GeometryLimits.maximumInputBytes else { reply(nil, CADImportStatus.budget.number); return }
        let acquired = Self.activeImports.withLock { count in
            guard count < Self.maximumConcurrentImports else { return false }
            count += 1; return true
        }
        guard acquired else { reply(nil, CADImportStatus.unavailable.number); return }
        let cancellation = CADImportCancellation()
        let accepted = state.withLock { state in
            guard !state.invalidated, state.active == nil else { return false }
            state.active = (requestID, cancellation); return true
        }
        guard accepted else {
            Self.activeImports.withLock { $0 -= 1 }
            reply(nil, CADImportStatus.unavailable.number); return
        }
        Self.logger.debug("cad.xpc.accepted")
        queue.async { [self] in
            let data: Data?, status: CADImportStatus?
            do {
                if cancellation.isCancelled { throw CancellationError() }
                let output = try operation(input, kind, cancellation)
                if cancellation.isCancelled { throw CancellationError() }
                guard output.count <= GeometryLimits.maximumSerializedBytes else { throw PreviewFailure.outputTooLarge }
                data = output; status = nil
            } catch { data = nil; status = CADImportStatus(error: error) }
            // The operation has returned (and its child is reaped). Release both
            // slots before reply: a callback may immediately submit another request.
            state.withLock { $0.active = nil }
            Self.activeImports.withLock { $0 -= 1 }
            Self.logger.debug("cad.xpc.finished status=\(status?.rawValue ?? 0, privacy: .public)")
            reply(data, status?.number)
        }
    }

    public func cancel(_ requestID: String) {
        let cancellation = state.withLock { $0.active?.id == requestID ? $0.active?.cancellation : nil }
        cancellation?.cancel()
    }

    public func cancelAll() {
        let cancellation = state.withLock { state in
            state.invalidated = true
            return state.active?.cancellation
        }
        cancellation?.cancel()
    }
}

final class CADImportCancellation: Sendable {
    private let value = Mutex(false)
    var isCancelled: Bool { value.withLock { $0 } }
    func cancel() { value.withLock { $0 = true } }
}

/// Only owned numeric error codes cross XPC; no parser messages or source metadata. `geometry` (7) is a finished model
/// beyond the geometry contract's ceilings, kept apart from `budget` (4, an input or output size) so the failure comes
/// back as `.geometryTooComplex` and the message can say "too complex" instead of "too large".
enum CADImportStatus: Int, Sendable {
    case unavailable = 1, malformed = 2, unsupported = 3, budget = 4, deadline = 5, cancelled = 6, geometry = 7
    var number: NSNumber { NSNumber(value: rawValue) }
    init(error: any Error) {
        if error is CancellationError { self = .cancelled; return }
        switch error as? PreviewFailure {
        case .malformedDocument: self = .malformed
        case .unsupportedFormat, .unsupportedVariant: self = .unsupported
        case .inputTooLarge, .outputTooLarge: self = .budget
        case .geometryTooComplex: self = .geometry
        case .deadlineExceeded: self = .deadline
        default: self = .unavailable
        }
    }
    var failure: PreviewFailure {
        switch self {
        case .malformed: .malformedDocument
        case .unsupported: .unsupportedFormat
        case .budget: .outputTooLarge
        case .geometry: .geometryTooComplex
        case .deadline: .deadlineExceeded
        case .unavailable, .cancelled: .unreadableFile
        }
    }
}

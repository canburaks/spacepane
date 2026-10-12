import Foundation
import OSLog
import Synchronization
import PreviewContracts

/// Bounded point dimensions only. No URL, file name, format value or source text enters host telemetry.
public struct PreviewHostGeometry: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init?(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, (0...16_384).contains(width), (0...16_384).contains(height) else { return nil }
        self.width = Int(width.rounded())
        self.height = Int(height.rounded())
    }
}

public enum PreviewHostOutcome: String, Equatable, Sendable {
    case ready, geometry, glyph, disabled, unavailable, cancelled, timedOut
    case settingsUnavailable, configurationUnavailable, invalidGeometry

    public init(_ outcome: PreviewOutcome) {
        switch outcome {
        case .ready: self = .ready
        case .geometryReady: self = .geometry
        case .disabledByUser: self = .disabled
        case .unavailable(.deadlineExceeded): self = .timedOut
        case .unavailable: self = .unavailable
        case .cancelled: self = .cancelled
        }
    }
}

/// Typed events intentionally cannot carry arbitrary messages or error descriptions.
public struct PreviewHostEvent: Equatable, Sendable {
    public enum Surface: String, Sendable { case preview, thumbnail }
    public enum Phase: String, Sendable { case started, settings, finished }
    public enum Settings: String, Sendable { case defaults, loaded, migrated, available, unavailable, unconfigured }
    public let requestID: UUID
    public let surface: Surface
    public let phase: Phase
    public let geometry: PreviewHostGeometry?
    public let settings: Settings?
    public let outcome: PreviewHostOutcome?
    public let elapsedMilliseconds: Double
}

/// One diagnostic lifecycle per host request. Completion is idempotent across work, timeout and teardown.
/// The injected recorder is for tests/diagnostics; the production sink emits debug-level unified log events.
public final class PreviewHostTrace: Sendable {
    private let requestID = UUID()
    private let surface: PreviewHostEvent.Surface
    private let started = ContinuousClock.now
    private let finished = Mutex(false)
    private let record: @Sendable (PreviewHostEvent) -> Void

    public init(surface: PreviewHostEvent.Surface, geometry: PreviewHostGeometry? = nil,
                subsystem: String = Bundle.main.bundleIdentifier ?? "PreviewHost",
                record: (@Sendable (PreviewHostEvent) -> Void)? = nil) {
        self.surface = surface
        self.record = record ?? Self.logger(subsystem: subsystem)
        emit(.started, geometry: geometry)
    }

    public func settings(_ settings: PreviewHostEvent.Settings) {
        guard !finished.withLock({ $0 }) else { return }
        emit(.settings, settings: settings)
    }

    public func finish(_ outcome: PreviewHostOutcome, geometry: PreviewHostGeometry? = nil) {
        let first = finished.withLock { closed in
            guard !closed else { return false }
            closed = true
            return true
        }
        if first { emit(.finished, geometry: geometry, outcome: outcome) }
    }

    private func emit(_ phase: PreviewHostEvent.Phase, geometry: PreviewHostGeometry? = nil,
                      settings: PreviewHostEvent.Settings? = nil, outcome: PreviewHostOutcome? = nil) {
        let elapsed = started.duration(to: .now).components
        record(PreviewHostEvent(requestID: requestID, surface: surface, phase: phase, geometry: geometry,
                                settings: settings, outcome: outcome,
                                elapsedMilliseconds: Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15))
    }

    private static func logger(subsystem: String) -> @Sendable (PreviewHostEvent) -> Void {
        let logger = Logger(subsystem: subsystem, category: "QuickLookHost")
        return { event in
            logger.debug("request=\(event.requestID.uuidString, privacy: .public) surface=\(event.surface.rawValue, privacy: .public) phase=\(event.phase.rawValue, privacy: .public) outcome=\(event.outcome?.rawValue ?? "none", privacy: .public) settings=\(event.settings?.rawValue ?? "none", privacy: .public) milliseconds=\(event.elapsedMilliseconds, privacy: .public) width=\(event.geometry?.width ?? -1, privacy: .public) height=\(event.geometry?.height ?? -1, privacy: .public)")
        }
    }
}

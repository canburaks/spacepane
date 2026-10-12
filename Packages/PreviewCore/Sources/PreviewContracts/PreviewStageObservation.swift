import Foundation
import OSLog
import Synchronization

/// Fixed measurement vocabulary. Events can carry counts and timing, never file names or source values.
public enum PreviewMeasurementStage: String, CaseIterable, Codable, Sendable {
    case preferences, pipeline, modes, tokens, lineIndex, storage, styling, layout, firstDraw, handler

    fileprivate var signpostName: StaticString {
        switch self {
        case .preferences: "preferences"
        case .pipeline: "pipeline"
        case .modes: "modes"
        case .tokens: "tokens"
        case .lineIndex: "lineIndex"
        case .storage: "storage"
        case .styling: "styling"
        case .layout: "layout"
        case .firstDraw: "firstDraw"
        case .handler: "handler"
        }
    }
}

/// A monotonic interval and an actual bounded work count; no wall-clock date or arbitrary label.
public struct PreviewStageObservation: Equatable, Sendable {
    public static let maximumCount = Int(Int32.max)
    public let stage: PreviewMeasurementStage
    public let startedAt: ContinuousClock.Instant
    public let duration: Duration
    public let count: Int

    public init?(stage: PreviewMeasurementStage, startedAt: ContinuousClock.Instant, duration: Duration, count: Int) {
        guard duration >= .zero, (0...Self.maximumCount).contains(count) else { return nil }
        self.stage = stage
        self.startedAt = startedAt
        self.duration = duration
        self.count = count
    }
}

/// An explicitly injected measurement sink. Keeping an optional observer nil does no clock/signpost work.
/// Recorders run synchronously on the measured executor; keep them bounded and never perform source I/O.
public struct PreviewStageObserver: Sendable {
    private let record: @Sendable (PreviewStageObservation) -> Void
    private let signposter: OSSignposter?

    public init(record: @escaping @Sendable (PreviewStageObservation) -> Void) {
        self.record = record
        self.signposter = nil
    }

    /// Opt in to real interval signposts using the caller's technical bundle/log subsystem.
    /// Stage names are fixed, metadata is a count, and the optional recorder sees the same interval.
    public init(signpostingSubsystem: String, record: (@Sendable (PreviewStageObservation) -> Void)? = nil) {
        self.record = record ?? { _ in }
        self.signposter = OSSignposter(subsystem: signpostingSubsystem, category: "PreviewStages")
    }

    public func begin(_ stage: PreviewMeasurementStage) -> PreviewStageInterval {
        PreviewStageInterval(stage: stage, record: record, signposter: signposter)
    }
}

/// One completion even if work, cancellation and teardown race to finish an interval.
public final class PreviewStageInterval: Sendable {
    private let stage: PreviewMeasurementStage
    private let startedAt: ContinuousClock.Instant
    private let record: @Sendable (PreviewStageObservation) -> Void
    private let signposter: OSSignposter?
    private let signpostState: OSSignpostIntervalState?
    private let finished = Mutex(false)

    fileprivate init(stage: PreviewMeasurementStage, record: @escaping @Sendable (PreviewStageObservation) -> Void,
                     signposter: OSSignposter?) {
        self.stage = stage
        self.record = record
        self.signposter = signposter
        self.startedAt = .now
        if let signposter {
            self.signpostState = signposter.beginInterval(stage.signpostName, id: signposter.makeSignpostID())
        } else {
            self.signpostState = nil
        }
    }

    public func finish(count: Int = 1) {
        let first = finished.withLock { closed in
            guard !closed else { return false }
            closed = true
            return true
        }
        guard first else { return }
        let elapsed = startedAt.duration(to: .now)
        guard let observation = PreviewStageObservation(stage: stage, startedAt: startedAt,
                                                         duration: elapsed, count: count) else {
            if let signposter, let signpostState { signposter.endInterval(stage.signpostName, signpostState) }
            return
        }
        if let signposter, let signpostState {
            signposter.endInterval(stage.signpostName, signpostState, "count=\(count, privacy: .public)")
        }
        record(observation)
    }
}

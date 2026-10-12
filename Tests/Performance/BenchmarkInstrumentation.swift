import Darwin
import Foundation
import PreviewContracts
import Synchronization

/// Actual task ledger footprint, not RSS. Unsupported task-info prefixes and
/// failed probes are unavailable. The kernel peak is a process-lifetime peak.
struct BenchmarkPhysicalFootprint: Sendable {
    let current: UInt64?
    let lifetimePeak: UInt64?

    static func read() -> Self {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return Self(current: nil, lifetimePeak: nil) }
        let returnedBytes = Int(count) * MemoryLayout<integer_t>.size
        let footprintEnd = (MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint) ?? Int.max)
            .addingReportingOverflow(MemoryLayout.size(ofValue: information.phys_footprint))
        let peakEnd = (MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak) ?? Int.max)
            .addingReportingOverflow(MemoryLayout.size(ofValue: information.ledger_phys_footprint_peak))
        let current = !footprintEnd.overflow && returnedBytes >= footprintEnd.partialValue ? information.phys_footprint : nil
        let peak = !peakEnd.overflow && returnedBytes >= peakEnd.partialValue && information.ledger_phys_footprint_peak >= 0
            ? UInt64(information.ledger_phys_footprint_peak) : nil
        return Self(current: current, lifetimePeak: peak)
    }
}

struct BenchmarkStageSample: Codable, Sendable {
    let stage: PreviewMeasurementStage
    let count: Int
    let startOffsetNanoseconds: Int64
    let durationNanoseconds: Int64
    let physicalFootprintBytes: UInt64?
    let threadQoS: UInt32
    let thermalState: Int
}

struct BenchmarkMeasurementSummary: Sendable {
    let stageObservations: [BenchmarkStageSample]
    let droppedStageObservationCount: Int
    /// Maximum of actual probes before/after and at stage boundaries, not a kernel request peak.
    let maxSampledPhysicalFootprintBytes: UInt64?
}

func benchmarkNanoseconds(_ duration: Duration) -> Int64 {
    duration.components.seconds * 1_000_000_000 + duration.components.attoseconds / 1_000_000_000
}

/// A bounded synchronous sink shared by both workers; no source I/O or arbitrary labels.
/// Probe/observer overhead is present in every newly instrumented A/B measurement.
final class BenchmarkStageCollector: Sendable {
    private struct State: Sendable {
        var epoch = ContinuousClock.now
        var samples: [BenchmarkStageSample] = []
        var dropped = 0
        var maximumFootprint: UInt64 = 0
        var footprintUnavailable = false
    }
    private let state = Mutex(State())

    func observer(signposts: Bool) -> PreviewStageObserver {
        let recorder: @Sendable (PreviewStageObservation) -> Void = { [self] in record($0) }
        return signposts ? PreviewStageObserver(signpostingSubsystem: "PreviewBenchmark", record: recorder)
            : PreviewStageObserver(record: recorder)
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    @discardableResult func samplePhysicalFootprint() -> BenchmarkPhysicalFootprint {
        let memory = BenchmarkPhysicalFootprint.read()
        state.withLock { state in
            if let footprint = memory.current { state.maximumFootprint = max(state.maximumFootprint, footprint) }
            else { state.footprintUnavailable = true }
        }
        return memory
    }

    private func record(_ observation: PreviewStageObservation) {
        let memory = samplePhysicalFootprint()
        let qos = qos_class_self().rawValue
        let thermalState = ProcessInfo.processInfo.thermalState.rawValue
        state.withLock { state in
            let start = benchmarkNanoseconds(state.epoch.duration(to: observation.startedAt))
            guard start >= 0, state.samples.count < 256 else { state.dropped += 1; return }
            state.samples.append(BenchmarkStageSample(stage: observation.stage, count: observation.count,
                startOffsetNanoseconds: start, durationNanoseconds: benchmarkNanoseconds(observation.duration),
                physicalFootprintBytes: memory.current, threadQoS: qos, thermalState: thermalState))
        }
    }

    func summary() -> BenchmarkMeasurementSummary {
        state.withLock { state in
            BenchmarkMeasurementSummary(stageObservations: state.samples, droppedStageObservationCount: state.dropped,
                maxSampledPhysicalFootprintBytes: state.footprintUnavailable ? nil : state.maximumFootprint)
        }
    }
}

import CoreGraphics
import Darwin
import Dispatch
import Foundation
import ImageIO
import Synchronization
import PreviewContracts
@testable import PreviewRenderers

private enum Failure: Error { case arguments, fixture, header, decode }

private struct Source: Sendable {
    let data: Data
    let width: Int
    let height: Int
    let requestedSide: Int
    let expectsRejection: Bool
}

private struct Bitmap: Codable {
    let width: Int
    let height: Int
    let bitsPerComponent: Int
    let bytesPerRow: Int
    let storageBytes: Int?
    init(_ image: CGImage) {
        width = image.width; height = image.height
        bitsPerComponent = image.bitsPerComponent; bytesPerRow = image.bytesPerRow
        let bytes = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        storageBytes = bytes.overflow ? nil : bytes.partialValue
    }
}

private struct Sampling: Codable {
    let count: Int
    let maximumPhysicalFootprintBytes: UInt64?
    let maximumActiveLeases: Int
    let maximumWaitingDecodes: Int
}

/// Samples actual task ledgers during the native call; stores maxima rather than an unbounded sample log.
private final class Collector: Sendable {
    private struct State {
        var count = 0
        var maximum: UInt64 = 0
        var unavailable = false
        var active = 0
        var waiting = 0
    }
    private let state = Mutex(State())
    private let admission: ImageDecodeAdmission
    init(admission: ImageDecodeAdmission) { self.admission = admission }
    @discardableResult func sample() -> BenchmarkPhysicalFootprint {
        let memory = BenchmarkPhysicalFootprint.read()
        let active = admission.runningCount
        let waiting = admission.waitingCount
        state.withLock { state in
            state.count += 1
            if let current = memory.current { state.maximum = max(state.maximum, current) }
            else { state.unavailable = true }
            state.active = max(state.active, active); state.waiting = max(state.waiting, waiting)
        }
        return memory
    }
    func summary() -> Sampling {
        state.withLock { state in
            Sampling(count: state.count, maximumPhysicalFootprintBytes: state.unavailable ? nil : state.maximum,
                     maximumActiveLeases: state.active, maximumWaitingDecodes: state.waiting)
        }
    }
}

@MainActor private final class Sampler {
    let collector: Collector
    private let timer: DispatchSourceTimer
    init(admission: ImageDecodeAdmission) {
        collector = Collector(admission: admission)
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "PreviewImageFootprint", qos: .userInitiated))
        let collector = collector
        timer.setEventHandler { @Sendable in collector.sample() }
        timer.schedule(deadline: .now(), repeating: .milliseconds(2))
        timer.resume()
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            timer.setCancelHandler { @Sendable in continuation.resume() }
            timer.cancel()
        }
    }
}


private extension KeyedEncodingContainer {
    /// Unavailable measurements remain explicit JSON null values; missing metrics are invalid reports.
    mutating func nullable<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value { try encode(value, forKey: key) } else { try encodeNil(forKey: key) }
    }
}

private struct Sample: Codable {
    let durationNanoseconds: Int64
    let baselinePhysicalFootprintBytes: UInt64?
    let baselineLifetimePeakPhysicalFootprintBytes: UInt64?
    let physicalFootprintHoldingBitmapsBytes: UInt64?
    let physicalFootprintAfterReleaseBytes: UInt64?
    let lifetimePeakPhysicalFootprintBytes: UInt64?
    let maximumSampledPhysicalFootprintBytes: UInt64?
    let sampledIncrementalPeakBytes: UInt64?
    let physicalSampleCount: Int
    let maximumActiveLeases: Int
    let maximumWaitingDecodes: Int
    let sourceWidths: [Int]
    let sourceHeights: [Int]
    let sourceEncodedBytes: [Int]
    let requestedDecodeSides: [Int]
    let decodedBitmaps: [Bitmap]
    let refusedImageCount: Int
    let thermalState: Int
    let cancelledAfterAdmission: Bool
    let retiredTaskReturnedBitmap: Bool?
    let cancellationInsideNativeCallObserved: Bool?
    private enum CodingKeys: String, CodingKey {
        case durationNanoseconds, baselinePhysicalFootprintBytes, baselineLifetimePeakPhysicalFootprintBytes, physicalFootprintHoldingBitmapsBytes, physicalFootprintAfterReleaseBytes, lifetimePeakPhysicalFootprintBytes, maximumSampledPhysicalFootprintBytes, sampledIncrementalPeakBytes, physicalSampleCount, maximumActiveLeases, maximumWaitingDecodes, sourceWidths, sourceHeights, sourceEncodedBytes, requestedDecodeSides, decodedBitmaps, refusedImageCount, thermalState, cancelledAfterAdmission, retiredTaskReturnedBitmap, cancellationInsideNativeCallObserved
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(durationNanoseconds, forKey: .durationNanoseconds)
        try container.nullable(baselinePhysicalFootprintBytes, forKey: .baselinePhysicalFootprintBytes)
        try container.nullable(baselineLifetimePeakPhysicalFootprintBytes, forKey: .baselineLifetimePeakPhysicalFootprintBytes)
        try container.nullable(physicalFootprintHoldingBitmapsBytes, forKey: .physicalFootprintHoldingBitmapsBytes)
        try container.nullable(physicalFootprintAfterReleaseBytes, forKey: .physicalFootprintAfterReleaseBytes)
        try container.nullable(lifetimePeakPhysicalFootprintBytes, forKey: .lifetimePeakPhysicalFootprintBytes)
        try container.nullable(maximumSampledPhysicalFootprintBytes, forKey: .maximumSampledPhysicalFootprintBytes)
        try container.nullable(sampledIncrementalPeakBytes, forKey: .sampledIncrementalPeakBytes)
        try container.encode(physicalSampleCount, forKey: .physicalSampleCount)
        try container.encode(maximumActiveLeases, forKey: .maximumActiveLeases)
        try container.encode(maximumWaitingDecodes, forKey: .maximumWaitingDecodes)
        try container.encode(sourceWidths, forKey: .sourceWidths)
        try container.encode(sourceHeights, forKey: .sourceHeights)
        try container.encode(sourceEncodedBytes, forKey: .sourceEncodedBytes)
        try container.encode(requestedDecodeSides, forKey: .requestedDecodeSides)
        try container.encode(decodedBitmaps, forKey: .decodedBitmaps)
        try container.encode(refusedImageCount, forKey: .refusedImageCount)
        try container.encode(thermalState, forKey: .thermalState)
        try container.encode(cancelledAfterAdmission, forKey: .cancelledAfterAdmission)
        try container.nullable(retiredTaskReturnedBitmap, forKey: .retiredTaskReturnedBitmap)
        try container.nullable(cancellationInsideNativeCallObserved, forKey: .cancellationInsideNativeCallObserved)
    }

}

private struct Report: Codable {
    let schemaVersion: Int
    let scenario: String
    let phase: String
    let unmeasuredWarmupPerformed: Bool
    let warmupLifetimePeakPhysicalFootprintBytes: UInt64?
    let afterReleaseScope: String
    let sampleIntervalMilliseconds: Int
    let baselinePhysicalFootprintBytes: UInt64?
    let baselineLifetimePeakPhysicalFootprintBytes: UInt64?
    let samples: [Sample]
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, scenario, phase, unmeasuredWarmupPerformed, warmupLifetimePeakPhysicalFootprintBytes, afterReleaseScope, sampleIntervalMilliseconds, baselinePhysicalFootprintBytes, baselineLifetimePeakPhysicalFootprintBytes, samples
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(scenario, forKey: .scenario)
        try container.encode(phase, forKey: .phase)
        try container.encode(unmeasuredWarmupPerformed, forKey: .unmeasuredWarmupPerformed)
        try container.nullable(warmupLifetimePeakPhysicalFootprintBytes, forKey: .warmupLifetimePeakPhysicalFootprintBytes)
        try container.encode(afterReleaseScope, forKey: .afterReleaseScope)
        try container.encode(sampleIntervalMilliseconds, forKey: .sampleIntervalMilliseconds)
        try container.nullable(baselinePhysicalFootprintBytes, forKey: .baselinePhysicalFootprintBytes)
        try container.nullable(baselineLifetimePeakPhysicalFootprintBytes, forKey: .baselineLifetimePeakPhysicalFootprintBytes)
        try container.encode(samples, forKey: .samples)
    }

}

private func paths(for scenario: String) throws -> [(String, Bool)] {
    switch scenario {
    case "png40-rgba": [("rgba40.png", false)]
    case "jpeg40-rgb": [("rgb40.jpg", false)]
    case "png16-pair": [("rgba16.png", false), ("rgba16.png", false)]
    case "png40-plus16-pair": [("rgba40.png", false), ("rgba16.png", false), ("rgba16.png", false)]
    case "refused100-rgba": [("rgba100.png", true)]
    case "tiny-avif": [("tiny.avif", false)]
    case "cancel-replace": [("rgba40.png", false), ("rgba40.png", false), ("rgba16.png", false), ("rgba16.png", false)]
    default: throw Failure.arguments
    }
}

private func readSource(_ url: URL, rejection: Bool) throws -> Source {
    let data = try Data(contentsOf: url)
    guard data.count <= 8 * 1_048_576, let format = PreviewImageFormat.sniff(data) else { throw Failure.fixture }
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) == 1,
          CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
          let identifier = CGImageSourceGetType(source) as String?, format.accepts(imageSourceTypeIdentifier: identifier),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
          (1...16_384).contains(width), (1...16_384).contains(height) else { throw Failure.header }
    let side = ImagePagesLayout.decodePixelSize(pixelWidth: width, pixelHeight: height, displayWidth: 2_048, backingScale: 2)
    return Source(data: data, width: width, height: height, requestedSide: side, expectsRejection: rejection)
}

@concurrent private func decode(_ sources: [Source], admission: ImageDecodeAdmission) async -> [DecodedPageImage?] {
    await withTaskGroup(of: (Int, DecodedPageImage?).self) { group in
        for (index, source) in sources.enumerated() {
            group.addTask {
                // This invokes the real production decoder with one shared native resource admission for the worker.
                let image = await ImagePageDecoder.decode(source.data, maximumPixelSize: source.requestedSide, admission: admission)
                return (index, image)
            }
        }
        var results = [DecodedPageImage?](repeating: nil, count: sources.count)
        for await (index, image) in group { results[index] = image }
        return results
    }
}

private final class AcquisitionSignal: Sendable {
    private struct State {
        var open = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())
    func mark() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.open = true
            let waiters = state.waiters; state.waiters = []; return waiters
        }
        for continuation in waiters { continuation.resume() }
    }
    func wait() async {
        await withCheckedContinuation { continuation in
            let open = state.withLock { state -> Bool in
                if state.open { return true }
                state.waiters.append(continuation); return false
            }
            if open { continuation.resume() }
        }
    }
}

private struct Decoded: Sendable {
    var images: [DecodedPageImage?]
    let retiredTaskReturnedBitmap: Bool?
}

@concurrent private func perform(_ sources: [Source], admission: ImageDecodeAdmission,
                                cancellation: AcquisitionSignal?) async -> Decoded {
    guard let cancellation else { return Decoded(images: await decode(sources, admission: admission), retiredTaskReturnedBitmap: nil) }
    let first = sources[0]
    let retired = Task { await ImagePageDecoder.decode(first.data, maximumPixelSize: first.requestedSide, admission: admission) }
    await cancellation.wait()
    // This proves cancellation was requested after acquisition. It does not prove that the native C call
    // had begun or was still executing at that instant; the memory workload still uses actual ImageIO.
    retired.cancel()
    let replacement = await decode(Array(sources.dropFirst()), admission: admission)
    let returned = await retired.value != nil
    return Decoded(images: [nil] + replacement, retiredTaskReturnedBitmap: returned)
}

@main private struct ReleaseImageDecodeBenchmark {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 5, let count = Int(arguments[4]), (1...21).contains(count),
              ["cold", "warm"].contains(arguments[3]), arguments[3] != "cold" || count == 1 else { throw Failure.arguments }
        let requested = try paths(for: arguments[1])
        let isCancellation = arguments[1] == "cancel-replace"
        let isWarm = arguments[3] == "warm"
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let initial = BenchmarkPhysicalFootprint.read()
        func admission(_ signal: AcquisitionSignal?) -> ImageDecodeAdmission {
            guard let signal else { return .processWide }
            return ImageDecodeAdmission(observe: { event in if event == .acquired { signal.mark() } })
        }
        func sources() throws -> [Source] {
            try requested.map { try readSource(directory.appendingPathComponent($0.0), rejection: $0.1) }
        }
        var warmupPeak: UInt64?
        if isWarm {
            let signal = isCancellation ? AcquisitionSignal() : nil
            var warmed = await perform(try sources(), admission: admission(signal), cancellation: signal)
            warmed.images = []
            warmupPeak = BenchmarkPhysicalFootprint.read().lifetimePeak
        }
        var samples: [Sample] = []
        for _ in 0..<count {
            let signal = isCancellation ? AcquisitionSignal() : nil
            let gate = admission(signal)
            // A fresh timer/collector per sample; stop() drains the old source before the next begins.
            let sampler = Sampler(admission: gate)
            let baseline = sampler.collector.sample()
            let start = ContinuousClock.now
            var input = try sources()
            var decoded = await perform(input, admission: gate, cancellation: signal)
            for (index, source) in input.enumerated() where !(isCancellation && index == 0) {
                if source.expectsRejection == (decoded.images[index] != nil) { throw Failure.decode }
            }
            let bitmaps = decoded.images.compactMap { $0.map { Bitmap($0.image) } }
            let widths = input.map(\.width), heights = input.map(\.height)
            let bytes = input.map { $0.data.count }, sides = input.map(\.requestedSide)
            let refused = zip(input, decoded.images).filter { $0.0.expectsRejection && $0.1 == nil }.count
            let holding = withExtendedLifetime(decoded.images) { sampler.collector.sample() }
            decoded.images = []; input = []
            let released = sampler.collector.sample()
            await sampler.stop()
            let summary = sampler.collector.summary()
            let finalMemory = BenchmarkPhysicalFootprint.read()
            guard gate.runningCount == 0, gate.waitingCount == 0 else { throw Failure.decode }
            let incremental = baseline.current.flatMap { base in
                summary.maximumPhysicalFootprintBytes.map { $0 > base ? $0 - base : 0 }
            }
            samples.append(Sample(durationNanoseconds: benchmarkNanoseconds(start.duration(to: .now)),
                                  baselinePhysicalFootprintBytes: baseline.current,
                                  baselineLifetimePeakPhysicalFootprintBytes: baseline.lifetimePeak,
                                  physicalFootprintHoldingBitmapsBytes: holding.current,
                                  physicalFootprintAfterReleaseBytes: released.current,
                                  lifetimePeakPhysicalFootprintBytes: finalMemory.lifetimePeak,
                                  maximumSampledPhysicalFootprintBytes: summary.maximumPhysicalFootprintBytes,
                                  sampledIncrementalPeakBytes: incremental, physicalSampleCount: summary.count,
                                  maximumActiveLeases: summary.maximumActiveLeases, maximumWaitingDecodes: summary.maximumWaitingDecodes,
                                  sourceWidths: widths, sourceHeights: heights, sourceEncodedBytes: bytes,
                                  requestedDecodeSides: sides, decodedBitmaps: bitmaps, refusedImageCount: refused,
                                  thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                                  cancelledAfterAdmission: isCancellation,
                                  retiredTaskReturnedBitmap: decoded.retiredTaskReturnedBitmap,
                                  cancellationInsideNativeCallObserved: nil))
        }
        let report = Report(schemaVersion: 1, scenario: arguments[1], phase: arguments[3],
                            unmeasuredWarmupPerformed: isWarm, warmupLifetimePeakPhysicalFootprintBytes: warmupPeak,
                            afterReleaseScope: "Swift image/source references dropped; immediate footprint may retain allocator/framework memory",
                            sampleIntervalMilliseconds: 2, baselinePhysicalFootprintBytes: initial.current,
                            baselineLifetimePeakPhysicalFootprintBytes: initial.lifetimePeak, samples: samples)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data([10]))
    }
}

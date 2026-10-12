import AppKit
import Darwin
import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewRenderers

private enum Failure: Error { case arguments, outcome, renderer, memory }

private struct Sample: Codable {
    let pipelineNanoseconds: Int64
    let constructionNanoseconds: Int64
    let initialDisplayDrawNanoseconds: Int64
    /// The `display` call alone; layout, line-fragment generation and bitmap drawing are the remainder.
    let initialDisplayCallNanoseconds: Int64
    let secondaryModeDrawNanoseconds: Int64?
    let restyleDrawNanoseconds: Int64
    let scrollDrawNanoseconds: Int64
    /// A display/draw of an already-safe appended snapshot after its predecessor.
    /// This is neither a filesystem watcher nor Finder first-visible timing.
    let logAppendDrawNanoseconds: Int64?
    let residentBeforeBytes: UInt64
    let residentAfterBytes: UInt64
    let lifetimePeakResidentBytes: UInt64
    let physicalFootprintBeforeBytes: UInt64?
    let physicalFootprintAfterBytes: UInt64?
    let maxSampledPhysicalFootprintBytes: UInt64?
    let lifetimePeakPhysicalFootprintBytes: UInt64?
    let stageObservations: [BenchmarkStageSample]
    let droppedStageObservationCount: Int
    let threadQoS: UInt32
    let thermalState: Int
}

private struct Report: Codable {
    let scenario: String
    let safeUTF8Bytes: Int
    let baselineResidentBytes: UInt64
    let baselineLifetimePeakResidentBytes: UInt64
    let baselinePhysicalFootprintBytes: UInt64?
    let baselineLifetimePeakPhysicalFootprintBytes: UInt64?
    let samples: [Sample]
}

private func nanoseconds(_ duration: Duration) -> Int64 {
    duration.components.seconds * 1_000_000_000 + duration.components.attoseconds / 1_000_000_000
}

private func residentBytes() throws -> UInt64 {
    var information = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &information) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { throw Failure.memory }
    return information.resident_size
}

private func peakBytes() throws -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw Failure.memory }
    return UInt64(usage.ru_maxrss)
}

@MainActor private func descendants(_ view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + descendants($0) }
}

/// Real AppKit offscreen rendering, with no app window, preferences or automation API.
@MainActor private func draw(_ view: NSView, collector: BenchmarkStageCollector) throws {
    view.layoutSubtreeIfNeeded()
    for text in descendants(view).compactMap({ $0 as? NSTextView }) where !text.isHidden {
        if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
    }
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
          bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { throw Failure.renderer }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    // Probe while the bitmap is still alive; this remains a sampled maximum.
    collector.samplePhysicalFootprint()
}

@MainActor private func verify(_ view: NSView) throws {
    for child in descendants(view) {
        let text = (child as? NSTextView)?.string ?? (child as? NSTextField)?.stringValue ?? ""
        guard !text.contains("synthetic-benchmark-private-value"),
              !text.contains("synthetic-payload-must-not-be-previewed") else { throw Failure.renderer }
    }
}

@main private struct ReleaseNativeRendererBenchmark {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        guard (arguments.count == 4 || (arguments.count == 5 && arguments[4] == "--signposts")),
              let count = Int(arguments[3]), (1...201).contains(count) else { throw Failure.arguments }
        let baselineResident = try residentBytes()
        let baselinePeak = try peakBytes()
        let baselineFootprint = BenchmarkPhysicalFootprint.read()
        // Initialize AppKit without activating a GUI application or creating windows.
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let collector = BenchmarkStageCollector()
        let observer = collector.observer(signposts: arguments.count == 5)
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, stageObserver: observer)
        let url = URL(fileURLWithPath: arguments[2])
        // Two immutable producer snapshots model a log append. Loading the old
        // snapshot is setup, outside the measured request and append display.
        let logBefore: PreviewOutcome?
        if arguments[1] == "log-append" {
            let prior = await pipeline.preview(url: url.deletingLastPathComponent().appendingPathComponent("before.log"))
            guard case .ready = prior else { throw Failure.outcome }
            logBefore = prior
        } else { logBefore = nil }
        var samples: [Sample] = []
        var safeBytes = 0
        for _ in 0..<count {
            collector.reset()
            let footprintBefore = collector.samplePhysicalFootprint()
            let qos = qos_class_self().rawValue
            let thermalState = ProcessInfo.processInfo.thermalState.rawValue
            let pipelineStart = ContinuousClock.now
            let outcome = await pipeline.preview(url: url)
            let pipelineTime = nanoseconds(pipelineStart.duration(to: .now))
            guard case .ready(let presentation) = outcome,
                  !presentation.text.contains("synthetic-benchmark-private-value") else { throw Failure.outcome }
            safeBytes = presentation.text.utf8.count
            let sample = try autoreleasepool {
                let residentBefore = try residentBytes()
                let constructionStart = ContinuousClock.now
                let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), stageObserver: observer)
                let construction = nanoseconds(constructionStart.duration(to: .now))
                let typography = PreviewTypography(showsLineNumbers: true)
                let firstDraw = observer.begin(.firstDraw)
                let initialStart = ContinuousClock.now
                view.display(outcome, typography: typography, resetsContentState: true)
                let displayCall = nanoseconds(initialStart.duration(to: .now))
                try draw(view, collector: collector)
                let initial = nanoseconds(initialStart.duration(to: .now))
                firstDraw.finish()
                try verify(view)
                var secondary: Int64?
                // The mode control may sit inside a header guide after the chrome skeleton; search the tree.
                if let modes = descendants(view).compactMap({ $0 as? NSSegmentedControl }).first {
                    // Validate the intended first presentations without reaching
                    // into internal renderer models or relying on English labels.
                    let expected: PreviewStrings.Key? = switch arguments[1] {
                    case "csv": .previewModeTable
                    case "listing": .previewModeFiles
                    case "markdown-contents": .previewModeRendered
                    default: nil
                    }
                    if let expected {
                        guard modes.selectedSegment >= 0,
                              modes.label(forSegment: modes.selectedSegment) == PreviewStrings.text(expected) else { throw Failure.renderer }
                    }
                    let contents = (0..<modes.segmentCount).first {
                        modes.label(forSegment: $0) == PreviewStrings.text(.previewModeContents)
                    }
                    let target = arguments[1] == "markdown-contents" ? contents
                        : (modes.segmentCount > 1 && modes.selectedSegment == 0 ? 1 : nil)
                    if arguments[1] == "markdown-contents", target == nil { throw Failure.renderer }
                    if let target {
                        let secondaryStart = ContinuousClock.now
                        modes.selectedSegment = target
                        guard modes.sendAction(modes.action, to: modes.target) else { throw Failure.renderer }
                        try draw(view, collector: collector)
                        secondary = nanoseconds(secondaryStart.duration(to: .now))
                        try verify(view)
                    }
                } else if ["csv", "listing", "markdown-contents"].contains(arguments[1]) {
                    throw Failure.renderer
                }
                let restyleStart = ContinuousClock.now
                view.display(outcome, typography: .init(fontSize: 18, showsLineNumbers: true), theme: .dark)
                try draw(view, collector: collector)
                let restyle = nanoseconds(restyleStart.duration(to: .now))
                let scrollStart = ContinuousClock.now
                for scroll in descendants(view).compactMap({ $0 as? NSScrollView }) where !scroll.isHidden {
                    if let outline = scroll.documentView as? NSOutlineView, outline.numberOfRows > 0 {
                        outline.scrollRowToVisible(outline.numberOfRows - 1)
                    } else if let document = scroll.documentView {
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
                try draw(view, collector: collector)
                let scroll = nanoseconds(scrollStart.duration(to: .now))
                try verify(view)
                var append: Int64?
                if let logBefore {
                    view.display(logBefore, typography: typography, resetsContentState: true)
                    try draw(view, collector: collector)
                    let appendStart = ContinuousClock.now
                    view.display(outcome, typography: typography)
                    try draw(view, collector: collector)
                    append = nanoseconds(appendStart.duration(to: .now))
                    try verify(view)
                }
                let footprintAfter = collector.samplePhysicalFootprint()
                let measurements = collector.summary()
                guard measurements.droppedStageObservationCount == 0,
                      measurements.stageObservations.filter({ $0.stage == .pipeline }).count == 1,
                      measurements.stageObservations.filter({ $0.stage == .firstDraw }).count == 1 else { throw Failure.renderer }
                return Sample(pipelineNanoseconds: pipelineTime, constructionNanoseconds: construction,
                    initialDisplayDrawNanoseconds: initial, initialDisplayCallNanoseconds: displayCall,
                    secondaryModeDrawNanoseconds: secondary,
                    restyleDrawNanoseconds: restyle, scrollDrawNanoseconds: scroll, logAppendDrawNanoseconds: append,
                    residentBeforeBytes: residentBefore, residentAfterBytes: try residentBytes(),
                    lifetimePeakResidentBytes: try peakBytes(), physicalFootprintBeforeBytes: footprintBefore.current,
                    physicalFootprintAfterBytes: footprintAfter.current,
                    maxSampledPhysicalFootprintBytes: measurements.maxSampledPhysicalFootprintBytes,
                    lifetimePeakPhysicalFootprintBytes: footprintAfter.lifetimePeak,
                    stageObservations: measurements.stageObservations,
                    droppedStageObservationCount: measurements.droppedStageObservationCount,
                    threadQoS: qos, thermalState: thermalState)
            }
            samples.append(sample)
        }
        let report = Report(scenario: arguments[1], safeUTF8Bytes: safeBytes,
            baselineResidentBytes: baselineResident, baselineLifetimePeakResidentBytes: baselinePeak,
            baselinePhysicalFootprintBytes: baselineFootprint.current,
            baselineLifetimePeakPhysicalFootprintBytes: baselineFootprint.lifetimePeak, samples: samples)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data([10]))
    }
}

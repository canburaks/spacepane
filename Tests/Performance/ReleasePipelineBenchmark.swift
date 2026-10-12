import Darwin
import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats

/// A command-line measurement worker, deliberately outside app/extension targets.
/// Its runner creates only synthetic files and checks them for changes afterward.
private enum FixtureCase: String {
    case text, json, jsonLines = "json-lines", malformedJSON = "malformed-json"
    case malformedJSONLines = "malformed-json-lines", oversizedText = "oversized-text"
    case zip, sqlite, denseSecrets = "dense-secrets"
    case csv, listing, markdownContents = "markdown-contents", environment
    case sourceOneMiB = "source-1mib", jsonOneMiB = "json-1mib", logAppend = "log-append"

    var formatID: FormatID {
        switch self {
        case .text, .oversizedText, .denseSecrets: .plainText
        case .logAppend: .log
        case .json, .malformedJSON, .jsonOneMiB: .json
        case .jsonLines, .malformedJSONLines: .jsonLines
        case .zip, .listing: .zip
        case .sqlite: .sqlite
        case .csv: .csv
        case .markdownContents: .markdown
        case .environment: .environment
        case .sourceOneMiB: .sourceCode
        }
    }

    func validate(_ outcome: PreviewOutcome) throws -> OutcomeSummary {
        switch self {
        case .malformedJSON:
            guard outcome == .unavailable(.malformedDocument) else { throw BenchmarkFailure.unexpectedOutcome }
            return OutcomeSummary(state: "unavailable.malformedDocument")
        case .oversizedText:
            // Plain text deliberately admits bounded complete leading lines. The fixture is over
            // the input budget; it must exercise that production policy, not an obsolete rejection.
            guard case .ready(let presentation) = outcome, presentation.formatID == .plainText,
                  presentation.truncatedSourceBytes == 1_048_578,
                  !presentation.text.isEmpty, presentation.text.utf8.count <= PreviewBudget.standard.maxInputBytes,
                  presentation.lineCount <= PreviewBudget.standard.maxTextLines else {
                throw BenchmarkFailure.unexpectedOutcome
            }
            return OutcomeSummary(state: "ready.truncated", outputUTF8Bytes: presentation.text.utf8.count,
                                  redactions: presentation.redactionCount)
        default:
            guard case .ready(let presentation) = outcome,
                  presentation.formatID == formatID,
                  !presentation.text.contains("synthetic-benchmark-private-value"),
                  !presentation.text.contains("synthetic-payload-must-not-be-previewed") else {
                throw BenchmarkFailure.unexpectedOutcome
            }
            if self == .malformedJSONLines {
                guard presentation.invalidRecordLines == [2], presentation.sourceRecordCount == 3 else {
                    throw BenchmarkFailure.unexpectedOutcome
                }
            } else if !presentation.invalidRecordLines.isEmpty {
                throw BenchmarkFailure.unexpectedOutcome
            }
            if self != .zip && self != .listing, presentation.redactionCount == 0 { throw BenchmarkFailure.unexpectedOutcome }
            if self == .environment, !presentation.findings.contains(where: { $0.kind == .hiddenZeroWidth }) {
                throw BenchmarkFailure.unexpectedOutcome
            }
            return OutcomeSummary(state: self == .malformedJSONLines ? "ready.concealedMalformedRecord" : "ready",
                outputUTF8Bytes: presentation.text.utf8.count, redactions: presentation.redactionCount)
        }
    }
}

private enum BenchmarkFailure: String, Error { case invalidArguments, unexpectedOutcome, memoryProbeFailed }

private struct OutcomeSummary: Codable, Equatable {
    let state: String
    var outputUTF8Bytes = 0
    var redactions = 0
}

private struct Sample: Codable {
    let requestNanoseconds: Int64
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

private struct RunReport: Codable {
    let scenario: String
    let pipelineConstructionNanoseconds: Int64
    let baselineResidentBytes: UInt64
    let baselineLifetimePeakResidentBytes: UInt64
    let baselinePhysicalFootprintBytes: UInt64?
    let baselineLifetimePeakPhysicalFootprintBytes: UInt64?
    let samples: [Sample]
    let outcome: OutcomeSummary
}

private func nanoseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    return components.seconds * 1_000_000_000 + components.attoseconds / 1_000_000_000
}

private func residentBytes() throws -> UInt64 {
    var information = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &information) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard status == KERN_SUCCESS else { throw BenchmarkFailure.memoryProbeFailed }
    return information.resident_size
}

private func lifetimePeakResidentBytes() throws -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0, usage.ru_maxrss >= 0 else { throw BenchmarkFailure.memoryProbeFailed }
    // Darwin reports ru_maxrss in bytes (unlike Linux's KiB convention).
    return UInt64(usage.ru_maxrss)
}

@main private struct ReleasePipelineBenchmark {
    static func main() async {
        do { try await measure() }
        catch {
            let kind = (error as? BenchmarkFailure)?.rawValue ?? "workerFailed"
            FileHandle.standardError.write(Data("Pipeline benchmark failed: \(kind)\n".utf8))
            exit(1)
        }
    }

    private static func measure() async throws {
        let arguments = CommandLine.arguments
        guard (arguments.count == 4 || (arguments.count == 5 && arguments[4] == "--signposts")),
              let scenario = FixtureCase(rawValue: arguments[1]),
              let count = Int(arguments[3]), (1...201).contains(count) else {
            throw BenchmarkFailure.invalidArguments
        }
        let url = URL(fileURLWithPath: arguments[2])
        let baselineResident = try residentBytes()
        let baselinePeak = try lifetimePeakResidentBytes()
        let baselineFootprint = BenchmarkPhysicalFootprint.read()
        let collector = BenchmarkStageCollector()
        let observer = collector.observer(signposts: arguments.count == 5)
        let constructionStart = ContinuousClock.now
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, stageObserver: observer)
        let construction = nanoseconds(constructionStart.duration(to: .now))
        var samples: [Sample] = []
        var summary: OutcomeSummary?
        for _ in 0..<count {
            collector.reset()
            let before = try residentBytes()
            let footprintBefore = collector.samplePhysicalFootprint()
            let qos = qos_class_self().rawValue
            let thermalState = ProcessInfo.processInfo.thermalState.rawValue
            let start = ContinuousClock.now
            let outcome = await pipeline.preview(url: url, preferences: .defaults, budget: .standard)
            let elapsed = nanoseconds(start.duration(to: .now))
            // Observe RSS while this request's safe result is still alive. The timer
            // excludes these outer probes, validation, encoding and file checks;
            // injected stage-recorder probes remain part of every instrumented run.
            let after = try residentBytes()
            let peak = try lifetimePeakResidentBytes()
            let footprintAfter = collector.samplePhysicalFootprint()
            let measurements = collector.summary()
            guard measurements.droppedStageObservationCount == 0,
                  measurements.stageObservations.count == 1,
                  measurements.stageObservations.first?.stage == .pipeline,
                  measurements.stageObservations.first?.count == 1 else { throw BenchmarkFailure.unexpectedOutcome }
            let current = try scenario.validate(outcome)
            if let summary, current != summary { throw BenchmarkFailure.unexpectedOutcome }
            summary = current
            samples.append(Sample(requestNanoseconds: elapsed, residentBeforeBytes: before,
                residentAfterBytes: after, lifetimePeakResidentBytes: peak,
                physicalFootprintBeforeBytes: footprintBefore.current, physicalFootprintAfterBytes: footprintAfter.current,
                maxSampledPhysicalFootprintBytes: measurements.maxSampledPhysicalFootprintBytes,
                lifetimePeakPhysicalFootprintBytes: footprintAfter.lifetimePeak,
                stageObservations: measurements.stageObservations, droppedStageObservationCount: measurements.droppedStageObservationCount,
                threadQoS: qos, thermalState: thermalState))
        }
        guard let summary else { throw BenchmarkFailure.unexpectedOutcome }
        let report = RunReport(scenario: scenario.rawValue, pipelineConstructionNanoseconds: construction,
            baselineResidentBytes: baselineResident, baselineLifetimePeakResidentBytes: baselinePeak,
            baselinePhysicalFootprintBytes: baselineFootprint.current, baselineLifetimePeakPhysicalFootprintBytes: baselineFootprint.lifetimePeak,
            samples: samples, outcome: summary)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data([10]))
    }
}

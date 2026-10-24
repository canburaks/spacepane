import Foundation
import Darwin
import Synchronization
import Testing
@testable import PreviewCADFormats
import PreviewContracts
import PreviewCore

@Suite("CAD import boundary") struct CADSafetyTests {
    func wire() -> Data {
        var data = Data("PRVCAD01".utf8)
        func u32(_ n: UInt32) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func f64(_ n: Double) { var v = n.bitPattern.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        [3, 3, 1, 1].forEach { u32(UInt32($0)) }
        [0, 0, 0, 10, 10, 0].forEach { f64(Double($0)) }
        for p: [Float] in [[-1,-1,0],[1,-1,0],[0,1,0]] { (p + [0,0,1]).forEach { u32($0.bitPattern) } }
        [0,1,2].forEach { u32(UInt32($0)) }
        return data
    }
    @Test func numericProtocolRejectsTruncationTrailingBytesCountsAndUnsafeCoordinates() throws {
        let context = RequestContext(budget: GeometryLimits.requestBudget), valid = wire()
        #expect(try CADMeshDecoder.decode(valid, context: context).indices == [0,1,2])
        for cut in [0,7,71,72,valid.count-1] {
            #expect(throws: PreviewFailure.malformedDocument) { try CADMeshDecoder.decode(Data(valid.prefix(cut)), context: context) }
        }
        #expect(throws: PreviewFailure.malformedDocument) { try CADMeshDecoder.decode(valid + Data([0]), context: context) }
        var huge = valid; huge.replaceSubrange(8..<12, with: [255,255,255,255])
        #expect(throws: PreviewFailure.outputTooLarge) { try CADMeshDecoder.decode(huge, context: context) }
        var nan = valid; nan.replaceSubrange(72..<76, with: [0,0,192,127])
        #expect(throws: PreviewFailure.malformedDocument) { try CADMeshDecoder.decode(nan, context: context) }
    }
    @Test func disabledCADNeverReadsOrConstructsImporter() async {
        let pipeline = PreviewPipeline(catalog: cadCatalog, registrations: CADFormatAdapters.registrations(workerURL: URL(fileURLWithPath: "/missing/helper")), reader: ForbiddenReader())
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/missing/private.igs")) == .disabledByUser(.iges))
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/missing/private.step")) == .disabledByUser(.step))
    }
    @Test func missingWorkerHasSpecificFailureAndExplicitEnablementWorks() async {
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: .iges, catalog: cadCatalog)
        let pipeline = PreviewPipeline(catalog: cadCatalog, registrations: CADFormatAdapters.registrations(workerURL: URL(fileURLWithPath: "/missing/helper")), reader: EmptyReader())
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/missing/private.igs"), preferences: preferences) == .unavailable(.unreadableFile))
    }
    @Test func formatBudgetIsSelectedOnlyForCADAndExplicitBudgetWins() async {
        let registration = AdapterRegistration(formatID: .iges, defaultBudget: GeometryLimits.requestBudget) { BudgetMeshAdapter() }
        let pipeline = PreviewPipeline(catalog: cadCatalog, registrations: [registration], reader: EmptyReader())
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: .iges, catalog: cadCatalog)
        let url = URL(fileURLWithPath: "/missing/test.igs")
        guard case .geometryReady = await pipeline.preview(url: url, preferences: preferences) else {
            Issue.record("CAD request did not receive its opt-in budget"); return
        }
        #expect(await pipeline.preview(url: url, preferences: preferences, budget: .standard) == .unavailable(.inputTooLarge))
    }
    @Test func centralPipelineEnforcesOutputBudgetForAnyGeometryAdapter() async {
        let registration = AdapterRegistration(formatID: .iges, defaultBudget: GeometryLimits.requestBudget) { BudgetMeshAdapter(enforcesBudget: false) }
        let pipeline = PreviewPipeline(catalog: cadCatalog, registrations: [registration], reader: EmptyReader())
        var preferences = PreviewPreferencesSnapshot.defaults; preferences.setEnabled(true, for: .iges, catalog: cadCatalog)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/missing/test.igs"), preferences: preferences,
            budget: PreviewBudget(maxOutputUTF8Bytes: 1)) == .unavailable(.outputTooLarge))
    }
    @Test func transportTerminatesBlockedChildAtDeadlineAndCancellation() async throws {
        let command = URL(fileURLWithPath: "/bin/sleep")
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try CADWorkerProcess.run(executable: command, arguments: ["5"], input: Data(), context: RequestContext(budget: PreviewBudget(maxMilliseconds: 60)))
        }
        // Cancellation is placed at a checkpoint of the polling loop, a few rounds after the child started, instead of
        // after a sleep: when other tests hold the shared thread pool, a sleeping test resumes only after the child has
        // finished on its own and finds nothing left to cancel (first hosted run of Round 2).
        let checkpoints = Mutex(0)
        let task = Task.detached { () -> Bool in
            var context = RequestContext(budget: GeometryLimits.requestBudget)
            context.checkpointObserver = {
                let count = checkpoints.withLock { $0 += 1; return $0 }
                if count == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            do { _ = try CADWorkerProcess.run(executable: command, arguments: ["5"], input: Data(), context: context) }
            catch is CancellationError { return true }
            catch { Issue.record("Unexpected cancellation failure: \(error)") }
            return false
        }
        #expect(await task.value, "A cancelled request must end instead of waiting for the blocked child")
    }
    @Test func transportBoundsOutputAndDrainsEarlyExit() throws {
        #expect(throws: PreviewFailure.outputTooLarge) {
            try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], input: Data(), context: RequestContext(budget: PreviewBudget(maxOutputUTF8Bytes: 64)))
        }
        let echoed = try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: Data(repeating: 42, count: 200_000), context: RequestContext(budget: .standard))
        #expect(echoed == Data(repeating: 42, count: 200_000))
        #expect(throws: PreviewFailure.unreadableFile) {
            try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], input: Data(repeating: 42, count: 200_000), context: RequestContext(budget: .standard))
        }
    }
    @Test func transportMissingExecutableFailsAndSuccessfulChildIsAlreadyReaped() throws {
        #expect(throws: PreviewFailure.unreadableFile) {
            try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/missing/CADWorker"), arguments: [],
                input: Data(), context: RequestContext(budget: .standard))
        }
        let output = try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%s' $$"], input: Data(), context: RequestContext(budget: .standard))
        let pid = try #require(Int32(String(decoding: output, as: UTF8.self)))
        var status: Int32 = 0
        #expect(waitpid(pid, &status, WNOHANG) == -1)
        #expect(errno == ECHILD)
    }
    @Test func transportDeadlineReapsChildBeforeReturning() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidURL = directory.appendingPathComponent("pid")
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", #"printf '%s' "$$" > "$1"; exec /bin/sleep 5"#, "cad-test", pidURL.path],
                input: Data(), context: RequestContext(budget: PreviewBudget(maxMilliseconds: 120)))
        }
        let pid = try #require(Int32(String(decoding: Data(contentsOf: pidURL), as: UTF8.self)))
        var status: Int32 = 0
        #expect(waitpid(pid, &status, WNOHANG) == -1)
        #expect(errno == ECHILD)
    }
    @Test func transportUsesOnlyOwnedEnvironment() throws {
        let output = try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: [],
            input: Data(), context: RequestContext(budget: .standard))
        #expect(Set(String(decoding: output, as: UTF8.self).split(separator: "\n")) == ["LANG=C", "LC_ALL=C"])
    }
    @Test(arguments: [2, 3, 4]) func transportPreservesTypedWorkerFailureStatuses(status: Int) {
        let failure: PreviewFailure = status == 2 ? .malformedDocument : status == 3 ? .unsupportedFormat : .outputTooLarge
        #expect(throws: failure) {
            try CADWorkerProcess.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit \(status)"],
                input: Data(), context: RequestContext(budget: .standard))
        }
    }
}
private struct ForbiddenReader: PreviewFileReading {
    func read(url: URL, context: RequestContext) throws -> FileBytes { Issue.record("Disabled CAD accessed source"); throw PreviewFailure.unreadableFile }
}
private struct EmptyReader: PreviewFileReading {
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: Data()) }
}

private struct BudgetMeshAdapter: GeometryFormatAdapter {
    var enforcesBudget = true
    func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        guard !enforcesBudget || context.budget == GeometryLimits.requestBudget else { throw PreviewFailure.inputTooLarge }
        return try PreviewMesh(positions: [SIMD3(-1,-1,0),SIMD3(1,-1,0),SIMD3(0,1,0)],
            normals: Array(repeating: SIMD3(0,0,1), count: 3), indices: [0,1,2],
            bounds: GeometryBounds(minimum: .zero, maximum: SIMD3(10,10,0)), faceCount: 1)
    }
}

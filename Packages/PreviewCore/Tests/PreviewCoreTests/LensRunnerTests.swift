import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore

// Decision 029: lenses read the concealed text, see only metadata about the file, never run for
// app-made summaries, and a lens's own failure never costs the preview or the other lenses' findings.

private struct BytesReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
}

private struct OriginAdapter: FormatAdapter {
    let origin: TextOrigin
    func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        ParsedTextDocument(text: input.text, origin: origin)
    }
}

/// Records what it was given and reports one finding on line 2.
private final class RecordingLens: PreviewTextLens {
    private let state = Mutex((calls: 0, texts: [String](), requests: [PreviewLensRequest]()))
    var calls: Int { state.withLock { $0.calls } }
    var texts: [String] { state.withLock { $0.texts } }
    var requests: [PreviewLensRequest] { state.withLock { $0.requests } }

    func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        state.withLock {
            $0.calls += 1
            $0.texts.append(text)
            $0.requests.append(request)
        }
        return [PreviewFinding(kind: .scriptElevates, count: 1, lines: [2])]
    }
}

private struct FailingLens: PreviewTextLens {
    func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        throw PreviewFailure.malformedDocument
    }
}

private struct CancellingLens: PreviewTextLens {
    func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        throw CancellationError()
    }
}

private func outcome(_ text: String, path: String, origin: TextOrigin = .source,
                     lenses: [any PreviewTextLens]) async -> PreviewOutcome {
    let registration = AdapterRegistration(formatID: .plainText) { OriginAdapter(origin: origin) }.adding(lenses: lenses)
    let pipeline = PreviewPipeline(registrations: [registration], reader: BytesReader(data: Data(text.utf8)))
    return await pipeline.preview(url: URL(fileURLWithPath: path))
}

@Suite("Lens runner")
struct LensRunnerTests {
    @Test func aLensReadsTheConcealedTextAndOnlyMetadataAboutTheFile() async throws {
        let lens = RecordingLens()
        let text = "first line\npassword = synthetic-not-a-real-secret-123\n"
        let result = await outcome(text, path: "/fixtures/.vscode/notes.txt", lenses: [lens])
        guard case .ready(let presentation) = result else { Issue.record("\(result)"); return }

        #expect(lens.calls == 1)
        let seen = try #require(lens.texts.first)
        #expect(seen == presentation.text)
        #expect(!seen.contains("synthetic-not-a-real-secret-123"))
        let request = try #require(lens.requests.first)
        #expect(request.formatID == .plainText)
        #expect(request.fileName == "notes.txt")
        #expect(request.parentDirectoryName == ".vscode")
        #expect(request.origin == .source)
        #expect(presentation.findings.contains(PreviewFinding(kind: .scriptElevates, count: 1, lines: [2])))
    }

    @Test func aFailingLensDropsOnlyItsOwnFindings() async {
        let lens = RecordingLens()
        let result = await outcome("a\nb\n", path: "/fixtures/notes.txt", lenses: [FailingLens(), lens])
        guard case .ready(let presentation) = result else { Issue.record("\(result)"); return }
        #expect(lens.calls == 1)
        #expect(presentation.findings.map(\.kind) == [.scriptElevates])
    }

    @Test func cancellationInsideALensCancelsTheRequest() async {
        let result = await outcome("a\nb\n", path: "/fixtures/notes.txt", lenses: [CancellingLens()])
        guard case .cancelled = result else { Issue.record("expected cancellation, got \(result)"); return }
    }

    @Test func appMadeSummariesAreNeverRead() async {
        let lens = RecordingLens()
        let result = await outcome("a\nb\n", path: "/fixtures/notes.txt", origin: .summary, lenses: [lens])
        guard case .ready(let presentation) = result else { Issue.record("\(result)"); return }
        #expect(lens.calls == 0)
        #expect(presentation.findings.isEmpty)
    }

    @Test func convertedTextIsReadAndTheRootHasNoParentName() async throws {
        let lens = RecordingLens()
        _ = await outcome("a\nb\n", path: "/notes.txt", origin: .converted, lenses: [lens])
        let request = try #require(lens.requests.first)
        #expect(request.origin == .converted)
        #expect(request.parentDirectoryName == nil)
    }

    @Test func registrationsWithoutLensesAreUnchanged() {
        let plain = AdapterRegistration(formatID: .plainText) { OriginAdapter(origin: .source) }
        #expect(plain.lenses.isEmpty)
        #expect(plain.adding(lenses: [FailingLens(), CancellingLens()]).lenses.count == 2)
    }
}

@Suite("Decision 029 finding details")
struct ValidityDetailTests {
    @Test func daysAndSecondsAreBoundedAndCompareByValue() {
        #expect(PreviewFinding(kind: .certificateExpiresSoon, count: 1, detail: .days(-4)).detail == .days(0))
        #expect(PreviewFinding(kind: .launchInterval, count: 1, detail: .seconds(-1)).detail == .seconds(0))
        #expect(PreviewFindingDetail.days(3) != .seconds(3))
        #expect(PreviewFindingDetail.seconds(300) == .seconds(300))
    }

    @Test func everyNewKindHasAStableDottedIdentityAndASeverity() {
        let groups = ["script.", "autorun.", "export.", "launch.", "certificate.", "profile."]
        let added = PreviewFindingKind.allCases.filter { kind in groups.contains { kind.rawValue.hasPrefix($0) } }
        #expect(added.count == 34)
        #expect(Set(added.map(\.rawValue)).count == added.count)
        #expect(added.filter { $0.defaultSeverity == .warning }.count == 14)
    }
}

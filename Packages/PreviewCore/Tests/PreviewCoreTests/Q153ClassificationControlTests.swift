import Foundation
import Darwin
import UniformTypeIdentifiers
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 classification compatibility and guarded kinds")
struct Q153ClassificationControlTests {
    @Test func materializedUnknownNameKeepsTheTypeAndPreviewPath() async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(), types = Q153ContentTypes(probe: probe)
        let counts = Q153ClassificationCounts(), pipeline = q153ClassificationPipeline(probe: probe, types: types, counts: counts)
        #expect(await pipeline.inspect(url: fixture.url) == .enabled(.plainText))
        guard case .ready(let presentation) = await pipeline.preview(url: fixture.url) else {
            Issue.record("Materialized fallback lost its preview"); return
        }
        #expect(presentation.text == "ordinary text" && presentation.formatID == .plainText)
        #expect(counts.snapshot.reads == 1 && counts.snapshot.factories == 1 && counts.snapshot.parses == 1)
        #expect(types.snapshot.calls == 2 && types.snapshot.outsideScopes == 0)
        #expect(probe.snapshot.entries == 2 && probe.snapshot.restores == 2)
        #expect(probe.attempts(.metadata(.preflight)) == 2 && probe.attempts(.metadata(.finalRead)) == 2)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test(arguments: [Q153TypeResult.ordinary, .posix(EACCES), .type(nil)])
    func ordinaryOptionalLookupErrorsStayUnsupported(result: Q153TypeResult) async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(), types = Q153ContentTypes(result, probe: probe), counts = Q153ClassificationCounts()
        #expect(await q153ClassificationPipeline(probe: probe, types: types, counts: counts).inspect(url: fixture.url) == .unsupported)
        #expect(counts.snapshot.reads == 0 && counts.snapshot.factories == 0)
        #expect(types.snapshot.calls == 1 && types.snapshot.outsideScopes == 0 && probe.snapshot.restores == 1)
        #expect(probe.attempts(.metadata(.finalRead)) == 1)
        probe.expectNoLeaks()
    }

    @Test func aliasesAndDisabledChoicesBypassFailingPolicyAndMetadata() async {
        let probe = Q153ReadProbe(dataless: .preflight, entryFails: true), types = Q153ContentTypes(.posix(EDEADLK), probe: probe)
        let counts = Q153ClassificationCounts(), pipeline = q153ClassificationPipeline(probe: probe, types: types, counts: counts, catalog: .standard)
        for (name, id) in [("document.JSON", FormatID.json), ("archive.ZIP", .zip), ("tune.MID", .midi)] {
            let url = URL(fileURLWithPath: "/unused/" + name)
            var enabled = PreviewPreferencesSnapshot.defaults; enabled.setEnabled(true, for: id)
            #expect(await pipeline.inspect(url: url, preferences: enabled) == .enabled(id))
            var disabled = enabled; disabled.setEnabled(false, for: id)
            #expect(await pipeline.inspect(url: url, preferences: disabled) == .disabledByUser(id))
            #expect(await pipeline.preview(url: url, preferences: disabled) == .disabledByUser(id))
        }
        #expect(types.snapshot.calls == 0 && probe.snapshot.entries == 0 && probe.snapshot.operations.isEmpty)
        #expect(counts.snapshot.reads == 0 && counts.snapshot.factories == 0)
    }

    @Test func nativeMaterializedDirectoryAndExtensionlessRoutingArePreserved() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let extensionless = fixture.directory.appendingPathComponent("owned-source")
        try Data("ordinary text".utf8).write(to: extensionless) // Fixture writer only.
        let before = try fixture.snapshot(), classifier = PreviewFileClassifier()
        #expect(try classifier.classify(fixture.directory, catalog: .standard) == .folder)
        #expect(try classifier.classify(extensionless, catalog: .standard) == .extensionlessText)
        try fixture.expectUnchanged(before)
        #expect(try Data(contentsOf: extensionless) == Data("ordinary text".utf8))
    }

    @Test(arguments: [false, true])
    func symlinkAndFIFORefuseBeforeTypeLookup(fifo: Bool) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("unknown-kind")
        if fifo { #expect(url.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) } == 0) }
        else { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: fixture.url) }
        let probe = Q153ReadProbe(), types = Q153ContentTypes(.type(.data), probe: probe)
        let classifier = PreviewFileClassifier(access: BoundedReadAccess(policy: probe, probe: probe), contentTypes: types)
        #expect(throws: PreviewFailure.notRegularFile) { try classifier.classify(url, catalog: .standard) }
        #expect(types.snapshot.calls == 0 && probe.attempts(.metadata(.finalRead)) == 0)
        #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
        probe.expectNoLeaks()
    }

    @Test(arguments: [Int32(ENOENT), EACCES])
    func rawMetadataErrorsKeepTheirSourceFailureMapping(code: Int32) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(fault: .metadata(.preflight), faultErrno: code), types = Q153ContentTypes(probe: probe)
        let classifier = PreviewFileClassifier(access: BoundedReadAccess(policy: probe, probe: probe), contentTypes: types)
        let expected: PreviewFailure = code == ENOENT ? .missingFile : .unreadableFile
        #expect(throws: expected) { try classifier.classify(fixture.url, catalog: q153ClassificationCatalog) }
        #expect(types.snapshot.calls == 0 && probe.snapshot.restores == 1)
        probe.expectNoLeaks()
    }

    @Test func invalidBudgetAndCancelledWorkerNeverStartClassification() async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(entryFails: true), types = Q153ContentTypes(probe: probe), counts = Q153ClassificationCounts()
        let pipeline = q153ClassificationPipeline(probe: probe, types: types, counts: counts)
        #expect(await pipeline.preview(url: fixture.url, budget: PreviewBudget(maxInputBytes: 0)) == .unavailable(.invalidBudget))
        let url = fixture.url
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.preview(url: url)
        }
        #expect(await cancelled.value == .cancelled)
        #expect(types.snapshot.calls == 0 && probe.snapshot.entries == 0 && probe.snapshot.operations.isEmpty)
        #expect(counts.snapshot.reads == 0 && counts.snapshot.factories == 0)
    }
}

import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 classification refusal")
struct Q153ClassificationTests {
    @Test(arguments: [BoundedReadMetadataCheck.preflight, .finalRead])
    func datalessFlagsNeverReachReaderOrFactory(check: BoundedReadMetadataCheck) async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot()
        for isPreview in [false, true] {
            let probe = Q153ReadProbe(dataless: check), counts = Q153ClassificationCounts()
            let types = Q153ContentTypes(probe: probe)
            let pipeline = q153ClassificationPipeline(probe: probe, types: types, counts: counts)
            if isPreview { #expect(await pipeline.preview(url: fixture.url) == .unavailable(.unavailableContent)) }
            else { #expect(await pipeline.inspect(url: fixture.url) == .unavailable(.unavailableContent)) }
            #expect(types.snapshot.calls == (check == .preflight ? 0 : 1))
            #expect(types.snapshot.outsideScopes == 0 && probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
            #expect(probe.attempts(.metadata(.preflight)) == 1)
            #expect(probe.attempts(.metadata(.finalRead)) == (check == .preflight ? 0 : 1))
            #expect(counts.snapshot.reads == 0 && counts.snapshot.factories == 0 && counts.snapshot.parses == 0)
            probe.expectNoLeaks()
        }
        try fixture.expectUnchanged(before)
    }

    @Test(arguments: [BoundedReadOperation.metadata(.preflight), .metadata(.finalRead)])
    func rawMetadataRefusalIsCapturedBeforeRestoration(operation: BoundedReadOperation) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(fault: operation, clobbersErrno: true), types = Q153ContentTypes(probe: probe)
        let classifier = PreviewFileClassifier(access: BoundedReadAccess(policy: probe, probe: probe), contentTypes: types)
        let savedErrno = errno; defer { errno = savedErrno }
        do { _ = try classifier.classify(fixture.url, catalog: q153ClassificationCatalog); Issue.record("Refused metadata returned a type") }
        catch {
            let restoredErrno = errno // Capture before Testing or other framework work.
            #expect(error as? PreviewFailure == .unavailableContent)
            #expect(restoredErrno == EACCES)
        }
        #expect(probe.attempts(operation) == 1 && probe.snapshot.restores == 1)
        #expect(types.snapshot.calls == (operation == .metadata(.preflight) ? 0 : 1))
        probe.expectNoLeaks()
    }

    @Test(arguments: [Q153TypeResult.posix(EDEADLK), .wrappedPOSIX(EDEADLK), .deepChain])
    func foundationRefusalNeverBecomesOptionalAbsence(result: Q153TypeResult) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(clobbersErrno: true), types = Q153ContentTypes(result, probe: probe)
        let classifier = PreviewFileClassifier(access: BoundedReadAccess(policy: probe, probe: probe), contentTypes: types)
        let savedErrno = errno; defer { errno = savedErrno }
        #expect(throws: PreviewFailure.unavailableContent) { try classifier.classify(fixture.url, catalog: q153ClassificationCatalog) }
        #expect(types.snapshot.calls == 1 && types.snapshot.outsideScopes == 0)
        #expect(probe.attempts(.metadata(.finalRead)) == 0 && probe.snapshot.restores == 1)
        probe.expectNoLeaks()
    }

    @Test(arguments: [false, true])
    func entryAndRestorationFailureNeverPublishClassification(restore: Bool) async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(entryFails: !restore, restoreFails: restore), types = Q153ContentTypes(probe: probe)
        let counts = Q153ClassificationCounts(), pipeline = q153ClassificationPipeline(probe: probe, types: types, counts: counts)
        #expect(await pipeline.inspect(url: fixture.url) == .unavailable(.unavailableContent))
        #expect(types.snapshot.calls == (restore ? 1 : 0) && types.snapshot.outsideScopes == 0)
        #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == (restore ? 1 : 0))
        #expect(probe.attempts(.metadata(.preflight)) == (restore ? 1 : 0))
        #expect(probe.attempts(.metadata(.finalRead)) == (restore ? 1 : 0))
        #expect(counts.snapshot.reads == 0 && counts.snapshot.factories == 0)
        probe.expectNoLeaks()
    }
}

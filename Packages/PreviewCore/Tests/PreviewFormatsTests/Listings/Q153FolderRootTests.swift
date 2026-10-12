import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Q153 selected folder root refusal")
struct Q153FolderRootTests {
    @Test(arguments: [DirectoryMetadataCheck.rootPreflight, .rootOpened, .rootFinal])
    func flagsRefuseTheSelectedRoot(check: DirectoryMetadataCheck) throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(dataless: check)
        #expect(throws: PreviewFailure.unavailableContent) {
            try FolderSummaryAdapter(access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        }
        let state = probe.snapshot
        #expect(state.entries == 1 && state.restores == 1)
        #expect(state.rootOpened.count == (check == .rootPreflight ? 0 : 1))
        probe.expectClean()
    }
    @Test(arguments: [true, false])
    func policyFailureDoesNotReturnASummary(entryFailure: Bool) throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(entryFails: entryFailure, restoreFails: !entryFailure)
        #expect(throws: PreviewFailure.unavailableContent) {
            try FolderSummaryAdapter(access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        }
        let state = probe.snapshot
        #expect(state.entries == 1 && state.restores == (entryFailure ? 0 : 1))
        #expect(state.rootOpened.count == (entryFailure ? 0 : 1))
        probe.expectClean()
    }
    @Test(arguments: [DirectoryReadOperation.openRoot, .metadata(.rootOpened)])
    func typedNativeRefusalSurvivesRestoreClobber(operation: DirectoryReadOperation) throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let originalErrno = errno; defer { errno = originalErrno }
        let probe = Q153DirectoryProbe(); probe.configure(fault: operation, error: EDEADLK, clobbersErrno: true)
        var failure: PreviewFailure?, restoredErrno: Int32?
        do { _ = try FolderSummaryAdapter(access: probe.access).parse(url: fixture.url, context: q153DirectoryContext()) }
        catch { restoredErrno = errno; failure = error as? PreviewFailure }
        #expect(failure == .unavailableContent && restoredErrno == EACCES)
        #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
        probe.expectClean()
    }
    @Test func localSuccessUsesOneWholeScopeAndClosesBeforeRestore() throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe()
        let document = try FolderSummaryAdapter(access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        #expect(document.text.contains("sample.txt"))
        #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == 1 && probe.snapshot.rootOpened.count == 1)
        probe.expectClean()
    }
    @Test func successfulSummaryDoesNotMutateSource() throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(); let probe = Q153DirectoryProbe()
        _ = try FolderSummaryAdapter(access: probe.access).parse(url: fixture.url, context: q153DirectoryContext())
        #expect(try fixture.snapshot() == before)
        probe.expectClean()
    }
    @Test func cancelledContextDoesNotEnterPolicyOrOpen() async throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(), url = fixture.url
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try FolderSummaryAdapter(access: probe.access).parse(url: url, context: q153DirectoryContext())
            }
        }
        await task.value
        #expect(probe.snapshot.entries == 0 && probe.snapshot.operations.isEmpty)
        probe.expectClean()
    }
}

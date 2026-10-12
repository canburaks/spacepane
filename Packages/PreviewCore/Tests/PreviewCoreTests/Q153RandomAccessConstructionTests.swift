import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 random source ownership and availability")
struct Q153RandomAccessConstructionTests {
    @Test(arguments: [BoundedReadMetadataCheck.preflight, .opened])
    func datalessMetadataNeverPublishesAByteSource(check: BoundedReadMetadataCheck) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(dataless: check)
        #expect(throws: PreviewFailure.unavailableContent) {
            try BoundedFileReader(policy: probe, probe: probe).openRandomAccess(url: fixture.url, context: q153Context())
        }
        #expect(probe.snapshot.entries == 1 && probe.snapshot.liveDescriptorsAtRestore == [0])
        #expect(probe.snapshot.opened.count == (check == .opened ? 1 : 0))
        #expect(probe.attempts(.pread) == 0 && probe.attempts(.read) == 0)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test(arguments: [BoundedReadOperation.open, .metadata(.opened)])
    func constructionErrnoIsMappedBeforeRestoreAndAcquiredDescriptorsClose(operation: BoundedReadOperation) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(fault: operation, clobbersErrno: true)
        let savedErrno = errno; defer { errno = savedErrno }
        do {
            var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
                .openRandomAccess(url: fixture.url, context: q153Context())
            #expect(source != nil)
            source = nil
            Issue.record("Refused construction published a source")
        } catch {
            let restoredErrno = errno
            #expect(error as? PreviewFailure == .unavailableContent)
            #expect(restoredErrno == EACCES)
        }
        #expect(probe.snapshot.liveDescriptorsAtRestore == [0])
        #expect(probe.snapshot.opened.count == (operation == .open ? 0 : 1))
        #expect(probe.attempts(operation) == 1 && probe.attempts(.pread) == 0)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test(arguments: [true, false])
    func policyEntryAndRestoreFailuresNeverPublishOwners(entryFails: Bool) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(entryFails: entryFails, restoreFails: !entryFails)
        #expect(throws: PreviewFailure.unavailableContent) {
            try BoundedFileReader(policy: probe, probe: probe).openRandomAccess(url: fixture.url, context: q153Context())
        }
        #expect(probe.snapshot.entries == 1)
        if entryFails {
            #expect(probe.snapshot.operations.isEmpty && probe.snapshot.opened.isEmpty && probe.snapshot.restores == 0)
        } else {
            // Completed owner was alive at restoration, then released before the caller observed failure.
            #expect(probe.snapshot.liveDescriptorsAtRestore == [1])
            #expect(probe.snapshot.opened.count == 1 && probe.snapshot.closed.count == 1)
        }
        probe.expectNoLeaks()
    }

    @Test func successfulConstructionKeepsTheCompleteOwnerUntilCallerRelease() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe()
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: q153Context(limit: 4))
        weak var observed: BoundedRandomAccessFile?
        if let source { observed = source as? BoundedRandomAccessFile }
        withExtendedLifetime(source) {
            #expect(source?.byteCount == 8 && observed != nil)
            #expect(probe.snapshot.opened.count == 1 && probe.snapshot.closed.isEmpty)
            #expect(probe.snapshot.liveDescriptorsAtRestore == [1])
            #expect(probe.snapshot.operations == [.metadata(.preflight), .open, .metadata(.opened)])
        }
        source = nil
        #expect(observed == nil && probe.snapshot.closed.count == 1)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }
}

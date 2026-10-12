import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 complete and leading safety controls")
struct Q153BoundedReadControlTests {
    @Test func completeAndLeadingReadsRetainByteLimitsAndOneWholeScope() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot()
        for leading in [false, true] {
            let probe = Q153ReadProbe(), reader = BoundedFileReader(policy: probe, probe: probe)
            if leading {
                let result = try reader.readLeading(url: fixture.url, context: q153Context(limit: 4))
                #expect(result.data == Data([1, 2, 3, 4]) && result.totalByteCount == 8)
                #expect(probe.attempts(.read) == 1 && probe.attempts(.metadata(.finalRead)) == 1)
            } else {
                #expect(throws: PreviewFailure.inputTooLarge) { try reader.read(url: fixture.url, context: q153Context(limit: 4)) }
                #expect(probe.attempts(.read) == 0)
            }
            #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
            #expect(probe.snapshot.closed.count == 1 && probe.snapshot.liveDescriptorsAtRestore == [0])
            probe.expectNoLeaks()
        }
        let probe = Q153ReadProbe()
        let result = try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context(limit: 8))
        #expect(result.data == before.bytes && result.totalByteCount == nil)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func scopeEntryAndRestorationFailuresNeverPublishBytes() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        for entryFails in [true, false] {
            let probe = Q153ReadProbe(entryFails: entryFails, restoreFails: !entryFails)
            #expect(throws: PreviewFailure.unavailableContent) {
                try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context())
            }
            #expect(probe.snapshot.entries == 1)
            #expect(entryFails ? probe.snapshot.operations.isEmpty : probe.snapshot.closed.count == 1)
            probe.expectNoLeaks()
        }
    }

    @Test func interruptedReadRetriesInsideTheSameScope() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(fault: .read, faultErrno: EINTR)
        let result = try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context())
        #expect(result.data == Data([1, 2, 3, 4, 5, 6, 7, 8]))
        #expect(probe.attempts(.read) == 3 && probe.snapshot.entries == 1)
        probe.expectNoLeaks()
    }

    @Test func sqliteSidecarPassesAndReadLockRetainTheirOrdering() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe()
        var context = q153Context(); context.sourceReadPolicy = .sqliteSnapshot
        #expect(try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: context).data == before.bytes)
        #expect(probe.snapshot.operations == [
            .sqliteSidecar, .sqliteSidecar, .sqliteSidecar, .metadata(.preflight), .open,
            .metadata(.opened), .sqliteLock, .sqliteSidecar, .sqliteSidecar, .sqliteSidecar,
            .read, .read, .metadata(.finalRead), .sqliteSidecar, .sqliteSidecar, .sqliteSidecar])
        #expect(probe.snapshot.entries == 1 && probe.snapshot.liveDescriptorsAtRestore == [0])
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
        let refused = Q153ReadProbe(fault: .sqliteSidecar, faultNumber: 4)
        #expect(throws: PreviewFailure.unavailableContent) {
            try BoundedFileReader(policy: refused, probe: refused).read(url: fixture.url, context: context)
        }
        #expect(refused.attempts(.sqliteLock) == 1 && refused.attempts(.read) == 0 && refused.snapshot.closed.count == 1)
        refused.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func sparseLocalFileWithoutDatalessFlagKeepsItsZeroBytes() throws {
        let fixture = try Q153ReadFixture(Data()); defer { fixture.remove() }
        let writer = try FileHandle(forWritingTo: fixture.url)
        try writer.truncate(atOffset: 8192); try writer.close()
        let before = try fixture.snapshot(), probe = Q153ReadProbe()
        let bytes = try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context(limit: 8192))
        #expect(bytes.data == Data(repeating: 0, count: 8192))
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func expiredRequestSkipsScopeAndAllSourceIO() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe()
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url,
                context: RequestContext(budget: .init(maxMilliseconds: 0)))
        }
        #expect(probe.snapshot.entries == 0 && probe.snapshot.operations.isEmpty)
    }

    @Test func cancelledRequestSkipsScopeAndAllSourceIO() async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(), url = fixture.url
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try BoundedFileReader(policy: probe, probe: probe).read(url: url, context: q153Context())
            }
        }
        await task.value
        #expect(probe.snapshot.entries == 0 && probe.snapshot.operations.isEmpty)
    }
}

import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 complete and leading dataless reads")
struct Q153BoundedReadTests {
    @Test(arguments: [false, true])
    func datalessPreflightNeverOpensContent(leading: Bool) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(dataless: .preflight)
        let reader = BoundedFileReader(policy: probe, probe: probe)
        #expect(throws: PreviewFailure.unavailableContent) {
            _ = try leading ? reader.readLeading(url: fixture.url, context: q153Context())
                            : reader.read(url: fixture.url, context: q153Context())
        }
        #expect(probe.attempts(.open) == 0 && probe.attempts(.read) == 0)
        #expect(probe.snapshot.entries == 1 && probe.snapshot.opened.isEmpty)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test(arguments: [false, true])
    func materializedPreflightThenDatalessOpenedDescriptorClosesWithoutReading(leading: Bool) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(dataless: .opened)
        let reader = BoundedFileReader(policy: probe, probe: probe)
        #expect(throws: PreviewFailure.unavailableContent) {
            _ = try leading ? reader.readLeading(url: fixture.url, context: q153Context())
                            : reader.read(url: fixture.url, context: q153Context())
        }
        #expect(probe.attempts(.metadata(.preflight)) == 1 && probe.attempts(.metadata(.opened)) == 1)
        #expect(probe.snapshot.opened.count == 1 && probe.snapshot.closed.count == 1)
        #expect(probe.attempts(.read) == 0 && probe.snapshot.liveDescriptorsAtRestore == [0])
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func failedAuthoritativeMetadataClosesExactlyOnce() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(fault: .metadata(.opened), faultErrno: EACCES)
        #expect(throws: PreviewFailure.unreadableFile) {
            try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context())
        }
        #expect(probe.snapshot.opened.count == 1 && probe.snapshot.closed.count == 1 && probe.attempts(.read) == 0)
        probe.expectNoLeaks()
    }

    @Test(arguments: [BoundedReadOperation.open, .read])
    func nativeMaterializationRefusalSurvivesRestorationClobberingErrno(operation: BoundedReadOperation) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(fault: operation, clobbersErrno: true)
        let savedErrno = errno; defer { errno = savedErrno }
        do {
            _ = try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context())
            Issue.record("Refused source read returned bytes")
        } catch {
            let restoredErrno = errno
            #expect(error as? PreviewFailure == .unavailableContent)
            #expect(restoredErrno == EACCES)
        }
        #expect(probe.attempts(operation) == 1 && probe.snapshot.restores == 1)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func finalDatalessFlagsNeverPublishPreviouslyReadBytes() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(dataless: .finalRead)
        #expect(throws: PreviewFailure.unavailableContent) {
            try BoundedFileReader(policy: probe, probe: probe).read(url: fixture.url, context: q153Context())
        }
        #expect(probe.attempts(.read) > 0 && probe.snapshot.closed.count == 1)
        probe.expectNoLeaks()
    }
}

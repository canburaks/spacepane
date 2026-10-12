import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 scoped random ranges and cumulative charging")
struct Q153RandomAccessRangeTests {
    @Test(arguments: [BoundedReadMetadataCheck.beforeRangeRead, .finalRead])
    func laterFlagTransitionsRejectBytesAndFailedValidRangesStayCharged(check: BoundedReadMetadataCheck) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(), context = q153Context(limit: 4)
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: context)
        #expect(try source?.read(offset: 0, count: 1, context: context) == Data([1]))
        probe.setDataless(check)
        #expect(throws: PreviewFailure.unavailableContent) { try source?.read(offset: 0, count: 1, context: context) }
        #expect(probe.attempts(.pread) == (check == .beforeRangeRead ? 1 : 2))
        probe.setDataless(nil)
        #expect(try source?.read(offset: 0, count: 2, context: context) == Data([1, 2]))
        #expect(throws: PreviewFailure.inputTooLarge) { try source?.read(offset: 0, count: 1, context: context) }
        #expect(probe.snapshot.entries == 4 && probe.snapshot.restores == 4)
        #expect(probe.attempts(.metadata(.beforeRangeRead)) == 3)
        source = nil
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func preadRefusalSurvivesRestoreErrnoAndItsRequestedBytesStayCharged() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(fault: .pread, clobbersErrno: true), context = q153Context(limit: 4)
        let savedErrno = errno; defer { errno = savedErrno }
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: context)
        do {
            _ = try source?.read(offset: 0, count: 3, context: context)
            Issue.record("Refused range returned bytes")
        } catch {
            let restoredErrno = errno
            #expect(error as? PreviewFailure == .unavailableContent)
            #expect(restoredErrno == EACCES)
        }
        #expect(throws: PreviewFailure.inputTooLarge) { try source?.read(offset: 0, count: 2, context: context) }
        #expect(probe.snapshot.entries == 2 && probe.attempts(.pread) == 1)
        #expect(try source?.read(offset: 0, count: 1, context: context) == Data([1]))
        #expect(probe.snapshot.entries == 3 && probe.attempts(.pread) == 2)
        source = nil
        probe.expectNoLeaks()
    }

    @Test(arguments: [true, false])
    func validRangesChargeEvenWhenPolicyEntryOrRestoreFails(entryFails: Bool) throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(), context = q153Context(limit: 3)
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: context)
        probe.setPolicyFailures(entry: entryFails, restore: !entryFails)
        #expect(throws: PreviewFailure.unavailableContent) { try source?.read(offset: 0, count: 2, context: context) }
        #expect(probe.attempts(.pread) == (entryFails ? 0 : 1))
        probe.setPolicyFailures()
        #expect(throws: PreviewFailure.inputTooLarge) { try source?.read(offset: 0, count: 2, context: context) }
        #expect(try source?.read(offset: 0, count: 1, context: context) == Data([1]))
        withExtendedLifetime(source) {
            #expect(probe.snapshot.entries == 3 && probe.snapshot.closed.isEmpty)
        }
        source = nil
        probe.expectNoLeaks()
    }

    @Test func overlapsChargeButInvalidAndExpiredAdmissionDoNot() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(), context = q153Context(limit: 4)
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: context)
        #expect(throws: PreviewFailure.malformedDocument) { try source?.read(offset: -1, count: 2, context: context) }
        #expect(throws: PreviewFailure.malformedDocument) { try source?.read(offset: 7, count: 2, context: context) }
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try source?.read(offset: 0, count: 3, context: RequestContext(budget: .init(maxMilliseconds: 0)))
        }
        #expect(probe.snapshot.entries == 1)
        #expect(try source?.read(offset: 0, count: 0, context: context) == Data())
        #expect(probe.attempts(.pread) == 0 && probe.snapshot.entries == 2)
        #expect(try source?.read(offset: 0, count: 2, context: context) == Data([1, 2]))
        #expect(try source?.read(offset: 0, count: 2, context: context) == Data([1, 2]))
        #expect(throws: PreviewFailure.inputTooLarge) { try source?.read(offset: 0, count: 1, context: context) }
        #expect(probe.snapshot.entries == 4 && probe.attempts(.metadata(.finalRead)) == 3)
        source = nil
        probe.expectNoLeaks()
    }

    @Test func interruptedPreadRetriesWithinOneScopeAndOneCharge() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(fault: .pread, faultErrno: EINTR), context = q153Context(limit: 4)
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: context)
        #expect(try source?.read(offset: 0, count: 4, context: context) == Data([1, 2, 3, 4]))
        #expect(probe.attempts(.pread) == 2 && probe.snapshot.entries == 2)
        #expect(throws: PreviewFailure.inputTooLarge) { try source?.read(offset: 0, count: 1, context: context) }
        #expect(probe.snapshot.entries == 2)
        source = nil
        probe.expectNoLeaks()
    }
}

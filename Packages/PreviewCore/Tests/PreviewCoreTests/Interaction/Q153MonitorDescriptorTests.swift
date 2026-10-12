import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

extension LiveReload {
    @Suite("Q153 event descriptor ownership and refusal")
    struct Q153MonitorDescriptorTests {
        @Test func datalessPreflightNeverAcquiresDescriptor() throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let before = try fixture.snapshot(), probe = Q153ReadProbe(dataless: .preflight)
            #expect(throws: PreviewFailure.unavailableContent) { try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe)) }
            #expect(probe.attempts(.open) == 0 && probe.snapshot.opened.isEmpty && probe.snapshot.entries == 1)
            probe.expectNoLeaks(); try fixture.expectUnchanged(before)
        }

        @Test(arguments: [false, true])
        func authoritativeFailureClosesLocallyBeforeRestoration(flags: Bool) throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe(dataless: flags ? .opened : nil,
                fault: flags ? nil : .metadata(.opened), faultErrno: EACCES)
            let expected: PreviewFailure = flags ? .unavailableContent : .unreadableFile
            #expect(throws: expected) { try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe)) }
            #expect(probe.snapshot.opened.count == 1 && probe.snapshot.closed.count == 1)
            #expect(probe.snapshot.liveDescriptorsAtRestore == [0] && probe.snapshot.entries == 1)
            probe.expectNoLeaks()
        }

        @Test func restorationFailureReleasesCompletedOwnerBeforeCatch() throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe(restoreFails: true)
            do {
                let owner = try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe))
                withExtendedLifetime(owner) { Issue.record("Failed restoration published an event owner") }
            } catch {
                #expect(error as? PreviewFailure == .unavailableContent)
                #expect(probe.snapshot.closed.count == 1)
            }
            #expect(probe.snapshot.liveDescriptorsAtRestore == [1])
            probe.expectNoLeaks()
        }

        @Test(arguments: [false, true])
        func regularAndDirectoryOwnersRemainLiveUntilRelease(directory: Bool) throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let before = try fixture.snapshot(), probe = Q153ReadProbe()
            var owner: PreviewMonitorDescriptor? = try PreviewMonitorDescriptor.open(
                watching: directory ? fixture.directory : fixture.url, access: access(probe))
            weak var weakOwner = owner
            withExtendedLifetime(owner) {
                #expect(weakOwner != nil && probe.snapshot.closed.isEmpty)
                #expect(probe.snapshot.liveDescriptorsAtRestore == [1] && probe.snapshot.entries == 1)
            }
            owner = nil
            #expect(weakOwner == nil && probe.snapshot.closed.count == 1)
            probe.expectNoLeaks(); try fixture.expectUnchanged(before)
        }

        @Test(arguments: [BoundedReadOperation.metadata(.preflight), .open, .metadata(.opened)])
        func nativeRefusalSurvivesRestorationClobberingErrno(operation: BoundedReadOperation) throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe(fault: operation, clobbersErrno: true)
            let savedErrno = errno; defer { errno = savedErrno }
            do {
                let owner = try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe))
                withExtendedLifetime(owner) { Issue.record("Refused event open published an owner") }
            } catch {
                let restoredErrno = errno
                #expect(error as? PreviewFailure == .unavailableContent)
                #expect(restoredErrno == EACCES)
            }
            #expect(probe.attempts(operation) == 1 && probe.snapshot.liveDescriptorsAtRestore == [0])
            probe.expectNoLeaks()
        }

        @Test func entryFailurePrecedesEveryNativeOperation() throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe(entryFails: true)
            #expect(throws: PreviewFailure.unavailableContent) { try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe)) }
            #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == 0 && probe.snapshot.operations.isEmpty)
            probe.expectNoLeaks()
        }

        @Test(arguments: [false, true])
        func symlinkAndFIFORefuseBeforeOpen(fifo: Bool) throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let url = fixture.directory.appendingPathComponent("unwatchable")
            if fifo { #expect(url.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) } == 0) }
            else { try FileManager.default.createSymbolicLink(at: url, withDestinationURL: fixture.url) }
            let probe = Q153ReadProbe()
            #expect(throws: PreviewFailure.notRegularFile) { try PreviewMonitorDescriptor.open(watching: url, access: access(probe)) }
            #expect(probe.attempts(.open) == 0 && probe.snapshot.entries == 1 && probe.snapshot.opened.isEmpty)
            probe.expectNoLeaks()
        }

        @Test(arguments: [0, 1, 2, 3])
        func currentOwnerCheckRefusesFlagsFaultEntryOrRestoreFailure(kind: Int) throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe(dataless: kind == 0 ? .finalRead : nil,
                fault: kind == 1 ? .metadata(.finalRead) : nil)
            var owner: PreviewMonitorDescriptor? = try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe))
            if kind > 1 { probe.setPolicyFailures(entry: kind == 2, restore: kind == 3) }
            #expect(throws: PreviewFailure.unavailableContent) { try owner?.requireAvailable() }
            withExtendedLifetime(owner) { #expect(probe.snapshot.closed.isEmpty) }
            #expect(probe.attempts(.metadata(.finalRead)) == (kind == 2 ? 0 : 1))
            #expect(probe.snapshot.entries == 2 && probe.snapshot.restores == (kind == 2 ? 1 : 2))
            owner = nil
            #expect(probe.snapshot.closed.count == 1)
            probe.expectNoLeaks()
        }

        @Test func closingTwiceAndCheckingClosedOwnerNeverTouchRecycledDescriptor() throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe()
            let owner = try PreviewMonitorDescriptor.open(watching: fixture.url, access: access(probe))
            owner.close(); owner.close()
            #expect(throws: PreviewFailure.unavailableContent) { try owner.requireAvailable() }
            #expect(probe.attempts(.metadata(.finalRead)) == 0 && probe.snapshot.closed.count == 1)
            probe.expectNoLeaks()
        }
        private func access(_ probe: Q153ReadProbe) -> BoundedReadAccess { BoundedReadAccess(policy: probe, probe: probe) }
    }
}

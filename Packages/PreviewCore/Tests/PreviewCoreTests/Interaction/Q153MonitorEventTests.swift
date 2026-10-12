import Foundation
import Dispatch
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

extension LiveReload {
    @Suite("Q153 owned monitor event and reopen refusal")
    struct Q153MonitorEventTests {
        @Test(arguments: [false, true])
        func refusedInitialConstructionInstallsNothing(entry: Bool) async throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let probe = Q153ReadProbe(dataless: entry ? nil : .preflight, entryFails: entry), timers = Q153MonitorTimers()
            let monitor = PreviewSourceMonitor(watching: fixture.url, access: access(probe), reopenScheduler: timers)
            #expect(monitor == nil && probe.snapshot.opened.isEmpty && timers.scheduledCount == 0)
            if let monitor { await monitor.stopAndWait() } // RED success also releases real registration.
            probe.expectNoLeaks()
        }

        @Test(arguments: [false, true])
        func attribRefusalFinishesOnceAndReleasesCurrentRegistration(flags: Bool) async throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let before = try fixture.snapshot(), timers = Q153MonitorTimers()
            let probe = Q153ReadProbe(dataless: flags ? .finalRead : nil, fault: flags ? nil : .metadata(.finalRead))
            let monitor = try #require(PreviewSourceMonitor(watching: fixture.url, access: access(probe), reopenScheduler: timers))
            await monitor.receive([.attrib]); await monitor.stopAndWait()
            var events = monitor.events.makeAsyncIterator()
            let first = await events.next(), second = await events.next()
            #expect(first == .revoked && second == nil)
            #expect(probe.snapshot.entries == 2 && probe.snapshot.restores == 2 && timers.scheduledCount == 0)
            #expect(probe.attempts(.metadata(.finalRead)) == 1 && probe.snapshot.closed.count == 1)
            probe.expectNoLeaks(); try fixture.expectUnchanged(before)
        }

        @Test(arguments: [0, 1, 2, 3])
        func refusedReopenIsTerminalWithoutRetry(kind: Int) async throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let timers = Q153MonitorTimers(), probe = Q153ReadProbe(fault: kind == 2 ? .open : nil, faultNumber: 2)
            let monitor = try #require(PreviewSourceMonitor(watching: fixture.url, access: access(probe), reopenScheduler: timers))
            if kind < 2 { probe.setDataless(kind == 0 ? .preflight : .opened) }
            if kind == 3 { probe.setPolicyFailures(restore: true) }
            await monitor.receive([.rename, .attrib]); await monitor.stopAndWait()
            var events = monitor.events.makeAsyncIterator()
            let first = await events.next(), second = await events.next()
            #expect(first == .revoked && second == nil)
            #expect(timers.scheduledCount == 0 && probe.snapshot.entries == 2 && probe.snapshot.restores == 2)
            #expect(probe.attempts(.metadata(.finalRead)) == 0, "rename precedes attrib validation")
            #expect(probe.snapshot.opened.count == (kind == 1 || kind == 3 ? 2 : 1))
            probe.expectNoLeaks()
        }

        @Test func retryableReopenUsesAnotherScopedFactoryWhenManualTimerFires() async throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let timers = Q153MonitorTimers(), probe = Q153ReadProbe(fault: .metadata(.preflight), faultNumber: 2, faultErrno: ENOENT)
            let monitor = try #require(PreviewSourceMonitor(watching: fixture.url, access: access(probe), reopenScheduler: timers))
            await monitor.receive([.rename])
            #expect(timers.scheduledCount == 1 && probe.snapshot.entries == 2)
            timers.fireFirst()
            await monitor.waitForPendingOperations() // Acknowledge Core's enqueued factory before shutdown.
            await monitor.stopAndWait()
            #expect(timers.scheduledCount == 1 && probe.snapshot.entries == 3 && probe.snapshot.restores == 3)
            #expect(probe.attempts(.metadata(.preflight)) == 3 && probe.snapshot.opened.count == 2)
            probe.expectNoLeaks()
        }

        @Test func stoppedMonitorIgnoresAlreadyQueuedRetryCallback() async throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let timers = Q153MonitorTimers(), probe = Q153ReadProbe(fault: .metadata(.preflight), faultNumber: 2, faultErrno: ENOENT)
            let monitor = try #require(PreviewSourceMonitor(watching: fixture.url, access: access(probe), reopenScheduler: timers))
            await monitor.receive([.rename]); await monitor.stopAndWait()
            timers.fireFirst(includingCancelled: true) // Simulate callback already released by its scheduler.
            await monitor.waitForPendingOperations() // Acknowledge stale callback; stopped Core does no work.
            #expect(probe.snapshot.entries == 2 && probe.snapshot.opened.count == 1 && timers.scheduledCount == 1)
            probe.expectNoLeaks()
        }

        @Test func revokePrecedesRenameAndAttribWithoutMetadataOrReopen() async throws {
            let fixture = try Q153ReadFixture(); defer { fixture.remove() }
            let timers = Q153MonitorTimers(), probe = Q153ReadProbe(dataless: .finalRead)
            let monitor = try #require(PreviewSourceMonitor(watching: fixture.url, access: access(probe), reopenScheduler: timers))
            await monitor.receive([.revoke, .rename, .attrib]); await monitor.stopAndWait()
            var events = monitor.events.makeAsyncIterator()
            let first = await events.next(), second = await events.next()
            #expect(first == .revoked && second == nil)
            #expect(probe.snapshot.entries == 1 && probe.attempts(.metadata(.preflight)) == 1)
            #expect(probe.attempts(.metadata(.finalRead)) == 0 && timers.scheduledCount == 0)
            probe.expectNoLeaks()
        }
        private func access(_ probe: Q153ReadProbe) -> BoundedReadAccess { BoundedReadAccess(policy: probe, probe: probe) }
    }
}

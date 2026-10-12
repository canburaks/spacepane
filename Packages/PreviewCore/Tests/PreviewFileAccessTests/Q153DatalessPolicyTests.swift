import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFileAccess

#if canImport(Darwin)
import Darwin

// These tests exercise an injected policy driver, never the process/thread's real I/O policy.
private final class Q153PolicyCalls: DatalessIOPolicyCalls, Sendable {
    struct State {
        var policy: Int32
        var events: [String] = []
        var failsGet = false
        var failsGetNumber: Int?
        var gets = 0
        var failsSetNumber: Int?
        var sets = 0
        var clobbersErrnoOnSetNumber: Int?
        var liveOwners = 0
        var ownersAtSets: [Int] = []
    }
    private let state: Mutex<State>
    init(policy: Int32 = Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON),
         failsGet: Bool = false, failsSetNumber: Int? = nil, failsGetNumber: Int? = nil,
         clobbersErrnoOnSetNumber: Int? = nil) {
        state = Mutex(State(policy: policy, failsGet: failsGet, failsGetNumber: failsGetNumber,
                            failsSetNumber: failsSetNumber, clobbersErrnoOnSetNumber: clobbersErrnoOnSetNumber))
    }
    func get(scope: Int32) -> Int32 {
        state.withLock { value in
            value.events.append("get:\(scope)")
            value.gets += 1
            return value.failsGet || value.gets == value.failsGetNumber ? -1 : value.policy
        }
    }
    func set(scope: Int32, policy: Int32) -> Int32 {
        state.withLock { value in
            value.events.append("set:\(scope):\(policy)")
            value.sets += 1
            value.ownersAtSets.append(value.liveOwners)
            if value.sets == value.clobbersErrnoOnSetNumber { errno = EACCES }
            guard value.sets != value.failsSetNumber else { return -1 }
            value.policy = policy
            return 0
        }
    }
    func note(_ event: String) { state.withLock { $0.events.append(event) } }
    var events: [String] { state.withLock { $0.events } }
    var policy: Int32 { state.withLock { $0.policy } }
    var liveOwners: Int { state.withLock { $0.liveOwners } }
    var ownersAtSets: [Int] { state.withLock { $0.ownersAtSets } }
    func ownerCreated() { state.withLock { $0.liveOwners += 1; $0.events.append("owner-created") } }
    func ownerReleased() { state.withLock { $0.liveOwners -= 1; $0.events.append("owner-released") } }
}

// A counted owned result stands in for a request-owned descriptor; no file or policy syscall.
private final class Q153OwnedResult: Sendable {
    private let calls: Q153PolicyCalls
    init(_ calls: Q153PolicyCalls) { self.calls = calls; calls.ownerCreated() }
    deinit { calls.ownerReleased() }
}

@Suite("Q153 dataless materialization policy")
struct Q153DatalessPolicyTests {
    @Test func onlyDatalessFlagsRefuseContentAndTheFlagIsReadOnlyMetadata() throws {
        #expect(!DatalessFiles.isDataless(flags: 0))
        #expect(!DatalessFiles.isDataless(flags: UInt32(UF_HIDDEN | UF_COMPRESSED)))
        #expect(DatalessFiles.isDataless(flags: UInt32(SF_DATALESS | UF_HIDDEN)))
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.requireMaterialized(flags: UInt32(SF_DATALESS))
        }
        try DatalessFiles.requireMaterialized(flags: 0)
        // No chflags/fchflags: a synthetic SF_DATALESS stat is not a real provider fixture.
    }

    @Test func materializationRefusalMapsWithoutChangingOtherErrnoPaths() {
        #expect(DatalessFiles.materializationFailure(forPOSIXError: EDEADLK) == .unavailableContent)
        for error in [ENOENT, ELOOP, EACCES, EINTR] {
            #expect(DatalessFiles.materializationFailure(forPOSIXError: error) == nil)
        }
    }

    @Test func processBootstrapRequestsOffAndPropagatesFailure() throws {
        let calls = Q153PolicyCalls()
        try DatalessFiles.refuseMaterializationForProcess(using: calls)
        #expect(calls.events == ["set:0:1"])
        let failing = Q153PolicyCalls(failsSetNumber: 1)
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.refuseMaterializationForProcess(using: failing)
        }
    }

    @Test func synchronousBodyRunsOffAndRestoresTheOriginalThreadPolicy() throws {
        let calls = Q153PolicyCalls()
        let value = try DatalessFiles.withoutMaterializing(using: calls) {
            #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF))
            calls.note("body")
            return 42
        }
        #expect(value == 42 && calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
        #expect(calls.events == ["get:1", "set:1:1", "body", "set:1:2"])
    }

    @Test func thrownBudgetAndCancellationErrorsRestoreTheOriginalPolicy() {
        let limited = Q153PolicyCalls()
        #expect(throws: PreviewFailure.inputTooLarge) {
            try DatalessFiles.withoutMaterializing(using: limited) { () throws -> Void in throw PreviewFailure.inputTooLarge }
        }
        #expect(limited.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
        let cancelled = Q153PolicyCalls()
        #expect(throws: CancellationError.self) {
            try DatalessFiles.withoutMaterializing(using: cancelled) { () throws -> Void in throw CancellationError() }
        }
        #expect(cancelled.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
    }

    @Test func nestedScopesRestoreOffInsideTheOuterScopeThenRestoreDefault() throws {
        let calls = Q153PolicyCalls(policy: Int32(IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT))
        try DatalessFiles.withoutMaterializing(using: calls) {
            try DatalessFiles.withoutMaterializing(using: calls) { calls.note("inner") }
            #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF))
        }
        #expect(calls.events == ["get:1", "set:1:1", "get:1", "set:1:1", "inner", "set:1:1", "set:1:0"])
        #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT))
    }

    @Test func policyEntryFailuresNeverEnterTheBodyAndRestoreFailureNeverReturnsSuccess() {
        for calls in [Q153PolicyCalls(failsGet: true), Q153PolicyCalls(failsSetNumber: 1)] {
            #expect(throws: PreviewFailure.unavailableContent) {
                try DatalessFiles.withoutMaterializing(using: calls) { Issue.record("Unsafe body entered") }
            }
            #expect(!calls.events.contains("body"))
        }
        let restoration = Q153PolicyCalls(failsSetNumber: 2)
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.withoutMaterializing(using: restoration) { restoration.note("body"); return 42 }
        }
        #expect(restoration.events == ["get:1", "set:1:1", "body", "set:1:2"])
    }

    @Test func restorationFailureOverridesThrownBodyAndStillAttemptsRestore() {
        let calls = Q153PolicyCalls(failsSetNumber: 2)
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.withoutMaterializing(using: calls) { () throws -> Void in
                calls.note("body")
                throw PreviewFailure.inputTooLarge
            }
        }
        #expect(calls.events == ["get:1", "set:1:1", "body", "set:1:2"])
        #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF))
    }

    @Test func nestedGetFailureSkipsInnerBodyAndRestoresOuterOriginalPolicy() {
        let calls = Q153PolicyCalls(failsGetNumber: 2)
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.withoutMaterializing(using: calls) {
                calls.note("outer")
                try DatalessFiles.withoutMaterializing(using: calls) { calls.note("inner") }
                calls.note("after-inner")
            }
        }
        #expect(calls.events == ["get:1", "set:1:1", "outer", "get:1", "set:1:2"])
        #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
    }

    @Test func nestedEntrySetFailureSkipsInnerBodyAndRestoresOuterOriginalPolicy() {
        let calls = Q153PolicyCalls(failsSetNumber: 2)
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.withoutMaterializing(using: calls) {
                calls.note("outer")
                try DatalessFiles.withoutMaterializing(using: calls) { calls.note("inner") }
                calls.note("after-inner")
            }
        }
        #expect(calls.events == ["get:1", "set:1:1", "outer", "get:1", "set:1:1", "set:1:2"])
        #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
    }

    @Test func nestedRestoreFailureStillRunsOuterRestoreAndNeverReturnsSuccess() {
        let calls = Q153PolicyCalls(failsSetNumber: 3)
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.withoutMaterializing(using: calls) {
                calls.note("outer")
                try DatalessFiles.withoutMaterializing(using: calls) { calls.note("inner") }
                calls.note("after-inner")
            }
        }
        #expect(calls.events == ["get:1", "set:1:1", "outer", "get:1", "set:1:1", "inner", "set:1:1", "set:1:2"])
        #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
    }

    @Test func ownedResultReleasesOnceBeforeRestorationFailureReachesCaller() {
        let calls = Q153PolicyCalls(failsSetNumber: 2)
        weak var observed: Q153OwnedResult?
        do {
            let result = try DatalessFiles.withoutMaterializing(using: calls) {
                let owner = Q153OwnedResult(calls)
                observed = owner
                return owner
            }
            _ = withExtendedLifetime(result) { Issue.record("Owned result published after restore failure") }
        } catch {
            calls.note("caught")
            #expect(error as? PreviewFailure == .unavailableContent)
        }
        #expect(observed == nil && calls.liveOwners == 0)
        #expect(calls.ownersAtSets == [0, 1])
        #expect(calls.events == ["get:1", "set:1:1", "owner-created", "set:1:2", "owner-released", "caught"])
    }

    @Test func successfulRestorationTransfersTheCompleteOwnerToTheCaller() throws {
        let calls = Q153PolicyCalls()
        weak var observed: Q153OwnedResult?
        var result: Q153OwnedResult? = try DatalessFiles.withoutMaterializing(using: calls) {
            let owner = Q153OwnedResult(calls)
            observed = owner
            return owner
        }
        #expect(result != nil && observed != nil && calls.liveOwners == 1)
        #expect(calls.ownersAtSets == [0, 1])
        #expect(calls.events == ["get:1", "set:1:1", "owner-created", "set:1:2"])
        result = nil
        #expect(observed == nil && calls.liveOwners == 0)
        #expect(calls.events == ["get:1", "set:1:1", "owner-created", "set:1:2", "owner-released"])
    }

    @Test func mappedSourceErrnoSurvivesRestorationClobberingErrno() {
        let originalErrno = errno
        defer { errno = originalErrno }
        let calls = Q153PolicyCalls(clobbersErrnoOnSetNumber: 2)
        // Thread-local errno is saved/restored; no async hop or real policy call occurs.
        do {
            try DatalessFiles.withoutMaterializing(using: calls) { () throws -> Void in
                calls.note("body")
                errno = EDEADLK
                let sourceErrno = errno
                throw DatalessFiles.materializationFailure(forPOSIXError: sourceErrno) ?? .unreadableFile
            }
            Issue.record("Mapped source failure was discarded")
        } catch {
            let restoredErrno = errno // Capture before assertion machinery can change it.
            #expect(error as? PreviewFailure == .unavailableContent)
            #expect(restoredErrno == EACCES)
        }
        #expect(calls.policy == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_ON))
        #expect(calls.events == ["get:1", "set:1:1", "body", "set:1:2"])
    }
}

#else
@Suite("Q153 unsupported platform fails closed")
struct Q153UnsupportedPlatformTests {
    @Test func unsupportedPolicyNeverRunsContentBody() {
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.withoutMaterializing { Issue.record("Unsupported source body ran") }
        }
        #expect(throws: PreviewFailure.unavailableContent) {
            try DatalessFiles.requireMaterialized(flags: 0)
        }
    }
}
#endif

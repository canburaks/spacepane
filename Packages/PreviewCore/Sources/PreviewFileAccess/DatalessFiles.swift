#if canImport(Darwin)
import Darwin
#endif
import PreviewContracts

public enum DatalessFiles {
    #if canImport(Darwin)
    static func isDataless(flags: UInt32) -> Bool {
        flags & UInt32(SF_DATALESS) != 0
    }
    #endif

    public static func requireMaterialized(flags: UInt32) throws {
        #if canImport(Darwin)
        guard !isDataless(flags: flags) else { throw PreviewFailure.unavailableContent }
        #else
        throw PreviewFailure.unavailableContent
        #endif
    }

    /// A materialization refusal is an existing content-unavailable state, not a new finding.
    public static func materializationFailure(forPOSIXError error: Int32) -> PreviewFailure? {
        #if canImport(Darwin)
        error == EDEADLK ? .unavailableContent : nil
        #else
        nil // Never interpret a Darwin errno number as another platform's materialization refusal.
        #endif
    }

    /// Call before extension work starts; each raw I/O boundary still sets thread OFF explicitly.
    public static func refuseMaterializationForProcess() throws {
        #if canImport(Darwin)
        try refuseMaterializationForProcess(using: DarwinDatalessIOPolicy())
        #else
        throw PreviewFailure.unavailableContent
        #endif
    }

    /// Synchronous only: no await, task/thread hop or escaping callback in the body.
    /// Return a complete owner for any resource that outlives the body; never a raw descriptor.
    public static func withoutMaterializing<T>(_ body: () throws -> T) throws -> T {
        #if canImport(Darwin)
        try withoutMaterializing(using: DarwinDatalessIOPolicy(), body)
        #else
        throw PreviewFailure.unavailableContent
        #endif
    }

    #if canImport(Darwin)
    static func refuseMaterializationForProcess(using calls: any DatalessIOPolicyCalls) throws {
        guard calls.set(scope: Int32(IOPOL_SCOPE_PROCESS), policy: Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF)) == 0
        else { throw PreviewFailure.unavailableContent }
    }

    static func withoutMaterializing<T>(using calls: any DatalessIOPolicyCalls, _ body: () throws -> T) throws -> T {
        let scope = Int32(IOPOL_SCOPE_THREAD)
        let previous = calls.get(scope: scope)
        guard previous >= 0,
              calls.set(scope: scope, policy: Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF)) == 0
        else { throw PreviewFailure.unavailableContent }
        // Preserve the typed outcome until restoration completes. On failure, unwinding releases
        // an owned successful result; callers must capture and map native errno inside the body.
        let result = Result(catching: body)
        guard calls.set(scope: scope, policy: previous) == 0 else { throw PreviewFailure.unavailableContent }
        return try result.get()
    }
    #endif
}

#if canImport(Darwin)
// Narrow syscall seam for deterministic scope/restore tests; never part of parser contracts.
protocol DatalessIOPolicyCalls: Sendable {
    func get(scope: Int32) -> Int32
    func set(scope: Int32, policy: Int32) -> Int32
}

private struct DarwinDatalessIOPolicy: DatalessIOPolicyCalls {
    func get(scope: Int32) -> Int32 {
        getiopolicy_np(Int32(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES), scope)
    }
    func set(scope: Int32, policy: Int32) -> Int32 {
        setiopolicy_np(Int32(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES), scope, policy)
    }
}
#endif

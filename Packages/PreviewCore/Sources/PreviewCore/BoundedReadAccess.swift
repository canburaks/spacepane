import Foundation
import Darwin
import PreviewContracts
import PreviewFileAccess

protocol BoundedReadPolicy: Sendable {
    func withoutMaterializing<T>(_ body: () throws -> T) throws -> T
}

enum BoundedReadMetadataCheck: Equatable, Sendable {
    case preflight
    case opened
    case beforeRangeRead
    case finalRead
}

enum BoundedReadOperation: Equatable, Sendable {
    case metadata(BoundedReadMetadataCheck)
    case open
    case read
    case pread
    case sqliteSidecar
    case sqliteLock
}

// The default probe is immutable and no-op. A request-local Mutex-backed test probe
// may substitute a captured errno/flag and observe actual acquisition/cleanup only.
// No source URL, path, content, byte buffer, stat struct or caller-owned fd is returned.
protocol BoundedReadProbe: Sendable {
    func beforeIO(_ operation: BoundedReadOperation) -> Int32?
    func flags(_ nativeFlags: UInt32, at check: BoundedReadMetadataCheck) -> UInt32
    func opened(_ descriptor: Int32)
    func closed(_ descriptor: Int32, result: Int32)
}

private struct LocalBoundedReadPolicy: BoundedReadPolicy {
    func withoutMaterializing<T>(_ body: () throws -> T) throws -> T {
        try DatalessFiles.withoutMaterializing(body)
    }
}

private struct SilentBoundedReadProbe: BoundedReadProbe {
    func beforeIO(_ operation: BoundedReadOperation) -> Int32? { nil }
    func flags(_ nativeFlags: UInt32, at check: BoundedReadMetadataCheck) -> UInt32 { nativeFlags }
    func opened(_ descriptor: Int32) {}
    func closed(_ descriptor: Int32, result: Int32) {}
}

struct BoundedReadCall: Sendable {
    let value: Int
    let error: Int32
}

/// Request-local read instrumentation; native operations and ownership stay concrete.
struct BoundedReadAccess: Sendable {
    let policy: any BoundedReadPolicy
    let probe: any BoundedReadProbe
    init() { policy = LocalBoundedReadPolicy(); probe = SilentBoundedReadProbe() }
    init(policy: any BoundedReadPolicy, probe: any BoundedReadProbe) { self.policy = policy; self.probe = probe }

    func call(_ operation: BoundedReadOperation, _ body: () -> Int) -> BoundedReadCall {
        if let error = probe.beforeIO(operation) { return BoundedReadCall(value: -1, error: error) }
        let value = body()
        let error = value < 0 ? errno : 0
        return BoundedReadCall(value: value, error: error)
    }

    func preflight(url: URL) throws {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return BoundedReadCall(value: -1, error: EINVAL) }
            return call(.metadata(.preflight)) { Int(lstat(path, &info)) }
        }
        guard result.value == 0 else {
            throw mappedFailure(result.error, fallback: result.error == ENOENT ? .missingFile : .unreadableFile)
        }
        try requireMaterialized(info, at: .preflight)
        guard info.st_mode & S_IFMT == S_IFREG else { throw PreviewFailure.notRegularFile }
    }

    func open(url: URL) throws -> Int32 {
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return BoundedReadCall(value: -1, error: EINVAL) }
            return call(.open) { Int(Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)) }
        }
        guard result.value >= 0 else {
            let fallback: PreviewFailure = result.error == ENOENT ? .missingFile
                : result.error == ELOOP ? .notRegularFile : .unreadableFile
            throw mappedFailure(result.error, fallback: fallback)
        }
        return Int32(result.value)
    }

    func metadata(descriptor: Int32, at check: BoundedReadMetadataCheck,
                  fallback: PreviewFailure) throws -> stat {
        var info = stat()
        let result = call(.metadata(check)) { Int(fstat(descriptor, &info)) }
        guard result.value == 0 else { throw mappedFailure(result.error, fallback: fallback) }
        try requireMaterialized(info, at: check)
        return info
    }

    func sidecarIsAbsent(url: URL) -> Bool {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return BoundedReadCall(value: -1, error: EINVAL) }
            return call(.sqliteSidecar) { Int(lstat(path, &info)) }
        }
        return result.value < 0 && result.error == ENOENT
    }

    func close(_ descriptor: Int32) {
        let result = Darwin.close(descriptor)
        probe.closed(descriptor, result: result)
    }

    func mappedFailure(_ error: Int32, fallback: PreviewFailure) -> PreviewFailure {
        DatalessFiles.materializationFailure(forPOSIXError: error) ?? fallback
    }

    private func requireMaterialized(_ info: stat, at check: BoundedReadMetadataCheck) throws {
        try DatalessFiles.requireMaterialized(flags: probe.flags(info.st_flags, at: check))
    }
}

import Foundation
import Darwin
import Synchronization
import PreviewContracts
import PreviewFileAccess

/// Owns an event-only fd across restoration and through its Dispatch cancel handler.
final class PreviewMonitorDescriptor: Sendable {
    static let openCount = Atomic<Int>(0)
    private let descriptor: Mutex<Int32?>
    private let access: BoundedReadAccess
    private init(_ descriptor: Int32, access: BoundedReadAccess) {
        self.descriptor = Mutex(descriptor); self.access = access
        Self.openCount.add(1, ordering: .relaxed)
    }
    deinit { close() }

    // Core calls this only on its queue before installation; cancel handler owns closing thereafter.
    func fileDescriptor() throws -> Int32 {
        try descriptor.withLock { value in
            guard let value else { throw PreviewFailure.unavailableContent }
            return value
        }
    }
    func close() {
        let value = descriptor.withLock { value -> Int32? in
            let owned = value; value = nil; return owned
        }
        guard let value else { return }
        access.close(value)
        Self.openCount.subtract(1, ordering: .relaxed)
    }

    static func open(watching url: URL, access: BoundedReadAccess) throws -> PreviewMonitorDescriptor {
        guard url.isFileURL else { throw PreviewFailure.unreadableFile }
        return try access.policy.withoutMaterializing { try acquire(url, access: access) }
    }
    private static func acquire(_ url: URL, access: BoundedReadAccess) throws -> PreviewMonitorDescriptor {
        var status = stat()
        let before = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return BoundedReadCall(value: -1, error: EINVAL) }
            return access.call(.metadata(.preflight)) { Int(lstat(path, &status)) }
        }
        guard before.value == 0 else { throw failure(before.error, access: access) }
        try DatalessFiles.requireMaterialized(flags: access.probe.flags(status.st_flags, at: .preflight))
        try requireWatchable(status.st_mode)
        let opened = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return BoundedReadCall(value: -1, error: EINVAL) }
            return access.call(.open) { Int(Darwin.open(path, O_EVTONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)) }
        }
        guard opened.value >= 0 else { throw failure(opened.error, access: access) }
        let fd = Int32(opened.value)
        var transferred = false
        defer { if !transferred { access.close(fd) } }
        access.probe.opened(fd)
        let info = try access.metadata(descriptor: fd, at: .opened, fallback: .unreadableFile)
        try requireWatchable(info.st_mode)
        let owner = PreviewMonitorDescriptor(fd, access: access)
        transferred = true
        return owner
    }
    func requireAvailable() throws {
        try access.policy.withoutMaterializing {
            // Hold ownership lock across fstat so close cannot race a check on a recycled fd.
            try descriptor.withLock { value in
                guard let value else { throw PreviewFailure.unavailableContent }
                let info = try access.metadata(descriptor: value, at: .finalRead, fallback: .unreadableFile)
                try Self.requireWatchable(info.st_mode)
            }
        }
    }
    private static func failure(_ error: Int32, access: BoundedReadAccess) -> PreviewFailure {
        access.mappedFailure(error, fallback: error == ENOENT ? .missingFile : error == ELOOP ? .notRegularFile : .unreadableFile)
    }
    private static func requireWatchable(_ mode: mode_t) throws {
        let kind = mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR else { throw PreviewFailure.notRegularFile }
    }
}

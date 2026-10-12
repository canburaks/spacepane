import Foundation
import Darwin
import PreviewContracts

public struct BoundedFileReader: PreviewFileReading, LeadingBytesReading {
    let access: BoundedReadAccess
    public init() { access = BoundedReadAccess() }
    init(policy: any BoundedReadPolicy, probe: any BoundedReadProbe) {
        access = BoundedReadAccess(policy: policy, probe: probe)
    }
    public func read(url: URL, context: RequestContext) throws -> FileBytes {
        try read(url: url, context: context, allowsLeadingPrefix: false)
    }

    /// Like `read`, but a regular file larger than the input budget yields its first `maxInputBytes`
    /// bytes and the file's size instead of `inputTooLarge`. Everything else (no-follow descriptor,
    /// regular-file check, cancellation, change detection) is shared with `read`.
    public func readLeading(url: URL, context: RequestContext) throws -> FileBytes {
        try read(url: url, context: context, allowsLeadingPrefix: true)
    }

    private func read(url: URL, context: RequestContext, allowsLeadingPrefix: Bool) throws -> FileBytes {
        try context.checkpoint()
        guard url.isFileURL else { throw PreviewFailure.unreadableFile }
        return try access.policy.withoutMaterializing {
            try readMaterialized(url: url, context: context, allowsLeadingPrefix: allowsLeadingPrefix)
        }
    }

    private func readMaterialized(url: URL, context: RequestContext, allowsLeadingPrefix: Bool) throws -> FileBytes {
        if case .sqliteSnapshot = context.sourceReadPolicy { try rejectDatabaseSidecars(url) }
        try access.preflight(url: url)
        let descriptor = try access.open(url: url)
        defer { access.close(descriptor) }
        access.probe.opened(descriptor)
        // The opened descriptor is authoritative; nofollow/nonblock protect replacement races.
        let descriptorInfo = try access.metadata(descriptor: descriptor, at: .opened, fallback: .unreadableFile)
        guard descriptorInfo.st_mode & S_IFMT == S_IFREG else { throw PreviewFailure.notRegularFile }
        let limit = context.budget.maxInputBytes
        let isLeadingPrefix = allowsLeadingPrefix && descriptorInfo.st_size > limit
        guard isLeadingPrefix || descriptorInfo.st_size <= limit else { throw PreviewFailure.inputTooLarge }
        if case .sqliteSnapshot = context.sourceReadPolicy {
            // Conservatively hold read locks over SQLite's pending/reserved/shared byte range.
            var lock = flock()
            lock.l_type = Int16(F_RDLCK)
            lock.l_whence = Int16(SEEK_SET)
            lock.l_start = 1_073_741_824
            lock.l_len = 512
            let result = access.call(.sqliteLock) { Int(fcntl(descriptor, F_SETLK, &lock)) }
            guard result.value == 0 else { throw access.mappedFailure(result.error, fallback: .unavailableContent) }
            try rejectDatabaseSidecars(url)
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        // Read at most one excess byte so a file growing after metadata cannot exceed the cap.
        while true {
            try context.checkpoint()
            let remaining = limit - data.count
            if isLeadingPrefix && remaining == 0 { break }
            let result = access.call(.read) {
                Darwin.read(descriptor, &buffer, min(buffer.count, isLeadingPrefix ? remaining : remaining + 1))
            }
            if result.value < 0 {
                if result.error == EINTR { continue }
                throw access.mappedFailure(result.error, fallback: .unreadableFile)
            }
            try context.checkpoint()
            guard result.value <= remaining else { throw PreviewFailure.inputTooLarge }
            if result.value == 0 { break }
            data.append(contentsOf: buffer.prefix(result.value))
        }
        let finalInfo = try access.metadata(descriptor: descriptor, at: .finalRead, fallback: .unavailableContent)
        guard descriptorInfo.st_size == finalInfo.st_size,
              descriptorInfo.st_mtimespec.tv_sec == finalInfo.st_mtimespec.tv_sec,
              descriptorInfo.st_mtimespec.tv_nsec == finalInfo.st_mtimespec.tv_nsec,
              descriptorInfo.st_ctimespec.tv_sec == finalInfo.st_ctimespec.tv_sec,
              descriptorInfo.st_ctimespec.tv_nsec == finalInfo.st_ctimespec.tv_nsec else {
            throw PreviewFailure.unavailableContent
        }
        if case .sqliteSnapshot = context.sourceReadPolicy { try rejectDatabaseSidecars(url) }
        return FileBytes(data: data, totalByteCount: isLeadingPrefix ? Int(descriptorInfo.st_size) : nil)
    }

    private func rejectDatabaseSidecars(_ url: URL) throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + suffix)
            guard access.sidecarIsAbsent(url: sidecar) else { throw PreviewFailure.unavailableContent }
        }
    }
}

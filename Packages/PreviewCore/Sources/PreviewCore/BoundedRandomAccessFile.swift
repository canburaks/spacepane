import Foundation
import Darwin
import Synchronization
import PreviewContracts

extension BoundedFileReader {
    public func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource {
        try context.checkpoint()
        guard url.isFileURL else { throw PreviewFailure.unreadableFile }
        return try access.policy.withoutMaterializing {
            try BoundedRandomAccessFile(url: url, context: context, access: access)
        }
    }
}

/// A request-owned descriptor permits archive-tail reads without reading the whole
/// source. Every requested byte is charged, including overlaps and failed attempts.
final class BoundedRandomAccessFile: PreviewByteSource, Sendable {
    let byteCount: Int64
    private let descriptor: Int32
    private let access: BoundedReadAccess
    private let readLimit: Int
    private let chargedBytes = Mutex(0)
    private let modifiedSeconds: Int
    private let modifiedNanos: Int
    private let changedSeconds: Int
    private let changedNanos: Int

    fileprivate init(url: URL, context: RequestContext, access: BoundedReadAccess) throws {
        try context.checkpoint()
        try access.preflight(url: url)
        let fd = try access.open(url: url)
        var transferred = false
        defer { if !transferred { access.close(fd) } }
        access.probe.opened(fd)
        let info = try access.metadata(descriptor: fd, at: .opened, fallback: .notRegularFile)
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { throw PreviewFailure.notRegularFile }
        descriptor = fd
        self.access = access
        byteCount = info.st_size
        readLimit = context.budget.maxInputBytes
        modifiedSeconds = info.st_mtimespec.tv_sec
        modifiedNanos = info.st_mtimespec.tv_nsec
        changedSeconds = info.st_ctimespec.tv_sec
        changedNanos = info.st_ctimespec.tv_nsec
        transferred = true // Every stored field is initialized; deinit owns the descriptor now.
    }

    deinit { access.close(descriptor) }

    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard offset >= 0, offset <= byteCount, count >= 0, Int64(count) <= byteCount - offset else {
            throw PreviewFailure.malformedDocument
        }
        try chargedBytes.withLock { charged in
            guard count <= min(readLimit, context.budget.maxInputBytes) - charged else {
                throw PreviewFailure.inputTooLarge
            }
            charged += count
        }
        return try access.policy.withoutMaterializing {
            try readMaterialized(offset: offset, count: count, context: context)
        }
    }

    private func readMaterialized(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        try validateSnapshot(at: .beforeRangeRead)
        var data = Data(count: count)
        if count > 0 {
            try data.withUnsafeMutableBytes { buffer in
                guard let base = buffer.baseAddress else { throw PreviewFailure.unreadableFile }
                var consumed = 0
                while consumed < count {
                    try context.checkpoint()
                    let result = access.call(.pread) {
                        pread(descriptor, base.advanced(by: consumed), min(65_536, count - consumed), offset + Int64(consumed))
                    }
                    if result.value < 0 && result.error == EINTR { continue }
                    guard result.value > 0 else { throw access.mappedFailure(result.error, fallback: .unavailableContent) }
                    consumed += result.value
                }
            }
        }
        try context.checkpoint()
        try validateSnapshot(at: .finalRead)
        return data
    }

    private func validateSnapshot(at check: BoundedReadMetadataCheck) throws {
        let info = try access.metadata(descriptor: descriptor, at: check, fallback: .unavailableContent)
        guard info.st_size == byteCount,
              info.st_mtimespec.tv_sec == modifiedSeconds, info.st_mtimespec.tv_nsec == modifiedNanos,
              info.st_ctimespec.tv_sec == changedSeconds, info.st_ctimespec.tv_nsec == changedNanos else {
            throw PreviewFailure.unavailableContent
        }
    }
}

import Foundation
import Darwin

enum PreferencesReadFailure: Error { case missing, unreadable, oversized }

/// Shared snapshot/theme reader: a bounded regular file read that never follows a symlink or opens for writing.
enum BoundedPreferencesData {
    static func read(at url: URL, maximumBytes: Int) throws -> Data {
        guard url.isFileURL else { throw PreferencesReadFailure.unreadable }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw errno == ENOENT ? PreferencesReadFailure.missing : PreferencesReadFailure.unreadable
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw PreferencesReadFailure.unreadable
        }
        guard info.st_size >= 0, info.st_size <= maximumBytes else { throw PreferencesReadFailure.oversized }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let remaining = maximumBytes - result.count
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, remaining + 1))
            if count < 0 {
                if errno == EINTR { continue }
                throw PreferencesReadFailure.unreadable
            }
            guard count <= remaining else { throw PreferencesReadFailure.oversized }
            if count == 0 { return result }
            result.append(contentsOf: buffer.prefix(count))
        }
    }
}

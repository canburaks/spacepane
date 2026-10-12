import Foundation
import Darwin
import PreviewContracts
import PreviewFileAccess

protocol DirectoryReadPolicy: Sendable {
    func withoutMaterializing<T>(_ body: () throws -> T) throws -> T
}
enum DirectoryMetadataCheck: Equatable, Sendable { case rootPreflight, rootOpened, rootFinal, listedChild, childPreflight, childOpened, beforeEnumeration, afterEnumeration }
enum DirectoryReadOperation: Equatable, Sendable { case metadata(DirectoryMetadataCheck), openRoot, openDirectory(root: Bool), openFile, directoryStream(root: Bool), nextEntry(root: Bool) }
protocol DirectoryReadProbe: Sendable {
    func beforeIO(_ operation: DirectoryReadOperation) -> Int32?
    func flags(_ native: UInt32, at check: DirectoryMetadataCheck) -> UInt32
    func opened(_ descriptor: Int32)
    func closed(_ descriptor: Int32, result: Int32)
}
private struct LocalDirectoryReadPolicy: DirectoryReadPolicy {
    func withoutMaterializing<T>(_ body: () throws -> T) throws -> T { try DatalessFiles.withoutMaterializing(body) }
}
private struct SilentDirectoryReadProbe: DirectoryReadProbe {
    func beforeIO(_ operation: DirectoryReadOperation) -> Int32? { nil }
    func flags(_ native: UInt32, at check: DirectoryMetadataCheck) -> UInt32 { native }
    func opened(_ descriptor: Int32) {}
    func closed(_ descriptor: Int32, result: Int32) {}
}
struct DirectoryReadCall: Sendable { let value: Int; let error: Int32 }
/// Native ownership stays in source; request-local probes cannot intercept cleanup.
struct DirectoryReadAccess: Sendable {
    let policy: any DirectoryReadPolicy
    let probe: any DirectoryReadProbe
    init() { policy = LocalDirectoryReadPolicy(); probe = SilentDirectoryReadProbe() }
    init(policy: any DirectoryReadPolicy, probe: any DirectoryReadProbe) { self.policy = policy; self.probe = probe }
    func call(_ operation: DirectoryReadOperation, _ body: () -> Int) -> DirectoryReadCall {
        if let error = probe.beforeIO(operation) { return DirectoryReadCall(value: -1, error: error) }
        let value = body()
        let error = value < 0 ? errno : 0
        return DirectoryReadCall(value: value, error: error)
    }
    func preflightRoot(url: URL, notDirectoryFailure: PreviewFailure = .unreadableFile) throws {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return DirectoryReadCall(value: -1, error: EINVAL) }
            return call(.metadata(.rootPreflight)) { Int(lstat(path, &info)) }
        }
        guard result.value == 0 else {
            throw mappedFailure(result.error, fallback: result.error == ENOENT ? .missingFile : .unreadableFile)
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw info.st_mode & S_IFMT == S_IFLNK ? PreviewFailure.unreadableFile : notDirectoryFailure
        }
        try DatalessFiles.requireMaterialized(flags: probe.flags(info.st_flags, at: .rootPreflight))
    }
    func openRoot(url: URL) throws -> Int32 {
        let call = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return DirectoryReadCall(value: -1, error: EINVAL) }
            return self.call(.openRoot) { Int(Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)) }
        }
        guard call.value >= 0 else { throw mappedFailure(call.error, fallback: call.error == ENOENT ? .missingFile : .unreadableFile) }
        let descriptor = Int32(call.value)
        probe.opened(descriptor)
        return descriptor
    }
    func metadata(descriptor: Int32, at check: DirectoryMetadataCheck, fallback: PreviewFailure = .notRegularFile) throws -> stat {
        var info = stat()
        let call = call(.metadata(check)) { Int(fstat(descriptor, &info)) }
        guard call.value == 0 else { throw mappedFailure(call.error, fallback: fallback) }
        info.st_flags = probe.flags(info.st_flags, at: check)
        guard info.st_mode & S_IFMT == S_IFDIR else { throw PreviewFailure.notRegularFile }
        try DatalessFiles.requireMaterialized(flags: info.st_flags)
        return info
    }
    func openDirectory(parent: Int32, name: String, root: Bool) throws -> Int32 {
        let preflight = try childMetadata(parent: parent, name: name, at: root ? .rootOpened : .childPreflight)
        guard preflight.st_mode & S_IFMT == S_IFDIR else { throw PreviewFailure.unreadableFile }
        try DatalessFiles.requireMaterialized(flags: preflight.st_flags)
        let result = name.withCString { name in
            call(.openDirectory(root: root)) { Int(openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)) }
        }
        guard result.value >= 0 else { throw mappedFailure(result.error, fallback: .unreadableFile) }
        let descriptor = Int32(result.value)
        probe.opened(descriptor)
        do {
            _ = try metadata(descriptor: descriptor, at: root ? .rootOpened : .childOpened, fallback: .unreadableFile)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }
    func childMetadata(parent: Int32, name: String, at check: DirectoryMetadataCheck) throws -> stat {
        var info = stat()
        let result = name.withCString { name in call(.metadata(check)) { Int(fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW)) } }
        guard result.value == 0 else { throw mappedFailure(result.error, fallback: .unreadableFile) }
        info.st_flags = probe.flags(info.st_flags, at: check)
        return info
    }
    func stream(_ descriptor: Int32, root: Bool) -> (value: UnsafeMutablePointer<DIR>?, error: Int32) {
        if let error = probe.beforeIO(.directoryStream(root: root)) { return (nil, error) }
        let value = fdopendir(descriptor)
        let error = value == nil ? errno : 0
        return (value, error)
    }
    func nextEntry(_ directory: UnsafeMutablePointer<DIR>, root: Bool) -> (value: UnsafeMutablePointer<dirent>?, error: Int32) {
        if let error = probe.beforeIO(.nextEntry(root: root)) { return (nil, error) }
        errno = 0
        let value = readdir(directory)
        let error = value == nil ? errno : 0
        return (value, error)
    }
    func closeStream(_ directory: UnsafeMutablePointer<DIR>) {
        let descriptor = dirfd(directory)
        let result = closedir(directory)
        probe.closed(descriptor, result: result)
    }
    func isDataless(_ info: stat) -> Bool { info.st_flags & UInt32(SF_DATALESS) != 0 }
    func mappedFailure(_ error: Int32, fallback: PreviewFailure) -> PreviewFailure {
        DatalessFiles.materializationFailure(forPOSIXError: error) ?? fallback
    }
    func close(_ descriptor: Int32) { probe.closed(descriptor, result: Darwin.close(descriptor)) }

    /// `fstatat` of one child, with probe flags applied when the stat succeeds.
    func statChild(parent: Int32, name: String, at check: DirectoryMetadataCheck) -> (call: DirectoryReadCall, info: stat) {
        var info = stat()
        let call = name.withCString { name in
            self.call(.metadata(check)) { Int(fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW)) }
        }
        if call.value == 0 { info.st_flags = probe.flags(info.st_flags, at: check) }
        return (call, info)
    }

    /// Opens one child without following links and records a live descriptor with the probe.
    func openChild(parent: Int32, name: String, directory: Bool) -> DirectoryReadCall {
        let flags = directory
            ? (O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            : (O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        let operation: DirectoryReadOperation = directory ? .openDirectory(root: false) : .openFile
        let call = name.withCString { name in self.call(operation) { Int(openat(parent, name, flags)) } }
        if call.value >= 0 { probe.opened(Int32(call.value)) }
        return call
    }

    /// Duplicates a directory descriptor and records the duplicate with the probe.
    func duplicate(_ descriptor: Int32) -> DirectoryReadCall {
        let call = call(.openDirectory(root: true)) { Int(fcntl(descriptor, F_DUPFD_CLOEXEC, 0)) }
        if call.value >= 0 { probe.opened(Int32(call.value)) }
        return call
    }

    /// `fstat` of an already opened descendant. Refuses dataless files and maps `EDEADLK`.
    func fileState(_ descriptor: Int32, at check: DirectoryMetadataCheck) throws -> stat {
        var info = stat()
        let call = call(.metadata(check)) { Int(fstat(descriptor, &info)) }
        guard call.value == 0 else { throw mappedFailure(call.error, fallback: .unreadableFile) }
        info.st_flags = probe.flags(info.st_flags, at: check)
        try DatalessFiles.requireMaterialized(flags: info.st_flags)
        return info
    }
}

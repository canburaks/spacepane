import Foundation
import Darwin
import PreviewContracts

/// The outcome of asking an application bundle for one file.
enum BundleFileRead {
    case absent
    case tooLarge
    case content(Data)
}

/// Totals gathered by a bounded, non-following walk of a bundle.
struct BundleMeasurement: Equatable {
    var bytes: Int64 = 0
    var items = 0
    /// True when the walk stopped at an item, depth or time limit, or hit an unreadable directory.
    var isPartial = false
}

/// A read-only, no-follow view of one authorized directory for application-bundle inspection.
///
/// Every path is resolved one component at a time with `openat` and `O_NOFOLLOW`, so a symlink inside
/// the bundle can never lead the reader outside it. Entries that are not regular files (FIFOs, devices,
/// sockets, symlinks) are never opened. Reads draw on one cumulative allowance, like the shared
/// byte-source reader, and the directory is never modified.
final class BundleDirectory {
    private let access: DirectoryReadAccess
    private let descriptor: Int32
    /// What remains of the request's input allowance for file reads.
    private(set) var remainingBytes: Int

    /// Caller owns the synchronous checked parse/construction scope.
    init(url: URL, allowance: Int, access: DirectoryReadAccess = DirectoryReadAccess()) throws {
        guard url.isFileURL else { throw PreviewFailure.unreadableFile }
        try access.preflightRoot(url: url, notDirectoryFailure: .unsupportedFormat)
        let opened = try access.openRoot(url: url)
        do {
            _ = try access.metadata(descriptor: opened, at: .rootOpened)
            descriptor = opened
            self.access = access
            remainingBytes = allowance
        } catch {
            access.close(opened)
            throw error
        }
    }

    deinit { access.close(descriptor) }

    func requireAvailable() throws { _ = try access.metadata(descriptor: descriptor, at: .rootFinal) }

    /// A path component that is one plain name: no separators, no traversal and no control characters.
    static func isPlainComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 255
            && !name.unicodeScalars.contains { $0 == "/" || $0.value < 32 }
    }

    /// Reads up to `limit` bytes from the start of a regular file (or the whole file when `wholeFile`).
    /// A missing, non-regular or unreachable path yields `.absent`; a whole file over `limit` is `.tooLarge`.
    func read(_ components: [String], limit: Int, wholeFile: Bool, context: RequestContext) throws -> BundleFileRead {
        try context.checkpoint()
        guard !components.isEmpty, components.allSatisfy(Self.isPlainComponent) else { return .absent }
        guard let file = try openFile(components) else { return .absent }
        defer { access.close(file) }
        let info = try access.fileState(file, at: .childOpened)
        guard info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 else { return .absent }
        let size = Int(clamping: info.st_size)
        let wanted = wholeFile ? size : min(size, limit)
        if wholeFile, size > limit { return .tooLarge }
        guard wanted <= remainingBytes else { throw PreviewFailure.inputTooLarge }
        remainingBytes -= wanted
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < wanted {
            try context.checkpoint()
            let count = Darwin.read(file, &buffer, min(buffer.count, wanted - data.count))
            if count < 0 {
                if errno == EINTR { continue }
                throw PreviewFailure.unreadableFile
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        try context.checkpoint()
        return .content(data)
    }

    private func openFile(_ components: [String]) throws -> Int32? {
        var current = descriptor
        var intermediates: [Int32] = []
        defer { intermediates.forEach { access.close($0) } }
        for (index, name) in components.enumerated() {
            let isLast = index == components.count - 1
            let stated = access.statChild(parent: current, name: name, at: .childPreflight)
            if stated.call.value != 0 {
                try refuseDeadlock(stated.call.error)
                if Self.isAbsent(stated.call.error) { return nil }
                throw PreviewFailure.unreadableFile
            }
            if access.isDataless(stated.info) { throw PreviewFailure.unavailableContent }
            let mode = stated.info.st_mode & S_IFMT
            if isLast {
                guard mode == S_IFREG else { return nil }
            } else {
                guard mode == S_IFDIR else { return nil }
            }
            let opened = access.openChild(parent: current, name: name, directory: !isLast)
            if opened.value < 0 {
                try refuseDeadlock(opened.error)
                if Self.isAbsent(opened.error) { return nil }
                throw PreviewFailure.unreadableFile
            }
            let next = Int32(opened.value)
            if isLast { return next }
            intermediates.append(next)
            current = next
        }
        return nil
    }

    private static func isAbsent(_ error: Int32) -> Bool { [ENOENT, ENOTDIR, ELOOP].contains(error) }

    private func refuseDeadlock(_ error: Int32) throws {
        if error == EDEADLK { throw access.mappedFailure(error, fallback: .unavailableContent) }
    }

    /// Sums regular-file sizes and counts items without following links or opening anything but
    /// directories. The walk stops, flagged partial, at an item, depth or time limit.
    func measure(maximumItems: Int, maximumDepth: Int, softDeadline: ContinuousClock.Instant,
                 context: RequestContext) throws -> BundleMeasurement {
        try context.checkpoint()
        var result = BundleMeasurement()
        let duplicated = access.duplicate(descriptor)
        guard duplicated.value >= 0 else { result.isPartial = true; return result }
        let rootDescriptor = Int32(duplicated.value)
        let streamed = access.stream(rootDescriptor, root: true)
        guard let root = streamed.value else {
            access.close(rootDescriptor)
            result.isPartial = true
            return result
        }
        // The duplicate shares its file offset with the original descriptor, so start from the beginning.
        rewinddir(root)
        var stack: [UnsafeMutablePointer<DIR>] = [root]
        defer { stack.forEach { access.closeStream($0) } }
        while let directory = stack.last {
            try context.checkpoint()
            if ContinuousClock.now >= softDeadline { result.isPartial = true; break }
            let next = access.nextEntry(directory, root: stack.count == 1)
            guard let entry = next.value else {
                if next.error != 0 { result.isPartial = true }
                access.closeStream(directory)
                stack.removeLast()
                continue
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            result.items += 1
            if result.items > maximumItems { result.items = maximumItems; result.isPartial = true; break }
            let parent = dirfd(directory)
            let stated = access.statChild(parent: parent, name: name, at: .listedChild)
            guard stated.call.value == 0 else {
                try refuseDeadlock(stated.call.error)
                result.isPartial = true
                continue
            }
            if access.isDataless(stated.info) { result.isPartial = true; continue }
            switch stated.info.st_mode & S_IFMT {
            case S_IFREG:
                result.bytes = result.bytes.addingReportingOverflow(Int64(max(0, stated.info.st_size))).partialValue
            case S_IFDIR:
                guard stack.count < maximumDepth else { result.isPartial = true; continue }
                let opened = access.openChild(parent: parent, name: name, directory: true)
                if opened.value < 0 {
                    try refuseDeadlock(opened.error)
                    result.isPartial = true
                    continue
                }
                let child = Int32(opened.value)
                let childStream = access.stream(child, root: false)
                guard let handle = childStream.value else {
                    access.close(child)
                    result.isPartial = true
                    continue
                }
                stack.append(handle)
            default:
                break
            }
        }
        return result
    }
}

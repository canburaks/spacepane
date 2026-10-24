import Foundation
import Darwin
import OSLog
import PreviewContracts

/// The synchronous kernel lives only in this owned child. Nonblocking pipes keep
/// cancellation, wall deadlines and output limits effective even if import stalls.
enum CADWorkerProcess {
    static var bundledExecutableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CADWorker")
    }

    private static let logger = Logger(subsystem: CADLogging.subsystem, category: "Worker")

    static func run(executable: URL, arguments: [String], input: Data, context: RequestContext,
                    isCancelled: @Sendable () -> Bool = { false }) throws -> Data {
        if isCancelled() { throw CancellationError() }
        try context.checkpoint()
        guard executable.isFileURL else { throw launchFailure(EINVAL) }
        var source = try makePipe()
        defer { closeDescriptors(source) }
        var output = try makePipe()
        defer { closeDescriptors(output) }
        let discard = try normalizeDescriptor(Darwin.open("/dev/null", O_WRONLY | O_CLOEXEC))
        defer { Darwin.close(discard) }
        let writeFD = source[1], readFD = output[0]
        guard fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK) == 0,
              fcntl(writeFD, F_SETNOSIGPIPE, 1) == 0 else { throw launchFailure(errno) }

        var actions: posix_spawn_file_actions_t?
        let actionsResult = posix_spawn_file_actions_init(&actions)
        guard actionsResult == 0 else { throw launchFailure(actionsResult) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        for (original, destination) in [(source[0], STDIN_FILENO), (output[1], STDOUT_FILENO), (discard, STDERR_FILENO)] {
            let result = posix_spawn_file_actions_adddup2(&actions, original, destination)
            guard result == 0 else { throw launchFailure(result) }
        }
        // Originals are always above stderr, so none of these closes can undo a dup2.
        for descriptor in source + output + [discard] {
            let result = posix_spawn_file_actions_addclose(&actions, descriptor)
            guard result == 0 else { throw launchFailure(result) }
        }
        var attributes: posix_spawnattr_t?
        let attributesResult = posix_spawnattr_init(&attributes)
        guard attributesResult == 0 else { throw launchFailure(attributesResult) }
        defer { posix_spawnattr_destroy(&attributes) }
        let flagsResult = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        guard flagsResult == 0 else { throw launchFailure(flagsResult) }

        var argv = ([executable.path] + arguments).map { value in value.withCString { strdup($0) } } + [nil]
        defer { for pointer in argv { free(pointer) } }
        var environment = ["LANG=C", "LC_ALL=C"].map { (value: String) in value.withCString { strdup($0) } } + [nil]
        defer { for pointer in environment { free(pointer) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), environment.dropLast().allSatisfy({ $0 != nil }) else {
            throw launchFailure(ENOMEM)
        }
        var pid: pid_t = 0
        let spawnResult = executable.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return EINVAL }
            return argv.withUnsafeMutableBufferPointer { arguments in
                environment.withUnsafeMutableBufferPointer { variables in
                    posix_spawn(&pid, path, &actions, &attributes, arguments.baseAddress!, variables.baseAddress!)
                }
            }
        }
        guard spawnResult == 0 else { throw launchFailure(spawnResult) }
        var child = OwnedChild(pid: pid)
        defer { child.terminateAndReap() }
        // Only the parent writer and reader remain; extra endpoints prevent EOF.
        Darwin.close(source[0]); source[0] = -1
        Darwin.close(output[1]); output[1] = -1
        func closeWriter() { Darwin.close(source[1]); source[1] = -1 }

        var sent = 0, result = Data(), reachedEOF = false
        let cap = min(context.budget.maxOutputUTF8Bytes, GeometryLimits.maximumSerializedBytes)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !reachedEOF || !child.reaped {
            if isCancelled() { throw CancellationError() }
            try context.checkpoint()
            try child.pollExit()
            if source[1] >= 0, sent < input.count {
                let written = input.withUnsafeBytes { bytes in
                    Darwin.write(writeFD, bytes.baseAddress!.advanced(by: sent), min(64 * 1024, input.count - sent))
                }
                if written > 0 { sent += written }
                else if written < 0, errno != EAGAIN, errno != EINTR { closeWriter() }
            }
            if source[1] >= 0, sent == input.count { closeWriter() }
            if !reachedEOF {
                let count = Darwin.read(readFD, &buffer, buffer.count)
                if count > 0 {
                    guard count <= cap - result.count else { throw PreviewFailure.outputTooLarge }
                    result.append(contentsOf: buffer.prefix(count))
                    continue
                } else if count == 0 { reachedEOF = true }
                else if errno != EAGAIN, errno != EINTR { throw PreviewFailure.malformedDocument }
            }
            var descriptors = [pollfd(fd: reachedEOF ? -1 : readFD, events: Int16(POLLIN), revents: 0),
                               pollfd(fd: source[1], events: Int16(POLLOUT), revents: 0)]
            _ = poll(&descriptors, nfds_t(descriptors.count), 10)
        }
        try context.checkpoint()
        if isCancelled() { throw CancellationError() }
        guard let status = child.status else { throw PreviewFailure.unreadableFile }
        // Darwin's wait status macros are not imported into Swift: low seven bits
        // distinguish signal termination, and the following byte is the exit code.
        guard status & 0x7f == 0 else { throw PreviewFailure.outputTooLarge }
        let exitCode = (status >> 8) & 0xff
        logger.debug("cad.worker.finished status=\(exitCode, privacy: .public)")
        switch exitCode {
        case 0: return result
        case 2: throw PreviewFailure.malformedDocument
        case 3: throw PreviewFailure.unsupportedFormat
        case 4: throw PreviewFailure.outputTooLarge
        case 6: throw PreviewFailure.geometryTooComplex
        default: throw PreviewFailure.unreadableFile
        }
    }

    private static func launchFailure(_ code: Int32) -> PreviewFailure {
        logger.error("cad.worker.launchFailed errno=\(code, privacy: .public)")
        return .unreadableFile
    }

    private static func normalizeDescriptor(_ descriptor: Int32) throws -> Int32 {
        guard descriptor >= 0 else { throw launchFailure(errno) }
        guard descriptor < STDERR_FILENO + 1 else { return descriptor }
        let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
        let failure = errno
        Darwin.close(descriptor)
        guard replacement >= 0 else { throw launchFailure(failure) }
        return replacement
    }

    private static func makePipe() throws -> [Int32] {
        var descriptors: [Int32] = [-1, -1]
        guard Darwin.pipe(&descriptors) == 0 else { throw launchFailure(errno) }
        do {
            for index in descriptors.indices {
                let original = descriptors[index]
                // Normalize closes its original on a failed duplication as well.
                descriptors[index] = -1
                descriptors[index] = try normalizeDescriptor(original)
                guard fcntl(descriptors[index], F_SETFD, FD_CLOEXEC) == 0 else { throw launchFailure(errno) }
            }
            return descriptors
        } catch { closeDescriptors(descriptors); throw error }
    }

    private static func closeDescriptors(_ descriptors: [Int32]) {
        for descriptor in descriptors where descriptor >= 0 { Darwin.close(descriptor) }
    }

    /// This request alone waits for its PID; no global SIGCHLD handler or reaper.
    private struct OwnedChild {
        let pid: pid_t
        var reaped = false
        var status: Int32?

        mutating func pollExit() throws {
            guard !reaped else { return }
            var value: Int32 = 0
            while true {
                let result = waitpid(pid, &value, WNOHANG)
                if result == pid { status = value; reaped = true; return }
                if result == 0 { return }
                if errno == EINTR { continue }
                if errno == ECHILD { reaped = true }
                throw PreviewFailure.unreadableFile
            }
        }

        mutating func terminateAndReap() {
            guard !reaped else { return }
            // Check first: ECHILD means this PID is no longer ours to signal.
            do { try pollExit() } catch { if reaped { return } }
            guard !reaped else { return }
            _ = kill(pid, SIGKILL)
            var value: Int32 = 0
            while true {
                let result = waitpid(pid, &value, 0)
                if result == pid { status = value; reaped = true; return }
                if result < 0, errno == EINTR { continue }
                // ECHILD also completes ownership; never retry a reused PID.
                reaped = true
                return
            }
        }
    }
}

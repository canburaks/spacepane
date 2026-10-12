import Foundation
import Darwin
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewCore

// Request-local probe: native acquisition and close always stay in the real reader.
final class Q153ReadProbe: BoundedReadPolicy, BoundedReadProbe, Sendable {
    struct State {
        var entries = 0, restores = 0, depth = 0, outsideScopes = 0
        var operations: [BoundedReadOperation] = []
        var opened: [Int32] = [], closed: [Int32] = [], closeResults: [Int32] = []
        var liveDescriptorsAtRestore: [Int] = []
        var dataless: BoundedReadMetadataCheck?
        var fault: BoundedReadOperation?
        var faultNumber = 1
        var faultErrno: Int32 = EDEADLK
        var entryFails = false, restoreFails = false, clobbersErrno = false
    }
    private let state: Mutex<State>
    init(dataless: BoundedReadMetadataCheck? = nil, fault: BoundedReadOperation? = nil,
         faultNumber: Int = 1, faultErrno: Int32 = EDEADLK, entryFails: Bool = false,
         restoreFails: Bool = false, clobbersErrno: Bool = false) {
        state = Mutex(State(dataless: dataless, fault: fault, faultNumber: faultNumber,
            faultErrno: faultErrno, entryFails: entryFails, restoreFails: restoreFails,
            clobbersErrno: clobbersErrno))
    }
    func withoutMaterializing<T>(_ body: () throws -> T) throws -> T {
        try state.withLock { value in
            value.entries += 1
            guard !value.entryFails else { throw PreviewFailure.unavailableContent }
            value.depth += 1
        }
        let result = Result(catching: body)
        let (fails, clobbersErrno) = state.withLock { value in
            value.restores += 1
            value.liveDescriptorsAtRestore.append(value.opened.count - value.closed.count)
            value.depth -= 1
            return (value.restoreFails, value.clobbersErrno)
        }
        if clobbersErrno { errno = EACCES } // After unlock, immediately before propagating the outcome.
        guard !fails else { throw PreviewFailure.unavailableContent }
        return try result.get()
    }
    func beforeIO(_ operation: BoundedReadOperation) -> Int32? {
        state.withLock { value in
            value.operations.append(operation)
            if value.depth == 0 { value.outsideScopes += 1 }
            return value.fault == operation && value.operations.filter({ $0 == operation }).count == value.faultNumber
                ? value.faultErrno : nil
        }
    }
    func flags(_ nativeFlags: UInt32, at check: BoundedReadMetadataCheck) -> UInt32 {
        state.withLock { $0.dataless == check ? nativeFlags | UInt32(SF_DATALESS) : nativeFlags }
    }
    func opened(_ descriptor: Int32) { state.withLock { $0.opened.append(descriptor) } }
    func closed(_ descriptor: Int32, result: Int32) {
        state.withLock { $0.closed.append(descriptor); $0.closeResults.append(result) }
    }
    func setDataless(_ check: BoundedReadMetadataCheck?) { state.withLock { $0.dataless = check } }
    func setPolicyFailures(entry: Bool = false, restore: Bool = false) {
        state.withLock { $0.entryFails = entry; $0.restoreFails = restore }
    }
    var snapshot: State { state.withLock { $0 } }
    func attempts(_ operation: BoundedReadOperation) -> Int { state.withLock { $0.operations.filter { $0 == operation }.count } }
    func expectNoLeaks() {
        let value = snapshot
        // Independent owners may close in a different order (for example a failed reopen
        // before the old Dispatch registration is cancelled). Preserve multiplicity.
        #expect(value.opened.sorted() == value.closed.sorted() && value.closeResults.allSatisfy { $0 == 0 })
        #expect(value.outsideScopes == 0 && value.depth == 0)
    }
}

struct Q153ReadFixture: Sendable {
    struct Snapshot: Equatable, Sendable {
        let bytes: Data
        let size: Int64
        let mode: UInt16
        let flags: UInt32
        let modifiedSeconds: Int, modifiedNanos: Int, changedSeconds: Int, changedNanos: Int
        let entries: [String]
    }
    let directory: URL
    let url: URL
    init(_ data: Data = Data([1, 2, 3, 4, 5, 6, 7, 8])) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        url = directory.appendingPathComponent("sample.bin")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do { try data.write(to: url) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func snapshot() throws -> Snapshot {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { lstat($0!, &info) }
        #expect(result == 0)
        return Snapshot(bytes: try Data(contentsOf: url), size: info.st_size, mode: info.st_mode, flags: info.st_flags,
            modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanos: info.st_mtimespec.tv_nsec,
            changedSeconds: info.st_ctimespec.tv_sec, changedNanos: info.st_ctimespec.tv_nsec,
            entries: try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted())
    }
    func expectUnchanged(_ before: Snapshot) throws { #expect(try snapshot() == before) }
}

func q153Context(limit: Int = 32) -> RequestContext {
    RequestContext(budget: .init(maxInputBytes: limit, maxMilliseconds: 30_000))
}

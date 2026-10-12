import Foundation
import Darwin
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

final class Q153DirectoryProbe: DirectoryReadPolicy, DirectoryReadProbe, Sendable {
    struct State {
        var entries = 0, restores = 0, depth = 0, outside = 0
        var operations: [DirectoryReadOperation] = []
        var opened: [Int32] = [], rootOpened: [Int32] = [], closed: [Int32] = [], closeResults: [Int32] = []
        var liveAtRestore = 0
        var dataless: DirectoryMetadataCheck?
        var entryFails = false, restoreFails = false, clobbersErrno = false
        var fault: DirectoryReadOperation?, faultError: Int32 = EIO
    }
    private let state = Mutex(State())
    var snapshot: State { state.withLock { $0 } }
    var access: DirectoryReadAccess { DirectoryReadAccess(policy: self, probe: self) }
    func configure(dataless: DirectoryMetadataCheck? = nil, entryFails: Bool = false,
                   restoreFails: Bool = false, fault: DirectoryReadOperation? = nil,
                   error: Int32 = EIO, clobbersErrno: Bool = false) {
        state.withLock {
            $0.dataless = dataless; $0.entryFails = entryFails; $0.restoreFails = restoreFails
            $0.fault = fault; $0.faultError = error; $0.clobbersErrno = clobbersErrno
        }
    }
    func withoutMaterializing<T>(_ body: () throws -> T) throws -> T {
        let entryFails = state.withLock { $0.entries += 1; if !$0.entryFails { $0.depth += 1 }; return $0.entryFails }
        if entryFails { throw PreviewFailure.unavailableContent }
        let result = Result(catching: body)
        let restore = state.withLock {
            $0.restores += 1; $0.depth -= 1; $0.liveAtRestore = $0.opened.count - $0.closed.count
            return (fails: $0.restoreFails, clobbers: $0.clobbersErrno)
        }
        if restore.clobbers { errno = EACCES }
        if restore.fails { throw PreviewFailure.unavailableContent }
        return try result.get()
    }
    func beforeIO(_ operation: DirectoryReadOperation) -> Int32? {
        state.withLock {
            $0.operations.append(operation); if $0.depth == 0 { $0.outside += 1 }
            return $0.fault == operation ? $0.faultError : nil
        }
    }
    func flags(_ native: UInt32, at check: DirectoryMetadataCheck) -> UInt32 {
        state.withLock { $0.dataless == check ? native | UInt32(SF_DATALESS) : native }
    }
    func opened(_ descriptor: Int32) {
        state.withLock {
            $0.opened.append(descriptor)
            if $0.operations.last == .openRoot { $0.rootOpened.append(descriptor) }
        }
    }
    func closed(_ descriptor: Int32, result: Int32) { state.withLock { $0.closed.append(descriptor); $0.closeResults.append(result) } }
    func expectClean() {
        let value = snapshot
        #expect(value.opened.sorted() == value.closed.sorted())
        #expect(value.closeResults.allSatisfy { $0 == 0 })
        #expect(value.depth == 0 && value.outside == 0 && value.liveAtRestore == 0)
    }
}
struct Q153DirectoryFixture {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("synthetic".utf8).write(to: url.appendingPathComponent("sample.txt"))
    }
    struct Snapshot: Equatable {
        let bytes: Data
        let root, child: [Int64]
        let names: [String]
    }
    func snapshot() throws -> Snapshot {
        func metadata(_ item: URL) throws -> [Int64] {
            var info = stat()
            try #require(item.withUnsafeFileSystemRepresentation { path in path.map { lstat($0, &info) == 0 } ?? false })
            return [Int64(info.st_size), Int64(info.st_mode), Int64(info.st_flags),
                    Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec),
                    Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec)]
        }
        let child = url.appendingPathComponent("sample.txt")
        return try Snapshot(bytes: Data(contentsOf: child), root: metadata(url), child: metadata(child),
                            names: FileManager.default.contentsOfDirectory(atPath: url.path).sorted())
    }
    func remove() { try? FileManager.default.removeItem(at: url) }
}
func q153DirectoryContext() -> RequestContext { RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)) }

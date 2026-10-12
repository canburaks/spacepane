import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Q153 folder child metadata and refusal")
struct Q153FolderChildTests {
    private func fixture() throws -> Q153DirectoryFixture {
        let fixture = try Q153DirectoryFixture()
        let branch = fixture.url.appendingPathComponent("branch", isDirectory: true)
        try FileManager.default.createDirectory(at: branch, withIntermediateDirectories: false)
        try Data("owned".utf8).write(to: branch.appendingPathComponent("leaf.txt"))
        return fixture
    }
    private func list(_ fixture: Q153DirectoryFixture, depth: Int, probe: Q153DirectoryProbe) throws -> [String: Any] {
        var context = q153DirectoryContext(); context.options = PreviewRequestOptions(folderDepth: depth)
        let document = try FolderSummaryAdapter(access: probe.access).parse(url: fixture.url, context: context)
        return try #require(try JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
    }
    @Test(arguments: [1, 2], [DirectoryMetadataCheck.listedChild, .childPreflight, .childOpened])
    func flaggedChildDirectoryIsListedWithoutEnumeration(depth: Int, check: DirectoryMetadataCheck) throws {
        let fixture = try fixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(dataless: check)
        let summary = try list(fixture, depth: depth, probe: probe)
        let entries = try #require(summary["entries"] as? [[String: Any]])
        let branch = try #require(entries.first { $0["path"] as? String == "branch" })
        #expect(branch["type"] as? String == "directory" && branch["items"] == nil)
        #expect(summary["partial"] as? Bool == true)
        #expect(!entries.contains { $0["path"] as? String == "branch/leaf.txt" })
        let operations = probe.snapshot.operations
        #expect(operations.filter { $0 == .openDirectory(root: false) }.count == (check == .childOpened ? 1 : 0))
        #expect(!operations.contains(.directoryStream(root: false)) && !operations.contains(.nextEntry(root: false)))
        #expect(probe.snapshot.entries == 1 && probe.snapshot.restores == 1)
        probe.expectClean()
    }
    @Test(arguments: [DirectoryMetadataCheck.beforeEnumeration, .afterEnumeration])
    func rootAvailabilityTransitionRefusesSummary(check: DirectoryMetadataCheck) throws {
        let fixture = try fixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(dataless: check)
        #expect(throws: PreviewFailure.unavailableContent) { try list(fixture, depth: 2, probe: probe) }
        if check == .beforeEnumeration { #expect(!probe.snapshot.operations.contains(.nextEntry(root: true))) }
        probe.expectClean()
    }
    @Test(arguments: [DirectoryReadOperation.openDirectory(root: true), .directoryStream(root: true), .nextEntry(root: true)])
    func rootNativeRefusalRemainsTypedThroughCleanup(operation: DirectoryReadOperation) throws {
        let fixture = try fixture(); defer { fixture.remove() }
        let originalErrno = errno; defer { errno = originalErrno }
        let probe = Q153DirectoryProbe(); probe.configure(fault: operation, error: EDEADLK, clobbersErrno: true)
        var failure: PreviewFailure?, restoredErrno: Int32?
        do { _ = try list(fixture, depth: 2, probe: probe) }
        catch { restoredErrno = errno; failure = error as? PreviewFailure }
        #expect(failure == .unavailableContent && restoredErrno == EACCES)
        probe.expectClean()
    }
    @Test func datalessRegularChildMetadataDoesNotRefuseMaterializedParent() throws {
        let fixture = try Q153DirectoryFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(); let probe = Q153DirectoryProbe(); probe.configure(dataless: .listedChild)
        let summary = try list(fixture, depth: 2, probe: probe)
        let entries = try #require(summary["entries"] as? [[String: Any]])
        #expect(entries.count == 1 && entries[0]["path"] as? String == "sample.txt")
        #expect(entries[0]["bytes"] as? Int == 9 && summary["partial"] as? Bool == false)
        #expect(!probe.snapshot.operations.contains(.openDirectory(root: false)))
        #expect(try fixture.snapshot() == before)
        probe.expectClean()
    }
    @Test(arguments: [DirectoryReadOperation.openDirectory(root: false), .directoryStream(root: false), .nextEntry(root: false)],
          [Int32(EACCES), Int32(EDEADLK)])
    func optionalChildFailureKeepsPartialMetadata(operation: DirectoryReadOperation, error: Int32) throws {
        let fixture = try fixture(); defer { fixture.remove() }
        let probe = Q153DirectoryProbe(); probe.configure(fault: operation, error: error)
        let summary = try list(fixture, depth: 1, probe: probe)
        let entries = try #require(summary["entries"] as? [[String: Any]])
        #expect(entries.contains { $0["path"] as? String == "sample.txt" })
        #expect(try #require(entries.first { $0["path"] as? String == "branch" })["items"] == nil)
        #expect(summary["partial"] as? Bool == true)
        probe.expectClean()
    }
}

import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// ZIP listing dates, encrypted members and budget-limited listings. Archives are built in memory.
@Suite("ZIP listing")
struct ZIPListingTests {
    private struct Member {
        var path: String
        var payload = Data("synthetic payload".utf8)
        var flags: UInt64 = 0x800
        var dosDate: UInt64 = 0
        var dosTime: UInt64 = 0
        var extra = Data()
        var unixMode: UInt64 = 0
    }

    private func little(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }

    private func dos(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> (date: UInt64, time: UInt64) {
        (UInt64((year - 1980) << 9 | month << 5 | day), UInt64(hour << 11 | minute << 5 | second / 2))
    }

    private func archive(_ members: [Member]) -> Data {
        var data = Data()
        var central = Data()
        for member in members {
            let name = Data(member.path.utf8)
            let offset = data.count
            data += little(0x04034b50, 4) + little(20, 2) + little(member.flags, 2) + little(0, 2)
            data += little(member.dosTime, 2) + little(member.dosDate, 2) + little(0, 4)
            data += little(UInt64(member.payload.count), 4) + little(UInt64(member.payload.count), 4)
            data += little(UInt64(name.count), 2) + little(UInt64(member.extra.count), 2) + name + member.extra + member.payload
            central += little(0x02014b50, 4) + little(20, 2) + little(20, 2) + little(member.flags, 2) + little(0, 2)
            central += little(member.dosTime, 2) + little(member.dosDate, 2) + little(0, 4)
            central += little(UInt64(member.payload.count), 4) + little(UInt64(member.payload.count), 4)
            central += little(UInt64(name.count), 2) + little(UInt64(member.extra.count), 2) + little(0, 2)
            central += little(0, 2) + little(0, 2) + little(member.unixMode << 16, 4) + little(UInt64(offset), 4)
            central += name + member.extra
        }
        let directoryOffset = data.count
        data += central
        data += little(0x06054b50, 4) + little(0, 4) + little(UInt64(members.count), 2) + little(UInt64(members.count), 2)
        data += little(UInt64(central.count), 4) + little(UInt64(directoryOffset), 4) + little(0, 2)
        return data
    }

    private func list(_ members: [Member], budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> (root: [String: Any], entries: [[String: Any]], text: String) {
        let document = try ZIPListingAdapter().parse(FileBytes(data: archive(members)), context: RequestContext(budget: budget))
        let root = try #require(try JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
        return (root, root["entries"] as? [[String: Any]] ?? [], document.text)
    }

    @Test func storedMSDOSTimesAreListedAsISOValuesMarkedUTCWallClock() throws {
        let stamp = dos(year: 2026, month: 10, day: 5, hour: 12, minute: 30, second: 20)
        let result = try list([Member(path: "docs/readme.txt", dosDate: stamp.date, dosTime: stamp.time)])
        #expect(result.entries.first?["modified"] as? String == "2026-10-05T12:30:20Z")
        #expect(result.root["timeZone"] as? String == "UTC")
    }

    @Test func theExtendedTimestampFieldOverridesTheDOSTime() throws {
        let stamp = dos(year: 1999, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        // 0x5455 "UT": flags = modification time present, then a little-endian Unix time (2026-01-01T00:00:00Z).
        let extra = little(0x5455, 2) + little(5, 2) + Data([1]) + little(1_767_225_600, 4)
        let result = try list([Member(path: "a.txt", dosDate: stamp.date, dosTime: stamp.time, extra: extra)])
        #expect(result.entries.first?["modified"] as? String == "2026-01-01T00:00:00Z")
    }

    @Test func anArchiveWithoutDatesWritesNoModifiedOrTimeZoneFields() throws {
        let result = try list([Member(path: "a.txt")])
        #expect(result.entries.first?["modified"] == nil)
        #expect(result.root["timeZone"] == nil)
    }

    @Test func encryptedMembersAreListedAndFlaggedWhileOthersStayUnflagged() throws {
        let result = try list([Member(path: "open.txt"), Member(path: "locked.txt", flags: 0x801), Member(path: "strong.txt", flags: 0x840)])
        #expect(result.entries.map { $0["path"] as? String } == ["open.txt", "locked.txt", "strong.txt"])
        #expect(result.entries[0]["encrypted"] == nil)
        #expect(result.entries[1]["encrypted"] as? Bool == true)
        #expect(result.entries[2]["encrypted"] as? Bool == true)
        #expect(!result.text.contains("synthetic payload"))
    }

    @Test func encryptedMembersStillRefuseToBeRead() throws {
        let data = archive([Member(path: "locked.txt", flags: 0x801)])
        let source = DataByteSource(data)
        let context = RequestContext(budget: .standard)
        let zip = try ZIPArchiveReader.read(source, context: context, encryptedEntries: .list)
        #expect(zip.entries.first?.isEncrypted == true)
        #expect(throws: PreviewFailure.encryptedContent) {
            try ZIPArchiveReader.readMember(zip.entries[0], from: source, maximumBytes: 1_024, context: context)
        }
    }

    @Test func kindsDirectoriesAndSizesKeepTheirExistingMeaning() throws {
        let result = try list([
            Member(path: "dir/", payload: Data()),
            Member(path: "dir/file.txt", payload: Data(repeating: 0x78, count: 42)),
            Member(path: "link", unixMode: 0xa000)
        ])
        #expect(result.entries.map { $0["type"] as? String } == ["directory", "file", "symlink"])
        #expect(result.entries[1]["bytes"] as? Int == 42)
    }

    @Test func anArchiveBeyondTheNodeBudgetListsItsFirstEntriesAsPartialInsteadOfFailing() throws {
        let members = (0..<200).map { Member(path: "file-\($0).txt") }
        let result = try list(members, budget: PreviewBudget(maxJSONNodes: 300, maxMilliseconds: 30_000))
        #expect(result.root["partial"] as? Bool == true)
        let listed = result.entries.count
        #expect(listed > 0 && listed < 200)
        #expect(result.root["listedEntries"] as? Int == listed)
        #expect(result.entries.first?["path"] as? String == "file-0.txt")
        // A comfortable budget lists everything and is not partial.
        let full = try list(members)
        #expect(full.root["partial"] as? Bool == false)
        #expect(full.entries.count == 200)
    }

    @Test func aPathLongerThanTheLineBudgetIsSkippedAndFlagsPartial() throws {
        let long = String(repeating: "a", count: 40_000)
        let result = try list([Member(path: "short.txt"), Member(path: long), Member(path: "after.txt")])
        #expect(result.entries.map { $0["path"] as? String } == ["short.txt", "after.txt"])
        #expect(result.root["partial"] as? Bool == true)
    }

    @Test func traversalIsListedAndFlaggedWhileMalformedArchivesFail() throws {
        // Listing never extracts, so an unsafe name is shown and reported as a risk (decision 012).
        let traversal = try ZIPListingAdapter().parse(FileBytes(data: archive([Member(path: "../escape")])),
                                                      context: RequestContext(budget: .standard))
        #expect(traversal.text.contains("\"path\": \"../escape\"") && traversal.text.contains("\"unsafePath\""))
        var corrupt = archive([Member(path: "a.txt")])
        corrupt[corrupt.count - 6] = 0xff
        #expect(throws: PreviewFailure.malformedDocument) {
            try ZIPListingAdapter().parse(FileBytes(data: corrupt), context: RequestContext(budget: .standard))
        }
    }

    @Test func aCancelledRequestStopsBeforeReadingTheArchive() async throws {
        let data = archive([Member(path: "a.txt")])
        let task = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try ZIPListingAdapter().parse(FileBytes(data: data), context: RequestContext(budget: .standard)); return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        task.cancel()
        #expect(await task.value)
    }
}

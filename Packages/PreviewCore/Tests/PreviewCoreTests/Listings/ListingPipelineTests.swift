import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

/// Folder and ZIP listings through the shared pipeline: preference options, enablement, concealment.
@Suite("Listing pipeline")
struct ListingPipelineTests {
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        for path in ["top.txt", ".hidden.txt", "docs/inner.txt", "docs/password=synthetic-secret-value.txt", "docs/deep/deeper.txt"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("source-must-never-appear".utf8).write(to: url)
        }
        return root
    }

    private func presentation(of url: URL, preferences: PreviewPreferencesSnapshot = .defaults) async throws -> TextPresentation {
        let outcome = await PreviewPipeline(registrations: StandardFormatAdapters.registrations).preview(url: url, preferences: preferences)
        guard case let .ready(presentation) = outcome else { throw PreviewFailure.unavailableContent }
        return presentation
    }

    @Test func folderDepthAndHiddenItemsComeFromThePreferenceSnapshotOnly() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try await presentation(of: root)
        #expect(defaults.text.contains("\"depth\": 1"))
        #expect(!defaults.text.contains("inner.txt"))
        #expect(!defaults.text.contains(".hidden.txt"))
        #expect(defaults.text.contains("\"hiddenEntries\": 1"))
        let nested = try await presentation(of: root, preferences: PreviewPreferencesSnapshot(folderDepth: 2, showsHiddenFolderItems: true))
        #expect(nested.text.contains("docs/inner.txt"))
        #expect(!nested.text.contains("docs/deep/deeper.txt"), "Depth 2 lists docs/deep but only counts its contents")
        #expect(nested.text.contains("docs/deep"))
        #expect(nested.text.contains(".hidden.txt"))
        #expect(nested.text.contains("\"depth\": 2"))
        #expect(!nested.text.contains("source-must-never-appear"))
        // An out-of-range request is clamped by the snapshot, never rejected.
        let clamped = try await presentation(of: root, preferences: PreviewPreferencesSnapshot(folderDepth: 99))
        #expect(clamped.text.contains("\"depth\": 4"))
    }

    @Test func nestedNamesThatLookLikeSecretAssignmentsAreConcealedAndTheJSONStaysValid() async throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await presentation(of: root, preferences: PreviewPreferencesSnapshot(folderDepth: 4))
        #expect(!result.text.contains("synthetic-secret-value"))
        #expect(result.redactionCount >= 1)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [String: Any])
        let paths = (object["entries"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
        #expect(paths.contains("docs/inner.txt"))
        #expect(paths.contains("••••"))
        #expect(paths.contains("docs/deep/deeper.txt"))
    }

    private final class Counter: Sendable {
        let constructed = Mutex(0)
    }

    @Test func aDisabledFolderOrZIPTypeIsNeverConstructedOrOpened() async throws {
        let counter = Counter()
        let registrations = [
            AdapterRegistration(formatID: .folder, urlAdapter: { counter.constructed.withLock { $0 += 1 }; return FolderSummaryAdapter() }),
            AdapterRegistration(formatID: .zip, randomAccessAdapter: { counter.constructed.withLock { $0 += 1 }; return ZIPListingAdapter() })
        ]
        let pipeline = PreviewPipeline(registrations: registrations)
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        var preferences = PreviewPreferencesSnapshot(folderDepth: 4, showsHiddenFolderItems: true)
        preferences.setEnabled(false, for: .folder)
        preferences.setEnabled(false, for: .zip)
        #expect(await pipeline.preview(url: root, preferences: preferences) == .disabledByUser(.folder))
        let zipURL = root.appendingPathComponent("archive.zip")
        try Data("not read".utf8).write(to: zipURL)
        #expect(await pipeline.preview(url: zipURL, preferences: preferences) == .disabledByUser(.zip))
        #expect(counter.constructed.withLock { $0 } == 0)
    }

    @Test func anEncryptedMemberIsListedThroughThePipelineWithoutDecryptingAnything() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("secrets.zip")
        try zip(path: "locked/api.txt", flags: 0x801).write(to: url)
        let result = try await presentation(of: url)
        #expect(result.formatID == .zip)
        #expect(result.text.contains("locked/api.txt"))
        #expect(result.text.contains("\"encrypted\": true"))
        #expect(result.text.contains("\"timeZone\": \"UTC\""))
        #expect(!result.text.contains("synthetic payload"))
    }

    private func zip(path: String, flags: UInt64) -> Data {
        func little(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
        let name = Data(path.utf8)
        let payload = Data("synthetic payload".utf8)
        // 2026-10-05 12:30:00 as MS-DOS date and time.
        let date: UInt64 = (46 << 9) | (10 << 5) | 5
        let time: UInt64 = (12 << 11) | (30 << 5)
        var data = little(0x04034b50, 4) + little(20, 2) + little(flags, 2) + little(0, 2) + little(time, 2) + little(date, 2) + little(0, 4)
        data += little(UInt64(payload.count), 4) + little(UInt64(payload.count), 4) + little(UInt64(name.count), 2) + little(0, 2) + name + payload
        let directory = data.count
        var central = little(0x02014b50, 4) + little(20, 2) + little(20, 2) + little(flags, 2) + little(0, 2) + little(time, 2) + little(date, 2) + little(0, 4)
        central += little(UInt64(payload.count), 4) + little(UInt64(payload.count), 4) + little(UInt64(name.count), 2) + little(0, 2) + little(0, 2)
        central += little(0, 2) + little(0, 2) + little(0, 4) + little(0, 4) + name
        data += central
        data += little(0x06054b50, 4) + little(0, 4) + little(1, 2) + little(1, 2) + little(UInt64(central.count), 4) + little(UInt64(directory), 4) + little(0, 2)
        return data
    }
}

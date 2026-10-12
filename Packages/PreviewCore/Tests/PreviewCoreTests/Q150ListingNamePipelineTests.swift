import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewCore

private func q150ListingTAR(_ names: [String]) -> Data {
    var data = Data()
    for name in names {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ text: String, at offset: Int) { for (index, byte) in text.utf8.enumerated() { header[offset + index] = byte } }
        put(name, at: 0)
        put("0000644\0", at: 100)
        put("00000000001\0", at: 124)
        header[156] = 48
        put("ustar\0", at: 257)
        for index in 148..<156 { header[index] = 32 }
        put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ", at: 148)
        data += Data(header) + Data([0x78]) + Data(repeating: 0, count: 511)
    }
    return data + Data(repeating: 0, count: 1024)
}

private final class Q150ListingReadCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private struct Q150ListingReader: PreviewFileReading {
    let reads: Q150ListingReadCounter
    func read(url: URL, context: RequestContext) throws -> FileBytes { reads.increment(); throw PreviewFailure.unreadableFile }
}

@Suite("Q150 listing name pipeline")
struct Q150ListingNamePipelineTests {
    @Test func aRealTARPreservesBytesAndNamesWhileItsFindingStaysCountOnly() async throws {
        let names = ["a\u{200B}.txt", "tag\u{E0070}\u{E0077}.txt", "שלום\u{200F}.txt"]
        let bytes = q150ListingTAR(names)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic.tar")
        try bytes.write(to: url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let outcome = await PreviewPipeline(registrations: StandardFormatAdapters.registrations).preview(url: url)
        guard case .ready(let presentation) = outcome else { Issue.record("No archive listing"); return }
        #expect(presentation.formatID == .tar && presentation.origin == .summary)
        let root = try #require(JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: Any])
        let entries = try #require(root["entries"] as? [[String: Any]])
        #expect(entries.compactMap { $0["path"] as? String }.map { Array($0.utf8) } == names.map { Array($0.utf8) })
        let finding = try #require(presentation.findings.first { $0.kind.rawValue == "listing.hiddenCharacters" })
        #expect(finding.count == 2 && finding.lines.isEmpty && finding.detail == .none)
        #expect(presentation.findings.first { $0.kind == .archiveDirectionalName }?.count == 1)
        #expect(!presentation.findings.contains { $0.kind.rawValue.hasPrefix("hidden.") })
        #expect(try Data(contentsOf: url) == bytes)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["synthetic.tar"])
    }

    @Test func theFolderPipelineReadsNoChildPayloadAndRespectsDisabledPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("child\u{200B}.txt")
        let bytes = Data("password=synthetic-child-content".utf8)
        try bytes.write(to: url)
        let reads = Q150ListingReadCounter()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: Q150ListingReader(reads: reads))
        let outcome = await pipeline.preview(url: directory)
        guard case .ready(let presentation) = outcome else { Issue.record("No folder listing"); return }
        #expect(presentation.formatID == .folder && presentation.origin == .summary)
        let finding = try #require(presentation.findings.first { $0.kind.rawValue == "listing.hiddenCharacters" })
        #expect(finding.count == 1 && finding.lines.isEmpty && finding.detail == .none)
        #expect(reads.value == 0 && !presentation.text.contains("synthetic-child-content"))
        var disabled = PreviewPreferencesSnapshot.defaults
        disabled.setEnabled(false, for: .folder)
        #expect(await pipeline.preview(url: directory, preferences: disabled) == .disabledByUser(.folder))
        #expect(reads.value == 0)
        #expect(try Data(contentsOf: url) == bytes)
    }
}

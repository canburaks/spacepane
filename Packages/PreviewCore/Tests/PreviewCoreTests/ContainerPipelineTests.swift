import Foundation
import SQLite3
import zlib
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

@Test func SQLitePipelineConcealsAllSourceRepresentationsWithoutChangingDatabaseOrCreatingSidecars() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("synthetic.sqlite")
    var connection: OpaquePointer?
    #expect(sqlite3_open(url.path, &connection) == SQLITE_OK)
    guard let connection else { throw PreviewFailure.malformedDocument }
    #expect(sqlite3_exec(connection, "CREATE TABLE user_tokens(password TEXT, normal TEXT); INSERT INTO user_tokens VALUES('synthetic-password','synthetic-token-value'); CREATE INDEX safe_idx ON user_tokens(normal);", nil, nil, nil) == SQLITE_OK)
    #expect(sqlite3_close(connection) == SQLITE_OK)
    let before = try Data(contentsOf: url)
    let beforeNames = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    let beforeAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
    let outcome = await pipeline.preview(url: url)
    guard case let .ready(presentation) = outcome else { Issue.record("Expected SQLite preview, got \(outcome)"); return }
    #expect(!presentation.text.contains("synthetic-password"))
    #expect(!presentation.text.contains("synthetic-token-value"))
    #expect(presentation.text.contains("safe_idx"))
    #expect(presentation.redactionCount >= 3)
    // Privacy replacement remains valid JSON, so outline/table/copy all consume one safe representation.
    #expect((try JSONSerialization.jsonObject(with: Data(presentation.text.utf8))) is [String: Any])
    #expect(try Data(contentsOf: url) == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == beforeNames)
    let afterAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect(afterAttributes[.modificationDate] as? Date == beforeAttributes[.modificationDate] as? Date)
}

@Test func FolderPipelineConcealsSecretAssignmentsInNamesWithoutReadingChildren() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let name = "password=synthetic-folder-secret.txt"
    try Data("source-must-never-appear".utf8).write(to: directory.appendingPathComponent(name))
    let outcome = await PreviewPipeline(registrations: StandardFormatAdapters.registrations).preview(url: directory)
    guard case let .ready(presentation) = outcome else { Issue.record("Expected folder preview"); return }
    #expect(!presentation.text.contains("synthetic-folder-secret"))
    #expect(!presentation.text.contains("source-must-never-appear"))
    #expect(presentation.redactionCount == 1)
    #expect((try JSONSerialization.jsonObject(with: Data(presentation.text.utf8))) is [String: Any])
}

// MARK: Archive risk findings

private func le(_ value: UInt64, _ width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }

/// Stored, unencrypted members with UTF-8 names.
private func zipFile(_ members: [(path: String, payload: Data)]) -> Data {
    var data = Data()
    var central = Data()
    for member in members {
        let name = Data(member.path.utf8)
        let size = UInt64(member.payload.count)
        let offset = data.count
        data += le(0x04034b50, 4) + le(20, 2) + le(0x800, 2) + le(0, 2) + Data(repeating: 0, count: 8) + le(size, 4) + le(size, 4)
        data += le(UInt64(name.count), 2) + le(0, 2) + name + member.payload
        central += le(0x02014b50, 4) + le(20, 2) + le(20, 2) + le(0x800, 2) + le(0, 2) + Data(repeating: 0, count: 8)
        central += le(size, 4) + le(size, 4) + le(UInt64(name.count), 2) + Data(repeating: 0, count: 8) + le(0, 4) + le(UInt64(offset), 4) + name
    }
    let start = data.count
    data += central + le(0x06054b50, 4) + Data(repeating: 0, count: 4) + le(UInt64(members.count), 2) + le(UInt64(members.count), 2)
    return data + le(UInt64(central.count), 4) + le(UInt64(start), 4) + le(0, 2)
}

private func tarFile(_ members: [(path: String, type: UInt8, link: String, mode: Int)]) -> Data {
    var data = Data()
    for member in members {
        var header = [UInt8](repeating: 0, count: 512)
        func put(_ string: String, at offset: Int, count: Int) {
            for (index, byte) in string.utf8.prefix(count).enumerated() { header[offset + index] = byte }
        }
        put(member.path, at: 0, count: 100)
        put(String(format: "%07o", member.mode) + "\0", at: 100, count: 8)
        put("00000000000\0", at: 124, count: 12)
        header[156] = member.type
        put(member.link, at: 157, count: 100)
        put("ustar\0", at: 257, count: 6)
        for index in 148..<156 { header[index] = 32 }
        put(String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ", at: 148, count: 8)
        data += Data(header)
    }
    return data + Data(repeating: 0, count: 1024)
}

private func gzipFile(_ data: Data) throws -> Data {
    var stream = z_stream()
    guard deflateInit2_(&stream, 6, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
        throw PreviewFailure.unavailableContent
    }
    defer { deflateEnd(&stream) }
    var result = Data(count: data.count + 256)
    let capacity = result.count
    return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
        try result.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            stream.next_out = output.bindMemory(to: UInt8.self).baseAddress!
            stream.avail_out = uInt(capacity)
            guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { throw PreviewFailure.unavailableContent }
            return Data(output.prefix(capacity - Int(stream.avail_out)))
        }
    }
}

/// Previews a synthetic archive written to a private directory and checks the source stayed untouched.
private func previewArchive(_ data: Data, named name: String) async throws -> TextPresentation {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    let outcome = await PreviewPipeline(registrations: StandardFormatAdapters.registrations).preview(url: url)
    guard case let .ready(presentation) = outcome else { throw PreviewFailure.unavailableContent }
    #expect(try Data(contentsOf: url) == data)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [name])
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date == modified)
    return presentation
}

@Test func ZIPPipelineCarriesRiskFindingsAndStillConcealsSecretsInRiskyNames() async throws {
    let payload = Data("synthetic payload".utf8)
    let archive = zipFile([
        (path: "../escape.txt", payload: payload),
        (path: "password=synthetic-zip-secret.exe", payload: payload),
        (path: "ok.txt", payload: payload)
    ])
    let presentation = try await previewArchive(archive, named: "risky.zip")
    let kinds = Set(presentation.findings.map(\.kind))
    #expect(kinds.isSuperset(of: [.archiveUnsafePath, .archiveExecutables]))
    #expect(presentation.findings.first { $0.kind == .archiveUnsafePath }?.count == 1)
    #expect(presentation.findings.filter { $0.kind.rawValue.hasPrefix("archive.") }.allSatisfy { $0.lines.isEmpty })
    #expect(presentation.text.contains("\"risks\""))
    #expect(presentation.text.contains("\"path\": \"../escape.txt\""))
    // The name is analyzed as stored, then shown through the same privacy handling as any other archive.
    #expect(!presentation.text.contains("synthetic-zip-secret"))
    #expect(!presentation.text.contains("synthetic payload"))
    #expect(presentation.redactionCount >= 1)
    #expect((try JSONSerialization.jsonObject(with: Data(presentation.text.utf8))) is [String: Any])
}

@Test func cleanArchivePipelineHasNoFindingsOrRiskFields() async throws {
    let archive = zipFile([(path: "docs/readme.txt", payload: Data("synthetic payload".utf8))])
    let presentation = try await previewArchive(archive, named: "clean.zip")
    #expect(presentation.findings.isEmpty)
    #expect(!presentation.text.contains("risks"))
    #expect(presentation.text.contains("docs/readme.txt"))
}

@Test func TARAndGZIPPipelinesShareTheArchiveAnalysis() async throws {
    let tar = tarFile([
        (path: "docs/", type: 53, link: "", mode: 0o755),
        (path: "docs/link", type: 50, link: "../../etc", mode: 0o777),
        (path: "docs/fine", type: 50, link: "sibling", mode: 0o777),
        (path: "bin/tool", type: 48, link: "", mode: 0o755),
        (path: "nested.zip", type: 48, link: "", mode: 0o644)
    ])
    let plain = try await previewArchive(tar, named: "risky.tar")
    let wrapped = try await previewArchive(gzipFile(tar), named: "risky.tar.gz")
    #expect(Set(plain.findings.map(\.kind)) == [.archiveLinkEscape, .archiveExecutables, .archiveNested])
    #expect(wrapped.findings == plain.findings)
    #expect(wrapped.text == plain.text)
    #expect(plain.text.contains("\"risks\""))
    // The link that stays inside the archive carries no risk.
    #expect(plain.findings.first { $0.kind == .archiveLinkEscape }?.count == 1)
    #expect(plain.findings.allSatisfy { $0.kind != .archiveLinks })
}

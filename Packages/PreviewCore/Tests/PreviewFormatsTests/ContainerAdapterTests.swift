import Foundation
import SQLite3
import Compression
import zlib
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

let containerContext = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))

func little(_ value: UInt64, width: Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
func big(_ value: UInt64, width: Int) -> Data { Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }

func zipFixture(path: String = "nested/日本語.txt", encrypted: Bool = false, zip64: Bool = false) -> Data {
    let name = Data(path.utf8)
    let payload = Data("synthetic source".utf8)
    let flags: UInt64 = 0x800 | (encrypted ? 1 : 0)
    var data = little(0x04034b50, width: 4) + little(20, width: 2) + little(flags, width: 2)
    data += little(0, width: 2) + Data(repeating: 0, count: 8)
    data += little(UInt64(payload.count), width: 4) + little(UInt64(payload.count), width: 4)
    data += little(UInt64(name.count), width: 2) + little(0, width: 2) + name + payload
    let start = data.count
    data += little(0x02014b50, width: 4) + little(20, width: 2) + little(20, width: 2) + little(flags, width: 2)
    data += little(0, width: 2) + Data(repeating: 0, count: 8)
    data += little(UInt64(payload.count), width: 4) + little(UInt64(payload.count), width: 4)
    data += little(UInt64(name.count), width: 2) + Data(repeating: 0, count: 12) + little(0, width: 4) + name
    let directorySize = data.count - start
    if zip64 {
        let recordOffset = data.count
        data += little(0x06064b50, width: 4) + little(44, width: 8) + little(45, width: 2) + little(45, width: 2)
        data += Data(repeating: 0, count: 8) + little(1, width: 8) + little(1, width: 8)
        data += little(UInt64(directorySize), width: 8) + little(UInt64(start), width: 8)
        data += little(0x07064b50, width: 4) + little(0, width: 4) + little(UInt64(recordOffset), width: 8) + little(1, width: 4)
    }
    data += little(0x06054b50, width: 4) + Data(repeating: 0, count: 4)
    data += little(zip64 ? 0xffff : 1, width: 2) + little(zip64 ? 0xffff : 1, width: 2)
    data += little(zip64 ? 0xffffffff : UInt64(directorySize), width: 4)
    data += little(zip64 ? 0xffffffff : UInt64(start), width: 4) + little(0, width: 2)
    return data
}

func tarFixture(path: String = "safe.txt", payload: Data = Data("synthetic text".utf8), type: UInt8 = 48) -> Data {
    var header = [UInt8](repeating: 0, count: 512)
    func put(_ string: String, at offset: Int, count: Int) {
        for (index, byte) in string.utf8.prefix(count).enumerated() { header[offset + index] = byte }
    }
    put(path, at: 0, count: 100)
    put("0000644\0", at: 100, count: 8)
    put(String(format: "%011o", payload.count) + "\0", at: 124, count: 12)
    header[156] = type
    put("ustar\0", at: 257, count: 6)
    for index in 148..<156 { header[index] = 32 }
    let checksum = header.reduce(0) { $0 + Int($1) }
    put(String(format: "%06o", checksum) + "\0 ", at: 148, count: 8)
    return Data(header) + payload + Data(repeating: 0, count: (512 - payload.count % 512) % 512 + 1024)
}

func compressFixture(_ data: Data, gzip: Bool) throws -> Data {
    var stream = z_stream()
    #expect(deflateInit2_(&stream, 6, Z_DEFLATED, gzip ? 31 : 15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
    defer { deflateEnd(&stream) }
    var result = Data(count: max(256, data.count * 2 + 128))
    let count = result.count
    return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
        try result.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            stream.next_out = output.bindMemory(to: UInt8.self).baseAddress!
            stream.avail_out = uInt(count)
            guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { throw PreviewFailure.malformedDocument }
            return Data(output.prefix(count - Int(stream.avail_out)))
        }
    }
}

func xzFixture(_ data: Data) -> Data {
    var output = [UInt8](repeating: 0, count: max(512, data.count * 2 + 128))
    let capacity = output.count
    let count = data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
        output.withUnsafeMutableBufferPointer { target in
            compression_encode_buffer(target.baseAddress!, capacity, input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZMA)
        }
    }
    return Data(output.prefix(count))
}

/// A CPIO "newc" archive from (name, mode, contents) members.
func cpioArchive(_ members: [(name: String, mode: Int, contents: Data)]) -> Data {
    func entry(_ name: String, mode: Int, contents: Data) -> Data {
        let fields = [1, mode, 0, 0, 1, 0, contents.count, 0, 0, 0, 0, name.utf8.count + 1, 0]
        var data = Data(("070701" + fields.map { String(format: "%08x", $0) }.joined()).utf8)
        data += Data(name.utf8) + Data([0])
        data += Data(repeating: 0, count: (4 - data.count % 4) % 4)
        data += contents + Data(repeating: 0, count: (4 - contents.count % 4) % 4)
        return data
    }
    return members.reduce(Data()) { $0 + entry($1.name, mode: $1.mode, contents: $1.contents) }
        + entry("TRAILER!!!", mode: 0x81a4, contents: Data())
}

func cpioFixture(path: String = "nested/safe.txt", payload: Data = Data("synthetic source".utf8)) -> Data {
    cpioArchive([(path, 0x81a4, payload)])
}

func xipFixture(path: String = "nested/safe.txt") throws -> Data { try xipContainer(cpio: cpioFixture(path: path)) }

/// A XIP wrapper (XAR table of contents plus one PBZX chunk) around a CPIO archive.
func xipContainer(cpio: Data) throws -> Data {
    let chunk = xzFixture(cpio)
    let pbzx = Data("pbzx".utf8) + big(0x01000000, width: 8) + big(0, width: 8) + big(UInt64(chunk.count), width: 8) + chunk
    let xml = Data("<xar><toc><file id=\"1\"><name>Content</name><type>file</type><data><offset>0</offset><length>\(pbzx.count)</length><size>\(pbzx.count)</size><encoding style=\"application/octet-stream\"/></data></file></toc></xar>".utf8)
    let compressed = try compressFixture(xml, gzip: false)
    return Data("xar!".utf8) + big(28, width: 2) + big(1, width: 2) + big(UInt64(compressed.count), width: 8)
        + big(UInt64(xml.count), width: 8) + big(0, width: 4) + compressed + pbzx
}

@Test func ZIPAndZIP64ListUnicodeAndNeverReadPayload() throws {
    for zip64 in [false, true] {
        let document = try ZIPListingAdapter().parse(FileBytes(data: zipFixture(zip64: zip64)), context: containerContext)
        #expect(document.text.contains("nested/日本語.txt"))
        #expect(document.text.contains(zip64 ? "ZIP64" : "ZIP"))
        #expect(!document.text.contains("synthetic source"))
        #expect(document.syntax == .json)
    }
}

@Test func ZIPListsEncryptedAndTraversalEntriesWithRisksAndRejectsMalformedOffsets() throws {
    // Listing never extracts, so these entries are shown and flagged instead of failing the archive.
    let encrypted = try ZIPListingAdapter().parse(FileBytes(data: zipFixture(encrypted: true)), context: containerContext)
    #expect(encrypted.text.contains("\"risks\""))
    #expect(encrypted.text.contains("\"encrypted\": true"))
    #expect(!encrypted.text.contains("synthetic source"))
    #expect(encrypted.findings.map(\.kind) == [.archiveEncrypted])
    let traversal = try ZIPListingAdapter().parse(FileBytes(data: zipFixture(path: "../escape")), context: containerContext)
    #expect(traversal.text.contains("\"path\": \"../escape\""))
    #expect(traversal.text.contains("\"unsafePath\""))
    #expect(traversal.findings.map(\.kind) == [.archiveUnsafePath])
    var corrupt = zipFixture()
    corrupt[corrupt.count - 6] = 0xff
    #expect(throws: PreviewFailure.malformedDocument) { try ZIPListingAdapter().parse(FileBytes(data: corrupt), context: containerContext) }
    #expect(throws: PreviewFailure.inputTooLarge) { try ZIPListingAdapter().parse(FileBytes(data: zipFixture()), context: RequestContext(budget: PreviewBudget(maxInputBytes: 20))) }
}

@Test func TARAndGZIPDistinguishListingTextAndUnknownPayload() throws {
    let tar = tarFixture()
    let document = try TARListingAdapter().parse(FileBytes(data: tar), context: containerContext)
    #expect(document.text.contains("safe.txt"))
    #expect(!document.text.contains("synthetic text"))
    let compressed = try compressFixture(tar, gzip: true)
    #expect(try GZIPPreviewAdapter().parse(FileBytes(data: compressed), context: containerContext).text.contains("TAR"))
    let text = "token=synthetic-secret\n日本語"
    #expect(try GZIPPreviewAdapter().parse(FileBytes(data: compressFixture(Data(text.utf8), gzip: true)), context: containerContext).text == text)
    #expect(try GZIPPreviewAdapter().parse(FileBytes(data: compressFixture(Data([0, 255]), gzip: true)), context: containerContext).text.contains("binary"))
}

@Test func TARRejectsSparseBadChecksumAndTruncationButListsTraversalWithRisk() throws {
    #expect(throws: PreviewFailure.unsupportedFormat) { try TARListingAdapter().parse(FileBytes(data: tarFixture(type: 83)), context: containerContext) }
    let traversal = try TARListingAdapter().parse(FileBytes(data: tarFixture(path: "../../escape")), context: containerContext)
    #expect(traversal.text.contains("\"path\": \"../../escape\""))
    #expect(traversal.findings.map(\.kind) == [.archiveUnsafePath])
    var corrupt = tarFixture(); corrupt[5] = 99
    #expect(throws: PreviewFailure.malformedDocument) { try TARListingAdapter().parse(FileBytes(data: corrupt), context: containerContext) }
    #expect(throws: PreviewFailure.malformedDocument) { try TARListingAdapter().parse(FileBytes(data: tarFixture().dropLast(512)), context: containerContext) }
}

@Test func GZIPRejectsCRCTruncationAndCumulativeDecompressionBomb() throws {
    var gzip = try compressFixture(Data("safe".utf8), gzip: true)
    gzip[gzip.count - 8] ^= 0xff
    #expect(throws: PreviewFailure.malformedDocument) { try GZIPPreviewAdapter().parse(FileBytes(data: gzip), context: containerContext) }
    let bomb = try compressFixture(Data(repeating: 65, count: 200_000), gzip: true)
    #expect(throws: PreviewFailure.outputTooLarge) {
        try GZIPPreviewAdapter().parse(FileBytes(data: bomb), context: RequestContext(budget: PreviewBudget(maxInputBytes: 512)))
    }
}

@Test func XIPListsRealInnerCPIOWithUnverifiedSignature() throws {
    let document = try XIPListingAdapter().parse(FileBytes(data: xipFixture()), context: containerContext)
    #expect(document.text.contains("nested/safe.txt"))
    #expect(document.text.contains("CPIO"))
    #expect(document.text.contains("\"signatureVerified\": false"))
    #expect(!document.text.contains("synthetic source"))
    let traversal = try XIPListingAdapter().parse(FileBytes(data: xipFixture(path: "../escape")), context: containerContext)
    #expect(traversal.text.contains("\"path\": \"../escape\""))
    #expect(traversal.findings.map(\.kind) == [.archiveUnsafePath])
}

private func sqliteFixture(sql: String) throws -> Data {
    var database: OpaquePointer?
    guard sqlite3_open(":memory:", &database) == SQLITE_OK, let database else { throw PreviewFailure.malformedDocument }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw PreviewFailure.malformedDocument }
    var count: Int64 = 0
    guard let bytes = sqlite3_serialize(database, "main", &count, 0) else { throw PreviewFailure.malformedDocument }
    defer { sqlite3_free(bytes) }
    return Data(bytes: bytes, count: Int(count))
}

@Test func SQLiteListsQuotedTablesSchemaIndexesAndBoundedSecretRows() throws {
    let fixture = try sqliteFixture(sql: "CREATE TABLE \"odd\"\"name\" (normal TEXT, password TEXT, payload BLOB); CREATE INDEX idx ON \"odd\"\"name\"(normal); INSERT INTO \"odd\"\"name\" VALUES('日本語','synthetic-secret',zeroblob(100000));")
    let document = try SQLiteInspectionAdapter().parse(FileBytes(data: fixture), context: containerContext)
    #expect(document.text.contains("idx"))
    #expect(document.text.contains("日本語"))
    #expect(document.text.contains("blobBytes"))
    #expect(!document.sensitiveRanges.isEmpty)
    let bytes = Array(document.text.utf8)
    #expect(document.sensitiveRanges.contains { String(decoding: bytes[$0.utf8Range], as: UTF8.self) == "synthetic-secret" })
}

@Test func SQLiteRejectsWALAndMalformedBytes() throws {
    var fixture = try sqliteFixture(sql: "CREATE TABLE safe(value); INSERT INTO safe VALUES('ok');")
    fixture[18] = 2; fixture[19] = 2
    #expect(throws: PreviewFailure.unavailableContent) { try SQLiteInspectionAdapter().parse(FileBytes(data: fixture), context: containerContext) }
    #expect(throws: PreviewFailure.malformedDocument) { try SQLiteInspectionAdapter().parse(FileBytes(data: Data(repeating: 0, count: 100)), context: containerContext) }
}

@Test func FolderListsImmediateChildrenWithoutFollowingSymlinksOrChangingSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("safe.txt")
    let bytes = Data("synthetic source".utf8)
    try bytes.write(to: file)
    let nested = root.appendingPathComponent("nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
    try Data("hidden".utf8).write(to: nested.appendingPathComponent("deep-secret.txt"))
    try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("outside").path, withDestinationPath: "/")
    let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    let document = try FolderSummaryAdapter().parse(url: root, context: containerContext)
    #expect(document.text.contains("symlink"))
    #expect(!document.text.contains("deep-secret"))
    #expect(!document.text.contains("synthetic source"))
    #expect(try Data(contentsOf: file) == bytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == before)
}

@Test func ContainerAdaptersCooperateWithPreCancelledRequest() async throws {
    let zip = zipFixture()
    let task = Task.detached {
        while !Task.isCancelled { await Task.yield() }
        do { _ = try ZIPListingAdapter().parse(FileBytes(data: zip), context: RequestContext(budget: .standard)); return false }
        catch is CancellationError { return true }
        catch { return false }
    }
    task.cancel()
    #expect(await task.value)
}

private final class SparseContainerSource: PreviewByteSource {
    let byteCount: Int64
    let spans: [(Int64, Data)]
    let reads = Mutex(0)
    init(byteCount: Int64, spans: [(Int64, Data)]) { self.byteCount = byteCount; self.spans = spans }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard offset >= 0, count >= 0, offset <= byteCount, Int64(count) <= byteCount - offset else { throw PreviewFailure.malformedDocument }
        try reads.withLock {
            guard count <= context.budget.maxInputBytes - $0 else { throw PreviewFailure.inputTooLarge }
            $0 += count
        }
        var result = Data(repeating: 0, count: count)
        for (start, data) in spans {
            let lower = max(offset, start)
            let upper = min(offset + Int64(count), start + Int64(data.count))
            if lower < upper {
                result.replaceSubrange(Int(lower - offset)..<Int(upper - offset), with: data[Int(lower - start)..<Int(upper - start)])
            }
        }
        return result
    }
}

@Test func ZIPRandomAccessListsLargeSourcesWithinCumulativeReadBudget() throws {
    let fixture = zipFixture()
    let end = fixture.count - 22
    let originalStart = Int(fixture[end + 16]) | Int(fixture[end + 17]) << 8 | Int(fixture[end + 18]) << 16 | Int(fixture[end + 19]) << 24
    let newStart: Int64 = 50_000_000
    var endRecord = Data(fixture.suffix(22))
    endRecord.replaceSubrange(16..<20, with: little(UInt64(newStart), width: 4))
    let source = SparseContainerSource(byteCount: newStart + Int64(end - originalStart) + 22,
        spans: [(0, Data(fixture.prefix(originalStart))), (newStart, fixture.subdata(in: originalStart..<end)),
                (newStart + Int64(end - originalStart), endRecord)])
    let document = try ZIPListingAdapter().parse(source, context: RequestContext(budget: .standard))
    #expect(document.text.contains("nested/日本語.txt"))
    #expect(source.reads.withLock { $0 } < 70_000)
}

@Test func ZIP64RejectsHeaderLengthsNearMaximumOffsetWithoutArithmeticOverflow() throws {
    let endOfFile = Int64.max
    let zip64Offset = endOfFile - 98
    let directorySize = 47
    let directoryOffset = zip64Offset - Int64(directorySize)
    let localOffset = directoryOffset - 30
    var local = little(0x04034b50, width: 4) + little(45, width: 2) + little(0x800, width: 2)
    local += Data(repeating: 0, count: 18) + little(65_535, width: 2) + little(65_535, width: 2)
    var directory = little(0x02014b50, width: 4) + little(45, width: 2) + little(45, width: 2) + little(0x800, width: 2)
    directory += Data(repeating: 0, count: 18) + little(1, width: 2) + little(12, width: 2)
    directory += Data(repeating: 0, count: 12) + little(0xffffffff, width: 4) + Data("a".utf8)
    // The central directory uses a ZIP64 local-header reference.
    directory += little(1, width: 2) + little(8, width: 2) + little(UInt64(localOffset), width: 8)
    let actualDirectorySize = directory.count
    let actualDirectoryOffset = zip64Offset - Int64(actualDirectorySize)
    let actualLocalOffset = actualDirectoryOffset - 30
    // Keep the synthetic local reference aligned with the directory's actual size.
    directory.replaceSubrange((directory.count - 8)..<directory.count, with: little(UInt64(actualLocalOffset), width: 8))
    var end = little(0x06064b50, width: 4) + little(44, width: 8) + little(45, width: 2) + little(45, width: 2)
    end += Data(repeating: 0, count: 8) + little(1, width: 8) + little(1, width: 8)
    end += little(UInt64(actualDirectorySize), width: 8) + little(UInt64(actualDirectoryOffset), width: 8)
    end += little(0x07064b50, width: 4) + little(0, width: 4) + little(UInt64(zip64Offset), width: 8) + little(1, width: 4)
    end += little(0x06054b50, width: 4) + Data(repeating: 0, count: 4) + little(0xffff, width: 2) + little(0xffff, width: 2)
    end += little(0xffffffff, width: 4) + little(0xffffffff, width: 4) + little(0, width: 2)
    let source = SparseContainerSource(byteCount: endOfFile,
        spans: [(actualLocalOffset, local), (actualDirectoryOffset, directory), (zip64Offset, end)])
    #expect(throws: PreviewFailure.malformedDocument) {
        try ZIPListingAdapter().parse(source, context: RequestContext(budget: .standard))
    }
}

@Test func TARRandomAccessReturnsPartialForEnormousFirstMemberWithoutReadingPayload() throws {
    var header = Array(tarFixture().prefix(512))
    let payloadSize = 100_663_296
    let size = Array((String(format: "%011o", payloadSize) + "\0").utf8)
    for index in 0..<12 { header[124 + index] = size[index] }
    for index in 148..<156 { header[index] = 32 }
    let sum = header.reduce(0) { $0 + Int($1) }
    let checksum = Array((String(format: "%06o", sum) + "\0 ").utf8)
    for index in 0..<8 { header[148 + index] = checksum[index] }
    let source = SparseContainerSource(byteCount: Int64(payloadSize + 1536), spans: [(0, Data(header))])
    let document = try TARListingAdapter().parse(source, context: RequestContext(budget: .standard))
    #expect(document.text.contains("safe.txt"))
    #expect(document.text.contains("\"partial\": true"))
    #expect(source.reads.withLock { $0 } == 512)
}

@Test func XIPReturnsExplicitPartialWhenCompressedChunkCannotFitSourceReadBudget() throws {
    let fixture = try xipFixture()
    let compressedTOC = fixture[8..<16].reduce(0) { ($0 << 8) | Int($1) }
    let budget = PreviewBudget(maxInputBytes: 28 + compressedTOC + 12 + 16 + 6 + 10)
    let document = try XIPListingAdapter().parse(FileBytes(data: fixture), context: RequestContext(budget: budget))
    #expect(document.text.contains("\"partial\": true"))
    #expect(document.text.contains("\"listedEntries\": 0"))
    #expect(document.text.contains("\"signatureVerified\": false"))
}

@Test func XZPreflightRejectsHugeDictionaryBeforeNativeAllocation() throws {
    var fixture = xzFixture(Data(repeating: 65, count: 1000))
    let headerEnd = 12 + (Int(fixture[12]) + 1) * 4 - 4
    let propertyMarker = (14..<(headerEnd - 2)).first { fixture[$0] == 0x21 && fixture[$0 + 1] == 1 }
    let offset = try #require(propertyMarker)
    fixture[offset + 2] = 40 // LZMA2's unbounded (4 GiB) dictionary marker.
    #expect(throws: PreviewFailure.inputTooLarge) {
        try BoundedDecompression.xz(fixture, context: RequestContext(budget: .standard), maximum: 10_000)
    }
}

@Test func XZPreflightRejectsMaximumLengthWithoutArithmeticOverflow() {
    let header: [UInt8] = [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0, 0, 0, 0, 0, 0, 0]
    let block: [UInt8] = [2, 0, 0x21, 1, 0, 0, 0, 0, 0, 0, 0, 0]
    let index: [UInt8] = [0, 1] + Array(repeating: 0xff, count: 8) + [0x7f, 0, 0, 0, 0, 0]
    let footer: [UInt8] = [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0x59, 0x5a]
    #expect(throws: PreviewFailure.malformedDocument) {
        try BoundedDecompression.xz(Data(header + block + index + footer), context: RequestContext(budget: .standard), maximum: 1_048_576)
    }
}

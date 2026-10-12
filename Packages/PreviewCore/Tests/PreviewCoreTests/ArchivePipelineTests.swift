import Compression
import Foundation
import Synchronization
import Testing
import zlib
import PreviewContracts
import PreviewCore
import PreviewFormats

/// End-to-end behavior of the archive family through classification, the enablement gate, bounded
/// reads, the adapter and the shared privacy stage, with real files in a temporary directory.
@Suite("Archive pipeline")
struct ArchivePipelineTests {
    private static let secret = "synthetic-secret-value"

    // MARK: Minimal builders (the adapter-level suites hold the exhaustive ones)

    private static func crc(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(truncatingIfNeeded: zlib.crc32(0, $0.baseAddress, uInt($0.count))) }
    }
    private static func le(_ value: UInt64, _ width: Int) -> [UInt8] { (0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) } }
    private static func vint(_ value: Int) -> [UInt8] {
        var value = value, out: [UInt8] = []
        while true {
            let byte = UInt8(value & 0x7F)
            value >>= 7
            if value == 0 { out.append(byte); return out }
            out.append(byte | 0x80)
        }
    }
    private static func rar5Block(type: Int, fields: [UInt8], data: [UInt8]? = nil) -> [UInt8] {
        var body = vint(type) + vint(data == nil ? 0 : 2)
        if let data { body += vint(data.count) }
        body += fields
        let size = vint(body.count)
        return le(UInt64(crc(size + body)), 4) + size + body + (data ?? [])
    }
    private static func rar5(_ files: [(String, [UInt8])]) -> Data {
        var out: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00] + rar5Block(type: 1, fields: vint(0))
        for (name, payload) in files {
            let nameBytes = Array(name.utf8)
            let fields = vint(0x04) + vint(payload.count) + vint(0x20) + le(UInt64(crc(payload)), 4) + vint(0) + vint(1) + vint(nameBytes.count) + nameBytes
            out += rar5Block(type: 2, fields: fields, data: payload)
        }
        return Data(out + rar5Block(type: 5, fields: vint(0)))
    }
    private static func sevenZipNumber(_ value: Int) -> [UInt8] {
        var first: UInt8 = 0, mask: UInt8 = 0x80, index = 0
        while index < 8 {
            if value < (1 << (7 * (index + 1))) { first |= UInt8(truncatingIfNeeded: value >> (8 * index)); break }
            first |= mask
            mask >>= 1
            index += 1
        }
        return [first] + (0..<index).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }
    private static func sevenZip(_ files: [(String, [UInt8])]) -> Data {
        let packed = files.flatMap { $0.1 }
        var header: [UInt8] = [0x01, 0x04, 0x06] + sevenZipNumber(0) + sevenZipNumber(1) + [0x09] + sevenZipNumber(packed.count) + [0x00]
        header += [0x07, 0x0B, 0x01, 0x00, 0x01, 0x01, 0x00, 0x0C] + sevenZipNumber(packed.count) + [0x00]
        header += [0x08, 0x0D] + sevenZipNumber(files.count) + [0x09] + files.dropLast().flatMap { sevenZipNumber($0.1.count) } + [0x00, 0x00]
        var names: [UInt8] = [0]
        for (name, _) in files { names += name.utf16.flatMap { le(UInt64($0), 2) } + [0, 0] }
        header += [0x05] + sevenZipNumber(files.count) + [0x11] + sevenZipNumber(names.count) + names + [0x00, 0x00]
        let start = le(UInt64(packed.count), 8) + le(UInt64(header.count), 8) + le(UInt64(crc(header)), 4)
        return Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04] + le(UInt64(crc(start)), 4) + start + packed + header)
    }
    private static func xz(_ data: Data) -> Data {
        var output = [UInt8](repeating: 0, count: max(512, data.count * 2 + 128))
        let capacity = output.count
        let count = data.withUnsafeBytes { input in
            output.withUnsafeMutableBufferPointer { target in
                compression_encode_buffer(target.baseAddress!, capacity, input.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZMA)
            }
        }
        return Data(output.prefix(count))
    }
    /// `bzip2` output for "password=synthetic-secret-value\nvisible line\n", made once with the system tool.
    private static let bzip2Text = Data(base64Encoded: "QlpoOTFBWSZTWftuPJcAAA7ZgAAQQAIAAj5l36AgACKAyAGamhRoyBo0yNKvNLDunEnQgmuJQndeLlmVh4j0wEOHcnfF3JFOFCQ+248lwA==") ?? Data()

    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    private func withFile<T>(_ name: String, _ data: Data, _ body: (URL, URL) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return try await body(url, directory)
    }

    private func ready(_ outcome: PreviewOutcome) throws -> TextPresentation {
        guard case .ready(let presentation) = outcome else { throw PreviewFailure.unavailableContent }
        return presentation
    }

    // MARK: Listings

    @Test func rarAndSevenZipListNamesAndConcealSecretLikeEntryNames() async throws {
        let files = [("docs/readme.txt", Array("hello".utf8)), ("password=\(Self.secret).txt", Array("payload-never-shown".utf8))]
        for (name, data, format) in [("sample.rar", Self.rar5(files), FormatID.rar), ("sample.7z", Self.sevenZip(files), FormatID.sevenZip)] {
            try await withFile(name, data) { url, _ in
                let presentation = try ready(await pipeline.preview(url: url))
                #expect(presentation.formatID == format)
                #expect(presentation.syntax == .json)
                #expect(presentation.text.contains("docs/readme.txt"))
                #expect(!presentation.text.contains(Self.secret), "\(name)")
                #expect(!presentation.text.contains("payload-never-shown"))
                #expect(presentation.redactionCount >= 1)
                // The concealed representation is still valid JSON, so every derived view shares one safe source.
                #expect(try JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) is [String: Any])
            }
        }
    }

    @Test func largeArchivesListFromHeadersWithoutReadingTheWholeFile() async throws {
        let big = [UInt8](repeating: 0x41, count: 3 << 20)
        for (name, data) in [("big.rar", Self.rar5([("big.bin", big), ("after.txt", [1])])), ("big.7z", Self.sevenZip([("big.bin", big), ("after.txt", [1])]))] {
            try await withFile(name, data) { url, _ in
                #expect(data.count > PreviewBudget.standard.maxInputBytes)
                let presentation = try ready(await pipeline.preview(url: url))
                #expect(presentation.text.contains("big.bin") && presentation.text.contains("after.txt"), "\(name)")
            }
        }
    }

    @Test func compressedStreamsListTARsAndConcealTextSecrets() async throws {
        try await withFile("secrets.txt.bz2", Self.bzip2Text) { url, _ in
            let presentation = try ready(await pipeline.preview(url: url))
            #expect(presentation.formatID == .bzip2)
            #expect(presentation.text.contains("visible line"))
            #expect(!presentation.text.contains(Self.secret))
            #expect(presentation.redactionCount == 1)
        }
        try await withFile("secrets.txt.xz", Self.xz(Data("password=\(Self.secret)\nvisible line\n".utf8))) { url, _ in
            let presentation = try ready(await pipeline.preview(url: url))
            #expect(presentation.formatID == .xz)
            #expect(presentation.text.contains("visible line"))
            #expect(!presentation.text.contains(Self.secret))
            #expect(presentation.redactionCount == 1)
        }
    }

    @Test func malformedTruncatedAndEncryptedArchivesFailWithTypedReasons() async throws {
        let rar = Self.rar5([("a.txt", Array("x".utf8))])
        try await withFile("cut.rar", rar.prefix(rar.count - 12)) { url, _ in
            #expect(await pipeline.preview(url: url) == .unavailable(.malformedDocument))
        }
        var encrypted: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
        encrypted += Self.rar5Block(type: 4, fields: Self.vint(0) + Self.vint(0) + [15] + [UInt8](repeating: 0, count: 16))
        try await withFile("locked.rar", Data(encrypted)) { url, _ in
            #expect(await pipeline.preview(url: url) == .unavailable(.encryptedContent))
        }
        try await withFile("junk.7z", Data("not a 7z archive".utf8)) { url, _ in
            #expect(await pipeline.preview(url: url) == .unavailable(.malformedDocument))
        }
        try await withFile("junk.bz2", Data("BZh9 definitely not bzip2".utf8)) { url, _ in
            #expect(await pipeline.preview(url: url) == .unavailable(.malformedDocument))
        }
    }

    // MARK: Policy, mutation and cancellation

    @Test func disabledTypesAreRefusedBeforeAnyAdapterIsConstructed() async throws {
        let constructed = Mutex<[String]>([])
        let registrations = [
            AdapterRegistration(formatID: .rar, randomAccessAdapter: { constructed.withLock { $0.append("rar") }; return RARListingAdapter() }),
            AdapterRegistration(formatID: .sevenZip, randomAccessAdapter: { constructed.withLock { $0.append("7z") }; return SevenZipListingAdapter() }),
            AdapterRegistration(formatID: .bzip2, binaryAdapter: { constructed.withLock { $0.append("bzip2") }; return BZip2PreviewAdapter() }),
            AdapterRegistration(formatID: .xz, binaryAdapter: { constructed.withLock { $0.append("xz") }; return XZPreviewAdapter() })
        ]
        let pipeline = PreviewPipeline(registrations: registrations)
        var preferences = PreviewPreferencesSnapshot.defaults
        for id in [FormatID.rar, .sevenZip, .bzip2, .xz] { preferences.setEnabled(false, for: id) }
        for (name, id) in [("a.rar", FormatID.rar), ("a.7z", .sevenZip), ("a.bz2", .bzip2), ("a.xz", .xz)] {
            try await withFile(name, Data("never read".utf8)) { url, _ in
                #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(id))
                #expect(await pipeline.inspect(url: url, preferences: preferences) == .disabledByUser(id))
            }
        }
        #expect(constructed.withLock { $0 }.isEmpty)
        // Each choice is independent: enabling one leaves the others disabled.
        preferences.setEnabled(true, for: .xz)
        try await withFile("ok.xz", Self.xz(Data("fine\n".utf8))) { url, _ in
            let presentation = try ready(await pipeline.preview(url: url, preferences: preferences))
            #expect(presentation.text == "fine\n")
        }
        #expect(constructed.withLock { $0 } == ["xz"])
    }

    @Test func previewingNeverModifiesTheSourceOrItsDirectory() async throws {
        for (name, data) in [("a.rar", Self.rar5([("a.txt", [1, 2, 3])])), ("a.7z", Self.sevenZip([("a.txt", [1, 2, 3])])),
                             ("a.bz2", Self.bzip2Text), ("a.xz", Self.xz(Data("x\n".utf8)))] {
            try await withFile(name, data) { url, directory in
                let before = try FileManager.default.attributesOfItem(atPath: url.path)
                let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
                _ = await pipeline.preview(url: url)
                #expect(try Data(contentsOf: url) == data)
                #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == names)
                let after = try FileManager.default.attributesOfItem(atPath: url.path)
                #expect(after[.modificationDate] as? Date == before[.modificationDate] as? Date)
                #expect(after[.size] as? Int == before[.size] as? Int)
            }
        }
    }

    @Test func cancelledRequestsReturnCancelledWithoutPartialContent() async throws {
        try await withFile("c.rar", Self.rar5((0..<200).map { ("file\($0).txt", [1]) })) { url, _ in
            let task = Task { await pipeline.preview(url: url) }
            task.cancel()
            let outcome = await task.value
            switch outcome {
            case .cancelled: break
            case .ready: break // the request may legitimately finish before cancellation is observed
            default: Issue.record("Unexpected outcome \(outcome)")
            }
        }
    }
}

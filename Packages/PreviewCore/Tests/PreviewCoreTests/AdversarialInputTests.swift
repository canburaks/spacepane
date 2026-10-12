import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

@Suite("Adversarial request boundaries")
struct AdversarialInputTests {
    @Test(arguments: [
        "<root><![CDATA[password=synthetic-cdata-secret]]><safe>visible</safe></root>",
        "<root><![CDATA[😀 \"api_key\": synthetic-cdata-secret\ncontinued]]><safe>visible</safe></root>",
        "<?inert password=synthetic-instruction-secret?><root><safe>visible</safe></root>",
        "<root><?inert 😀 \"api_key\": synthetic-instruction-secret\ncontinued?><safe>visible</safe></root>"
    ])
    func XMLNonFieldPayloadsConcealAssignmentsAndRetainValidMarkup(source: String) throws {
        let context = RequestContext(budget: .standard)
        let document = try XMLSourceAdapter().parse(.init(text: source, encoding: .utf8,
                                                        byteCount: source.utf8.count), context: context)
        let safe = try DefaultPrivacyFilter().filter(document, context: context)
        #expect(!safe.text.contains("synthetic-"))
        #expect(safe.redactionCount == 1)
        #expect(safe.text.contains("<safe>visible</safe>"))
        let parser = XMLParser(data: Data(safe.text.utf8))
        parser.shouldResolveExternalEntities = false
        #expect(parser.parse())
    }

    @Test func everyRegisteredAdapterChecksCancellationBeforeInputAccess() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            for registration in StandardFormatAdapters.registrations {
                #expect(throws: CancellationError.self, "Adapter: \(registration.formatID.rawValue)") {
                    try Self.invoke(registration, context: RequestContext(budget: .standard))
                }
            }
        }
        await task.value
    }

    @Test func everyRegisteredAdapterChecksExpiredDeadlineBeforeInputAccess() {
        for registration in StandardFormatAdapters.registrations {
            #expect(throws: PreviewFailure.deadlineExceeded, "Adapter: \(registration.formatID.rawValue)") {
                try Self.invoke(registration, context: RequestContext(budget: .init(maxMilliseconds: 0)))
            }
        }
    }

    @Test func sameSizeSourceMutationInvalidatesAnOpenedArchiveSnapshot() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3, 4]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let context = RequestContext(budget: .standard)
        let source = try BoundedFileReader().openRandomAccess(url: url, context: context)
        #expect(try source.read(offset: 0, count: 1, context: context) == Data([1]))
        // Keep inode and size: the snapshot must detect timestamps rather than relying
        // only on length. The test writer, never the reader, changes synthetic bytes.
        let writer = try FileHandle(forWritingTo: url)
        try writer.write(contentsOf: Data([9, 8, 7, 6]))
        try writer.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: url.path)
        #expect(throws: PreviewFailure.unavailableContent) {
            try source.read(offset: 0, count: 1, context: context)
        }
        #expect(try Data(contentsOf: url) == Data([9, 8, 7, 6]))
    }

    @Test func cancellationAfterAnArchiveReadDoesNotProducePartialReadyContent() async {
        let source = CancellationSource()
        let task = Task.detached {
            do {
                _ = try ZIPListingAdapter().parse(source, context: .init(budget: .standard))
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }
        #expect(await task.value)
        #expect(source.reads.withLock { $0 } == 1)
    }

    @Test func concatenatedGZIPMembersSpendOneDecodedBudgetWithoutChangingSource() async throws {
        // Deterministic gzip of 20,000 synthetic ASCII A bytes (mtime 0). Each
        // member fits a 512 * 64 decoded budget; concatenation must not reset it.
        let member = try #require(Data(base64Encoded: "H4sIAAAAAAAC/+3BMQEAAADCoGzrX8oaHkABAAAAAAAAAAAAAAAAAAAAAAAA8GAbEJrYIE4AAA=="))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cumulative.gz")
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        let budget = PreviewBudget(maxInputBytes: 512)
        try member.write(to: url)
        guard case .ready(let presentation) = await pipeline.preview(url: url, budget: budget) else {
            Issue.record("One member must fit the decoded budget"); return
        }
        #expect(presentation.text == String(repeating: "A", count: 20_000))
        let bomb = member + member
        try bomb.write(to: url)
        #expect(await pipeline.preview(url: url, budget: budget) == .unavailable(.outputTooLarge))
        #expect(try Data(contentsOf: url) == bomb)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["cumulative.gz"])
    }

    @Test func cyclicBinaryPlistReferencesFailClosedBeforeNativeGraphExpansion() {
        // bplist object 0 is a one-item array referring to itself. One-byte
        // offset/reference widths, one object, root 0, offset table at byte 10.
        var data = Data("bplist00".utf8) + Data([0xa1, 0x00, 0x08])
        data += Data(repeating: 0, count: 6) + Data([1, 1])
        for value: UInt64 in [1, 0, 10] {
            data += Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        #expect(throws: PreviewFailure.malformedDocument) {
            try PropertyListSourceAdapter().parse(.init(data: data), context: .init(budget: .standard))
        }
    }

    private static func invoke(_ registration: AdapterRegistration, context: RequestContext) throws {
        switch registration.inputPath {
        case .text(let make):
            _ = try make().parse(.init(text: "", encoding: .utf8, byteCount: 0), context: context)
        case .geometry(let make):
            _ = try make().parse(.init(data: Data()), context: context)
        case .binary(let make):
            _ = try make().parse(.init(data: Data()), context: context)
        case .url(let make):
            _ = try make().parse(url: URL(fileURLWithPath: "/never-opened-adversarial-folder"), context: context)
        case .randomAccess(let make):
            _ = try make().parse(UnreadableSource(), context: context)
        }
    }
}

private struct UnreadableSource: PreviewByteSource {
    let byteCount: Int64 = 0
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        Issue.record("Cancellation/deadline must precede source access")
        throw PreviewFailure.unreadableFile
    }
}

private final class CancellationSource: PreviewByteSource {
    let byteCount: Int64 = 22
    let reads = Mutex(0)
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        reads.withLock { $0 += 1 }
        withUnsafeCurrentTask { $0?.cancel() }
        return Data(repeating: 0, count: count)
    }
}

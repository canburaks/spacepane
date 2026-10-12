import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewFormats
import PreviewCADFormats
@testable import PreviewCore

@Suite("Expanded input boundaries")
struct ExpandedInputPathTests {
    private struct UnusedReader: PreviewFileReading {
        func read(url: URL, context: RequestContext) throws -> FileBytes { Issue.record("Disabled input must not be read"); throw PreviewFailure.unreadableFile }
        func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource { Issue.record("Disabled input must not open a descriptor"); throw PreviewFailure.unreadableFile }
    }
    private struct BinaryEcho: BinaryFormatAdapter {
        func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument { ParsedTextDocument(text: "api_key=synthetic-secret") }
    }
    private struct LocationEcho: URLFormatAdapter {
        func parse(url: URL, context: RequestContext) throws -> ParsedTextDocument { Issue.record("Disabled location must not be enumerated"); return ParsedTextDocument(text: "") }
    }
    private struct RangeEcho: RandomAccessFormatAdapter {
        func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument { Issue.record("Disabled ranges must not be read"); return ParsedTextDocument(text: "") }
    }
    @Test func disabledBinaryLocationAndRandomAccessNeverReachFactories() async {
        let registrations = [
            AdapterRegistration(formatID: .json, binaryAdapter: { Issue.record("Disabled binary factory"); return BinaryEcho() }),
            AdapterRegistration(formatID: .json, urlAdapter: { Issue.record("Disabled location factory"); return LocationEcho() }),
            AdapterRegistration(formatID: .json, randomAccessAdapter: { Issue.record("Disabled random-access factory"); return RangeEcho() })
        ]
        for registration in registrations {
            let pipeline = PreviewPipeline(registrations: [registration], reader: UnusedReader())
            let outcome = await pipeline.preview(url: URL(fileURLWithPath: "/not-read.json"), preferences: .init(defaultEnabled: false))
            #expect(outcome == .disabledByUser(.json))
        }
    }
    @Test func everyCatalogRegistrationHonorsDisableAllIncludingFolders() async throws {
        let catalog = FormatCatalog.standard
        #expect(Set((StandardFormatAdapters.registrations + CADFormatAdapters.registrations).map(\.formatID)) == Set(catalog.descriptors.map(\.id)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: UnusedReader())
        for descriptor in catalog.descriptors {
            let url: URL
            if descriptor.id == .folder { url = directory }
            else if let filename = descriptor.filenameAliases.first { url = directory.appendingPathComponent(filename) }
            else if descriptor.id == .extensionlessText {
                // Identified by the type macOS reports for a real file without a suffix; its bytes stay unread.
                url = directory.appendingPathComponent("fixture")
                try Data().write(to: url)
            }
            else { url = directory.appendingPathComponent("fixture." + (descriptor.suffixAliases.first ?? "unknown")) }
            let outcome = await pipeline.preview(url: url, preferences: .init(defaultEnabled: false))
            #expect(outcome == .disabledByUser(descriptor.id))
        }
    }

    @Test func filenameSpecificPoliciesPrecedeSharedTypesAndSuffixes() {
        let catalog = FormatCatalog.standard
        #expect(catalog.classify(url: URL(fileURLWithPath: "/package.json"), contentType: .json) == .packageJSON)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/other.json"), contentType: .json) == .json)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/.env"), contentType: .plainText) == .environment)
        #expect(catalog.classify(url: URL(fileURLWithPath: "/.env.local"), contentType: .plainText) == .environment)
    }
    @Test func archiveTailReadUsesCumulativeBudgetNotWholeFileSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("archive.bin")
        try Data(repeating: 0, count: 4096).write(to: url)
        let context = RequestContext(budget: .init(maxInputBytes: 8))
        let reader = BoundedFileReader()
        let source = try reader.openRandomAccess(url: url, context: context)
        #expect(source.byteCount == 4096)
        #expect(try source.read(offset: 4092, count: 4, context: context) == Data(repeating: 0, count: 4))
        #expect(try source.read(offset: 0, count: 4, context: context).count == 4)
        #expect(throws: PreviewFailure.inputTooLarge) { try source.read(offset: 0, count: 1, context: context) }
        #expect(try Data(contentsOf: url).count == 4096)
    }
    @Test func randomAccessRejectsMutationAndInvalidRanges() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1,2,3,4]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let context = RequestContext(budget: .standard)
        let source = try BoundedFileReader().openRandomAccess(url: url, context: context)
        #expect(throws: PreviewFailure.malformedDocument) { try source.read(offset: -1, count: 1, context: context) }
        #expect(throws: PreviewFailure.malformedDocument) { try source.read(offset: 3, count: 2, context: context) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([5])); try handle.close()
        #expect(throws: PreviewFailure.unavailableContent) { try source.read(offset: 0, count: 1, context: context) }
    }
    @Test func databaseSidecarsFailClosedWithoutChangingSources() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sample.sqlite")
        let original = Data(repeating: 7, count: 100)
        try original.write(to: url)
        var context = RequestContext(budget: .standard)
        context.sourceReadPolicy = .sqliteSnapshot
        #expect(try BoundedFileReader().read(url: url, context: context).data == original)
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = directory.appendingPathComponent("sample.sqlite" + suffix)
            try Data([1,2,3]).write(to: sidecar)
            #expect(throws: PreviewFailure.unavailableContent) { try BoundedFileReader().read(url: url, context: context) }
            #expect(try Data(contentsOf: url) == original)
            #expect(try Data(contentsOf: sidecar) == Data([1,2,3]))
            try FileManager.default.removeItem(at: sidecar)
        }
    }
}

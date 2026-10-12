import Foundation
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewCore

/// The data formats through the real pipeline: classification, the enablement gate, bounded reads,
/// the adapter, shared concealment and the final presentation.
@Suite("Data formats through the pipeline", .serialized)
struct DataPipelineTests {
    struct Sample: Sendable, CustomTestStringConvertible {
        let formatID: FormatID
        let filename: String
        let data: Data
        /// Redactions the shared filter must report for the synthetic secret in this fixture.
        let redactions: Int
        var testDescription: String { filename }
    }

    static let samples: [Sample] = [
        Sample(formatID: .parquet, filename: "table.parquet", data: DataFixtures.parquet, redactions: 1),
        Sample(formatID: .parquet, filename: "rows.parquet", data: DataFixtures.parquetRows, redactions: 4),
        Sample(formatID: .avro, filename: "records.avro", data: DataFixtures.avro, redactions: 3),
        Sample(formatID: .avro, filename: "records-deflate.avro", data: DataFixtures.avroDeflate, redactions: 3),
        Sample(formatID: .arrow, filename: "batches.arrow", data: DataFixtures.arrowFile, redactions: 1),
        Sample(formatID: .arrow, filename: "batches.feather", data: DataFixtures.arrowFile, redactions: 1),
        Sample(formatID: .arrow, filename: "batches.arrows", data: DataFixtures.arrowStream, redactions: 1),
        Sample(formatID: .numpy, filename: "matrix.npy", data: DataFixtures.numpy, redactions: 0),
        Sample(formatID: .numpyArchive, filename: "arrays.npz", data: DataFixtures.numpyArchive, redactions: 0),
        Sample(formatID: .har, filename: "capture.har", data: DataFixtures.har, redactions: 2),
        Sample(formatID: .geoJSON, filename: "places.geojson", data: DataFixtures.geoJSON, redactions: 0),
        Sample(formatID: .gpx, filename: "morning.gpx", data: DataFixtures.gpx, redactions: 0),
        Sample(formatID: .kml, filename: "places.kml", data: DataFixtures.kml, redactions: 0),
        Sample(formatID: .kml, filename: "places.kmz", data: DataFixtures.kmz, redactions: 0)
    ]

    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test(arguments: DataPipelineTests.samples) func everyFormatPreviewsAsAConcealedJSONSummary(_ sample: Sample) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(sample.filename)
        try sample.data.write(to: url)
        guard case .ready(let presentation) = await pipeline.preview(url: url) else {
            Issue.record("Expected a ready presentation for \(sample.filename)"); return
        }
        #expect(presentation.formatID == sample.formatID)
        #expect(presentation.syntax == .json)
        #expect(presentation.redactionCount == sample.redactions)
        // The synthetic secret appears in no representation, and the concealed text is still valid JSON.
        #expect(!presentation.text.contains(DataFixtures.secret))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(presentation.text.utf8)) as? [String: Any])
        #expect(object["dataFormat"] is String)
        if sample.redactions > 0 { #expect(presentation.text.contains("••••")) }
        // The outline the native views build is limited to 256 Ki UTF-16 units.
        #expect(presentation.text.utf16.count < 262_144)
    }

    @Test(arguments: DataPipelineTests.samples) func disabledTypesNeverOpenTheFile(_ sample: Sample) async throws {
        struct UnusedReader: PreviewFileReading {
            func read(url: URL, context: RequestContext) throws -> FileBytes { Issue.record("Disabled input must not be read"); throw PreviewFailure.unreadableFile }
            func openRandomAccess(url: URL, context: RequestContext) throws -> any PreviewByteSource { Issue.record("Disabled input must not be opened"); throw PreviewFailure.unreadableFile }
        }
        let guarded = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: UnusedReader())
        let url = URL(fileURLWithPath: "/never-read/" + sample.filename)
        #expect(await guarded.preview(url: url, preferences: .init(formatOverrides: [sample.formatID: false]))
                == .disabledByUser(sample.formatID))
        #expect(await guarded.preview(url: url, preferences: .init(defaultEnabled: false)) == .disabledByUser(sample.formatID))
        #expect(await guarded.inspect(url: url, preferences: .init(formatOverrides: [sample.formatID: false]))
                == .disabledByUser(sample.formatID))
    }

    @Test(arguments: DataPipelineTests.samples) func theSourceFileAndItsFolderAreNeverChanged(_ sample: Sample) async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(sample.filename)
        try sample.data.write(to: url)
        let before = try attributes(of: url)
        let listing = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        for _ in 0..<2 { _ = await pipeline.preview(url: url) }
        #expect(try attributes(of: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == listing)
    }

    private struct FileState: Equatable {
        let bytes: Data
        let size: Int
        let modified: Date?
    }

    private func attributes(of url: URL) throws -> FileState {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileState(bytes: try Data(contentsOf: url), size: values[.size] as? Int ?? -1,
                         modified: values[.modificationDate] as? Date)
    }

    @Test func inputBudgetsAreEnforcedOnBothInputPaths() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let capture = folder.appendingPathComponent("capture.har")
        try DataFixtures.har.write(to: capture)
        #expect(await pipeline.preview(url: capture, budget: PreviewBudget(maxInputBytes: 200)) == .unavailable(.inputTooLarge))
        let table = folder.appendingPathComponent("table.parquet")
        try DataFixtures.parquet.write(to: table)
        #expect(await pipeline.preview(url: table, budget: PreviewBudget(maxInputBytes: 64)) == .unavailable(.inputTooLarge))
        let avro = folder.appendingPathComponent("records.avro")
        try DataFixtures.avro.write(to: avro)
        #expect(await pipeline.preview(url: avro, budget: PreviewBudget(maxInputBytes: 32)) == .unavailable(.inputTooLarge))
        // The minimum budgets that suffice keep working.
        if case .ready = await pipeline.preview(url: table, budget: PreviewBudget(maxInputBytes: 1_024)) {} else {
            Issue.record("A small footer fits a 1 KiB budget")
        }
    }

    @Test func gigabyteSparseFilesPreviewWithoutBeingRead() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A Parquet file whose footer sits 2 GiB into the file.
        let table = folder.appendingPathComponent("huge.parquet")
        let footer = DataFixtures.parquet.dropFirst(12)       // the generator's footer, length and trailing magic
        FileManager.default.createFile(atPath: table.path, contents: nil)
        let handle = try FileHandle(forWritingTo: table)
        try handle.write(contentsOf: Data("PAR1".utf8))
        try handle.seek(toOffset: 2 * 1_073_741_824)
        try handle.write(contentsOf: footer)
        try handle.close()
        let size = try #require(try FileManager.default.attributesOfItem(atPath: table.path)[.size] as? Int)
        #expect(size > 2 * 1_073_741_824)
        guard case .ready(let parquet) = await pipeline.preview(url: table) else { Issue.record("Expected a Parquet preview"); return }
        #expect(parquet.text.contains("\"rowCount\": 3"))
        #expect(!parquet.text.contains(DataFixtures.secret))

        // A NumPy array of 3.2 GB of float64 zeros, never allocated on disk.
        let array = folder.appendingPathComponent("zeros.npy")
        let dictionary = "{'descr': '<f8', 'fortran_order': False, 'shape': (400000000,), }"
        var text = Array(dictionary.utf8)
        text += [UInt8](repeating: 0x20, count: (64 - (10 + text.count + 1) % 64) % 64) + [0x0A]
        var bytes: [UInt8] = [0x93, 0x4E, 0x55, 0x4D, 0x50, 0x59, 1, 0, UInt8(text.count & 0xFF), UInt8(text.count >> 8)]
        bytes += text
        FileManager.default.createFile(atPath: array.path, contents: nil)
        let arrayHandle = try FileHandle(forWritingTo: array)
        try arrayHandle.write(contentsOf: Data(bytes))
        try arrayHandle.truncate(atOffset: UInt64(bytes.count + 3_200_000_000))
        try arrayHandle.close()
        guard case .ready(let numpy) = await pipeline.preview(url: array) else { Issue.record("Expected a NumPy preview"); return }
        #expect(numpy.text.contains("\"elementCount\": 400000000"))
        #expect(numpy.text.contains("\"0.0\""))
    }

    @Test func aCancelledRequestReportsCancellationNotPartialContent() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("capture.har")
        try DataFixtures.har.write(to: url)
        let pipeline = self.pipeline
        let task = Task.detached { () -> PreviewOutcome in
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.preview(url: url)
        }
        #expect(await task.value == .cancelled)
    }

    @Test func suffixesClassifyWithoutReadingContent() {
        let catalog = FormatCatalog.standard
        let expected: [(String, FormatID)] = [
            ("a.parquet", .parquet), ("a.avro", .avro), ("a.arrow", .arrow), ("a.feather", .arrow), ("a.arrows", .arrow),
            ("a.npy", .numpy), ("a.npz", .numpyArchive), ("a.har", .har), ("a.geojson", .geoJSON), ("a.gpx", .gpx),
            ("a.kml", .kml), ("a.kmz", .kml), ("A.PARQUET", .parquet)
        ]
        for (name, format) in expected {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/" + name)) == format, "\(name)")
        }
    }
}

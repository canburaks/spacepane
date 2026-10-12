import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats

private enum NotebookImageFixture {
    static func png() -> Data {
        let width = 640
        var state: UInt32 = 0x1234_5678
        var pixels = [UInt8](repeating: 0, count: width * width * 4)
        for index in pixels.indices {
            state = state &* 1_664_525 &+ 1_013_904_223
            pixels[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 24)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: width, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func source(_ image: Data) -> String {
        #"{"nbformat":4,"cells":[{"cell_type":"code","execution_count":1,"source":"password = before-canary","outputs":[{"output_type":"display_data","data":{"image/png":""#
            + image.base64EncodedString() + #""}}]},{"cell_type":"code","source":"token = after-canary","outputs":[]}]}"#
    }
}

private final class ImageNotebookReads: Sendable {
    private let reads = Mutex(0)
    func record() { reads.withLock { $0 += 1 } }
    var count: Int { reads.withLock { $0 } }
}

private struct ImageNotebookReader: PreviewFileReading {
    let data: Data
    let reads: ImageNotebookReads
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        reads.record()
        return FileBytes(data: data)
    }
}

@Suite("Notebook image pipeline")
struct NotebookImagePipelineTests {
    @Test func realisticImageUsesNotebookBudgetConcealsShiftedSecretsAndNeverWritesSource() async throws {
        let png = NotebookImageFixture.png()
        let original = Data(NotebookImageFixture.source(png).utf8)
        try #require(original.count > PreviewBudget.standard.maxInputBytes)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("figure.ipynb")
        try original.write(to: url)
        let before = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        let preview = await pipeline.previewResult(url: url)
        let result: TextPresentation
        if case .ready(let value) = preview.outcome { result = value }
        else { Issue.record("Expected realistic notebook image, got \(preview.outcome)"); return }
        #expect(result.images.map(\.data) == [png])
        #expect(result.origin == .converted)
        #expect(result.byteCount == original.count)
        #expect(result.redactionCount == 2)
        #expect(!result.text.contains("before-canary"))
        #expect(!result.text.contains("after-canary"))
        #expect(result.text.contains(#""image/png":null"#))
        #expect(preview.effectiveBudget?.maxInputBytes == 16_777_216)
        #expect(preview.effectiveBudget?.maxMilliseconds == 5_000)
        #expect(try Data(contentsOf: url) == original)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == before.contentModificationDate)
    }

    @Test(arguments: [TextEncoding.utf8, .utf16LittleEndian, .utf16BigEndian])
    func strictBOMDecodingReportsOriginalEncoding(encoding: TextEncoding) async throws {
        let text = NotebookImageFixture.source(NotebookImageFixture.png())
        let data: Data
        switch encoding {
        case .utf8: data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        case .utf16LittleEndian: data = Data([0xFF, 0xFE]) + (text.data(using: .utf16LittleEndian) ?? Data())
        case .utf16BigEndian: data = Data([0xFE, 0xFF]) + (text.data(using: .utf16BigEndian) ?? Data())
        case .codePage437: return
        }
        let reads = ImageNotebookReads()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: ImageNotebookReader(data: data, reads: reads))
        guard case .ready(let result) = await pipeline.preview(url: URL(fileURLWithPath: "/unused/figure.ipynb")) else {
            Issue.record("Expected a notebook in \(encoding)"); return
        }
        #expect(result.encoding == encoding)
        #expect(result.byteCount == data.count)
        #expect(result.images.count == 1)
    }

    @Test func disabledNotebookNeverReadsLargeImage() async {
        let reads = ImageNotebookReads()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: ImageNotebookReader(data: Data(repeating: 65, count: 2_000_000), reads: reads))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .jupyterNotebook)
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/figure.ipynb"), preferences: preferences) == .disabledByUser(.jupyterNotebook))
        #expect(reads.count == 0)
    }

    @Test func safetyLensLinesFollowOmittedArrayAndConcealedDisplayedSource() async throws {
        let text = """
        {"nbformat":4,"cells":[{"cell_type":"code","execution_count":1,"source":"password = before-canary","outputs":[{"output_type":"display_data","data":{"image/png":[
        "invalid",
        "image"
        ]}}]},
        {"cell_type":"code","source":"é \u{202E} tail","outputs":[]}]}
        """
        let data = Data(text.utf8)
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: ImageNotebookReader(data: data, reads: ImageNotebookReads()))
        guard case .ready(let result) = await pipeline.preview(url: URL(fileURLWithPath: "/unused/figure.ipynb")) else {
            Issue.record("Expected bounded notebook source"); return
        }
        #expect(result.origin == .converted)
        #expect(!result.text.contains("before-canary"))
        #expect(result.text.contains("é \u{202E} tail"))
        let hidden = try #require(result.findings.first { $0.kind == .hiddenBidirectionalControls })
        #expect(hidden.count == 1)
        #expect(hidden.lines == [2])
        #expect(result.findings.contains(PreviewFinding(kind: .notebookUnexecutedCells, count: 1, detail: .cells([2]))))
    }

    @Test(arguments: [Data([0xFF]), Data([0xFF, 0xFE, 0x00]), Data([0xFF, 0xFE, 0x00, 0xD8]), Data([0xFE, 0xFF, 0xDC, 0x00])])
    func invalidTextEncodingFailsBeforeJSON(data: Data) async {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: ImageNotebookReader(data: data, reads: ImageNotebookReads()))
        #expect(await pipeline.preview(url: URL(fileURLWithPath: "/unused/figure.ipynb")) == .unavailable(.unsupportedEncoding))
    }
}

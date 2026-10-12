import CoreGraphics
import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewRenderers

/// End-to-end checks of the diagram family: file → shared pipeline (classification, enablement,
/// bounded read, adapter, privacy filter) → derived Diagram mode.
@Suite("Diagram pipeline")
struct DiagramPipelineTests {
    private let secret = "synthetic-secret-value"
    private let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)

    private struct Directory {
        let url: URL
        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("diagram-tests-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        func write(_ name: String, _ text: String) throws -> URL {
            let file = url.appendingPathComponent(name)
            try Data(text.utf8).write(to: file)
            return file
        }
        func remove() { try? FileManager.default.removeItem(at: url) }
    }

    private func presentation(_ outcome: PreviewOutcome) throws -> TextPresentation {
        guard case .ready(let presentation) = outcome else {
            Issue.record("Expected a ready presentation, got \(outcome)")
            throw PreviewFailure.unavailableContent
        }
        return presentation
    }

    // MARK: Catalog

    @Test func theCatalogDescribesBothFormatsWithImportedTypes() throws {
        let catalog = FormatCatalog.standard
        let mermaid = try #require(catalog.descriptor(for: .mermaid))
        let drawio = try #require(catalog.descriptor(for: .drawio))
        #expect(mermaid.suffixAliases == ["mmd", "mermaid"] && drawio.suffixAliases == ["drawio", "dio"])
        #expect(mermaid.group == .text && drawio.group == .text)
        #expect(mermaid.defaultEnabled && drawio.defaultEnabled)
        #expect(mermaid.thumbnail == .content && drawio.thumbnail == .content)
        for descriptor in [mermaid, drawio] {
            #expect(descriptor.contentTypes.count == 1)
            #expect(descriptor.canonicalContentType.identifier.hasPrefix("org.webmeister.spacepane.type."))
            #expect(![UTType.data, .item, .content].contains(descriptor.canonicalContentType))
            #expect(descriptor.nameKey == "format.\(descriptor.id.rawValue).name")
        }
        for (name, expected) in [("a.mmd", FormatID.mermaid), ("a.MERMAID", .mermaid), ("a.drawio", .drawio), ("a.dio", .drawio), ("a.xml", .xml), ("a.md", .markdown)] {
            #expect(catalog.classify(url: URL(fileURLWithPath: "/tmp/" + name)) == expected, "\(name)")
        }
        #expect(StandardFormatAdapters.registrations.contains { $0.formatID == .mermaid })
        #expect(StandardFormatAdapters.registrations.contains { $0.formatID == .drawio })
    }

    // MARK: Mermaid files

    @Test func aMermaidFileBecomesAConcealedPresentationAndADiagram() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let file = try directory.write("flow.mmd", """
        flowchart TD
          A[Token: \(secret)] --> B[Review]
          B -->|ok| C[Ship]
          %% password=\(secret)
        """)
        let shown = try presentation(await pipeline.preview(url: file))
        #expect(shown.formatID == .mermaid && shown.syntax == .mermaid)
        #expect(!shown.text.contains(secret))
        #expect(shown.text.contains("A[Token: ••••] --> B[Review]"))
        #expect(shown.redactionCount == 2)
        let modes = SafePreviewModes(shown, locale: Locale(identifier: "en_US"))
        let diagram = try #require(modes.diagram)
        // The concealed label did not cost the edge or the nodes after it.
        #expect(diagram.accessibilityNodes.map(\.label) == ["Token: ••••", "Review", "Ship"])
        #expect(diagram.connectionCount == 2)
        #expect(modes.available == [.source, .diagram])
        for node in diagram.accessibilityNodes { #expect(!node.label.contains(secret)) }
    }

    @Test func aMermaidFileWithTheMermaidSuffixAndUnsupportedTypeKeepsSource() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let file = try directory.write("plan.mermaid", "gantt\n  title Plan\n  section A\n  Task :a1, 2024-01-01, 3d\n")
        let shown = try presentation(await pipeline.preview(url: file))
        let modes = SafePreviewModes(shown, locale: .current)
        #expect(modes.diagram == nil && modes.hasStructureFallback && modes.available == [.source])
        #expect(shown.text.contains("Task :a1"))
    }

    // MARK: draw.io files

    @Test func aCompressedDrawioFileIsConcealedCountedAndDrawn() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let cells = DrawioFixtures.cells + "<mxCell id=\"5\" value=\"password: \(secret)\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"40\" y=\"200\" width=\"160\" height=\"40\" as=\"geometry\"/></mxCell>"
        let second = DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"9\" value=\"Hidden second page\" vertex=\"1\" parent=\"1\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell>")
        let file = try directory.write("flow.drawio", DrawioFixtures.file(compressedPages: [DrawioFixtures.model(cells), second]))
        let shown = try presentation(await pipeline.preview(url: file))
        #expect(shown.formatID == .drawio && shown.syntax == .drawio)
        #expect(shown.sourceRecordCount == 2)
        #expect(!shown.text.contains(secret) && !shown.text.contains("Hidden second page"))
        #expect(shown.text.contains("value=\"password: ••••\""))
        #expect(shown.redactionCount == 1)
        let modes = SafePreviewModes(shown, locale: Locale(identifier: "en_US"))
        let diagram = try #require(modes.diagram)
        #expect(diagram.kind == .drawio)
        #expect(diagram.accessibilityNodes.map(\.label) == ["Start", "Finish", "password: ••••"])
        #expect(diagram.connections == [DiagramConnection(source: "Start", target: "Finish", label: "go")])
        let notices = PresentationNotices.lines(for: shown, locale: Locale(identifier: "en_US"))
        #expect(notices == [PreviewStrings.format(.diagramDrawioPage, arguments: [Int64(2)], locale: Locale(identifier: "en_US"))])
    }

    @Test func aPlainDioFileWorksAndMalformedFilesFailWithTypedErrors() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let plain = try directory.write("plain.dio", DrawioFixtures.model())
        #expect(try presentation(await pipeline.preview(url: plain)).sourceRecordCount == 1)
        let corrupt = try directory.write("corrupt.drawio", "<mxfile><diagram>%%%not-base64%%%</diagram></mxfile>")
        #expect(await pipeline.preview(url: corrupt) == .unavailable(.malformedDocument))
        let entity = try directory.write("entity.drawio", "<!DOCTYPE x [<!ENTITY e SYSTEM \"file:///etc/hosts\">]><mxfile><diagram>&e;</diagram></mxfile>")
        #expect(await pipeline.preview(url: entity) == .unavailable(.malformedDocument))
        let big = try directory.write("big.drawio", String(repeating: " ", count: 4_096) + DrawioFixtures.model())
        #expect(await pipeline.preview(url: big, budget: PreviewBudget(maxInputBytes: 1_024)) == .unavailable(.inputTooLarge))
    }

    @Test func aLargeCompressedDrawioFileSurvivesTheTextLineLimit() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        var state: UInt64 = 0x2545F4914F6CDD1D
        func token() -> String {
            (0..<60).map { _ -> String in
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return String(Int(state >> 40) % 36, radix: 36)
            }.joined()
        }
        let cells = (0..<700).map { "<mxCell id=\"c\($0)\" value=\"\(token())\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"\($0 * 3)\" width=\"10\" height=\"10\" as=\"geometry\"/></mxCell>" }.joined()
        let text = DrawioFixtures.file(compressedPages: [DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>" + cells)])
        #expect(text.utf8.count > PreviewBudget.standard.maxLineUTF8Bytes)
        let file = try directory.write("large.drawio", text)
        let shown = try presentation(await pipeline.preview(url: file))
        #expect(shown.sourceRecordCount == 1 && shown.lineCount > 1_000)
        #expect(SafePreviewModes(shown, locale: .current).diagram?.nodeCount == 700)
    }

    // MARK: Policy, mutation, cancellation

    private final class Counter: Sendable {
        private let value = Mutex(0)
        func increment() { value.withLock { $0 += 1 } }
        var count: Int { value.withLock { $0 } }
    }
    private struct SpyReader: PreviewFileReading {
        let reads: Counter
        func read(url: URL, context: RequestContext) throws -> FileBytes {
            reads.increment()
            return FileBytes(data: Data("flowchart TD\nA --> B".utf8))
        }
    }

    @Test func aDisabledDiagramTypeNeitherReadsNorConstructsAnAdapter() async {
        for (format, name) in [(FormatID.mermaid, "flow.mmd"), (.drawio, "flow.drawio")] {
            let reads = Counter(), factories = Counter()
            let spy = PreviewPipeline(registrations: [AdapterRegistration(formatID: format) {
                factories.increment()
                return MermaidSourceAdapter()
            }], reader: SpyReader(reads: reads))
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: format)
            let url = URL(fileURLWithPath: "/unused/" + name)
            #expect(await spy.preview(url: url, preferences: preferences) == .disabledByUser(format))
            #expect(await spy.inspect(url: url, preferences: preferences) == .disabledByUser(format))
            #expect(reads.count == 0 && factories.count == 0)
            // A disabled diagram must not fall back to the generic text adapter either.
            let general = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: SpyReader(reads: reads))
            #expect(await general.preview(url: url, preferences: preferences) == .disabledByUser(format))
            #expect(reads.count == 0)
        }
    }

    @Test func previewingNeverChangesOrAddsFiles() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let mermaid = try directory.write("a.mmd", "flowchart TD\nA --> B\n")
        let drawio = try directory.write("b.drawio", DrawioFixtures.file(compressedPages: [DrawioFixtures.model()]))
        func snapshot() throws -> [String: Data] {
            Dictionary(uniqueKeysWithValues: try FileManager.default.contentsOfDirectory(atPath: directory.url.path).map {
                ($0, (try? Data(contentsOf: directory.url.appendingPathComponent($0))) ?? Data())
            })
        }
        let before = try snapshot()
        let dates = try [mermaid, drawio].map { try FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        for url in [mermaid, drawio] { _ = try presentation(await pipeline.preview(url: url)) }
        #expect(try snapshot() == before)
        #expect(try [mermaid, drawio].map { try FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date } == dates)
    }

    @Test func aCancelledRequestProducesNoPresentation() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let file = try directory.write("a.mmd", "flowchart TD\nA --> B\n")
        let task = Task.detached { [pipeline] in
            withUnsafeCurrentTask { $0?.cancel() }
            return await pipeline.preview(url: file)
        }
        #expect(await task.value == .cancelled)
    }

    // MARK: Reuse by other presentations

    @Test func theDrawingAPIRendersConcealedSourceWithoutAnyView() async throws {
        let directory = try Directory()
        defer { directory.remove() }
        let file = try directory.write("flow.mmd", "flowchart LR\nA[Alpha] --> B[Beta: password = \(secret)]\n")
        let shown = try presentation(await pipeline.preview(url: file))
        // A Markdown fence or a thumbnail passes concealed text straight to the module API.
        let diagram = try #require(SafeDiagram.parse(mermaid: shown.text))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 800, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        diagram.draw(in: context, size: CGSize(width: 200, height: 120), palette: .standard(isDark: false))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let pixels = UnsafeBufferPointer(start: data, count: 200 * 120 * 4)
        #expect(Set(stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }).count > 3)
        #expect(diagram.accessibilityNodes.map(\.label) == ["Alpha", "Beta: password = ••••"])
    }
}

import Foundation
import Testing
import PreviewTestSupport
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q52 facts from cached safe models", .serialized)
struct Q52FactsProviderTests {
    private let english = Locale(identifier: "en_US")

    @Test func sourceFactsUseConcealedLineCountAndReadBytesWithoutTouchingTheFile() {
        let presentation = text("one\ntwo", bytes: 7)
        let facts = supplied(presentation).facts
        #expect(facts == [.encoding(.utf8), .lines(2), .size(7)])
        let reformatted = text("one\ntwo", bytes: 7, origin: .reformatted)
        #expect(supplied(reformatted).facts.contains(.encoding(.utf8)))
    }

    @Test func summaryAndConvertedTextNeverAdvertiseLegacyTextFieldsAsSourceFacts() {
        for origin in [TextOrigin.summary, .converted] {
            let facts = supplied(text("Q52 summary", bytes: 500, origin: origin)).facts
            #expect(!facts.contains { if case .encoding = $0 { return true }; return false })
            #expect(!facts.contains { if case .lines = $0 { return true }; return false })
            #expect(!facts.contains { if case .size = $0 { return true }; return false })
            let typed = PresentationFacts([.size(500)])
            #expect(supplied(text("Q52 summary", bytes: 123, origin: origin, facts: typed)).facts.contains(.size(500)))
            #expect(!supplied(text("Q52 summary", bytes: 123, origin: origin, facts: typed)).facts.contains(.size(123)))
        }
        let directory = text("Q52 folder summary", bytes: 0, origin: .summary, format: .folder)
        #expect(!supplied(directory).facts.contains(.size(0)))
    }

    @Test func parserDatasetCountsTakePriorityOverDisplayedSampleRowsWithoutComputingProfile() {
        let parserFacts = PresentationFacts([.grid(rows: 98_765, columns: 4, rowsAreLowerBound: false), .size(500)])
        let presentation = text("a,b\n1,2\n", bytes: 8, format: .csv, syntax: .commaSeparated, facts: parserFacts)
        let modes = SafePreviewModes(presentation, locale: english)
        #expect(modes.table?.rows.count == 1)
        #expect(Array(PresentationFactsProvider.facts(for: presentation, modes: modes).facts.prefix(2)) == parserFacts.facts)
        #expect(modes.profile?.isComputed == false)
    }

    @Test func bytePrefixRemainsDistinctFromAWholeFileSize() {
        let presentation = text("one\ntwo", bytes: 7, totalBytes: 500)
        let facts = supplied(presentation).facts
        #expect(facts.contains(.shownSize(shown: 7, total: 500)))
        #expect(!facts.contains(.size(7)))
    }

    @Test func onlySourceDelimitedPrefixGridsLoseTheirExactRowTotal() {
        let grid = PresentationFacts([.grid(rows: 98_765, columns: 2, rowsAreLowerBound: false)])
        for (format, syntax) in [(FormatID.csv, TextSyntax.commaSeparated), (.tsv, .tabSeparated)] {
            let presentation = text("a\n1\n", bytes: 4, totalBytes: 500, format: format, syntax: syntax, facts: grid)
            #expect(supplied(presentation).facts.contains(.grid(rows: 98_765, columns: 2, rowsAreLowerBound: true)))
            #expect(!supplied(presentation).facts.contains(.grid(rows: 98_765, columns: 2, rowsAreLowerBound: false)))
        }
        let summary = text("{}", bytes: 4, totalBytes: 500, origin: .summary, format: .parquet, syntax: .json, facts: grid)
        #expect(supplied(summary).facts.contains(.grid(rows: 98_765, columns: 2, rowsAreLowerBound: false)))
    }

    @Test func cachedSchemaRowsNeverBecomeDatasetRowsAndProfileRemainsLazy() {
        let presentation = text("{}", bytes: 500, origin: .summary, format: .sqlite, syntax: .json)
        var modes = SafePreviewModes(presentation, locale: english)
        let schema = SafeTable(columns: ["table", "column"], rows: [["Q52", "a"]], truncation: .rows, origin: .dataSummary)
        modes.table = schema
        let profile = LazyDataProfile(source: schema, locale: english)
        modes.profile = profile
        let facts = PresentationFactsProvider.facts(for: presentation, modes: modes).facts
        #expect(!facts.contains { if case .grid = $0 { return true }; return false })
        #expect(!profile.isComputed)
    }

    @Test func anOversizedSyntheticOutlineIsNotCountedAsAnExactStructure() {
        let presentation = text("safe", bytes: 4)
        var modes = SafePreviewModes(presentation, locale: english)
        modes.outline = (0..<20_001).map { SafeOutlineNode(id: $0, name: "safe", value: "safe") }
        #expect(!PresentationFactsProvider.facts(for: presentation, modes: modes).facts.contains {
            if case .nodes = $0 { return true }; return false
        })
    }

    @Test func listingFactsCountOnlyExplicitEntriesAndSkipDirectoryAllocationSizes() {
        let summary = #"{"partial":true,"entries":[{"path":"implied/Q52_FILENAME_MARKER","type":"file","bytes":12},{"path":"empty/","type":"directory","bytes":4000}]}"#
        let presentation = text(summary, bytes: 0, origin: .summary, format: .zip, syntax: .json)
        let modes = SafePreviewModes(presentation, locale: english)
        #expect(modes.tree?.nodeCount == 3, "The tree additionally contains the implied parent folder")
        #expect(modes.listingFacts.facts == [.listing(files: 1, folders: 1, isLowerBound: true, listedBytes: 12)])
        let facts = PresentationFactsProvider.facts(for: presentation, modes: modes)
        #expect(facts.facts.contains(.listing(files: 1, folders: 1, isLowerBound: true, listedBytes: 12)))
        let lines = PresentationFactsFormatter.lines(for: facts, compact: false, locale: english, languagePreferences: ["en"])
        #expect(!lines.contains { $0.contains("Q52_FILENAME_MARKER") || $0.contains("implied") || $0.contains("4,000") })
    }

    @Test func missingNegativeAndOverflowingListedSizesRemainUnknown() {
        let summaries: [(String, Int)] = [
            (#"{"entries":[{"path":"a","type":"file"}]}"#, 1),
            (#"{"entries":[{"path":"a","type":"file","bytes":-1}]}"#, 1),
            (#"{"entries":[{"path":"a","type":"file","bytes":9223372036854775807},{"path":"b","type":"file","bytes":1}]}"#, 2)
        ]
        for (summary, count) in summaries {
            let presentation = text(summary, bytes: 0, origin: .summary, format: .zip, syntax: .json)
            let modes = SafePreviewModes(presentation, locale: english)
            #expect(modes.files?.rows.count == count)
            #expect(modes.listingFacts.facts == [.listing(files: count, folders: 0, isLowerBound: false, listedBytes: nil)])
        }
    }

    @Test func pixelFactsUseEncodedMetadataWithoutNeedingAnImageDecoder() {
        let image = PreviewImage(data: Data([1]), pixelWidth: 640, pixelHeight: 480, role: .cover)
        let presentation = TextPresentation(formatID: .epub, text: "safe summary", lineCount: 1, byteCount: 500,
            encoding: .utf8, redactionCount: 0, images: [image], origin: .summary)
        #expect(supplied(presentation).facts.contains(.pixels(width: 640, height: 480)))
        #expect(supplied(presentation).facts.contains(.records(1, .images, isLowerBound: true)))
        var modes = SafePreviewModes(presentation, locale: english)
        modes.images.append(PreviewImage(data: Data([2]), pixelWidth: 80, pixelHeight: 80, role: .page))
        #expect(!PresentationFactsProvider.facts(for: presentation, modes: modes).facts.contains {
            if case .pixels = $0 { return true }; return false
        })
    }

    @Test func carriedImagesAreOnlyALowerBoundUnlessTheParserSuppliesAnExhaustiveCount() {
        let image = PreviewImage(data: Data([1]), pixelWidth: 640, pixelHeight: 480, role: .cover)
        func presentation(facts: PresentationFacts = .none) -> TextPresentation {
            TextPresentation(formatID: .epub, text: "safe summary", lineCount: 1, byteCount: 500,
                encoding: .utf8, redactionCount: 0, images: [image], origin: .summary, facts: facts)
        }
        let carried = supplied(presentation())
        #expect(carried.facts.contains(.records(1, .images, isLowerBound: true)))
        #expect(PresentationFactsFormatter.lines(for: carried, compact: false, locale: english,
            languagePreferences: ["en"]).contains("Embedded images: 1+"))
        let exhaustive = supplied(presentation(facts: PresentationFacts([.records(8, .images)])))
        #expect(exhaustive.facts.contains(.records(8, .images)))
        #expect(!exhaustive.facts.contains(.records(1, .images, isLowerBound: true)))
    }

    @Test func playbackFactsUseTypedMIDIMetadataAndDoNotDescribeGeneratedSummaryText() {
        let midi = MIDIPresentation(format: 1, trackCount: 3, ticksPerQuarter: 96, durationSeconds: 125, events: [])
        let presentation = TextPresentation(formatID: .midi, text: "Q52 MIDI summary", lineCount: 99,
            byteCount: 500, encoding: .utf8, redactionCount: 0, midi: midi, origin: .summary)
        #expect(supplied(presentation).facts == [.playback(tracks: 3, seconds: 125)])
    }

    @Test func geometryFactsKeepCappedFacesAndDeclaredUnitsWithoutScanningTriangles() throws {
        let extent = SIMD3<Double>(25.4, 50.8, 76.2)
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: .init(minimum: .zero, maximum: extent), faceCount: GeometryLimits.maximumFaces,
            unitProvenance: .declared(.inch), faceCountIsCapped: true)
        let presentation = GeometryPresentation(formatID: CADTestFormatIDs.step, mesh: mesh, byteCount: 123)
        #expect(PresentationFactsProvider.facts(for: presentation).facts.contains(.geometry(
            faces: GeometryLimits.maximumFaces, bodies: nil, extentMillimetres: extent,
            unit: .declared(.inch), facesAreLowerBound: true)))
        #expect(!PresentationFactsProvider.facts(for: presentation).facts.contains(.size(123)))
    }

    private func supplied(_ presentation: TextPresentation) -> PresentationFacts {
        PresentationFactsProvider.facts(for: presentation, modes: SafePreviewModes(presentation, locale: english))
    }

    private func text(_ value: String, bytes: Int, totalBytes: Int? = nil, origin: TextOrigin = .source,
                      format: FormatID = .plainText, syntax: TextSyntax = .plain,
                      facts: PresentationFacts = .none) -> TextPresentation {
        .init(formatID: format, text: value, lineCount: value.components(separatedBy: "\n").count,
            byteCount: bytes, encoding: .utf8, redactionCount: 0, syntax: syntax,
            truncatedSourceBytes: totalBytes, origin: origin, facts: facts)
    }
}

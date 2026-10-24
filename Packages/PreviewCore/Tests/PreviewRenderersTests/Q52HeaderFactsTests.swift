import AppKit
import Foundation
import PreviewTestSupport
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Off-screen facade assertions use the chrome's provisional density constants; they do not measure Finder.
@Suite("Q52 facts in the single header row", .serialized)
@MainActor
struct Q52HeaderFactsTests {
    private let english = Locale(identifier: "en_US")

    @Test func theFacadeShowsSourceAndSuppliedDatasetFactsWithTheirOwnProvenance() {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        show(text("one\ntwo", bytes: 7), in: host)
        #expect(host.view.displayedFacts == ["UTF-8", PreviewStrings.count(.previewCountLines, 2, locale: english),
            format(.previewFactsSize, [SafeListingFormatting.sizeText(7, locale: english)])])
        let facts = PresentationFacts([.grid(rows: 98_765, columns: 4, rowsAreLowerBound: false), .size(500)])
        show(text("{}", bytes: 123, origin: .summary, format: .sqlite, syntax: .json, facts: facts), in: host)
        #expect(host.view.displayedFacts == [format(.previewFactsRows, ["98,765"]),
            format(.previewFactsColumns, ["4"]), format(.previewFactsSize, [SafeListingFormatting.sizeText(500, locale: english)])])
        #expect(!host.view.displayedFacts.contains("UTF-8"))
        #expect(!host.view.dataProfileIsComputed)
    }

    @Test func MIDIMetadataReplacesThePreviousFactsInsteadOfDescribingGeneratedText() {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        show(text("old\nsource", bytes: 10), in: host)
        let midi = MIDIPresentation(format: 1, trackCount: 3, ticksPerQuarter: 96, durationSeconds: 125, events: [])
        let presentation = TextPresentation(formatID: .midi, text: "Q52 generated summary", lineCount: 99,
            byteCount: 500, encoding: .utf8, redactionCount: 0, midi: midi, origin: .summary)
        show(presentation, in: host)
        #expect(host.view.displayedFacts == [format(.previewFactsTracks, ["3"]), format(.previewFactsDuration, ["02:05"])])
        #expect(!host.view.displayedFacts.contains("UTF-8"))
        #expect(!host.view.dataProfileIsComputed)
    }

    @Test func geometryFactsUseCappedFacesAndDeclaredUnitsThroughTheFacade() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        host.view.geometryViewFactory = {
            NativeGeometryPreviewView(frame: .zero, backendFactory: { _ in Q52GeometryBackendProbe() })
        }
        show(text("old source", bytes: 10), in: host)
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: .zero, maximum: SIMD3<Double>(20, 20, 1)),
            faceCount: GeometryLimits.maximumFaces, unitProvenance: .declared(.millimetre), faceCountIsCapped: true)
        host.view.display(.geometryReady(GeometryPresentation(formatID: CADTestFormatIDs.step, mesh: mesh, byteCount: 123)), locale: english)
        host.view.layoutSubtreeIfNeeded()
        let symbol = try #require(GeometrySummaryUnits(.declared(.millimetre))?.lengthSymbol(locale: english))
        #expect(host.view.displayedFacts == [format(.previewFactsFaces, [format(.previewFactsLowerBound, ["100,000"])]),
            format(.previewFactsDimensions, ["20", "20", "1", symbol])])
        #expect(!host.view.displayedFacts.contains("UTF-8"))
        show(text("replacement", bytes: 11), in: host)
        #expect(host.view.displayedFacts.first == "UTF-8")
        #expect(!host.view.displayedFacts.contains { $0.contains("100,000") })
    }

    @Test func resizingChangesTheScalarBudgetAndRestoresRegularFacts() {
        let high = PreviewChrome.compactWidth + PreviewChrome.compactHysteresis
        let low = PreviewChrome.compactWidth - PreviewChrome.compactHysteresis
        let host = InteractionHarness(width: high + 80)
        defer { host.release() }
        let facts = PresentationFacts([.grid(rows: 12, columns: 7, rowsAreLowerBound: false), .records(3, .records), .size(1024)])
        show(text("{}", bytes: 500, origin: .summary, format: .parquet, syntax: .json, facts: facts), in: host)
        let regular = [format(.previewFactsRows, ["12"]), format(.previewFactsColumns, ["7"]),
            format(.previewFactsRecords, ["3"]), format(.previewFactsSize, [SafeListingFormatting.sizeText(1024, locale: english)])]
        #expect(host.view.density == .regular && host.view.displayedFacts == regular)
        resize(host.view, to: low - 1)
        #expect(host.view.density == .compact && host.view.displayedFacts == Array(regular.prefix(2)))
        resize(host.view, to: high)
        #expect(host.view.density == .regular && host.view.displayedFacts == regular)
    }

    @Test func noncontentStatesAndAReplacementWithNoFactsClearTheLabelAndItsMetadata() {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        host.view.chromeScheduler = ManualChromeScheduler()
        let source = text("safe", bytes: 4)
        for outcome in [PreviewOutcome.unavailable(.missingFile), .disabledByUser(.json), .cancelled] {
            show(source, in: host)
            #expect(!host.view.displayedFacts.isEmpty)
            host.view.display(outcome, locale: english)
            expectCleared(host.view)
        }
        show(source, in: host)
        host.view.showLoading()
        expectCleared(host.view)
        show(source, in: host)
        host.view.showSettingsUnavailable()
        expectCleared(host.view)
        show(source, in: host)
        host.view.showSettingsConfigurationUnavailable()
        expectCleared(host.view)
        show(source, in: host)
        show(text("", bytes: 0), in: host)
        expectCleared(host.view)
        show(source, in: host)
        show(text("safe generated summary", bytes: 500, origin: .summary), in: host)
        expectCleared(host.view)
    }

    @Test func modeStyleZoomAndFiltersKeepFactsCurrentAndProfileLazyUntilSelected() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        let facts = PresentationFacts([.grid(rows: 12, columns: 2, rowsAreLowerBound: false)])
        let csv = text("name,value\na,1\nb,2\n", bytes: 19, format: .csv, syntax: .commaSeparated, facts: facts)
        show(csv, in: host)
        let baseline = host.view.displayedFacts
        #expect(!host.view.dataProfileIsComputed)
        for mode in [.source, .table] as [NativePreviewMode] {
            try select(mode, in: host.view)
            #expect(host.view.displayedFacts == baseline && !host.view.dataProfileIsComputed)
        }
        #expect(host.press("=", .command))
        #expect(host.view.displayedFacts == baseline && !host.view.dataProfileIsComputed)
        host.view.display(.ready(csv), typography: PreviewTypography(fontSize: 20), theme: .dark,
            syntaxStyle: PreviewSyntaxStyle(usesColor: false), locale: english)
        #expect(host.view.displayedFacts == baseline && !host.view.dataProfileIsComputed)
        try select(.profile, in: host.view)
        #expect(host.view.dataProfileIsComputed && host.view.displayedFacts == baseline)
        try select(.source, in: host.view)
        #expect(host.view.dataProfileIsComputed && host.view.displayedFacts == baseline)

        let json = text(#"{"Q52_NAME_MARKER":[1,2]}"#, bytes: 25, format: .json, syntax: .json,
            facts: PresentationFacts([.nodes(42)]))
        show(json, in: host)
        let structuredFacts = host.view.displayedFacts
        #expect(structuredFacts.first == format(.previewFactsNodes, ["42"]))
        #expect(!structuredFacts.contains { $0.contains("Q52_NAME_MARKER") })
        try select(.outline, in: host.view)
        let field = host.view.accessoryBar.filterBar.searchField
        field.stringValue = "Q52 no matches"
        #expect(field.sendAction(field.action, to: field.target))
        #expect(host.view.displayedFacts == structuredFacts && !host.view.dataProfileIsComputed)
    }

    @Test func aTruncatedFactsLabelStaysInOneRowAndExposesItsFullValueAndTooltip() throws {
        let host = InteractionHarness(width: PreviewChrome.compactWidth + PreviewChrome.compactHysteresis + 1)
        defer { host.release() }
        let facts = PresentationFacts([.grid(rows: 987_654_321, columns: 123_456_789, rowsAreLowerBound: false),
            .records(987_654_321, .records), .size(987_654_321)])
        show(text("{}", bytes: 500, origin: .summary, format: .parquet, syntax: .json, facts: facts), in: host)
        let label = host.view.factsLabel
        let fullText = host.view.displayedFacts.joined(separator: PreviewStrings.text(.previewFactsSeparator))
        #expect(host.view.displayedFacts.count == 4)
        #expect(label.stringValue == fullText && !label.isHidden)
        #expect(label.lineBreakMode == .byTruncatingMiddle && label.maximumNumberOfLines == 1)
        #expect(label.toolTip == fullText && label.accessibilityValue() as? String == fullText)
        #expect(label.intrinsicContentSize.width > label.bounds.width, "The fixture actually requires truncation")
        let row = host.view.headerGuide.frame
        let labelFrame = host.view.convert(label.bounds, from: label)
        #expect(row.height > 0 && row.height <= PreviewChrome.headerHeight)
        #expect(labelFrame.minY >= row.minY && labelFrame.maxY <= row.maxY)
        #expect(!host.view.hasAmbiguousLayout && !label.hasAmbiguousLayout)
    }

    private func format(_ key: PreviewStrings.Key, _ arguments: [String]) -> String {
        PreviewStrings.format(key, arguments: arguments, locale: english)
    }
    private func show(_ presentation: TextPresentation, in host: InteractionHarness) {
        host.view.display(.ready(presentation), locale: english, resetsContentState: true)
        host.view.layoutSubtreeIfNeeded()
    }
    private func resize(_ view: NativePreviewView, to width: CGFloat) {
        view.setFrameSize(NSSize(width: width, height: 420))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }
    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        view.modeControl.selectedSegment = try #require(view.displayedModes.firstIndex(of: mode))
        #expect(view.modeControl.sendAction(view.modeControl.action, to: view.modeControl.target))
        view.layoutSubtreeIfNeeded()
    }
    private func expectCleared(_ view: NativePreviewView) {
        #expect(view.displayedFacts.isEmpty && view.factsLabel.stringValue.isEmpty && view.factsLabel.isHidden)
        #expect(view.factsLabel.toolTip == nil)
        #expect(((view.factsLabel.accessibilityValue() as? String) ?? "").isEmpty)
    }
    private func text(_ value: String, bytes: Int, origin: TextOrigin = .source, format: FormatID = .plainText,
                      syntax: TextSyntax = .plain, facts: PresentationFacts = .none) -> TextPresentation {
        .init(formatID: format, text: value, lineCount: value.components(separatedBy: "\n").count,
            byteCount: bytes, encoding: .utf8, redactionCount: 0, syntax: syntax, origin: origin, facts: facts)
    }
}

@MainActor
private final class Q52GeometryBackendProbe: GeometryRenderingBackend {
    let surface = NSView()
    var failureHandler: (@MainActor () -> Void)?
    func update(camera: GeometryCamera, style: GeometryRenderStyle) {}
    func suspend() {}
}

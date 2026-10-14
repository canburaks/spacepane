import AppKit
import PreviewContracts
import PreviewFormats
import Testing
@testable import PreviewRenderers

/// The Mesh Print Check lines of the geometry view (decision 029). The models are read by the real STL adapter, so the
/// measurements are the ones a preview gets. The tests assert which lines appear and the numbers behind them
/// (`GeometryPrintCheck`), not English wording: the resources for the new keys are added when the lead integrates them.
@Suite("Mesh Print Check in the geometry view")
@MainActor
struct MeshPrintCheckTests {
    private let english = Locale(identifier: "en")

    /// An axis-aligned box centred on the origin as ASCII STL: twelve triangles, outward facing, closed.
    private func boxSTL(_ size: SIMD3<Double>, omittingFace face: Int? = nil) -> Data {
        let h = size / 2
        let v = [SIMD3(-h.x, -h.y, -h.z), SIMD3(h.x, -h.y, -h.z), SIMD3(h.x, h.y, -h.z), SIMD3(-h.x, h.y, -h.z),
                 SIMD3(-h.x, -h.y, h.z), SIMD3(h.x, -h.y, h.z), SIMD3(h.x, h.y, h.z), SIMD3(-h.x, h.y, h.z)]
        let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
        var triangles = quads.enumerated().filter { $0.offset != face }.flatMap { [[$0.element[0], $0.element[1], $0.element[2]], [$0.element[0], $0.element[2], $0.element[3]]] }
        if triangles.isEmpty { triangles = [[0, 1, 2]] }
        return stl(v, triangles)
    }

    private func stl(_ vertices: [SIMD3<Double>], _ triangles: [[Int]]) -> Data {
        var text = "solid synthetic\n"
        for triangle in triangles {
            text += "facet normal 0 0 0\nouter loop\n"
            for index in triangle { text += "vertex \(vertices[index].x) \(vertices[index].y) \(vertices[index].z)\n" }
            text += "endloop\nendfacet\n"
        }
        return Data((text + "endsolid synthetic\n").utf8)
    }

    /// A presentation whose mesh the real STL reader built, then labelled with the unit a 3MF would have declared.
    private func presentation(_ data: Data, formatID: FormatID = .meshSTL,
                              provenance: GeometryUnitProvenance? = nil) throws -> GeometryPresentation {
        var mesh = try STLAdapter().parse(FileBytes(data: data), context: RequestContext(budget: MeshLimits.requestBudget))
        if let provenance {
            let relabelled = try #require(mesh.measurements).declaring(unitProvenance: provenance)
            mesh = mesh.attaching(measurements: relabelled, headerFacts: nil, unitProvenance: provenance)
        }
        return GeometryPresentation(formatID: formatID, mesh: mesh, byteCount: data.count)
    }

    private func check(_ presentation: GeometryPresentation, upAxis: GeometryUpAxis = .z) -> GeometryPrintCheck? {
        GeometryPrintCheck(presentation: presentation, upAxis: upAxis)
    }

    private func lineCount(_ presentation: GeometryPresentation, upAxis: GeometryUpAxis = .z) -> Int {
        NativeGeometryPreviewView.summaryLines(for: presentation, upAxis: upAxis, locale: english, languagePreferences: ["en"]).count
    }

    // MARK: Which lines appear

    @Test func aClosedUndeclaredModelShowsTheSizeAndNothingElse() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)))
        let result = try #require(check(model))
        #expect(result.units == nil)
        #expect(result.openEdgeCount == 0 && result.nonManifoldEdgeCount == 0)
        #expect(result.estimate == nil, "An undeclared unit gives no estimate")
        // The model summary, its measurements, and the size: no count lines, no estimate.
        #expect(lineCount(model) == 3)
        #expect(result.lines(locale: english, languagePreferences: ["en"]).count == 1)
    }

    @Test func aClosedModelInADeclaredUnitAddsTheEstimate() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF, provenance: .declared(.millimetre))
        let result = try #require(check(model))
        #expect(result.units != nil && result.units?.millimetresPerUnit == 1)
        let estimate = try #require(result.estimate)
        // 30 x 20 x 10 mm = 6 cm³ of PLA at 1.24 g/cm³.
        #expect(abs(estimate.massGrams - 7.44) < 1e-4)
        #expect(lineCount(model) == 4) // Summary, measurements, size, estimate.
    }

    @Test func anAssumedMillimetreUnitAlsoGetsTheEstimate() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF, provenance: .assumedMillimetres)
        #expect(try #require(check(model)).estimate != nil)
        #expect(lineCount(model) == 4)
    }

    @Test func openEdgesAddALineAndTheVolumeBasedEstimateGoesAway() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10), omittingFace: 0), formatID: .mesh3MF, provenance: .declared(.millimetre))
        let result = try #require(check(model))
        #expect(result.openEdgeCount == 4 && result.nonManifoldEdgeCount == 0)
        #expect(result.estimate == nil)
        #expect(lineCount(model) == 4) // Summary, measurements (volume unavailable), size, open edges.
    }

    @Test func threeTrianglesOnOneEdgeAddBothCountLines() throws {
        let vertices: [SIMD3<Double>] = [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0), SIMD3(0, 0, 10), SIMD3(0, -10, 0)]
        let model = try presentation(stl(vertices, [[0, 1, 2], [0, 1, 3], [0, 1, 4]]))
        let result = try #require(check(model))
        #expect(result.openEdgeCount == 6 && result.nonManifoldEdgeCount == 1)
        #expect(lineCount(model) == 5) // Summary, measurements, size, open edges, non-manifold edges.
    }

    @Test func aModelOfAnotherFormatKeepsItsSummaryUnchanged() throws {
        // CAD models, and any format outside the four print formats, get no print check at all.
        for formatID in [FormatID.step, .iges, FormatID(rawValue: "image.png")] {
            let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: formatID, provenance: .declared(.millimetre))
            #expect(check(model) == nil, "\(formatID.rawValue)")
            let plain = NativeGeometryPreviewView.summaryLines(for: model.mesh, locale: english, languagePreferences: ["en"])
            let shown = NativeGeometryPreviewView.summaryLines(for: model, upAxis: .y, locale: english, languagePreferences: ["en"])
            #expect(shown == plain, "\(formatID.rawValue)")
        }
    }

    // MARK: Size

    @Test func theSizeIsWidthDepthAndHeightAlongTheAxisThatIsUp() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)))
        let standingOnZ = try #require(check(model, upAxis: .z))
        #expect((standingOnZ.width, standingOnZ.depth, standingOnZ.height) == (30, 20, 10))
        let standingOnY = try #require(check(model, upAxis: .y))
        #expect((standingOnY.width, standingOnY.depth, standingOnY.height) == (30, 10, 20))
    }

    @Test func theSizeIsInTheDisplayUnit() throws {
        // 30 x 20 x 10 mm declared in centimetres is 3 x 2 x 1 cm; in inches 30 mm is 1.1811 in.
        let centimetres = try #require(check(try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF,
                                                              provenance: .declared(.centimetre))))
        #expect((centimetres.width, centimetres.depth, centimetres.height) == (3, 2, 1))
        let inches = try #require(check(try presentation(boxSTL(SIMD3(25.4, 50.8, 12.7)), formatID: .mesh3MF,
                                                         provenance: .declared(.inch))))
        #expect(abs(inches.width - 1) < 1e-9 && abs(inches.depth - 2) < 1e-9 && abs(inches.height - 0.5) < 1e-9)
        // Undeclared: the millimetre numbers, shown without a unit.
        let plain = try #require(check(try presentation(boxSTL(SIMD3(30, 20, 10)))))
        #expect(plain.units == nil && plain.width == 30)
    }

    @Test func theEstimateIsPhysicalWhateverTheDisplayUnit() throws {
        // The stored values are always millimetres: relabelling the unit changes the size that is shown, never the mass.
        let millimetres = try #require(check(try presentation(boxSTL(SIMD3(10, 10, 10)), formatID: .mesh3MF,
                                                              provenance: .declared(.millimetre))))
        let inches = try #require(check(try presentation(boxSTL(SIMD3(10, 10, 10)), formatID: .mesh3MF,
                                                         provenance: .declared(.inch))))
        #expect(abs(try #require(millimetres.estimate).massGrams - 1.24) < 1e-5)
        #expect(abs(try #require(inches.estimate).massGrams - 1.24) < 1e-5)
    }

    // MARK: The view

    private func makeView() -> NativeGeometryPreviewView {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), backendFactory: { _ in
            throw GeometryRenderFailure.unavailable
        })
        view.announcer?.handler = { _ in }
        return view
    }

    @Test func theViewShowsTheLinesAndExposesThemToVoiceOver() throws {
        let view = makeView()
        let model = try presentation(boxSTL(SIMD3(30, 20, 10), omittingFace: 0), formatID: .mesh3MF, provenance: .declared(.millimetre))
        view.show(model, theme: .light, locale: english)
        let expected = NativeGeometryPreviewView.summaryLines(for: model, upAxis: view.camera.upAxis, locale: english).joined(separator: "\n")
        #expect(view.accessibilitySummary == expected)
        #expect(view.accessibilitySummary.components(separatedBy: "\n").count == 4)
        view.clear()
        #expect(view.accessibilitySummary.isEmpty)
    }

    @Test func aModelOfAnotherFormatStillShowsOnlyItsSummary() throws {
        let view = makeView()
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .step, provenance: .declared(.millimetre))
        view.show(model, theme: .light, locale: english)
        #expect(view.accessibilitySummary.components(separatedBy: "\n").count == 2)
    }

    @Test func theUpAxisButtonRewritesTheSizeForTheNewAxis() throws {
        let view = makeView()
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF, provenance: .declared(.millimetre))
        view.show(model, theme: .light, locale: english)
        #expect(view.camera.upAxis == .z)
        view.navigate(.toggleUpAxis)
        #expect(view.camera.upAxis == .y)
        let expected = NativeGeometryPreviewView.summaryLines(for: model, upAxis: .y, locale: english).joined(separator: "\n")
        #expect(view.accessibilitySummary == expected)
        #expect(check(model, upAxis: .y)?.height == 20)
    }

    @Test(arguments: ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"])
    func everyLanguageCompletesEveryLine(language: String) throws {
        // Declared unit with a known volume (estimate), then an open model with both counts, then an undeclared one.
        let vertices: [SIMD3<Double>] = [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0), SIMD3(0, 0, 10), SIMD3(0, -10, 0)]
        let models = [try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF, provenance: .declared(.inch)),
                      try presentation(stl(vertices, [[0, 1, 2], [0, 1, 3], [0, 1, 4]]), formatID: .mesh3MF,
                                       provenance: .declared(.centimetre)),
                      try presentation(boxSTL(SIMD3(30, 20, 10)))]
        for model in models {
            let result = try #require(check(model))
            for line in result.lines(locale: Locale(identifier: language), languagePreferences: [language]) {
                #expect(!line.isEmpty && !line.contains("%") && !line.contains("mesh.printCheck"), "\(language): \(line)")
            }
        }
    }
}

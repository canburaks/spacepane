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

    private func check(_ presentation: GeometryPresentation) -> GeometryPrintCheck? {
        GeometryPrintCheck(presentation: presentation)
    }

    private func lineCount(_ presentation: GeometryPresentation) -> Int {
        NativeGeometryPreviewView.summaryLines(for: presentation, locale: english, languagePreferences: ["en"]).count
    }

    // MARK: Which lines appear

    @Test func aClosedUndeclaredModelGetsTheEstimateConditionalOnMillimetres() throws {
        // STL, OBJ and PLY state no unit: the estimate is shown, worded as "if the units are millimetres".
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)))
        let result = try #require(check(model))
        #expect(result.openEdgeCount == 0 && result.nonManifoldEdgeCount == 0)
        let estimate = try #require(result.estimate)
        #expect(estimate.isConditionalOnMillimetres)
        #expect(abs(estimate.massGrams - 7.44) < 1e-4)
        #expect(lineCount(model) == 3) // Summary, measurements, conditional estimate.
        #expect(result.lines(locale: english, languagePreferences: ["en"]).count == 1)
    }

    @Test func aClosedModelInADeclaredUnitKeepsThePlainEstimate() throws {
        for provenance in [GeometryUnitProvenance.declared(.centimetre), .declared(.millimetre), .assumedMillimetres] {
            let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF, provenance: provenance)
            let result = try #require(check(model))
            let estimate = try #require(result.estimate, "\(provenance)")
            #expect(!estimate.isConditionalOnMillimetres, "\(provenance)")
            // 30 x 20 x 10 mm = 6 cm³ of PLA at 1.24 g/cm³, whatever the label.
            #expect(abs(estimate.massGrams - 7.44) < 1e-4, "\(provenance)")
            #expect(lineCount(model) == 3, "\(provenance)") // Summary, measurements, estimate.
        }
    }

    @Test func openEdgesAddALineAndTheVolumeBasedEstimateGoesAway() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10), omittingFace: 0), formatID: .mesh3MF, provenance: .declared(.millimetre))
        let result = try #require(check(model))
        #expect(result.openEdgeCount == 4 && result.nonManifoldEdgeCount == 0)
        #expect(result.estimate == nil)
        #expect(lineCount(model) == 3) // Summary, measurements (volume unavailable), open edges.
    }

    @Test func anUndeclaredModelWithoutAClosedVolumeGetsNeitherEstimate() throws {
        let model = try presentation(boxSTL(SIMD3(30, 20, 10), omittingFace: 0))
        let result = try #require(check(model))
        #expect(result.estimate == nil)
        #expect(result.openEdgeCount == 4)
        #expect(lineCount(model) == 3) // Summary, measurements (volume unavailable), open edges.
    }

    @Test func threeTrianglesOnOneEdgeAddBothCountLines() throws {
        let vertices: [SIMD3<Double>] = [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0), SIMD3(0, 0, 10), SIMD3(0, -10, 0)]
        let model = try presentation(stl(vertices, [[0, 1, 2], [0, 1, 3], [0, 1, 4]]))
        let result = try #require(check(model))
        #expect(result.openEdgeCount == 6 && result.nonManifoldEdgeCount == 1)
        #expect(lineCount(model) == 4) // Summary, measurements, open edges, non-manifold edges.
    }

    @Test func aModelOfAnotherFormatKeepsItsSummaryUnchanged() throws {
        // CAD models, and any format outside the four print formats, get no print check at all.
        for formatID in [FormatID.step, .iges, FormatID(rawValue: "image.png")] {
            let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: formatID, provenance: .declared(.millimetre))
            #expect(check(model) == nil, "\(formatID.rawValue)")
            let plain = NativeGeometryPreviewView.summaryLines(for: model.mesh, locale: english, languagePreferences: ["en"])
            let shown = NativeGeometryPreviewView.summaryLines(for: model, locale: english, languagePreferences: ["en"])
            #expect(shown == plain, "\(formatID.rawValue)")
        }
    }

    @Test func theEstimateIsPhysicalWhateverTheDisplayUnit() throws {
        // The stored values are always millimetres: relabelling the unit changes the summary that is shown, never the mass.
        let millimetres = try #require(check(try presentation(boxSTL(SIMD3(10, 10, 10)), formatID: .mesh3MF,
                                                              provenance: .declared(.millimetre))))
        let inches = try #require(check(try presentation(boxSTL(SIMD3(10, 10, 10)), formatID: .mesh3MF,
                                                         provenance: .declared(.inch))))
        let first = try #require(millimetres.estimate), second = try #require(inches.estimate)
        #expect(abs(first.massGrams - 1.24) < 1e-5)
        #expect(abs(second.massGrams - 1.24) < 1e-5)
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
        let expected = NativeGeometryPreviewView.summaryLines(for: model, locale: english).joined(separator: "\n")
        #expect(view.accessibilitySummary == expected)
        #expect(view.accessibilitySummary.components(separatedBy: "\n").count == 3)
        view.clear()
        #expect(view.accessibilitySummary.isEmpty)
    }

    @Test func aModelOfAnotherFormatStillShowsOnlyItsSummary() throws {
        let view = makeView()
        let model = try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .step, provenance: .declared(.millimetre))
        view.show(model, theme: .light, locale: english)
        #expect(view.accessibilitySummary.components(separatedBy: "\n").count == 2)
    }

    @Test(arguments: ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"])
    func everyLanguageCompletesEveryLine(language: String) throws {
        // Declared unit with a known volume (plain estimate), an open model with both counts, and an undeclared closed
        // one (conditional estimate).
        let vertices: [SIMD3<Double>] = [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(0, 10, 0), SIMD3(0, 0, 10), SIMD3(0, -10, 0)]
        let models = [try presentation(boxSTL(SIMD3(30, 20, 10)), formatID: .mesh3MF, provenance: .declared(.inch)),
                      try presentation(stl(vertices, [[0, 1, 2], [0, 1, 3], [0, 1, 4]]), formatID: .mesh3MF,
                                       provenance: .declared(.centimetre)),
                      try presentation(boxSTL(SIMD3(30, 20, 10)))]
        for model in models {
            #expect(check(model) != nil)
            for line in NativeGeometryPreviewView.summaryLines(for: model, locale: Locale(identifier: language),
                                                                languagePreferences: [language]) {
                #expect(!line.isEmpty && !line.contains("%") && !line.contains("mesh.printCheck") && !line.contains("cad."), "\(language): \(line)")
            }
        }
    }
}

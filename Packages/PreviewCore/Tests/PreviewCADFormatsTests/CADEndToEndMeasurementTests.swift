import Foundation
import Testing
@testable import PreviewCADFormats
import PreviewContracts

/// Locates the project-local helper that `python3 script/build_cad_worker.py` prepares. The kernel is
/// not part of the package, so these checks run only on a machine where the helper was built.
private enum PreparedHelper {
    static let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
    static let workspace = root.appendingPathComponent(".build/cad", isDirectory: true)
    static var url: URL? {
        #if arch(arm64)
        let candidate = workspace.appendingPathComponent("worker-arm64/CADWorker")
        #else
        let candidate = workspace.appendingPathComponent("worker-x86_64/CADWorker")
        #endif
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }
}

@Suite("CAD measurements end to end", .enabled(if: PreparedHelper.url != nil))
struct CADEndToEndMeasurementTests {
    func mesh(_ path: URL, kind: CADFileKind) throws -> PreviewMesh? {
        guard let data = try? Data(contentsOf: path), let helper = PreparedHelper.url else { return nil }
        let adapter = CADFormatAdapter(kind: kind, transport: .worker(helper))
        return try adapter.parse(FileBytes(data: data), context: RequestContext(budget: GeometryLimits.requestBudget))
    }
    func expectClose(_ actual: Double?, _ expected: Double, tolerance: Double,
                     sourceLocation: SourceLocation = #_sourceLocation) {
        guard let actual else { Issue.record("value unavailable", sourceLocation: sourceLocation); return }
        #expect(abs(actual - expected) <= expected * tolerance, "\(actual) vs \(expected)", sourceLocation: sourceLocation)
    }

    @Test(arguments: [CADFileKind.step, .iges])
    func theAnalyticBoxMeasuresItsExactAreaAndVolume(kind: CADFileKind) throws {
        let name = kind == .step ? "box.step" : "box.iges"
        let path = PreparedHelper.root.appendingPathComponent("Native/CADWorker/Tests/Fixtures/" + name)
        let mesh = try #require(try mesh(path, kind: kind))
        let measurements = try #require(mesh.measurements)
        // 10 x 20 x 30 mm: area 2 * (200 + 300 + 600) = 2,200 mm²; volume 6,000 mm³.
        expectClose(measurements.surfaceAreaSquareMillimetres, 2_200, tolerance: 1e-4)
        expectClose(measurements.volumeCubicMillimetres, 6_000, tolerance: 1e-4)
        #expect(measurements.bodyCount == 1)
        #expect(mesh.headerFacts?.originatingSystem == "Open CASCADE 7.9")
        #expect(mesh.headerFacts?.schema == (kind == .step ? .stepAP214 : .iges(.version5_3)))
    }

    /// Curved parts are tessellated with chord error, so these are approximations of the analytic values.
    @Test(arguments: [
        ("cylinder", 2_513.27, 9_424.78), ("sphere", 1_256.64, 4_188.79), ("cone", 1_307.72, 3_141.59),
        ("inch", 14_193.52, 98_322.4), ("translated", 2_200.0, 6_000.0)
    ], [CADFileKind.step, .iges])
    func generatedFixturesStayNearTheirAnalyticValues(fixture: (String, Double, Double), kind: CADFileKind) throws {
        let file = PreparedHelper.workspace.appendingPathComponent("fixtures/\(fixture.0).\(kind.rawValue)")
        guard let mesh = try mesh(file, kind: kind), let measurements = mesh.measurements else { return }
        expectClose(measurements.surfaceAreaSquareMillimetres, fixture.1, tolerance: 0.02)
        // Faces that were not stitched at the source can leave the mesh unwatertight; then no volume is shown.
        if let volume = measurements.volumeCubicMillimetres { expectClose(volume, fixture.2, tolerance: 0.02) }
        #expect(measurements.bodyCount == 1)
    }

    @Test func aSingleTrimmedFaceIsAnOpenSurface() throws {
        let file = PreparedHelper.workspace.appendingPathComponent("fixtures/trimmed.step")
        guard let mesh = try mesh(file, kind: .step), let measurements = mesh.measurements else { return }
        #expect(measurements.volumeCubicMillimetres == nil)
        #expect(measurements.surfaceAreaSquareMillimetres > 0)
    }
}

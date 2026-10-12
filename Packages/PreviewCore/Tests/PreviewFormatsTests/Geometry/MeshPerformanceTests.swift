import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// Records parse times for a synthetic 100,000-triangle model in every format. The numbers are printed
/// as `MESH-PERFORMANCE` lines for the validation record; the assertions only guard against a
/// regression of an order of magnitude. Run this suite alone for meaningful timings: other suites share
/// the machine, and a Debug build is far slower than Release.
@Suite("Mesh parse performance")
struct MeshPerformanceTests {
    private func configuration() -> String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    @Test func parsesAHundredThousandTrianglesInEveryFormat() throws {
        let torus = MeshFixtures.torus(segments: 250, sides: 200)
        // Three decimals keep the text formats compact enough for the 16 MiB input cap.
        let vertices = torus.vertices.map { SIMD3<Double>(($0.x * 1000).rounded() / 1000, ($0.y * 1000).rounded() / 1000, ($0.z * 1000).rounded() / 1000) }
        let triangles = MeshFixtures.triangles(torus.quads)
        #expect(triangles.count == 100_000)
        let inputs: [(name: String, adapter: any GeometryFormatAdapter, data: Data)] = [
            ("STL binary", STLAdapter(), MeshFixtures.stlBinary(vertices, triangles)),
            ("STL ASCII", STLAdapter(), MeshFixtures.stlASCII(vertices, triangles, compact: true)),
            ("OBJ", OBJAdapter(), MeshFixtures.obj(vertices, faces: torus.quads)),
            ("PLY ASCII", PLYAdapter(), MeshFixtures.plyASCII(vertices, faces: torus.quads)),
            ("PLY binary", PLYAdapter(), MeshFixtures.plyBinary(vertices, faces: torus.quads)),
            ("3MF", ThreeMFAdapter(), MeshFixtures.threeMF(vertices: vertices, triangles: triangles))]
        let budget = PreviewBudget(maxInputBytes: GeometryLimits.maximumInputBytes, maxOutputUTF8Bytes: GeometryLimits.maximumSerializedBytes,
                                   maxJSONNodes: 1_000_000, maxMilliseconds: 30_000)
        for input in inputs {
            #expect(input.data.count <= GeometryLimits.maximumInputBytes, "\(input.name) fixture exceeds the input cap")
            let start = ContinuousClock.now
            let mesh = try input.adapter.parse(FileBytes(data: input.data), context: RequestContext(budget: budget))
            let elapsed = ContinuousClock.now - start
            let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            print("MESH-PERFORMANCE configuration=\(configuration()) format=\"\(input.name)\" inputBytes=\(input.data.count) "
                  + "triangles=\(MeshFixtures.triangleCount(mesh)) vertices=\(mesh.positions.count) parseMilliseconds=\(Int(milliseconds.rounded()))")
            #expect(MeshFixtures.triangleCount(mesh) == 100_000, "\(input.name)")
            #expect(mesh.faceCount == GeometryLimits.maximumFaces || mesh.faceCount == 50_000 || mesh.faceCount == 100_000)
            #expect(elapsed < .seconds(25), "\(input.name) took \(milliseconds) ms")
        }
        // Process-wide high-water mark: it includes the test runner and every fixture built above,
        // so it bounds, rather than isolates, the parsers' own use.
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("MESH-PERFORMANCE configuration=\(configuration()) processPeakResidentMiB=\(Int(usage.ru_maxrss) / 1_048_576)")
    }

    /// The largest inputs the contract admits: a binary STL at the 16 MiB input cap and a 3MF at the
    /// 500,000-triangle ceiling. These bound the worst case a Finder preview can be asked to do.
    @Test func parsesTheLargestAdmittedInputs() throws {
        let budget = PreviewBudget(maxInputBytes: GeometryLimits.maximumInputBytes, maxOutputUTF8Bytes: GeometryLimits.maximumSerializedBytes,
                                   maxJSONNodes: 1_000_000, maxMilliseconds: 30_000)
        let stl = MeshFixtures.torus(segments: 410, sides: 408)
        let stlTriangles = MeshFixtures.triangles(stl.quads)
        let stlData = MeshFixtures.stlBinary(stl.vertices, stlTriangles)
        #expect(stlData.count <= GeometryLimits.maximumInputBytes)
        let threeMF = MeshFixtures.torus(segments: 500, sides: 500)
        let threeMFVertices = threeMF.vertices.map { SIMD3<Double>(($0.x * 1000).rounded() / 1000, ($0.y * 1000).rounded() / 1000, ($0.z * 1000).rounded() / 1000) }
        let threeMFData = MeshFixtures.threeMF(vertices: threeMFVertices, triangles: MeshFixtures.triangles(threeMF.quads))
        let inputs: [(name: String, adapter: any GeometryFormatAdapter, data: Data, triangles: Int)] = [
            ("STL binary at the input cap", STLAdapter(), stlData, stlTriangles.count),
            ("3MF at the triangle ceiling", ThreeMFAdapter(), threeMFData, MeshLimits.maximumTriangles)]
        for input in inputs {
            let start = ContinuousClock.now
            let mesh = try input.adapter.parse(FileBytes(data: input.data), context: RequestContext(budget: budget))
            let elapsed = ContinuousClock.now - start
            let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            print("MESH-PERFORMANCE configuration=\(configuration()) format=\"\(input.name)\" inputBytes=\(input.data.count) "
                  + "triangles=\(MeshFixtures.triangleCount(mesh)) vertices=\(mesh.positions.count) parseMilliseconds=\(Int(milliseconds.rounded()))")
            #expect(MeshFixtures.triangleCount(mesh) == input.triangles, "\(input.name)")
            #expect(elapsed < .seconds(25), "\(input.name) took \(milliseconds) ms")
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("MESH-PERFORMANCE configuration=\(configuration()) largestInputsProcessPeakResidentMiB=\(Int(usage.ru_maxrss) / 1_048_576)")
    }
}

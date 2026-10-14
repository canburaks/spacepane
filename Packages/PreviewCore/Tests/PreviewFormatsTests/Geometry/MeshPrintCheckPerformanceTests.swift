import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// Records what the shared measurer adds to a mesh request, on the largest meshes the readers admit. The numbers
/// are printed as `MESH-PRINTCHECK-PERFORMANCE` lines for the validation record; the assertions only guard against a
/// regression of an order of magnitude. Run this suite alone and in Release (`swift test -c release
/// -Xswiftc -enable-testing`) for meaningful timings: a Debug build is ten to twenty times slower.
@Suite("Mesh Print Check performance")
struct MeshPrintCheckPerformanceTests {
    private func configuration() -> String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    private func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15).rounded())
    }

    /// Loose triangles on a grid: no vertex is shared, so the output mesh has three positions per triangle (the
    /// most the 32 MiB output allowance admits at this size) and every edge is an open one. Binary STL at 50 bytes
    /// a triangle: 334,000 of them fill the 16 MiB input cap.
    private func triangleSoupSTL(triangles: Int) -> Data {
        var data = Data(repeating: 0x20, count: 80) + MeshFixtures.little32(UInt32(triangles))
        data.reserveCapacity(84 + 50 * triangles)
        func float(_ value: Float) { data += MeshFixtures.little32(value.bitPattern) }
        for triangle in 0..<triangles {
            let x = Float(triangle % 600), y = Float(triangle / 600)
            data += Data(repeating: 0, count: 12)
            for corner in [(x, y, Float(0)), (x + 0.5, y, 0), (x, y + 0.5, 0.25)] {
                float(corner.0); float(corner.1); float(corner.2)
            }
            data += Data([0, 0])
        }
        return data
    }

    @Test func measuresTheLargestAdmittedMeshesWithinTheBudget() throws {
        let budget = PreviewBudget(maxInputBytes: GeometryLimits.maximumInputBytes, maxOutputUTF8Bytes: GeometryLimits.maximumSerializedBytes,
                                   maxJSONNodes: 1_000_000, maxMilliseconds: 30_000)
        let torus = MeshFixtures.torus(segments: 500, sides: 500)
        let torusVertices = torus.vertices.map { SIMD3<Double>(($0.x * 1000).rounded() / 1000, ($0.y * 1000).rounded() / 1000, ($0.z * 1000).rounded() / 1000) }
        let inputs: [(name: String, adapter: any GeometryFormatAdapter, data: Data)] = [
            ("3MF at the triangle ceiling", ThreeMFAdapter(),
             MeshFixtures.threeMF(vertices: torusVertices, triangles: MeshFixtures.triangles(torus.quads))),
            ("STL binary soup at the input cap", STLAdapter(), triangleSoupSTL(triangles: 334_000))]
        for input in inputs {
            #expect(input.data.count <= GeometryLimits.maximumInputBytes, "\(input.name) fixture exceeds the input cap")
            let parseStart = ContinuousClock.now
            let mesh = try input.adapter.parse(FileBytes(data: input.data), context: RequestContext(budget: budget))
            let parseTime = ContinuousClock.now - parseStart
            // The measurer alone on the finished mesh: what the request pays for the facts.
            let measureStart = ContinuousClock.now
            let measured = try GeometryMeasurer.measure(mesh, context: RequestContext(budget: budget))
            let measureTime = ContinuousClock.now - measureStart
            print("MESH-PRINTCHECK-PERFORMANCE configuration=\(configuration()) format=\"\(input.name)\" "
                  + "triangles=\(mesh.indices.count / 3) vertices=\(mesh.positions.count) "
                  + "parseWithMeasurementMilliseconds=\(milliseconds(parseTime)) measureMilliseconds=\(milliseconds(measureTime))")
            // The reader attached the same facts the second measurement computes.
            #expect(mesh.measurements != nil && measured != nil, "\(input.name)")
            #expect(mesh.measurements?.openEdgeCount == measured?.openEdgeCount, "\(input.name)")
            #expect(measureTime < .seconds(25), "\(input.name) measured in \(milliseconds(measureTime)) ms")
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("MESH-PRINTCHECK-PERFORMANCE configuration=\(configuration()) processPeakResidentMiB=\(Int(usage.ru_maxrss) / 1_048_576)")
    }
}

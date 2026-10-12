import Foundation
import Synchronization
import Testing
import zlib
import PreviewContracts
import PreviewCore
import PreviewFormats

/// The mesh formats through the production pipeline: classification, file-type policy, bounded
/// reading, geometry outcomes and failure mapping. Parser behavior has its own suites in
/// PreviewFormatsTests; these tests cover what only the pipeline decides.
@Suite("Mesh formats through the pipeline")
struct MeshPipelineTests {
    private static let secret = "synthetic-mesh-pipeline-secret"

    private final class Counter: Sendable {
        private let value = Mutex(0)
        func increment() { value.withLock { $0 += 1 } }
        var count: Int { value.withLock { $0 } }
    }

    private struct Fixture {
        let directory: URL
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("mesh-pipeline-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        func write(_ name: String, _ data: Data) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url)
            return url
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private let vertices: [SIMD3<Double>] = [[-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1], [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]
    private let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
    private var triangles: [[Int]] { quads.flatMap { [[$0[0], $0[1], $0[2]], [$0[0], $0[2], $0[3]]] } }

    private func le32(_ value: UInt32) -> Data { Data([UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8(value >> 24)]) }
    private func le16(_ value: UInt16) -> Data { Data([UInt8(value & 255), UInt8(value >> 8)]) }

    private func stl() -> Data {
        var data = Data("solid \(Self.secret)".utf8) + Data(repeating: 0x20, count: 80 - "solid \(Self.secret)".utf8.count) + le32(12)
        for triangle in triangles {
            data += Data(repeating: 0, count: 12)
            for index in triangle { for value in [vertices[index].x, vertices[index].y, vertices[index].z] { data += le32(Float(value).bitPattern) } }
            data += Data([0, 0])
        }
        return data
    }

    private func obj() -> Data {
        var text = "# password=\(Self.secret)\nmtllib secret-material.mtl\n"
        for v in vertices { text += "v \(v.x) \(v.y) \(v.z)\n" }
        for face in quads { text += "f " + face.map { String($0 + 1) }.joined(separator: " ") + "\n" }
        return Data(text.utf8)
    }

    private func ply() -> Data {
        var text = "ply\nformat ascii 1.0\ncomment password=\(Self.secret)\nelement vertex 8\nproperty float x\nproperty float y\nproperty float z\nelement face 6\nproperty list uchar int vertex_indices\nend_header\n"
        for v in vertices { text += "\(v.x) \(v.y) \(v.z)\n" }
        for face in quads { text += "4 " + face.map(String.init).joined(separator: " ") + "\n" }
        return Data(text.utf8)
    }

    /// A stored (uncompressed) ZIP holding the minimal 3MF parts.
    private func threeMF() -> Data {
        var model = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><model unit=\"millimeter\" xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\">"
            + "<metadata name=\"Title\">password=\(Self.secret)</metadata><resources><object id=\"1\" type=\"model\"><mesh><vertices>"
        for v in vertices { model += "<vertex x=\"\(v.x)\" y=\"\(v.y)\" z=\"\(v.z)\"/>" }
        model += "</vertices><triangles>"
        for t in triangles { model += "<triangle v1=\"\(t[0])\" v2=\"\(t[1])\" v3=\"\(t[2])\"/>" }
        model += "</triangles></mesh></object></resources><build><item objectid=\"1\"/></build></model>"
        let part = Data(model.utf8)
        let name = Data("3D/3dmodel.model".utf8)
        let checksum = part.withUnsafeBytes { buffer -> UInt32 in
            UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
        let size = UInt32(part.count)
        var archive = Data()
        for piece in [le32(0x04034b50), le16(20), le16(0), le16(0), le16(0), le16(33), le32(checksum), le32(size), le32(size),
                      le16(UInt16(name.count)), le16(0), name, part] { archive.append(piece) }
        let directoryStart = UInt32(archive.count)
        var directory = Data()
        for piece in [le32(0x02014b50), le16(20), le16(20), le16(0), le16(0), le16(0), le16(33), le32(checksum), le32(size), le32(size),
                      le16(UInt16(name.count)), le16(0), le16(0), le16(0), le16(0), le32(0), le32(0), name] { directory.append(piece) }
        archive.append(directory)
        for piece in [le32(0x06054b50), le16(0), le16(0), le16(1), le16(1), le32(UInt32(directory.count)), le32(directoryStart), le16(0)] {
            archive.append(piece)
        }
        return archive
    }

    private var inputs: [(id: FormatID, name: String, data: Data)] {
        [(.meshSTL, "part.stl", stl()), (.meshOBJ, "part.obj", obj()), (.meshPLY, "part.ply", ply()), (.mesh3MF, "part.3mf", threeMF())]
    }

    private var pipeline: PreviewPipeline { PreviewPipeline(registrations: StandardFormatAdapters.registrations) }

    @Test func everyFormatProducesAGeometryOutcomeWithDefaultPreferences() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for input in inputs {
            let url = try fixture.write(input.name, input.data)
            #expect(await pipeline.inspect(url: url) == .enabled(input.id))
            guard case .geometryReady(let presentation) = await pipeline.preview(url: url) else {
                Issue.record("\(input.id.rawValue) did not produce geometry")
                continue
            }
            #expect(presentation.formatID == input.id)
            #expect(presentation.byteCount == input.data.count)
            #expect(presentation.mesh.indices.count == 36)
            #expect(presentation.mesh.bounds.minimum == SIMD3<Double>(-1, -1, -1))
            #expect(presentation.mesh.bounds.maximum == SIMD3<Double>(1, 1, 1))
            #expect(presentation.mesh.outputByteCount <= GeometryLimits.maximumSerializedBytes)
            // Only numbers cross the boundary: no comment, header or title text can reach a view.
            #expect(!String(describing: presentation).contains(Self.secret))
        }
    }

    @Test func aDisabledFormatReturnsBeforeAnyReadOrAdapterConstruction() async throws {
        let constructed = Counter()
        let registrations = MeshFormatAdapters.registrations.map { registration -> AdapterRegistration in
            AdapterRegistration(formatID: registration.formatID, defaultBudget: MeshLimits.requestBudget) {
                constructed.increment()
                return STLAdapter()
            }
        }
        let guarded = PreviewPipeline(registrations: registrations)
        for input in inputs {
            var preferences = PreviewPreferencesSnapshot.defaults
            preferences.setEnabled(false, for: input.id)
            let missing = URL(fileURLWithPath: "/never-read/\(input.name)")
            #expect(await guarded.inspect(url: missing, preferences: preferences) == .disabledByUser(input.id))
            #expect(await guarded.preview(url: missing, preferences: preferences) == .disabledByUser(input.id))
        }
        #expect(constructed.count == 0)
        // Disabling one format leaves the others available.
        let fixture = try Fixture()
        defer { fixture.remove() }
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .meshSTL)
        let other = try fixture.write("part.ply", ply())
        guard case .geometryReady = await pipeline.preview(url: other, preferences: preferences) else {
            Issue.record("Disabling STL must not disable PLY")
            return
        }
    }

    @Test func disablingAFormatNeverFallsBackToTextEvenForTextBasedOBJ() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.write("part.obj", obj())
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(false, for: .meshOBJ)
        #expect(await pipeline.preview(url: url, preferences: preferences) == .disabledByUser(.meshOBJ))
    }

    @Test func theStandardBudgetStillAppliesWhenACallerSuppliesIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let small = try fixture.write("small.stl", stl())
        guard case .geometryReady = await pipeline.preview(url: small, budget: .standard) else {
            Issue.record("A tiny model fits the standard budget")
            return
        }
        // Over the caller's 1 MiB input budget but within the format's own default.
        var big = stl()
        big.replaceSubrange(80..<84, with: le32(UInt32((1_100_000 - 84) / 50)))
        big += Data(repeating: 0, count: 1_100_000 - big.count)
        let large = try fixture.write("large.stl", big)
        #expect(await pipeline.preview(url: large, budget: .standard) == .unavailable(.inputTooLarge))
    }

    @Test func theFormatsOwnDefaultBudgetAdmitsLargeFilesUpToTheContractCap() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // 2 MiB of valid triangles repeated: far beyond the 1 MiB text budget, within the mesh budget.
        let count = (2_097_152 - 84) / 50
        var data = Data(repeating: 0x20, count: 80) + le32(UInt32(count))
        let record = stl().dropFirst(84).prefix(50)
        for _ in 0..<count { data += record }
        let url = try fixture.write("many.stl", data)
        guard case .geometryReady(let presentation) = await pipeline.preview(url: url) else {
            Issue.record("A 2 MiB STL must be within the mesh budget")
            return
        }
        #expect(presentation.byteCount == data.count)
        // One byte over the contract's input cap is refused by the bounded reader.
        let tooLarge = try fixture.write("cap.stl", Data(count: GeometryLimits.maximumInputBytes + 1))
        #expect(await pipeline.preview(url: tooLarge) == .unavailable(.inputTooLarge))
    }

    @Test func aTriangleCeilingFromTheBudgetIsReportedAsTooLarge() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.write("part.obj", obj())
        let budget = PreviewBudget(maxInputBytes: 1_000_000, maxOutputUTF8Bytes: 72 + 143)
        #expect(await pipeline.preview(url: url, budget: budget) == .unavailable(.outputTooLarge))
    }

    @Test func malformedMissingAndNonRegularSourcesFailWithTypedOutcomes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(await pipeline.preview(url: try fixture.write("empty.stl", Data())) == .unavailable(.malformedDocument))
        #expect(await pipeline.preview(url: try fixture.write("junk.ply", Data("not a ply".utf8))) == .unavailable(.malformedDocument))
        #expect(await pipeline.preview(url: try fixture.write("junk.3mf", Data("PK not a zip".utf8))) == .unavailable(.malformedDocument))
        #expect(await pipeline.preview(url: fixture.directory.appendingPathComponent("absent.obj")) == .unavailable(.missingFile))
        let folder = fixture.directory.appendingPathComponent("folder.stl", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        #expect(await pipeline.preview(url: folder) == .unavailable(.notRegularFile))
    }

    @Test func aCancelledRequestReportsCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.write("part.stl", stl())
        let local = pipeline
        let task = Task.detached { await local.preview(url: url) }
        task.cancel()
        let outcome = await task.value
        // Either the request was cancelled first, or it finished before the cancellation landed.
        switch outcome {
        case .cancelled, .geometryReady: break
        default: Issue.record("Unexpected outcome \(outcome)")
        }
    }

    @Test func readingNeverModifiesTheSourceOrTouchesLinkedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.write("part.obj", obj())
        // The material library named by the OBJ exists but is unreadable: any attempt to open it would be an error.
        let library = try fixture.write("secret-material.mtl", Data("newmtl m\nKd 1 0 0\nmap_Kd texture.png\n".utf8))
        let texture = try fixture.write("texture.png", Data([0x89, 0x50]))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: library.path)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: texture.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: library.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: texture.path)
        }
        func snapshot() throws -> [String: Date?] {
            try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).reduce(into: [:]) {
                $0[$1] = try FileManager.default.attributesOfItem(atPath: fixture.directory.appendingPathComponent($1).path)[.modificationDate] as? Date
            }
        }
        let before = try snapshot()
        let bytes = try Data(contentsOf: source)
        guard case .geometryReady = await pipeline.preview(url: source) else {
            Issue.record("OBJ with an unreadable material library must still preview")
            return
        }
        #expect(try snapshot() == before)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).sorted()
                == ["part.obj", "secret-material.mtl", "texture.png"])
    }

    @Test func presentationIdentityIsPerRequest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = try fixture.write("part.stl", stl())
        guard case .geometryReady(let first) = await pipeline.preview(url: url),
              case .geometryReady(let second) = await pipeline.preview(url: url) else {
            Issue.record("Both requests must produce geometry")
            return
        }
        #expect(first != second)
        #expect(first.mesh == second.mesh)
    }
}

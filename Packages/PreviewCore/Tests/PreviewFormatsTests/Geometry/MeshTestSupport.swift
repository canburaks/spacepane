import Foundation
import Testing
import zlib
import PreviewContracts
import PreviewFormats

/// Synthetic meshes and byte-level writers for the mesh-format tests. Everything is built in memory
/// from authored numbers; no model file is read or downloaded.
enum MeshFixtures {
    typealias Vertex = SIMD3<Double>

    /// A fresh context per use: a `RequestContext` carries its deadline from construction, so a shared
    /// static one expires partway through a long parallel test run (seen on the hosted runner).
    static var context: RequestContext { RequestContext(budget: MeshLimits.requestBudget) }
    static func context(budget: PreviewBudget) -> RequestContext { RequestContext(budget: budget) }

    /// An axis-aligned cube centred on the origin, edge length `size`, as twelve triangles.
    static func cube(size: Double = 2) -> (vertices: [Vertex], triangles: [[Int]]) {
        let h = size / 2
        let vertices = [Vertex(-h, -h, -h), Vertex(h, -h, -h), Vertex(h, h, -h), Vertex(-h, h, -h),
                        Vertex(-h, -h, h), Vertex(h, -h, h), Vertex(h, h, h), Vertex(-h, h, h)]
        let quads = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]
        return (vertices, triangles(quads))
    }

    static func torus(segments: Int, sides: Int, major: Double = 10, minor: Double = 4) -> (vertices: [Vertex], quads: [[Int]]) {
        var vertices: [Vertex] = []
        for i in 0..<segments {
            let a = 2 * Double.pi * Double(i) / Double(segments)
            for j in 0..<sides {
                let b = 2 * Double.pi * Double(j) / Double(sides)
                let radius = major + minor * cos(b)
                vertices.append(Vertex(radius * cos(a), radius * sin(a), minor * sin(b)))
            }
        }
        var quads: [[Int]] = []
        for i in 0..<segments {
            for j in 0..<sides {
                let a = i * sides + j, b = ((i + 1) % segments) * sides + j
                let c = ((i + 1) % segments) * sides + (j + 1) % sides, d = i * sides + (j + 1) % sides
                quads.append([a, b, c, d])
            }
        }
        return (vertices, quads)
    }

    static func triangles(_ quads: [[Int]]) -> [[Int]] {
        quads.flatMap { [[$0[0], $0[1], $0[2]], [$0[0], $0[2], $0[3]]] }
    }

    // MARK: Byte writers

    static func little32(_ value: UInt32) -> Data { Data([UInt8(value & 255), UInt8((value >> 8) & 255), UInt8((value >> 16) & 255), UInt8(value >> 24)]) }
    static func little16(_ value: UInt16) -> Data { Data([UInt8(value & 255), UInt8(value >> 8)]) }
    static func big32(_ value: UInt32) -> Data { Data(little32(value).reversed()) }

    static func stlBinary(_ vertices: [Vertex], _ triangles: [[Int]], header: String = "Synthetic binary STL") -> Data {
        var data = Data(header.utf8.prefix(80)) + Data(repeating: 0x20, count: max(0, 80 - header.utf8.count))
        data += little32(UInt32(triangles.count))
        for triangle in triangles {
            data += Data(repeating: 0, count: 12)
            for index in triangle {
                for value in [vertices[index].x, vertices[index].y, vertices[index].z] { data += little32(Float(value).bitPattern) }
            }
            data += Data([0, 0])
        }
        return data
    }

    static func stlASCII(_ vertices: [Vertex], _ triangles: [[Int]], name: String = "synthetic", compact: Bool = false) -> Data {
        var text = "solid \(name)\n"
        for triangle in triangles {
            text += compact ? "facet normal 0 0 0\nouter loop\n" : "  facet normal 0 0 1\n    outer loop\n"
            for index in triangle { text += "vertex \(vertices[index].x) \(vertices[index].y) \(vertices[index].z)\n" }
            text += compact ? "endloop\nendfacet\n" : "    endloop\n  endfacet\n"
        }
        text += "endsolid \(name)\n"
        return Data(text.utf8)
    }

    static func obj(_ vertices: [Vertex], faces: [[Int]], comment: String = "synthetic") -> Data {
        var text = "# \(comment)\nmtllib missing-material-library.mtl\no part\n"
        for v in vertices { text += "v \(v.x) \(v.y) \(v.z)\n" }
        text += "usemtl missing-material\n"
        for face in faces { text += "f " + face.map { String($0 + 1) }.joined(separator: " ") + "\n" }
        return Data(text.utf8)
    }

    static func plyHeader(_ format: String, vertices: Int, faces: Int, extra: String = "") -> String {
        "ply\nformat \(format) 1.0\ncomment synthetic\nelement vertex \(vertices)\nproperty float x\nproperty float y\nproperty float z\n"
        + extra + "element face \(faces)\nproperty list uchar int vertex_indices\nend_header\n"
    }

    static func plyASCII(_ vertices: [Vertex], faces: [[Int]]) -> Data {
        var text = plyHeader("ascii", vertices: vertices.count, faces: faces.count)
        for v in vertices { text += "\(v.x) \(v.y) \(v.z)\n" }
        for face in faces { text += "\(face.count) " + face.map(String.init).joined(separator: " ") + "\n" }
        return Data(text.utf8)
    }

    static func plyBinary(_ vertices: [Vertex], faces: [[Int]], bigEndian: Bool = false) -> Data {
        var data = Data(plyHeader(bigEndian ? "binary_big_endian" : "binary_little_endian", vertices: vertices.count, faces: faces.count).utf8)
        func word(_ value: UInt32) -> Data { bigEndian ? big32(value) : little32(value) }
        for v in vertices { for value in [v.x, v.y, v.z] { data += word(Float(value).bitPattern) } }
        for face in faces {
            data.append(UInt8(face.count))
            for index in face { data += word(UInt32(index)) }
        }
        return data
    }

    // MARK: ZIP and 3MF

    static func rawDeflate(_ data: Data) -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            Issue.record("deflateInit2_ failed")
            return data
        }
        defer { deflateEnd(&stream) }
        var output = Data()
        var input = [UInt8](data)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        input.withUnsafeMutableBufferPointer { source in
            stream.next_in = source.baseAddress
            stream.avail_in = uInt(source.count)
            var status: Int32 = Z_OK
            while status != Z_STREAM_END {
                buffer.withUnsafeMutableBufferPointer { target in
                    stream.next_out = target.baseAddress
                    stream.avail_out = uInt(target.count)
                    status = deflate(&stream, Z_FINISH)
                    output.append(target.baseAddress!, count: target.count - Int(stream.avail_out))
                }
                if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR { break }
            }
        }
        return output
    }

    static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer -> UInt32 in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return 0 }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
    }

    static func zip(_ entries: [(name: String, data: Data)], deflate: Bool = true) -> Data {
        var output = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let payload = deflate ? rawDeflate(entry.data) : entry.data
            let method: UInt16 = deflate ? 8 : 0
            let offset = UInt32(output.count)
            let checksum = crc32(entry.data)
            var local = little32(0x04034b50) + little16(20) + little16(0) + little16(method) + little16(0) + little16(33)
            local += little32(checksum) + little32(UInt32(payload.count)) + little32(UInt32(entry.data.count))
            local += little16(UInt16(name.count)) + little16(0) + name
            output += local + payload
            var central = little32(0x02014b50) + little16(20) + little16(20) + little16(0) + little16(method) + little16(0) + little16(33)
            central += little32(checksum) + little32(UInt32(payload.count)) + little32(UInt32(entry.data.count))
            central += little16(UInt16(name.count)) + little16(0) + little16(0) + little16(0) + little16(0) + little32(0) + little32(offset) + name
            directory += central
        }
        let start = UInt32(output.count)
        output += directory
        output += little32(0x06054b50) + little16(0) + little16(0) + little16(UInt16(entries.count)) + little16(UInt16(entries.count))
        output += little32(UInt32(directory.count)) + little32(start) + little16(0)
        return output
    }

    static let coreNamespace = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    static let productionNamespace = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"

    static func meshObject(id: Int, vertices: [Vertex], triangles: [[Int]], type: String = "model") -> String {
        var xml = "<object id=\"\(id)\" type=\"\(type)\"><mesh><vertices>"
        for v in vertices { xml += "<vertex x=\"\(v.x)\" y=\"\(v.y)\" z=\"\(v.z)\"/>" }
        xml += "</vertices><triangles>"
        for t in triangles { xml += "<triangle v1=\"\(t[0])\" v2=\"\(t[1])\" v3=\"\(t[2])\"/>" }
        return xml + "</triangles></mesh></object>"
    }

    static func modelXML(unit: String? = "millimeter", resources: String, build: String,
                         extraNamespaces: String = "", doctype: String = "") -> String {
        let unitAttribute = unit.map { " unit=\"\($0)\"" } ?? ""
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\(doctype)<model\(unitAttribute) xmlns=\"\(coreNamespace)\"\(extraNamespaces)>"
            + "<resources>\(resources)</resources><build>\(build)</build></model>"
    }

    static let relationships = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        + "<Relationship Target=\"/3D/3dmodel.model\" Id=\"rel0\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\"/></Relationships>"

    static func threeMF(model: String, relationships: String? = MeshFixtures.relationships,
                        extraParts: [(name: String, data: Data)] = [], deflate: Bool = true) -> Data {
        var entries: [(name: String, data: Data)] = [("[Content_Types].xml", Data("<Types/>".utf8))]
        if let relationships { entries.append(("_rels/.rels", Data(relationships.utf8))) }
        entries.append(("3D/3dmodel.model", Data(model.utf8)))
        return zip(entries + extraParts, deflate: deflate)
    }

    static func threeMF(vertices: [Vertex], triangles: [[Int]], unit: String? = "millimeter") -> Data {
        threeMF(model: modelXML(unit: unit, resources: meshObject(id: 1, vertices: vertices, triangles: triangles),
                                build: "<item objectid=\"1\"/>"))
    }

    // MARK: Mesh inspection

    /// Dimensions of the physical bounds in millimetres.
    static func extent(_ mesh: PreviewMesh) -> SIMD3<Double> { mesh.bounds.maximum - mesh.bounds.minimum }
    static func triangleCount(_ mesh: PreviewMesh) -> Int { mesh.indices.count / 3 }

    /// Every invariant the viewer relies on, checked independently of `PreviewMesh`'s own initializer.
    static func expectWellFormed(_ mesh: PreviewMesh, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(mesh.positions.count == mesh.normals.count, sourceLocation: sourceLocation)
        #expect(mesh.indices.count.isMultiple(of: 3), sourceLocation: sourceLocation)
        #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, sourceLocation: sourceLocation)
        #expect(mesh.positions.allSatisfy { abs($0.x) <= 1.0001 && abs($0.y) <= 1.0001 && abs($0.z) <= 1.0001 }, sourceLocation: sourceLocation)
        #expect(mesh.normals.allSatisfy { abs(($0.x * $0.x + $0.y * $0.y + $0.z * $0.z) - 1) < 1e-3 }, sourceLocation: sourceLocation)
        #expect(mesh.faceCount > 0 && mesh.faceCount <= GeometryLimits.maximumFaces, sourceLocation: sourceLocation)
        // The longest side spans the normalized extent of two.
        let largest = mesh.positions.reduce(0 as Float) { max($0, abs($1.x), abs($1.y), abs($1.z)) }
        #expect(largest > 0.999, sourceLocation: sourceLocation)
    }
}

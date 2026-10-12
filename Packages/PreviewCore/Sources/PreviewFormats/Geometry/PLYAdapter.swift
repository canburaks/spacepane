import Foundation
import PreviewContracts

/// Stanford PLY in its three encodings (`ascii`, `binary_little_endian`, `binary_big_endian`).
/// Vertex `x`, `y` and `z` may use any scalar type; faces come from a `vertex_indices` or
/// `vertex_index` list of triangles or polygons (fan-triangulated). Every other element and property
/// (normals, colours, texture coordinates, edges, strips, user data) is skipped by size or token
/// without being interpreted. PLY has no units, so coordinates are taken as millimetres and the mesh
/// says its unit is `.undeclared` (see `STLAdapter`).
public struct PLYAdapter: GeometryFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        try context.checkpoint()
        let allowance = MeshAllowance(context)
        guard input.data.count <= allowance.inputBytes else { throw PreviewFailure.inputTooLarge }
        let mesh = try input.data.withUnsafeBytes { raw -> TriangleMesh in
            let bytes = raw.bindMemory(to: UInt8.self)
            let header = try PLYHeader.read(bytes, allowance: allowance, context: context)
            switch header.encoding {
            case .ascii:
                var source = ASCIIPLYSource(scanner: ASCIIScanner(bytes, position: header.dataOffset))
                return try Self.readElements(&source, header: header, allowance: allowance, context: context)
            case .littleEndian, .bigEndian:
                var source = BinaryPLYSource(raw: raw, offset: header.dataOffset, bigEndian: header.encoding == .bigEndian)
                return try Self.readElements(&source, header: header, allowance: allowance, context: context)
            }
        }
        return try MeshBuilder.makePreviewMesh(mesh, context: context)
    }

    private static func readElements<Source: PLYValueSource>(_ source: inout Source, header: PLYHeader,
                                                             allowance: MeshAllowance,
                                                             context: RequestContext) throws -> TriangleMesh {
        var positions = [SIMD3<Double>]()
        var indices = [UInt32]()
        var faceCount = 0
        let vertexCount = header.elements.first { $0.name == "vertex" }?.count ?? 0
        for element in header.elements {
            switch element.name {
            case "vertex":
                var slots = [Int](repeating: -1, count: element.properties.count)
                for (axis, name) in ["x", "y", "z"].enumerated() {
                    guard let index = element.properties.firstIndex(where: { $0.name == name }),
                          case .scalar = element.properties[index].kind, slots[index] < 0 else {
                        throw PreviewFailure.malformedDocument
                    }
                    slots[index] = axis
                }
                positions.reserveCapacity(element.count)
                for row in 0..<element.count {
                    if row & 0xFFF == 0 { try context.checkpoint() }
                    var position = SIMD3<Double>()
                    for (index, property) in element.properties.enumerated() {
                        switch property.kind {
                        case .scalar(let type):
                            if slots[index] >= 0 {
                                let value = try source.scalar(type)
                                guard value.isFinite else { throw PreviewFailure.malformedDocument }
                                position[slots[index]] = value
                            } else {
                                try source.skip(type, count: 1)
                            }
                        case .list(let countType, let itemType):
                            let length = try source.integer(countType)
                            try source.skip(itemType, count: length)
                        }
                    }
                    positions.append(position)
                }
            case "face":
                let listIndex = element.properties.firstIndex { property in
                    guard case .list = property.kind else { return false }
                    return property.name == "vertex_indices" || property.name == "vertex_index"
                }
                var polygon = [Int]()
                for row in 0..<element.count {
                    if row & 0xFFF == 0 { try context.checkpoint() }
                    for (index, property) in element.properties.enumerated() {
                        switch property.kind {
                        case .scalar(let type):
                            try source.skip(type, count: 1)
                        case .list(let countType, let itemType):
                            let length = try source.integer(countType)
                            guard length >= 0 else { throw PreviewFailure.malformedDocument }
                            guard index == listIndex else { try source.skip(itemType, count: length); continue }
                            guard length >= 3 else { throw PreviewFailure.malformedDocument }
                            guard length <= allowance.triangles + 2,
                                  indices.count / 3 + length - 2 <= allowance.triangles else { throw allowance.triangleOverflow }
                            polygon.removeAll(keepingCapacity: true)
                            for _ in 0..<length {
                                let vertex = try source.integer(itemType)
                                guard vertex >= 0, vertex < vertexCount else { throw PreviewFailure.malformedDocument }
                                polygon.append(vertex)
                            }
                            faceCount += 1
                            for k in 1..<(length - 1) {
                                indices.append(UInt32(polygon[0]))
                                indices.append(UInt32(polygon[k]))
                                indices.append(UInt32(polygon[k + 1]))
                            }
                        }
                    }
                }
            default:
                try Self.skip(element, from: &source, context: context)
            }
        }
        guard !positions.isEmpty else { throw PreviewFailure.malformedDocument }
        // A point cloud, or a file whose faces carry no index list, has no surface to draw.
        guard faceCount > 0 else { throw PreviewFailure.unsupportedFormat }
        return TriangleMesh(positions: positions, indices: indices, faceCount: faceCount, unitProvenance: .undeclared)
    }

    private static func skip<Source: PLYValueSource>(_ element: PLYHeader.Element, from source: inout Source,
                                                     context: RequestContext) throws {
        // An element with no properties occupies no data, however large its declared count.
        guard !element.properties.isEmpty else { return }
        for row in 0..<element.count {
            if row & 0xFFF == 0 { try context.checkpoint() }
            for property in element.properties {
                switch property.kind {
                case .scalar(let type): try source.skip(type, count: 1)
                case .list(let countType, let itemType):
                    let length = try source.integer(countType)
                    guard length >= 0 else { throw PreviewFailure.malformedDocument }
                    try source.skip(itemType, count: length)
                }
            }
        }
    }
}

enum PLYScalarType {
    case int8, uint8, int16, uint16, int32, uint32, float32, float64

    init?(name: Substring) {
        switch name {
        case "char", "int8": self = .int8
        case "uchar", "uint8": self = .uint8
        case "short", "int16": self = .int16
        case "ushort", "uint16": self = .uint16
        case "int", "int32": self = .int32
        case "uint", "uint32": self = .uint32
        case "float", "float32": self = .float32
        case "double", "float64": self = .float64
        default: return nil
        }
    }

    var size: Int {
        switch self {
        case .int8, .uint8: 1
        case .int16, .uint16: 2
        case .int32, .uint32, .float32: 4
        case .float64: 8
        }
    }
}

struct PLYHeader {
    enum Encoding { case ascii, littleEndian, bigEndian }
    enum PropertyKind {
        case scalar(PLYScalarType)
        case list(count: PLYScalarType, item: PLYScalarType)
    }
    struct Property {
        let name: String
        let kind: PropertyKind
    }
    struct Element {
        let name: String
        let count: Int
        var properties: [Property] = []
    }

    static let maximumHeaderBytes = 65_536
    static let maximumLineBytes = 4_096
    static let maximumElements = 32
    static let maximumProperties = 64

    let encoding: Encoding
    let elements: [Element]
    let dataOffset: Int

    static func read(_ bytes: UnsafeBufferPointer<UInt8>, allowance: MeshAllowance, context: RequestContext) throws -> PLYHeader {
        var position = 0
        func nextLine() throws -> String {
            let limit = min(bytes.count, maximumHeaderBytes, position + maximumLineBytes)
            var end = position
            while end < limit, bytes[end] != 0x0A { end += 1 }
            guard end < limit, bytes[end] == 0x0A else { throw PreviewFailure.malformedDocument }
            let lineEnd = end > position && bytes[end - 1] == 0x0D ? end - 1 : end
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[position..<lineEnd]), as: UTF8.self)
            position = end + 1
            return text
        }
        guard try nextLine() == "ply" else { throw PreviewFailure.malformedDocument }
        var encoding: Encoding?
        var elements: [Element] = []
        var lines = 0
        let maximumLines = min(4_096, context.budget.maxJSONNodes)
        while true {
            lines += 1
            guard lines <= maximumLines else { throw PreviewFailure.tooManyNodes }
            let line = try nextLine()
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = parts.first else { continue }
            switch keyword {
            case "format":
                guard encoding == nil, parts.count >= 2 else { throw PreviewFailure.malformedDocument }
                switch parts[1] {
                case "ascii": encoding = .ascii
                case "binary_little_endian": encoding = .littleEndian
                case "binary_big_endian": encoding = .bigEndian
                default: throw PreviewFailure.unsupportedFormat
                }
            case "comment", "obj_info":
                continue
            case "element":
                guard encoding != nil, parts.count == 3, elements.count < maximumElements,
                      let declared = UInt64(parts[2]), declared <= 1 << 40 else { throw PreviewFailure.malformedDocument }
                let name = String(parts[1])
                guard !elements.contains(where: { $0.name == name }) else { throw PreviewFailure.malformedDocument }
                let count = Int(declared)
                if name == "vertex", count > allowance.vertices { throw allowance.vertexOverflow }
                if name == "face", count > allowance.triangles { throw allowance.triangleOverflow }
                elements.append(Element(name: name, count: count))
            case "property":
                guard var element = elements.popLast(), element.properties.count < maximumProperties else {
                    throw PreviewFailure.malformedDocument
                }
                if parts.count == 5, parts[1] == "list" {
                    guard let countType = PLYScalarType(name: parts[2]), let itemType = PLYScalarType(name: parts[3]) else {
                        throw PreviewFailure.unsupportedFormat
                    }
                    element.properties.append(Property(name: String(parts[4]), kind: .list(count: countType, item: itemType)))
                } else if parts.count == 3 {
                    guard let type = PLYScalarType(name: parts[1]) else { throw PreviewFailure.unsupportedFormat }
                    element.properties.append(Property(name: String(parts[2]), kind: .scalar(type)))
                } else {
                    throw PreviewFailure.malformedDocument
                }
                elements.append(element)
            case "end_header":
                guard let encoding else { throw PreviewFailure.malformedDocument }
                let header = PLYHeader(encoding: encoding, elements: elements, dataOffset: position)
                try header.validateDataSize(available: bytes.count - position)
                return header
            default:
                throw PreviewFailure.malformedDocument
            }
        }
    }

    /// Rejects a header whose declared rows cannot fit in the file, before any row storage is
    /// reserved or any loop runs. Binary rows have a known minimum size; ASCII values need at least
    /// two bytes each (a digit and a separator).
    private func validateDataSize(available: Int) throws {
        var minimum = 0
        for element in elements {
            let perRow: Int
            switch encoding {
            case .ascii:
                perRow = element.properties.count * 2
            case .littleEndian, .bigEndian:
                perRow = element.properties.reduce(0) { total, property in
                    switch property.kind {
                    case .scalar(let type): total + type.size
                    case .list(let countType, _): total + countType.size
                    }
                }
            }
            let (product, overflow) = element.count.multipliedReportingOverflow(by: perRow)
            let (sum, sumOverflow) = minimum.addingReportingOverflow(product)
            guard !overflow, !sumOverflow, sum <= available else { throw PreviewFailure.malformedDocument }
            minimum = sum
        }
    }
}

/// Reads PLY values in one encoding. `skip` consumes values without interpreting them, so unused
/// properties never need to be well-formed numbers.
protocol PLYValueSource {
    mutating func scalar(_ type: PLYScalarType) throws -> Double
    mutating func integer(_ type: PLYScalarType) throws -> Int
    mutating func skip(_ type: PLYScalarType, count: Int) throws
}

struct ASCIIPLYSource: PLYValueSource {
    var scanner: ASCIIScanner

    mutating func scalar(_ type: PLYScalarType) throws -> Double {
        guard let token = scanner.token(), let value = scanner.double(token) else { throw PreviewFailure.malformedDocument }
        return value
    }

    mutating func integer(_ type: PLYScalarType) throws -> Int {
        guard let token = scanner.token(), let value = scanner.integer(token) else { throw PreviewFailure.malformedDocument }
        return value
    }

    mutating func skip(_ type: PLYScalarType, count: Int) throws {
        guard count >= 0 else { throw PreviewFailure.malformedDocument }
        for _ in 0..<count { guard scanner.token() != nil else { throw PreviewFailure.malformedDocument } }
    }
}

struct BinaryPLYSource: PLYValueSource {
    let raw: UnsafeRawBufferPointer
    var offset: Int
    let bigEndian: Bool

    private func unsigned16(_ at: Int) -> UInt16 {
        let value = raw.loadUnaligned(fromByteOffset: at, as: UInt16.self)
        return bigEndian ? UInt16(bigEndian: value) : UInt16(littleEndian: value)
    }
    private func unsigned32(_ at: Int) -> UInt32 {
        let value = raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)
        return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
    }
    private func unsigned64(_ at: Int) -> UInt64 {
        let value = raw.loadUnaligned(fromByteOffset: at, as: UInt64.self)
        return bigEndian ? UInt64(bigEndian: value) : UInt64(littleEndian: value)
    }

    mutating func scalar(_ type: PLYScalarType) throws -> Double {
        guard type.size <= raw.count - offset else { throw PreviewFailure.malformedDocument }
        defer { offset += type.size }
        switch type {
        case .int8: return Double(Int8(bitPattern: raw[offset]))
        case .uint8: return Double(raw[offset])
        case .int16: return Double(Int16(bitPattern: unsigned16(offset)))
        case .uint16: return Double(unsigned16(offset))
        case .int32: return Double(Int32(bitPattern: unsigned32(offset)))
        case .uint32: return Double(unsigned32(offset))
        case .float32: return Double(Float(bitPattern: unsigned32(offset)))
        case .float64: return Double(bitPattern: unsigned64(offset))
        }
    }

    mutating func integer(_ type: PLYScalarType) throws -> Int {
        guard type.size <= raw.count - offset else { throw PreviewFailure.malformedDocument }
        defer { offset += type.size }
        switch type {
        case .int8: return Int(Int8(bitPattern: raw[offset]))
        case .uint8: return Int(raw[offset])
        case .int16: return Int(Int16(bitPattern: unsigned16(offset)))
        case .uint16: return Int(unsigned16(offset))
        case .int32: return Int(Int32(bitPattern: unsigned32(offset)))
        case .uint32: return Int(unsigned32(offset))
        // List lengths and vertex indices are integers by definition.
        case .float32, .float64: throw PreviewFailure.malformedDocument
        }
    }

    mutating func skip(_ type: PLYScalarType, count: Int) throws {
        guard count >= 0 else { throw PreviewFailure.malformedDocument }
        let (bytes, overflow) = count.multipliedReportingOverflow(by: type.size)
        guard !overflow, bytes <= raw.count - offset else { throw PreviewFailure.malformedDocument }
        offset += bytes
    }
}

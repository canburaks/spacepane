import Foundation
import PreviewContracts

/// 3D Manufacturing Format: an Open Packaging Convention ZIP whose model part holds objects with
/// meshes, component lists with transforms, and a build list. The model part is the target of the
/// `_rels/.rels` relationship ending `/3dmodel`, or `3D/3dmodel.model`. Build items and components
/// compose their 3x4 transforms; component cycles, excessive depth and excessive instancing are
/// refused. Slicer packages that keep objects in other model parts of the same archive (the
/// production extension's `path` attribute) are followed, and only inside the archive. Colours,
/// materials, textures, thumbnails, slicer settings and other extensions are ignored, and support
/// objects are not drawn. Coordinates are converted from the model's `unit` to millimetres. The mesh
/// carries where that unit came from: `.declared` when the model names it, `.assumedMillimetres` when it
/// omits the attribute and the specification's default applies.
public struct ThreeMFAdapter: GeometryFormatAdapter {
    public init() {}

    static let defaultModelPath = "3D/3dmodel.model"
    static let relationshipsPath = "_rels/.rels"
    static let maximumRelationshipsBytes = 1_048_576
    static let maximumModelParts = 32
    static let maximumComponentDepth = 32
    static let maximumInstances = 100_000

    public func parse(_ input: FileBytes, context: RequestContext) throws -> PreviewMesh {
        try context.checkpoint()
        let allowance = MeshAllowance(context)
        guard input.data.count <= allowance.inputBytes else { throw PreviewFailure.inputTooLarge }
        let source = MemoryByteSource(data: input.data)
        let archive = try ZIPArchiveReader.read(source, context: context)
        var assembler = ThreeMFAssembler(archive: archive, source: source, context: context, allowance: allowance)
        return try MeshBuilder.makePreviewMesh(try assembler.assemble(), context: context)
    }
}

private struct ThreeMFAssembler {
    let archive: ZIPArchive
    let source: MemoryByteSource
    let context: RequestContext
    let allowance: MeshAllowance
    private var remainingBytes: Int
    private var remainingNodes: Int
    private var remainingVertices: Int
    private var remainingTriangles: Int
    private var parts: [String: ThreeMFModelParser] = [:]
    private var positions: [SIMD3<Double>] = []
    private var indices: [UInt32] = []
    private var scale = 1.0
    private var unitProvenance = GeometryUnitProvenance.undeclared
    private var instances = 0

    private struct VisitKey: Hashable {
        let part: String
        let identifier: Int
    }

    init(archive: ZIPArchive, source: MemoryByteSource, context: RequestContext, allowance: MeshAllowance) {
        self.archive = archive
        self.source = source
        self.context = context
        self.allowance = allowance
        remainingBytes = ContainerLimits(context: context).maxDecodedBytes
        remainingNodes = context.budget.maxJSONNodes
        remainingVertices = allowance.vertices
        remainingTriangles = allowance.triangles
    }

    mutating func assemble() throws -> TriangleMesh {
        let rootPath = try locateModelPart()
        let root = try part(at: rootPath)
        // The unit applies to every part: parts that omit it must not fall back to millimetres.
        guard let unit = ThreeMFUnit(rawValue: root.unit ?? ThreeMFUnit.millimeter.rawValue) else {
            throw PreviewFailure.malformedDocument
        }
        scale = unit.millimetres
        // The unit applies to every part, so the root model's attribute decides what the file declared.
        unitProvenance = root.unit == nil ? .assumedMillimetres : .declared(unit.lengthUnit)
        var items = root.items
        if items.isEmpty {
            // No build list: draw every object that no component refers to.
            let referenced = Set(root.objects.values.flatMap { $0.components.filter { $0.path == nil }.map(\.objectID) })
            items = root.objectOrder.filter { !referenced.contains($0) }
                .map { ThreeMFModelParser.Item(objectID: $0, path: nil, transform: .identity) }
        }
        var active = Set<VisitKey>()
        for item in items {
            let itemPath: String
            if let declared = item.path {
                guard let found = entryPath(declared) else { throw PreviewFailure.malformedDocument }
                itemPath = found
            } else {
                itemPath = rootPath
            }
            try instantiate(partPath: itemPath, identifier: item.objectID, transform: item.transform, depth: 0, active: &active)
        }
        guard !indices.isEmpty else { throw PreviewFailure.malformedDocument }
        return TriangleMesh(positions: positions, indices: indices, faceCount: indices.count / 3, unitProvenance: unitProvenance)
    }

    // MARK: Package parts

    private func normalized(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    /// The archive path of an existing member, matched exactly and then ignoring case (OPC part
    /// names are case-insensitive).
    private func entryPath(_ path: String) -> String? {
        let wanted = normalized(path)
        if archive.entry(at: wanted) != nil { return wanted }
        return archive.entries.first { $0.path.caseInsensitiveCompare(wanted) == .orderedSame }?.path
    }

    private mutating func locateModelPart() throws -> String {
        var target = ThreeMFAdapter.defaultModelPath
        if let relationships = entryPath(ThreeMFAdapter.relationshipsPath), let entry = archive.entry(at: relationships) {
            let data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: ThreeMFAdapter.maximumRelationshipsBytes,
                                                       context: context)
            let parser = ThreeMFRelationshipsParser(context: context, nodeAllowance: 4_096)
            try parser.run(data)
            if let declared = parser.modelTarget { target = declared }
        }
        guard let path = entryPath(target) else { throw PreviewFailure.malformedDocument }
        return path
    }

    private mutating func part(at path: String) throws -> ThreeMFModelParser {
        if let cached = parts[path] { return cached }
        guard parts.count < ThreeMFAdapter.maximumModelParts else { throw PreviewFailure.tooManyNodes }
        guard let entry = archive.entry(at: path) else { throw PreviewFailure.malformedDocument }
        // The declared size is checked against the remaining allowance before any byte is inflated.
        let data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: remainingBytes, context: context)
        remainingBytes -= data.count
        let parser = ThreeMFModelParser(context: context, nodeAllowance: remainingNodes,
                                        vertexAllowance: remainingVertices, triangleAllowance: remainingTriangles,
                                        triangleOverflow: allowance.triangleOverflow)
        try parser.run(data)
        guard parser.sawModel else { throw PreviewFailure.malformedDocument }
        remainingNodes -= parser.nodes
        remainingVertices -= parser.vertices.count
        remainingTriangles -= parser.triangleCount
        parts[path] = parser
        return parser
    }

    // MARK: Instantiation

    private mutating func instantiate(partPath: String, identifier: Int, transform: ThreeMFTransform, depth: Int,
                                      active: inout Set<VisitKey>) throws {
        instances += 1
        guard instances <= ThreeMFAdapter.maximumInstances else { throw PreviewFailure.tooManyNodes }
        guard depth <= min(ThreeMFAdapter.maximumComponentDepth, context.budget.maxJSONDepth) else {
            throw PreviewFailure.structureTooDeep
        }
        if instances & 0xFF == 0 { try context.checkpoint() }
        let model = try part(at: partPath)
        guard let object = model.objects[identifier] else { throw PreviewFailure.malformedDocument }
        let key = VisitKey(part: partPath, identifier: identifier)
        // An object that contains itself, directly or through other objects, has no finite geometry.
        guard active.insert(key).inserted else { throw PreviewFailure.malformedDocument }
        defer { active.remove(key) }
        // Support structures are not part of the finished object.
        guard object.type != "support", object.type != "solidsupport" else { return }
        if !object.triangleRange.isEmpty {
            guard positions.count + object.vertexRange.count <= allowance.vertices else { throw allowance.vertexOverflow }
            guard indices.count / 3 + object.triangleRange.count <= allowance.triangles else { throw allowance.triangleOverflow }
            let base = UInt32(positions.count)
            for (offset, vertex) in model.vertices[object.vertexRange].enumerated() {
                if offset & 0xFFFF == 0 { try context.checkpoint() }
                positions.append(transform.apply(vertex) * scale)
            }
            for slot in (object.triangleRange.lowerBound * 3)..<(object.triangleRange.upperBound * 3) {
                indices.append(base + model.triangles[slot])
            }
        }
        for component in object.components {
            let childPath: String
            if let declared = component.path {
                guard let found = entryPath(declared) else { throw PreviewFailure.malformedDocument }
                childPath = found
            } else {
                childPath = partPath
            }
            try instantiate(partPath: childPath, identifier: component.objectID,
                            transform: component.transform.then(transform), depth: depth + 1, active: &active)
        }
    }
}

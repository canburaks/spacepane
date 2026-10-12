import Foundation
import PreviewContracts

/// Registrations for the pure-Swift triangle-mesh readers (STL, OBJ, PLY, 3MF). They return the
/// neutral `PreviewMesh` that the CAD importers also produce, so hosts and the native Metal viewer
/// need no per-suffix code. Every reader works on the bounded bytes the pipeline already read: it
/// never opens a sibling file, so material libraries and textures are not read.
public enum MeshFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .meshSTL, defaultBudget: MeshLimits.requestBudget) { STLAdapter() },
        AdapterRegistration(formatID: .meshOBJ, defaultBudget: MeshLimits.requestBudget) { OBJAdapter() },
        AdapterRegistration(formatID: .meshPLY, defaultBudget: MeshLimits.requestBudget) { PLYAdapter() },
        AdapterRegistration(formatID: .mesh3MF, defaultBudget: MeshLimits.requestBudget) { ThreeMFAdapter() }
    ]
}

/// Request budget and the limits derived from it. The geometry contract's own caps always apply; a
/// caller-supplied budget can only lower them.
public enum MeshLimits {
    /// Mesh readers parse in process, so the deadline is shorter than the CAD helper's. The node
    /// allowance is for 3MF's XML elements: one per vertex and per triangle.
    public static let requestBudget = PreviewBudget(
        maxInputBytes: GeometryLimits.maximumInputBytes,
        maxOutputUTF8Bytes: GeometryLimits.maximumSerializedBytes,
        maxJSONDepth: 64, maxJSONNodes: 1_000_000, maxMilliseconds: 10_000)
    /// Triangles the shared contract can carry (three indices each).
    public static let maximumTriangles = GeometryLimits.maximumIndices / 3
}

/// Per-request ceilings, checked before any allocation they bound.
struct MeshAllowance {
    let inputBytes: Int
    let outputBytes: Int
    /// A triangle costs at least three four-byte indices in the output, whatever the vertex sharing.
    let triangles: Int
    let vertices: Int
    init(_ context: RequestContext) {
        inputBytes = min(context.budget.maxInputBytes, GeometryLimits.maximumInputBytes)
        outputBytes = min(context.budget.maxOutputUTF8Bytes, GeometryLimits.maximumSerializedBytes)
        triangles = min(MeshLimits.maximumTriangles, max(0, outputBytes - 72) / 12)
        // Source vertices the readers may hold. Unreferenced ones are dropped before output.
        vertices = GeometryLimits.maximumVertices
    }

    /// The failure for more triangles than `triangles`. At the contract's own ceiling the model is too complex
    /// for the viewer (`geometryTooComplex`); below it the caller lowered the output budget, which stays an
    /// output-size failure, so a message about the model's geometry never blames a budget (decision 027, Q-11).
    var triangleOverflow: PreviewFailure {
        triangles >= MeshLimits.maximumTriangles ? .geometryTooComplex : .outputTooLarge
    }

    /// The failure for more source vertices than `vertices`, which is always the contract's own ceiling.
    var vertexOverflow: PreviewFailure { .geometryTooComplex }

    /// The failure for output that does not fit `outputBytes`, by the same rule as `triangleOverflow`.
    var outputOverflow: PreviewFailure {
        outputBytes >= GeometryLimits.maximumSerializedBytes ? .geometryTooComplex : .outputTooLarge
    }
}

/// A read-only view of bytes that are already in memory, for the shared ZIP reader. No cumulative
/// read accounting: the bytes were bounded when the pipeline read the file.
struct MemoryByteSource: PreviewByteSource {
    let data: Data
    var byteCount: Int64 { Int64(data.count) }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard offset >= 0, count >= 0, offset <= byteCount, Int64(count) <= byteCount - offset else {
            throw PreviewFailure.malformedDocument
        }
        let start = data.startIndex + Int(offset)
        return data.subdata(in: start..<(start + count))
    }
}

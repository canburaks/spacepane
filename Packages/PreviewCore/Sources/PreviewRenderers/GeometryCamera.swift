import Foundation
import PreviewContracts
import simd

enum GeometryStandardView { case front, side, top }

/// Which model axis points up on screen. A model file does not record its own convention, so this is a per-format
/// default and a per-view choice that is never persisted (decision 027, Q-80, and owner decision D-3D): STL and 3MF
/// follow 3D printing and point Z up; OBJ, PLY, STEP and IGES stay Y up until real files show otherwise.
enum GeometryUpAxis: Equatable, Sendable {
    case y, z

    /// The default for a format; any format without a convention of its own is Y up.
    static func conventional(for formatID: FormatID) -> GeometryUpAxis {
        switch formatID {
        case .meshSTL, .mesh3MF: .z
        default: .y
        }
    }

    var toggled: GeometryUpAxis { self == .y ? .z : .y }

    /// The axis's technical name. An axis name is not translated, so it is defined once, here.
    var letter: String { self == .y ? "Y" : "Z" }

    /// A direction of the camera's world, whose up is +Y and whose viewer looks along -Z, in the model's own axes.
    /// Z up turns the model a quarter turn about X, so the model's +Z is the world's +Y and the model's -Y faces the viewer.
    func modelDirection(forWorld world: SIMD3<Float>) -> SIMD3<Float> {
        switch self {
        case .y: world
        case .z: SIMD3<Float>(world.x, -world.z, world.y)
        }
    }
}

/// Camera state contains no document data or GPU objects.
struct GeometryCamera: Equatable {
    private(set) var yaw: Float = .pi / 4
    private(set) var pitch: Float = .pi / 6
    private(set) var panOffset = SIMD2<Float>.zero
    private(set) var distance: Float = 5
    /// The model axis that points up on screen. The standard views and the default angle follow it, so Front shows
    /// a Z-up model from the front and Top from above, whichever axis the file's convention makes vertical.
    private(set) var upAxis: GeometryUpAxis
    private let boundingRadius: Float

    private static let halfFieldOfView: Float = .pi / 8
    private static let pitchLimit: Float = .pi / 2 - 0.01

    init(boundingRadius: Float = sqrt(3), upAxis: GeometryUpAxis = .y) {
        self.boundingRadius = boundingRadius.isFinite ? min(max(boundingRadius, 1), sqrt(3)) : sqrt(3)
        self.upAxis = upAxis
    }

    mutating func orbit(delta: SIMD2<Float>) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        yaw = (yaw + delta.x * 0.008).truncatingRemainder(dividingBy: .pi * 2)
        pitch = min(max(pitch + delta.y * 0.008, -Self.pitchLimit), Self.pitchLimit)
    }

    mutating func pan(delta: SIMD2<Float>, viewport: CGSize) {
        guard delta.x.isFinite, delta.y.isFinite, viewport.height.isFinite, viewport.height > 0 else { return }
        let scale = 2 * distance * tan(Self.halfFieldOfView) / Float(viewport.height)
        let next = panOffset + SIMD2<Float>(delta.x, -delta.y) * scale
        guard next.x.isFinite, next.y.isFinite else { return }
        panOffset = simd_clamp(next, SIMD2<Float>(repeating: -10_000), SIMD2<Float>(repeating: 10_000))
    }

    mutating func zoom(by factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        distance = min(max(distance * factor, 0.2), 10_000)
    }

    mutating func fit(viewport: CGSize) {
        let aspect = Self.aspect(viewport)
        let limitingAngle = min(Self.halfFieldOfView, atan(tan(Self.halfFieldOfView) * aspect))
        // The enclosing sphere fits after any orbit without scanning mesh vertices.
        distance = min(boundingRadius * 1.1 / sin(limitingAngle), 10_000)
        panOffset = .zero
    }

    mutating func reset(viewport: CGSize) {
        yaw = .pi / 4; pitch = .pi / 6
        fit(viewport: viewport)
    }

    /// Turns the model to stand on another axis. The angles that suited the old axis mean nothing for the new one,
    /// so the view starts again from the default angle, fitted.
    mutating func setUpAxis(_ axis: GeometryUpAxis, viewport: CGSize) {
        upAxis = axis
        reset(viewport: viewport)
    }

    mutating func preset(_ view: GeometryStandardView, viewport: CGSize) {
        switch view {
        case .front: yaw = 0; pitch = 0
        case .side: yaw = .pi / 2; pitch = 0
        case .top: yaw = 0; pitch = Self.pitchLimit
        }
        fit(viewport: viewport)
    }

    /// The camera's right, up and outward (toward the viewer) directions, in the model's own axes.
    private var viewBasis: (right: SIMD3<Float>, up: SIMD3<Float>, outward: SIMD3<Float>) {
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let up = SIMD3<Float>(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch))
        let outward = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        return (upAxis.modelDirection(forWorld: right), upAxis.modelDirection(forWorld: up),
                upAxis.modelDirection(forWorld: outward))
    }

    /// A model-space normal in view space: x to the right, y up and z toward the viewer. The light lives in this
    /// space, so it stays fixed to the view while the model turns (`GeometryLighting`).
    func viewNormal(forModelNormal normal: SIMD3<Float>) -> SIMD3<Float> {
        let basis = viewBasis
        return SIMD3<Float>(dot(basis.right, normal), dot(basis.up, normal), dot(basis.outward, normal))
    }

    /// The rotation `viewNormal(forModelNormal:)` applies, as the matrix the shader multiplies normals by.
    var normalTransform: simd_float4x4 {
        let basis = viewBasis
        return simd_float4x4(columns: (
            SIMD4<Float>(basis.right.x, basis.up.x, basis.outward.x, 0),
            SIMD4<Float>(basis.right.y, basis.up.y, basis.outward.y, 0),
            SIMD4<Float>(basis.right.z, basis.up.z, basis.outward.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    func viewProjection(viewport: CGSize) -> simd_float4x4 {
        let basis = viewBasis
        let view = simd_float4x4(columns: (
            SIMD4<Float>(basis.right.x, basis.up.x, basis.outward.x, 0),
            SIMD4<Float>(basis.right.y, basis.up.y, basis.outward.y, 0),
            SIMD4<Float>(basis.right.z, basis.up.z, basis.outward.z, 0),
            SIMD4<Float>(panOffset.x, panOffset.y, -distance, 1)
        ))
        let near: Float = 0.01
        let far = max(100, distance * 4 + 10)
        let focal = 1 / tan(Self.halfFieldOfView)
        let projection = simd_float4x4(columns: (
            SIMD4<Float>(focal / Self.aspect(viewport), 0, 0, 0),
            SIMD4<Float>(0, focal, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, near * far / (near - far), 0)
        ))
        return projection * view
    }

    private static func aspect(_ viewport: CGSize) -> Float {
        guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0 else { return 1 }
        return min(max(Float(viewport.width / viewport.height), 0.0001), 10_000)
    }
}

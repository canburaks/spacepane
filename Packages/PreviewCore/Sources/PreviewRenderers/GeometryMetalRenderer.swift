import AppKit
import MetalKit
import PreviewContracts
import simd

/// The light of the 3D viewport. It lives in view space (x right, y up, z toward the viewer), so it stays fixed to
/// the view while the model turns and the lit side always faces the person looking, unlike a light fixed to the model
/// whose far side stays dark however the model is turned (decision 027, Q-80). `intensity(forViewNormal:)` is the
/// pure-math twin of the fragment shader below: change both together; the offscreen pixel check compares them.
struct GeometryLighting: Equatable, Sendable {
    /// Unit direction toward the light, in view space: above, to the left of and in front of the viewer.
    let direction: SIMD3<Float>
    /// The share of the material every surface shows whatever its angle to the light, so no face goes black.
    let ambient: Float

    static let standard = GeometryLighting(direction: unit(SIMD3<Float>(-0.35, 0.55, 0.76)), ambient: 0.45)

    private static func unit(_ vector: SIMD3<Float>) -> SIMD3<Float> { vector / dot(vector, vector).squareRoot() }

    /// The share of the material's color a surface with this view-space normal shows, from `ambient` (turned away from
    /// the light) to 1 (facing it). A surface turned away from the viewer is lit as if it faced the viewer, so a model
    /// whose triangles wind the other way still shows its shape. A zero normal receives only the ambient share.
    func intensity(forViewNormal normal: SIMD3<Float>) -> Float {
        let length = dot(normal, normal).squareRoot()
        guard length > 0, length.isFinite else { return ambient }
        var facing = normal / length
        if facing.z < 0 { facing = -facing }
        return ambient + (1 - ambient) * max(0, dot(facing, direction))
    }
}

/// The material of the viewport, chosen from the background it is drawn on. The model is never drawn in the text ink:
/// that made it a near-black silhouette in light schemes and removed all shading in High Contrast light (decision 027,
/// Q-80). Each appearance gets one neutral mid-tone, light enough on a dark background and dark enough on a light one
/// that the darkest and the brightest face both stand clear of the background in every color scheme.
enum GeometryShading {
    struct Profile: Equatable, Sendable {
        /// sRGB-encoded albedo, the encoding the shader multiplies in.
        let material: SIMD3<Float>
        let lighting: GeometryLighting
    }

    /// Relative luminance of middle gray (about L* 50): a background darker than this is a dark viewport.
    static let darkBackgroundLuminance = 0.18
    static let lightBackgroundMaterial = SIMD3<Float>(repeating: 0.60)
    static let darkBackgroundMaterial = SIMD3<Float>(repeating: 0.78)

    /// The material and light for a background given as sRGB, 0 to 1 per channel.
    static func profile(forBackground background: SIMD3<Float>) -> Profile {
        let isDark = relativeLuminance(of: background) < darkBackgroundLuminance
        return Profile(material: isDark ? darkBackgroundMaterial : lightBackgroundMaterial, lighting: .standard)
    }

    /// The color a surface with this view-space normal is drawn in, in the shader's encoding.
    static func shade(_ profile: Profile, viewNormal: SIMD3<Float>) -> SIMD3<Float> {
        profile.material * profile.lighting.intensity(forViewNormal: viewNormal)
    }

    /// WCAG relative luminance of an sRGB color.
    static func relativeLuminance(of color: SIMD3<Float>) -> Double {
        func linear(_ channel: Float) -> Double {
            let value = Double(min(max(channel, 0), 1))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
    }
}

/// Owns only trusted shaders and numeric mesh buffers. There are no textures,
/// document shaders, external URLs or idle draw loop.
@MainActor
final class GeometryMetalRenderer: NSObject, GeometryRenderingBackend, MTKViewDelegate {
    private let metalView: MTKView
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLRenderPipelineState
    private let depthState: any MTLDepthStencilState
    private var positions: (any MTLBuffer)?
    private var normals: (any MTLBuffer)?
    private var indices: (any MTLBuffer)?
    private let indexCount: Int
    private var camera = GeometryCamera()
    private var style = GeometryRenderStyle(background: SIMD4<Float>(1, 1, 1, 1), material: SIMD4<Float>(0.6, 0.6, 0.6, 1))
    private var inFlightCommands = 0
    private var redrawPending = false
    var failureHandler: (@MainActor () -> Void)?
    var surface: NSView { metalView }

    init(mesh: PreviewMesh, device suppliedDevice: (any MTLDevice)? = nil) throws {
        guard mesh.positions.count > 0, mesh.positions.count <= GeometryLimits.maximumVertices,
              mesh.positions.count == mesh.normals.count, mesh.indices.count > 0,
              mesh.indices.count <= GeometryLimits.maximumIndices, mesh.indices.count.isMultiple(of: 3),
              mesh.indices.allSatisfy({ $0 < mesh.positions.count }) else { throw GeometryRenderFailure.invalidGeometry }
        guard let device = suppliedDevice ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(maxCommandBufferCount: 3) else { throw GeometryRenderFailure.unavailable }
        self.queue = queue
        metalView = MTKView(frame: .zero, device: device)
        metalView.isPaused = true
        metalView.enableSetNeedsDisplay = true
        metalView.autoResizeDrawable = true
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = .depth32Float
        metalView.framebufferOnly = true
        metalView.sampleCount = 1
        metalView.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        let library: any MTLLibrary
        do { library = try device.makeLibrary(source: Self.shaderSource, options: nil) }
        catch { throw GeometryRenderFailure.unavailable }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "geometryVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "geometryFragment")
        descriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        do { pipeline = try device.makeRenderPipelineState(descriptor: descriptor) }
        catch { throw GeometryRenderFailure.unavailable }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else { throw GeometryRenderFailure.unavailable }
        self.depthState = depthState
        positions = Self.buffer(mesh.positions, device: device)
        normals = Self.buffer(mesh.normals, device: device)
        indices = Self.buffer(mesh.indices, device: device)
        guard positions != nil, normals != nil, indices != nil else { throw GeometryRenderFailure.unavailable }
        indexCount = mesh.indices.count
        super.init()
        metalView.delegate = self
    }

    func update(camera: GeometryCamera, style: GeometryRenderStyle) {
        self.camera = camera; self.style = style
        metalView.clearColor = MTLClearColor(red: Double(style.background.x), green: Double(style.background.y),
            blue: Double(style.background.z), alpha: 1)
        metalView.needsDisplay = true
    }

    func suspend() {
        metalView.delegate = nil
        metalView.isPaused = true
        metalView.releaseDrawables()
        metalView.device = nil
        positions = nil; normals = nil; indices = nil
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.needsDisplay = true }

    func draw(in view: MTKView) {
        guard inFlightCommands < 3 else { redrawPending = true; return }
        guard positions != nil, view.drawableSize.width > 0, view.drawableSize.height > 0,
              let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        guard encode(into: command, descriptor: descriptor, size: view.drawableSize) else {
            failureHandler?()
            return
        }
        inFlightCommands += 1
        command.addCompletedHandler { [weak self] completed in
            let failed = completed.status == .error
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlightCommands -= 1
                if failed { self.failureHandler?() }
                else if self.redrawPending, self.positions != nil {
                    self.redrawPending = false
                    self.metalView.needsDisplay = true
                }
            }
        }
        command.present(drawable)
        command.commit()
    }

    /// Shared encoding boundary also permits deterministic offscreen GPU validation.
    func encode(into command: any MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, size: CGSize) -> Bool {
        guard let positions, let normals, let indices,
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
        let lighting = style.lighting
        var uniforms = GeometryUniforms(transform: camera.viewProjection(viewport: size), normalTransform: camera.normalTransform,
                                        color: style.material,
                                        light: SIMD4<Float>(lighting.direction.x, lighting.direction.y, lighting.direction.z, lighting.ambient))
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(positions, offset: 0, index: 0)
        encoder.setVertexBuffer(normals, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GeometryUniforms>.stride, index: 2)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: .uint32,
            indexBuffer: indices, indexBufferOffset: 0)
        encoder.endEncoding()
        return true
    }

    private static func buffer<T>(_ values: [T], device: any MTLDevice) -> (any MTLBuffer)? {
        values.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: pointer.count * MemoryLayout<T>.stride, options: .storageModeShared)
        }
    }

    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct GeometryUniforms { float4x4 transform; float4x4 normalTransform; float4 color; float4 light; };
        struct GeometryVertexOutput { float4 position [[position]]; float3 normal; float4 color; float4 light; };
        vertex GeometryVertexOutput geometryVertex(uint vertexID [[vertex_id]],
            device const float3 *positions [[buffer(0)]], device const float3 *normals [[buffer(1)]],
            constant GeometryUniforms &uniforms [[buffer(2)]]) {
            GeometryVertexOutput result;
            result.position = uniforms.transform * float4(positions[vertexID], 1.0);
            result.normal = (uniforms.normalTransform * float4(normals[vertexID], 0.0)).xyz;
            result.color = uniforms.color;
            result.light = uniforms.light;
            return result;
        }
        // Keep in step with GeometryLighting.intensity(forViewNormal:). The light is a view-space direction in
        // light.xyz and the ambient share is light.w; a surface turned away from the viewer is lit as if it faced it.
        fragment float4 geometryFragment(GeometryVertexOutput in [[stage_in]]) {
            float3 normal = normalize(in.normal);
            if (normal.z < 0.0) { normal = -normal; }
            float intensity = in.light.w + (1.0 - in.light.w) * max(dot(normal, in.light.xyz), 0.0);
            return float4(in.color.rgb * intensity, 1.0);
        }
        """
}

/// The layout of the shader's `GeometryUniforms`: two matrices, then two four-component vectors.
private struct GeometryUniforms {
    let transform: simd_float4x4
    let normalTransform: simd_float4x4
    let color: SIMD4<Float>
    let light: SIMD4<Float>
}

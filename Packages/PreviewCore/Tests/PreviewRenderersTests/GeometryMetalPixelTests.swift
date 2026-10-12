import AppKit
import Metal
import MetalKit
import PreviewContracts
import simd
import Testing
@testable import PreviewRenderers

/// Offscreen pixel checks of the viewport's shading (decision 027, Q-80). A machine without a GPU, such as a hosted
/// virtual machine, skips them; a Mac with one runs them, with no environment variable to set.
@Suite("Geometry shading on the GPU", .serialized)
@MainActor
struct GeometryMetalPixelTests {
    private static let size = 128

    /// Two triangles side by side that both face the camera, so both are drawn, but whose shading normals differ: the
    /// left one's normal is the light direction itself (fully lit) and the right one's turns away from it (ambient only).
    /// In the Front view of a Y-up camera view space and model space are the same, so each normal is its view normal.
    private func twoShadeMesh(lit: SIMD3<Float>, shadowed: SIMD3<Float>) throws -> PreviewMesh {
        let left: [SIMD3<Float>] = [SIMD3<Float>(-0.9, -0.6, 0), SIMD3<Float>(-0.1, -0.6, 0), SIMD3<Float>(-0.5, 0.6, 0)]
        let right: [SIMD3<Float>] = [SIMD3<Float>(0.1, -0.6, 0), SIMD3<Float>(0.9, -0.6, 0), SIMD3<Float>(0.5, 0.6, 0)]
        return try PreviewMesh(positions: left + right,
            normals: Array(repeating: lit, count: 3) + Array(repeating: shadowed, count: 3), indices: [0, 1, 2, 3, 4, 5],
            bounds: GeometryBounds(minimum: SIMD3<Double>(-1, -1, 0), maximum: SIMD3<Double>(1, 1, 0)), faceCount: 2)
    }

    /// The pixel a model-space point lands on, from the camera's own matrix; Metal's origin is the top left.
    private func pixel(of point: SIMD3<Float>, camera: GeometryCamera, size: CGSize) -> (x: Int, y: Int) {
        let clip = camera.viewProjection(viewport: size) * SIMD4<Float>(point.x, point.y, point.z, 1)
        let ndc = SIMD2<Float>(clip.x / clip.w, clip.y / clip.w)
        return (x: Int(((ndc.x + 1) / 2 * Float(size.width)).rounded(.down)),
                y: Int(((1 - ndc.y) / 2 * Float(size.height)).rounded(.down)))
    }

    /// Renders offscreen and returns BGRA pixels. A renderer that cannot be created is a real failure on a Mac with a GPU.
    private func render(_ mesh: PreviewMesh, camera: GeometryCamera, style: GeometryRenderStyle, device: any MTLDevice,
                        queue: any MTLCommandQueue) throws -> [UInt8] {
        let renderer = try GeometryMetalRenderer(mesh: mesh, device: device)
        renderer.update(camera: camera, style: style)
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Self.size,
                                                                       height: Self.size, mipmapped: false)
        colorDescriptor.usage = [.renderTarget]; colorDescriptor.storageMode = .shared
        let color = try #require(device.makeTexture(descriptor: colorDescriptor))
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: Self.size,
                                                                       height: Self.size, mipmapped: false)
        depthDescriptor.usage = [.renderTarget]; depthDescriptor.storageMode = .private
        let depth = try #require(device.makeTexture(descriptor: depthDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(style.background.x), green: Double(style.background.y),
                                                            blue: Double(style.background.z), alpha: 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        let command = try #require(queue.makeCommandBuffer())
        #expect(renderer.encode(into: command, descriptor: pass, size: CGSize(width: Self.size, height: Self.size)))
        command.commit(); command.waitUntilCompleted()
        #expect(command.status == .completed)
        var pixels = [UInt8](repeating: 0, count: Self.size * Self.size * 4)
        pixels.withUnsafeMutableBytes { bytes in
            color.getBytes(bytes.baseAddress!, bytesPerRow: Self.size * 4,
                           from: MTLRegionMake2D(0, 0, Self.size, Self.size), mipmapLevel: 0)
        }
        renderer.suspend()
        return pixels
    }

    private func channels(_ pixels: [UInt8], at point: (x: Int, y: Int)) -> SIMD3<Int> {
        let offset = (point.y * Self.size + point.x) * 4
        return SIMD3<Int>(Int(pixels[offset + 2]), Int(pixels[offset + 1]), Int(pixels[offset])) // BGRA to RGB
    }

    private func byte(_ value: Float) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }

    private func style(background: SIMD3<Float>, profile: GeometryShading.Profile) -> GeometryRenderStyle {
        GeometryRenderStyle(background: SIMD4<Float>(background.x, background.y, background.z, 1),
            material: SIMD4<Float>(profile.material.x, profile.material.y, profile.material.z, 1), lighting: profile.lighting)
    }

    private func isClose(_ actual: SIMD3<Int>, to expected: SIMD3<Float>, within tolerance: Int = 3) -> Bool {
        abs(actual.x - byte(expected.x)) <= tolerance && abs(actual.y - byte(expected.y)) <= tolerance
            && abs(actual.z - byte(expected.z)) <= tolerance
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func theRenderedShadesMatchTheShadingModelInLightAndHighContrastSchemes() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return }
        let lighting = GeometryLighting.standard
        let away = SIMD3<Float>(-lighting.direction.x, -lighting.direction.y, 0)
        let shadowed = away / (away * away).sum().squareRoot()
        let mesh = try twoShadeMesh(lit: lighting.direction, shadowed: shadowed)
        let size = CGSize(width: Self.size, height: Self.size)
        var camera = GeometryCamera()
        camera.preset(.front, viewport: size)
        let litPixel = pixel(of: SIMD3<Float>(-0.5, -0.2, 0), camera: camera, size: size)
        let shadowedPixel = pixel(of: SIMD3<Float>(0.5, -0.2, 0), camera: camera, size: size)
        let backgrounds: [(name: String, color: SIMD3<Float>)] = [
            (name: "Standard light", color: SIMD3<Float>(1, 1, 1)),
            (name: "High Contrast light", color: SIMD3<Float>(1, 1, 1)),
            (name: "Standard dark", color: SIMD3<Float>(27, 27, 27) / 255),
            (name: "High Contrast dark", color: SIMD3<Float>(0, 0, 0))]
        for background in backgrounds {
            let profile = GeometryShading.profile(forBackground: background.color)
            let pixels = try render(mesh, camera: camera, style: style(background: background.color, profile: profile),
                                    device: device, queue: queue)
            // The background is untouched by the model.
            let corner = channels(pixels, at: (x: 2, y: 2))
            #expect(isClose(corner, to: background.color, within: 1), "\(background.name): background \(corner)")
            // Each model pixel is the material times the share of light the shading model computes for its normal.
            let lit = channels(pixels, at: litPixel)
            let dark = channels(pixels, at: shadowedPixel)
            let litShade = GeometryShading.shade(profile, viewNormal: lighting.direction)
            let shadowedShade = GeometryShading.shade(profile, viewNormal: shadowed)
            #expect(isClose(lit, to: litShade), "\(background.name) lit: \(lit) against \(litShade)")
            #expect(isClose(dark, to: shadowedShade), "\(background.name) shadowed: \(dark) against \(shadowedShade)")
            // Shading shows, and the model is a mid-tone: High Contrast light used to draw a flat black silhouette.
            #expect(lit.x - dark.x >= 30, "\(background.name): lit \(lit) shadowed \(dark)")
            #expect(lit.x > 100 && lit.x < 245, "\(background.name): lit \(lit)")
            #expect(corner != lit && corner != dark, "\(background.name)")
        }
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func theLightStaysFixedToTheViewForTurnedCamerasAndBothUpAxes() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return }
        // One flat triangle in the model's XY plane with the shading normal +Z. The model never changes; only the camera
        // does, and the shade the GPU draws must follow the shading model for each camera.
        let mesh = try PreviewMesh(
            positions: [SIMD3<Float>(-0.8, -0.8, 0), SIMD3<Float>(0.8, -0.8, 0), SIMD3<Float>(0, 0.8, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(-1, -1, 0), maximum: SIMD3<Double>(1, 1, 0)), faceCount: 1)
        let size = CGSize(width: Self.size, height: Self.size)
        let background = SIMD3<Float>(1, 1, 1)
        let profile = GeometryShading.profile(forBackground: background)
        var front = GeometryCamera()
        front.preset(.front, viewport: size)
        var pitched = front
        pitched.orbit(delta: SIMD2<Float>(0, Float.pi / 3 / 0.008))
        var isometric = GeometryCamera()
        isometric.reset(viewport: size)
        var isometricZUp = GeometryCamera(upAxis: .z)
        isometricZUp.reset(viewport: size)
        let cameras: [(name: String, camera: GeometryCamera)] = [
            (name: "front", camera: front), (name: "pitched", camera: pitched),
            (name: "isometric Y up", camera: isometric), (name: "isometric Z up", camera: isometricZUp)]
        var shades: [Int] = []
        for entry in cameras {
            let pixels = try render(mesh, camera: entry.camera, style: style(background: background, profile: profile),
                                    device: device, queue: queue)
            let centroid = pixel(of: SIMD3<Float>(0, -0.8 / 3, 0), camera: entry.camera, size: size)
            let actual = channels(pixels, at: centroid)
            let expected = GeometryShading.shade(profile,
                viewNormal: entry.camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1)))
            #expect(isClose(actual, to: expected), "\(entry.name): \(actual) against \(expected)")
            shades.append(actual.x)
        }
        // The same face is brighter seen from the front than from above at sixty degrees, and brighter on a Z-up model
        // seen from its default angle than on a Y-up one: the light followed the camera, not the model.
        #expect(shades[0] - shades[1] >= 30, "front \(shades[0]) pitched \(shades[1])")
        #expect(shades[3] - shades[2] >= 20, "isometric Y up \(shades[2]) Z up \(shades[3])")
    }
}

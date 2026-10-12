import AppKit
import MetalKit
import PreviewContracts
import Testing
@testable import PreviewRenderers

@Suite("Native geometry Metal encoding", .serialized)
@MainActor
struct GeometryMetalRendererTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PREV_VALIDATE_METAL"] == "1"))
    func ownedShaderRendersTrianglesWithDepthAndReleasesBuffers() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let triangle = [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)]
        let positions = triangle.map { $0 + SIMD3<Float>(0, 0, 0.4) } + triangle.map { $0 - SIMD3<Float>(0, 0, 0.4) }
        let mesh = try PreviewMesh(positions: positions,
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3) + Array(repeating: SIMD3<Float>(1, 0, 0), count: 3),
            indices: [0, 1, 2, 3, 4, 5], bounds: .init(minimum: SIMD3<Double>(-1, -1, -0.4), maximum: SIMD3<Double>(1, 1, 0.4)), faceCount: 2)
        let renderer = try GeometryMetalRenderer(mesh: mesh, device: device)
        var camera = GeometryCamera(); camera.preset(.front, viewport: CGSize(width: 128, height: 128))
        renderer.update(camera: camera, style: GeometryRenderStyle(background: SIMD4<Float>(0, 0, 0, 1), material: SIMD4<Float>(1, 0, 0, 1)))
        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 128, height: 128, mipmapped: false)
        colorDescriptor.usage = [.renderTarget]; colorDescriptor.storageMode = .shared
        let color = try #require(device.makeTexture(descriptor: colorDescriptor))
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 128, height: 128, mipmapped: false)
        depthDescriptor.usage = [.renderTarget]; depthDescriptor.storageMode = .private
        let depth = try #require(device.makeTexture(descriptor: depthDescriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        let command = try #require(queue.makeCommandBuffer())
        #expect(renderer.encode(into: command, descriptor: pass, size: CGSize(width: 128, height: 128)))
        command.commit(); command.waitUntilCompleted()
        #expect(command.status == .completed)
        var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            color.getBytes(bytes.baseAddress!, bytesPerRow: 128 * 4, from: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0)
        }
        let center = (64 * 128 + 64) * 4
        #expect(pixels[center + 2] > 200) // Near triangle remains visible after the farther, darker triangle.
        #expect(pixels[center] == 0 && pixels[center + 1] == 0)
        #expect(pixels[2] == 0) // Background remains untouched.
        let surface = try #require(renderer.surface as? MTKView)
        #expect(surface.isPaused && surface.enableSetNeedsDisplay)
        renderer.suspend()
        #expect(surface.device == nil && surface.delegate == nil)
        let afterRelease = try #require(queue.makeCommandBuffer())
        #expect(!renderer.encode(into: afterRelease, descriptor: pass, size: CGSize(width: 128, height: 128)))
    }
}

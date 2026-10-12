import Foundation
import simd
import Testing
@testable import PreviewRenderers

@Suite("Geometry camera navigation")
struct GeometryCameraTests {
    @Test func fitKeepsNormalizedGeometryInsideWideAndTallViewports() {
        for viewport in [CGSize(width: 640, height: 360), CGSize(width: 180, height: 800)] {
            var camera = GeometryCamera()
            camera.fit(viewport: viewport)
            let transform = camera.viewProjection(viewport: viewport)
            for x: Float in [-1, 1] {
                for y: Float in [-1, 1] {
                    for z: Float in [-1, 1] {
                        let projected = transform * SIMD4<Float>(x, y, z, 1)
                        let ndc = projected / projected.w
                        #expect(abs(ndc.x) < 1 && abs(ndc.y) < 1)
                        #expect(ndc.z > 0 && ndc.z < 1)
                    }
                }
            }
        }
    }

    @Test func orbitPanZoomAndPresetsRemainFiniteAndResetPredictably() {
        let viewport = CGSize(width: 640, height: 480)
        var camera = GeometryCamera()
        camera.reset(viewport: viewport)
        let original = camera
        #expect(abs(original.yaw - .pi / 4) < 0.0001)
        #expect(abs(original.pitch - .pi / 6) < 0.0001)
        camera.orbit(delta: SIMD2<Float>(60, 10))
        camera.pan(delta: SIMD2<Float>(30, -20), viewport: viewport)
        camera.zoom(by: 0.5)
        #expect(camera != original)
        #expect(camera.distance < original.distance)
        #expect(camera.panOffset != .zero)
        camera.fit(viewport: viewport)
        #expect(camera.panOffset == .zero)
        #expect(camera.yaw != original.yaw)
        camera.preset(.front, viewport: viewport)
        #expect(camera != original)
        #expect(camera.yaw == 0 && camera.pitch == 0)
        camera.preset(.side, viewport: viewport)
        #expect(abs(camera.yaw - .pi / 2) < 0.0001)
        camera.preset(.top, viewport: viewport)
        #expect(camera.pitch > 1.5)
        camera.orbit(delta: SIMD2<Float>(0, Float.greatestFiniteMagnitude))
        #expect(abs(camera.pitch) < .pi / 2)
        camera.zoom(by: .infinity)
        camera.zoom(by: .nan)
        camera.pan(delta: SIMD2<Float>(.nan, .infinity), viewport: .zero)
        let matrix = camera.viewProjection(viewport: .zero)
        for column in 0..<4 { for row in 0..<4 { #expect(matrix[column][row].isFinite) } }
        camera.reset(viewport: viewport)
        #expect(camera == original)
    }

    @Test func skinnyModelFitUsesItsBoundedRadiusInsteadOfTheWholeCube() {
        let viewport = CGSize(width: 640, height: 480)
        var skinny = GeometryCamera(boundingRadius: 1)
        var cube = GeometryCamera()
        skinny.reset(viewport: viewport); cube.reset(viewport: viewport)
        #expect(skinny.distance < cube.distance * 0.6)
        var invalid = GeometryCamera(boundingRadius: .nan)
        invalid.reset(viewport: viewport)
        #expect(invalid == cube)
    }
}

import AppKit
import Foundation
import PreviewContracts
import simd
import Testing
@testable import PreviewRenderers

private func isClose(_ first: SIMD3<Float>, _ second: SIMD3<Float>, tolerance: Float = 1e-4) -> Bool {
    abs(first.x - second.x) <= tolerance && abs(first.y - second.y) <= tolerance && abs(first.z - second.z) <= tolerance
}

@Suite("Geometry up axis")
struct GeometryUpAxisTests {
    private let viewport = CGSize(width: 640, height: 480)

    @Test func eachFormatStartsUprightByItsOwnConvention() {
        // Owner decision D-3D: Z up for STL and 3MF; Y up for OBJ, PLY, STEP and IGES until real files are observed.
        #expect(GeometryUpAxis.conventional(for: .meshSTL) == .z)
        #expect(GeometryUpAxis.conventional(for: .mesh3MF) == .z)
        for formatID in [FormatID.meshOBJ, .meshPLY, .step, .iges, .plainText] {
            #expect(GeometryUpAxis.conventional(for: formatID) == .y, "\(formatID.rawValue)")
        }
        #expect(GeometryUpAxis.y.toggled == .z && GeometryUpAxis.z.toggled == .y)
        #expect(GeometryUpAxis.y.letter == "Y" && GeometryUpAxis.z.letter == "Z")
    }

    /// The view and projection a Y-up camera has always built, written out again from the camera's own state.
    private func originalViewProjection(of camera: GeometryCamera, viewport: CGSize) -> simd_float4x4 {
        let yaw = camera.yaw, pitch = camera.pitch
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let up = SIMD3<Float>(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch))
        let outward = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        let view = simd_float4x4(columns: (
            SIMD4<Float>(right.x, up.x, outward.x, 0),
            SIMD4<Float>(right.y, up.y, outward.y, 0),
            SIMD4<Float>(right.z, up.z, outward.z, 0),
            SIMD4<Float>(camera.panOffset.x, camera.panOffset.y, -camera.distance, 1)))
        let near: Float = 0.01
        let far = max(100, camera.distance * 4 + 10)
        let focal = 1 / tan(Float.pi / 8)
        let aspect = Float(viewport.width / viewport.height)
        let projection = simd_float4x4(columns: (
            SIMD4<Float>(focal / aspect, 0, 0, 0),
            SIMD4<Float>(0, focal, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, near * far / (near - far), 0)))
        return projection * view
    }

    @Test func aYUpCameraBuildsTheSameMatricesAsBeforeTheUpAxisExisted() {
        var camera = GeometryCamera()
        camera.reset(viewport: viewport)
        var cameras = [camera]
        camera.orbit(delta: SIMD2<Float>(60, 10))
        camera.pan(delta: SIMD2<Float>(30, -20), viewport: viewport)
        camera.zoom(by: 0.5)
        cameras.append(camera)
        for standardView in [GeometryStandardView.front, .side, .top] {
            var standard = GeometryCamera(boundingRadius: 1.2)
            standard.preset(standardView, viewport: viewport)
            cameras.append(standard)
        }
        for camera in cameras {
            let expected = originalViewProjection(of: camera, viewport: viewport)
            let actual = camera.viewProjection(viewport: viewport)
            for column in 0..<4 {
                for row in 0..<4 {
                    #expect(abs(actual[column][row] - expected[column][row]) < 1e-5, "column \(column) row \(row)")
                }
            }
        }
    }

    @Test func zUpPresetsLookAlongTheConventionalAxesWithTheModelsUpOnScreenUp() {
        var camera = GeometryCamera(upAxis: .z)
        // Front: the viewer is on the model's -Y side looking along +Y, Z up and X to the right.
        camera.preset(.front, viewport: viewport)
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(0, -1, 0)), SIMD3<Float>(0, 0, 1)))
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1)), SIMD3<Float>(0, 1, 0)))
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(1, 0, 0)), SIMD3<Float>(1, 0, 0)))
        // Side: the viewer is on the model's +X side looking along -X, Z up and Y to the right.
        camera.preset(.side, viewport: viewport)
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(1, 0, 0)), SIMD3<Float>(0, 0, 1)))
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 1, 0)), SIMD3<Float>(1, 0, 0)))
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1)), SIMD3<Float>(0, 1, 0)))
        // Top: the viewer is above looking along -Z, X to the right and the model's +Y at the top of the screen.
        camera.preset(.top, viewport: viewport)
        #expect(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1)).z > 0.99)
        #expect(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 1, 0)).y > 0.99)
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(1, 0, 0)), SIMD3<Float>(1, 0, 0)))
    }

    @Test func yUpPresetsAreUnchanged() {
        var camera = GeometryCamera(upAxis: .y)
        camera.preset(.front, viewport: viewport)
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1)), SIMD3<Float>(0, 0, 1)))
        #expect(isClose(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 1, 0)), SIMD3<Float>(0, 1, 0)))
        camera.preset(.top, viewport: viewport)
        #expect(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 1, 0)).z > 0.99)
        #expect(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, -1)).y > 0.99)
    }

    @Test func changingTheUpAxisStandsTheModelUpAndRestartsFromTheDefaultAngle() {
        var camera = GeometryCamera()
        camera.orbit(delta: SIMD2<Float>(80, 25))
        camera.pan(delta: SIMD2<Float>(30, -20), viewport: viewport)
        camera.zoom(by: 0.5)
        camera.setUpAxis(.z, viewport: viewport)
        #expect(camera.upAxis == .z)
        #expect(abs(camera.yaw - Float.pi / 4) < 1e-5 && abs(camera.pitch - Float.pi / 6) < 1e-5)
        #expect(camera.panOffset == .zero)
        // At the default angle the model's own Z points up the screen.
        #expect(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1)).y > 0.8)
        camera.setUpAxis(.y, viewport: viewport)
        #expect(camera.upAxis == .y)
        #expect(camera.viewNormal(forModelNormal: SIMD3<Float>(0, 1, 0)).y > 0.8)
    }

    @Test func bothAxesTurnTheModelWithoutMirroringItAndTheShaderMatrixAgrees() {
        for axis in [GeometryUpAxis.y, .z] {
            var camera = GeometryCamera(upAxis: axis)
            for delta in [SIMD2<Float>(0, 0), SIMD2<Float>(40, 15), SIMD2<Float>(-90, 60), SIMD2<Float>(200, -30)] {
                camera.orbit(delta: delta)
                let x = camera.viewNormal(forModelNormal: SIMD3<Float>(1, 0, 0))
                let y = camera.viewNormal(forModelNormal: SIMD3<Float>(0, 1, 0))
                let z = camera.viewNormal(forModelNormal: SIMD3<Float>(0, 0, 1))
                // Unit lengths, perpendicular and right-handed: a rotation, never a mirror.
                for axisVector in [x, y, z] { #expect(abs(dot(axisVector, axisVector) - 1) < 1e-5, "\(axis)") }
                #expect(abs(dot(x, y)) < 1e-5 && abs(dot(y, z)) < 1e-5 && abs(dot(x, z)) < 1e-5, "\(axis)")
                #expect(abs(dot(cross(x, y), z) - 1) < 1e-5, "\(axis)")
                for normal in [SIMD3<Float>(0.6, -0.48, 0.64), SIMD3<Float>(-0.3, 0.9, 0.1)] {
                    let expected = camera.viewNormal(forModelNormal: normal)
                    let product = camera.normalTransform * SIMD4<Float>(normal.x, normal.y, normal.z, 0)
                    #expect(isClose(SIMD3<Float>(product.x, product.y, product.z), expected, tolerance: 1e-5), "\(axis)")
                }
            }
        }
    }
}

@Suite("Geometry up axis in the view", .serialized)
@MainActor
struct GeometryUpAxisViewTests {
    private func presentation(_ formatID: FormatID) throws -> GeometryPresentation {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1)
        return GeometryPresentation(formatID: formatID, mesh: mesh, byteCount: 100)
    }

    private func makeView() -> NativeGeometryPreviewView {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), backendFactory: { _ in
            throw GeometryRenderFailure.unavailable
        })
        view.announcer?.handler = { _ in } // These tests are about the axis; speech has its own tests.
        return view
    }

    private func upAxisButton(in view: NativeGeometryPreviewView, naming axis: GeometryUpAxis) -> NSButton? {
        let title = PreviewStrings.format(.cadUpAxis, arguments: [axis.letter])
        return descendants(of: NSButton.self, in: view).first { $0.title == title }
    }

    @Test func eachNewModelStartsUprightByItsFormatAndTheChoiceIsNeverCarriedOver() throws {
        let view = makeView()
        let english = Locale(identifier: "en")
        let printed = try presentation(.meshSTL)
        view.show(printed, theme: .light, locale: english)
        #expect(view.camera.upAxis == .z)
        view.navigate(.toggleUpAxis)
        #expect(view.camera.upAxis == .y)
        // Restyling the same model keeps the person's choice; it is part of this view of this model.
        view.show(printed, theme: .dark, locale: english)
        #expect(view.camera.upAxis == .y)
        // A different model starts from its own format's convention, whatever was chosen for the last one.
        view.show(try presentation(.step), theme: .light, locale: english)
        #expect(view.camera.upAxis == .y)
        view.navigate(.toggleUpAxis)
        #expect(view.camera.upAxis == .z)
        view.show(try presentation(.meshOBJ), theme: .light, locale: english)
        #expect(view.camera.upAxis == .y)
        view.show(try presentation(.mesh3MF), theme: .light, locale: english)
        #expect(view.camera.upAxis == .z)
        // Nothing is shared between views and nothing is stored: a new view knows only the convention.
        let other = makeView()
        other.show(try presentation(.meshOBJ), theme: .light, locale: english)
        #expect(other.camera.upAxis == .y)
        let again = makeView()
        again.show(try presentation(.meshSTL), theme: .light, locale: english)
        #expect(again.camera.upAxis == .z)
    }

    @Test func theUpAxisButtonNamesTheAxisThatIsUpAndTogglesIt() throws {
        let view = makeView()
        view.show(try presentation(.meshSTL), theme: .light, locale: Locale(identifier: "en"))
        let button = try #require(upAxisButton(in: view, naming: .z))
        #expect(button.isEnabled)
        #expect(button.toolTip == PreviewStrings.text(.cadUpAxisHelp))
        #expect(button.accessibilityHelp() == PreviewStrings.text(.cadUpAxisHelp))
        #expect(button.accessibilityLabel() == button.title)
        button.performClick(nil)
        #expect(view.camera.upAxis == .y)
        #expect(button.title == PreviewStrings.format(.cadUpAxis, arguments: [GeometryUpAxis.y.letter]))
        #expect(button.accessibilityLabel() == button.title)
        button.performClick(nil)
        #expect(view.camera.upAxis == .z && button.title == PreviewStrings.format(.cadUpAxis, arguments: [GeometryUpAxis.z.letter]))
    }

    @Test func withoutAModelTheButtonDoesNothingAndAClearedViewDisablesIt() throws {
        let view = makeView()
        view.navigate(.toggleUpAxis)
        #expect(view.camera.upAxis == .y)
        view.show(try presentation(.meshSTL), theme: .light, locale: Locale(identifier: "en"))
        let button = try #require(descendants(of: NSButton.self, in: view).first { $0.title.hasSuffix(GeometryUpAxis.z.letter) })
        #expect(button.isEnabled)
        view.clear()
        #expect(!button.isEnabled)
    }
}

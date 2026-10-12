import AppKit
import Foundation
import PreviewContracts
import Testing
@testable import PreviewRenderers

/// Colour maths written independently of the production helper, so a wrong constant there cannot hide here.
private enum ShadeMath {
    static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance of an sRGB color with channels from 0 to 1.
    static func luminance(_ color: SIMD3<Double>) -> Double {
        0.2126 * linear(color.x) + 0.7152 * linear(color.y) + 0.0722 * linear(color.z)
    }

    /// CIE 1976 lightness L* of a relative luminance.
    static func lightness(ofLuminance y: Double) -> Double {
        y > 216.0 / 24389.0 ? 116 * cbrt(y) - 16 : y * 24389.0 / 27.0
    }

    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    static func color(hex: UInt32) -> SIMD3<Double> {
        SIMD3<Double>(Double((hex >> 16) & 0xFF), Double((hex >> 8) & 0xFF), Double(hex & 0xFF)) / 255
    }

    static func double(_ color: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3<Double>(Double(color.x), Double(color.y), Double(color.z))
    }

    /// The largest channel difference between two colors with channels from 0 to 1.
    static func largestDifference(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        max(abs(first.x - second.x), abs(first.y - second.y), abs(first.z - second.z))
    }

    /// Unit view-space normals that face the viewer, spread evenly over the hemisphere (a golden-angle spiral).
    static func visibleNormals(count: Int) -> [SIMD3<Float>] {
        (0..<count).map { index in
            let z = (Float(index) + 0.5) / Float(count)
            let radius = (1 - z * z).squareRoot()
            let angle = Float(index) * 2.399_963
            return SIMD3<Float>(radius * cos(angle), radius * sin(angle), z)
        }
    }
}

@Suite("Geometry shading model")
struct GeometryShadingTests {
    /// Every palette a viewport can draw on: each appearance with each scheme it offers, and High Contrast.
    private var palettes: [(name: String, dark: Bool, background: UInt32)] {
        var result: [(name: String, dark: Bool, background: UInt32)] = []
        for dark in [false, true] {
            for highContrast in [false, true] {
                for scheme in PreviewColorSchemeID.choices(for: dark ? .dark : .light) {
                    let palette = NativeColorSchemes.palette(for: scheme, dark: dark, highContrast: highContrast)
                    result.append((name: "\(scheme.rawValue) dark=\(dark) highContrast=\(highContrast)", dark: dark,
                                   background: palette.background))
                }
            }
        }
        return result
    }

    @Test func everySchemeShowsAtLeastTwentyFiveLightnessUnitsOfShadingAndEveryFaceStandsClearOfItsBackground() {
        let normals = ShadeMath.visibleNormals(count: 4_000) + [GeometryLighting.standard.direction, SIMD3<Float>(0, 0, 1)]
        for entry in palettes {
            let background = ShadeMath.color(hex: entry.background)
            let backgroundLuminance = ShadeMath.luminance(background)
            let profile = GeometryShading.profile(forBackground: SIMD3<Float>(background))
            var darkest = Double.infinity, brightest = -Double.infinity
            for normal in normals {
                let shade = GeometryShading.shade(profile, viewNormal: normal)
                let luminance = ShadeMath.luminance(ShadeMath.double(shade))
                darkest = min(darkest, luminance)
                brightest = max(brightest, luminance)
            }
            let spread = ShadeMath.lightness(ofLuminance: brightest) - ShadeMath.lightness(ofLuminance: darkest)
            #expect(spread >= 25, "\(entry.name): lit spread \(spread) L*")
            let darkestRatio = ShadeMath.contrast(darkest, backgroundLuminance)
            #expect(darkestRatio >= 1.5, "\(entry.name): darkest lit face \(darkestRatio):1")
            let brightestRatio = ShadeMath.contrast(brightest, backgroundLuminance)
            #expect(brightestRatio >= 1.5, "\(entry.name): brightest lit face \(brightestRatio):1")
        }
    }

    @Test func theMaterialIsAMidToneChosenFromTheBackgroundAndNeverTheTextInk() {
        for entry in palettes {
            let background = ShadeMath.color(hex: entry.background)
            let profile = GeometryShading.profile(forBackground: SIMD3<Float>(background))
            let material = ShadeMath.double(profile.material)
            let lightness = ShadeMath.lightness(ofLuminance: ShadeMath.luminance(material))
            #expect(lightness > 40 && lightness < 90, "\(entry.name): material L* \(lightness)")
            // A neutral gray: no hue, so no color scheme can tint the model.
            #expect(profile.material.x == profile.material.y && profile.material.y == profile.material.z, "\(entry.name)")
            // Dark viewports get the lighter material and light viewports the darker one.
            let darkViewport = ShadeMath.lightness(ofLuminance: ShadeMath.luminance(background)) < 50
            #expect(darkViewport == entry.dark, "\(entry.name): polarity")
            let lightMaterial = ShadeMath.luminance(ShadeMath.double(GeometryShading.lightBackgroundMaterial))
            let darkMaterial = ShadeMath.luminance(ShadeMath.double(GeometryShading.darkBackgroundMaterial))
            #expect(ShadeMath.luminance(material) == (entry.dark ? darkMaterial : lightMaterial), "\(entry.name)")
        }
        // The old defect: the text ink was the material, so High Contrast light drew a flat black silhouette.
        for scheme in [NativeColorSchemes.standardLight, NativeColorSchemes.standardHighContrastLight,
                       NativeColorSchemes.standardDark, NativeColorSchemes.standardHighContrastDark] {
            let profile = GeometryShading.profile(forBackground: SIMD3<Float>(ShadeMath.color(hex: scheme.background)))
            let ink = ShadeMath.color(hex: scheme.foreground)
            let difference = ShadeMath.largestDifference(ShadeMath.double(profile.material), ink)
            #expect(difference > 0.1, "background \(scheme.background)")
        }
    }

    @Test func theLightIsAViewSpaceDirectionFromAboveLeftAndInFrontWithAGenerousAmbientShare() {
        let lighting = GeometryLighting.standard
        let direction = lighting.direction
        #expect(abs((direction * direction).sum() - 1) < 1e-5)
        #expect(direction.x < 0 && direction.y > 0 && direction.z > 0.5)
        #expect(lighting.ambient >= 0.35 && lighting.ambient < 1)
    }

    @Test func intensityRunsFromTheAmbientShareToOneAndLightsBackFacesLikeFrontFaces() {
        let lighting = GeometryLighting.standard
        #expect(abs(lighting.intensity(forViewNormal: lighting.direction) - 1) < 1e-5)
        // Turned fully away from the light but not from the viewer: only the ambient share remains.
        let away = SIMD3<Float>(-lighting.direction.x, -lighting.direction.y, 0)
        let awayUnit = away / (away * away).sum().squareRoot()
        #expect(abs(lighting.intensity(forViewNormal: awayUnit) - lighting.ambient) < 1e-5)
        // A face turned from the viewer is lit as if it faced the viewer, so reversed triangles keep their shape.
        for normal in ShadeMath.visibleNormals(count: 64) {
            #expect(abs(lighting.intensity(forViewNormal: -normal) - lighting.intensity(forViewNormal: normal)) < 1e-6)
        }
        #expect(abs(lighting.intensity(forViewNormal: -lighting.direction) - 1) < 1e-5)
        // The length of a normal does not matter, and an empty normal cannot produce NaN.
        #expect(abs(lighting.intensity(forViewNormal: lighting.direction * 3) - 1) < 1e-5)
        #expect(lighting.intensity(forViewNormal: .zero) == lighting.ambient)
        for normal in ShadeMath.visibleNormals(count: 200) {
            let value = lighting.intensity(forViewNormal: normal)
            #expect(value >= lighting.ambient - 1e-6 && value <= 1 + 1e-6)
        }
    }

    @Test func theLightStaysFixedToTheViewWhileTheModelTurns() {
        let lighting = GeometryLighting.standard
        for upAxis in [GeometryUpAxis.y, .z] {
            var camera = GeometryCamera(upAxis: upAxis)
            let model = SIMD3<Float>(1, 0, 0)
            let first = lighting.intensity(forViewNormal: camera.viewNormal(forModelNormal: model))
            camera.orbit(delta: SIMD2<Float>(Float.pi / 2 / 0.008, 0)) // A quarter turn about the vertical axis.
            let second = lighting.intensity(forViewNormal: camera.viewNormal(forModelNormal: model))
            // The same side of the model is lit differently once the camera has gone round it: the light did not stay
            // with the model. (A half turn would show the same face from behind, which two-sided lighting shades alike.)
            #expect(abs(first - second) > 0.1, "\(upAxis)")
            // Whatever the angle, some surface of the model faces the light and some does not.
            var brightest: Float = 0, darkest: Float = 1
            for normal in ShadeMath.visibleNormals(count: 500) + ShadeMath.visibleNormals(count: 500).map({ -$0 }) {
                let value = lighting.intensity(forViewNormal: camera.viewNormal(forModelNormal: normal))
                brightest = max(brightest, value)
                darkest = min(darkest, value)
            }
            #expect(brightest > 0.99 && abs(darkest - lighting.ambient) < 1e-3, "\(upAxis)")
        }
    }

    @Test func aStyleThatSaysNothingUsesTheStandardLight() {
        let style = GeometryRenderStyle(background: SIMD4<Float>(1, 1, 1, 1), material: SIMD4<Float>(0.5, 0.5, 0.5, 1))
        #expect(style.lighting == GeometryLighting.standard)
    }
}

@Suite("Geometry viewport material", .serialized)
@MainActor
struct GeometryViewportMaterialTests {
    @MainActor
    private final class StyleProbe: GeometryRenderingBackend {
        let surface = NSView()
        var failureHandler: (@MainActor () -> Void)?
        var styles: [GeometryRenderStyle] = []
        func update(camera: GeometryCamera, style: GeometryRenderStyle) { styles.append(style) }
        func suspend() {}
    }

    private func presentation() throws -> GeometryPresentation {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1)
        return GeometryPresentation(formatID: .meshSTL, mesh: mesh, byteCount: 100)
    }

    private func lastStyle(theme: PreviewTheme, appearance: NSAppearance.Name, scheme: PreviewSyntaxStyle = PreviewSyntaxStyle()) throws
        -> GeometryRenderStyle {
        let probe = StyleProbe()
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), backendFactory: { _ in probe })
        view.appearance = NSAppearance(named: appearance)
        view.syntaxStyle = scheme
        view.show(try presentation(), theme: theme, locale: Locale(identifier: "en"))
        view.resume()
        return try #require(probe.styles.last)
    }

    @Test func theViewHandsTheBackendAMaterialFromTheBackgroundNotTheTextInk() throws {
        let cases: [(PreviewTheme, NSAppearance.Name, NativeSchemePalette)] = [
            (.light, .aqua, NativeColorSchemes.standardLight),
            (.dark, .darkAqua, NativeColorSchemes.standardDark),
            (.highContrast, .aqua, NativeColorSchemes.standardHighContrastLight),
            (.highContrast, .darkAqua, NativeColorSchemes.standardHighContrastDark)]
        for (theme, appearance, palette) in cases {
            let style = try lastStyle(theme: theme, appearance: appearance)
            let background = ShadeMath.color(hex: palette.background)
            let expected = GeometryShading.profile(forBackground: SIMD3<Float>(background))
            let material = SIMD3<Float>(style.material.x, style.material.y, style.material.z)
            #expect(material == expected.material && style.material.w == 1, "background \(palette.background)")
            #expect(style.lighting == expected.lighting)
            let ink = ShadeMath.color(hex: palette.foreground)
            #expect(ShadeMath.largestDifference(ShadeMath.double(material), ink) > 0.1, "background \(palette.background)")
        }
    }

    @Test func aChosenColorSchemeChangesTheBackgroundTheMaterialIsChosenFor() throws {
        let nord = PreviewSyntaxStyle(lightScheme: .standard, darkScheme: .nord)
        let style = try lastStyle(theme: .dark, appearance: .darkAqua, scheme: nord)
        let background = ShadeMath.color(hex: NativeColorSchemes.nord.background)
        let expected = GeometryShading.profile(forBackground: SIMD3<Float>(background))
        #expect(style.material.x == expected.material.x)
        #expect(abs(style.background.x - Float(background.x)) < 0.003)
    }
}

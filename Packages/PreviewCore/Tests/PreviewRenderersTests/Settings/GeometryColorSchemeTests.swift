import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Geometry viewport follows the color scheme", .serialized)
@MainActor
struct GeometryColorSchemeTests {
    private func backgroundHex(_ view: NativeGeometryPreviewView) throws -> UInt32 {
        let cgColor = try #require(view.layer?.backgroundColor)
        let color = try #require(NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB))
        func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent)
    }

    @Test func viewportBackgroundUsesTheChosenSchemeForTheEffectiveAppearance() throws {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                             backendFactory: { _ in throw GeometryRenderFailure.unavailable })
        view.appearance = NSAppearance(named: .aqua)
        view.syntaxStyle = PreviewSyntaxStyle(lightScheme: .paper, darkScheme: .midnight)
        #expect(try backgroundHex(view) == NativeColorSchemes.paper.background)
        view.appearance = NSAppearance(named: .darkAqua)
        view.viewDidChangeEffectiveAppearance()
        #expect(try backgroundHex(view) == NativeColorSchemes.midnight.background)
        view.syntaxStyle = PreviewSyntaxStyle()
        #expect(try backgroundHex(view) == NativeColorSchemes.standardDark.background)
    }
}

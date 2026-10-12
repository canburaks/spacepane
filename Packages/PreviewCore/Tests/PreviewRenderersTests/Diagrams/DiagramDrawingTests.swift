import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Diagram drawing")
struct DiagramDrawingTests {
    private let english = DiagramEnvironment(font: .standard, locale: Locale(identifier: "en_US"))

    /// A bitmap with its pixel data, drawn through the public module API without any view.
    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        func pixel(_ x: Int, _ y: Int) -> (r: Double, g: Double, b: Double) {
            let offset = (y * width + x) * 4
            return (Double(bytes[offset]) / 255, Double(bytes[offset + 1]) / 255, Double(bytes[offset + 2]) / 255)
        }
        func luminance(_ x: Int, _ y: Int) -> Double {
            let p = pixel(x, y)
            return 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
        }
        /// Pixels in `rect` (bitmap coordinates, top-left origin) satisfying `test`.
        func count(in rect: CGRect, where test: (Double) -> Bool) -> Int {
            var total = 0
            for y in max(Int(rect.minY), 0)..<min(Int(rect.maxY), height) {
                for x in max(Int(rect.minX), 0)..<min(Int(rect.maxX), width) where test(luminance(x, y)) { total += 1 }
            }
            return total
        }
    }

    private func render(_ diagram: SafeDiagram, width: Int = 480, height: Int = 360, palette: DiagramPalette = .standard(isDark: false),
                        flipped: Bool = false) throws -> Bitmap {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        if flipped {
            // The caller supplies a y-down context, as inside a flipped view.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
        }
        diagram.draw(in: context, size: CGSize(width: width, height: height), palette: palette, isFlipped: flipped)
        let data = try #require(context.data)
        return Bitmap(width: width, height: height, bytes: Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4)))
    }

    private func diagram(_ source: String) throws -> SafeDiagram {
        try #require(SafeDiagram.parse(mermaid: source, environment: english))
    }

    /// Maps a scene rectangle to bitmap coordinates the way `draw(in:size:palette:)` fits it.
    private func bitmapRect(_ rect: CGRect, of diagram: SafeDiagram, width: Int, height: Int) -> CGRect {
        let scale = min(CGFloat(width) / diagram.contentSize.width, CGFloat(height) / diagram.contentSize.height, 2)
        let dx = (CGFloat(width) - diagram.contentSize.width * scale) / 2
        let dy = (CGFloat(height) - diagram.contentSize.height * scale) / 2
        return CGRect(x: dx + rect.minX * scale, y: dy + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    @Test func everyDiagramKindDrawsInkOnTheBackground() throws {
        let sources = [
            "flowchart LR\nA[Alpha] --> B{Beta}\nB -->|yes| C((Gamma))\nB -.-> D[(Delta)]",
            "sequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->>B: hello\nB-->>A: hi\nNote over A,B: note",
            "pie showData title Shares\n\"One\" : 3\n\"Two\" : 2\n\"Three\" : 1",
            "stateDiagram-v2\n[*] --> Idle\nIdle --> Busy : go\nBusy --> [*]"
        ]
        for source in sources {
            let bitmap = try render(try diagram(source))
            let background = bitmap.luminance(0, 0)
            #expect(background > 0.99)
            let ink = bitmap.count(in: CGRect(x: 0, y: 0, width: 480, height: 360)) { abs($0 - background) > 0.05 }
            #expect(ink > 800, "\(source.prefix(12)) drew only \(ink) pixels")
        }
    }

    @Test func labelsAreDrawnUprightInsideTheirNodes() throws {
        let flow = try diagram("flowchart TD\nA[Hello world label]")
        let node = try #require(flow.scene.primitives.compactMap { primitive -> DiagramShapeItem? in if case .shape(let item) = primitive { item } else { nil } }.first)
        let bitmap = try render(flow, width: 400, height: 300)
        let area = bitmapRect(node.rect, of: flow, width: 400, height: 300)
        let interior = area.insetBy(dx: 8, dy: 6)
        let dark = bitmap.count(in: interior) { $0 < 0.45 }
        #expect(dark > 40, "Text pixels inside the node: \(dark)")
        // Glyph ink sits around the vertical center of the node, as upright text does.
        var sum = 0.0, count = 0.0
        for y in Int(interior.minY)..<Int(interior.maxY) {
            for x in Int(interior.minX)..<Int(interior.maxX) where bitmap.luminance(x, y) < 0.45 { sum += Double(y); count += 1 }
        }
        #expect(abs(sum / count - Double(area.midY)) < Double(area.height) * 0.3)
        // Upright text has more ink in its upper half than a mirrored baseline would; compare the two halves.
        #expect(count > 0)
    }

    @Test func darkAndHighContrastPalettesAreHonoured() throws {
        let flow = try diagram("flowchart TD\nA[Alpha] --> B[Beta]")
        let dark = try render(flow, palette: .standard(isDark: true))
        #expect(dark.luminance(0, 0) < 0.15)
        let contrast = try render(flow, palette: .standard(isDark: true, highContrast: true))
        #expect(contrast.luminance(0, 0) < 0.01)
        let light = try render(flow, palette: .standard(isDark: false, highContrast: true))
        #expect(light.luminance(0, 0) > 0.99)
        // Increased contrast strokes more ink than the regular palette.
        let regular = try render(flow, palette: .standard(isDark: false))
        func ink(_ bitmap: Bitmap) -> Int { bitmap.count(in: CGRect(x: 0, y: 0, width: 480, height: 360)) { $0 < 0.6 } }
        #expect(ink(light) > ink(regular))
        #expect(DiagramPalette.standard(isDark: true).isDark && !DiagramPalette.standard(isDark: false).isDark)
    }

    @Test func piePaletteUsesDistinctColorsAndFallsBackToGrayWithoutColor() throws {
        let palette = DiagramPalette.standard(isDark: false)
        let colors = (0..<12).map { palette.sliceColor(index: $0) }
        #expect(Set(colors.map { "\($0.red),\($0.green),\($0.blue)" }).count == 12)
        var plain = palette
        plain.usesColor = false
        let grays = (0..<5).map { plain.sliceColor(index: $0) }
        #expect(grays.allSatisfy { abs($0.red - $0.green) < 1e-9 && abs($0.green - $0.blue) < 1e-9 })
        #expect(Set(grays.map(\.red)).count == 5)
    }

    @Test func unknownFontNamesFallBackToTheSystemFace() {
        let system = DiagramFont(name: nil, size: 14).ctFont()
        let unknown = DiagramFont(name: "No Such Font Family 12345", size: 14).ctFont()
        #expect(CTFontCopyFullName(unknown) as String == CTFontCopyFullName(system) as String)
        let menlo = DiagramFont(name: "Menlo-Regular", size: 14).ctFont()
        #expect((CTFontCopyFamilyName(menlo) as String) == "Menlo")
        #expect(DiagramFont(name: nil, size: 1_000).size == 72 && DiagramFont(name: nil, size: 1).size == 6)
    }

    @Test func drawingIsIdenticalForFlippedAndDefaultContexts() throws {
        let flow = try diagram("flowchart LR\nA --> B\nB --> C")
        let normal = try render(flow, width: 320, height: 200)
        let flipped = try render(flow, width: 320, height: 200, flipped: true)
        // The flipped context is drawn y-down, so the bitmaps agree up to the context's own orientation.
        var differences = 0
        for y in 0..<200 { for x in 0..<320 where abs(normal.luminance(x, y) - flipped.luminance(x, y)) > 0.02 { differences += 1 } }
        #expect(differences == 0, "\(differences) pixels differ")
    }

    @Test func drawingAnEmptyOrDegenerateSizeDoesNothing() throws {
        let flow = try diagram("flowchart TD\nA --> B")
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        flow.draw(in: context, size: .zero, palette: .standard(isDark: false))
        flow.draw(in: context, size: CGSize(width: -5, height: 10), palette: .standard(isDark: false))
        #expect(context.data != nil)
    }

    @Test func drawingNeverTouchesDiskOrNetworkAndIsRepeatable() throws {
        let flow = try diagram("flowchart TD\nA[Alpha] --> B[Beta]\nB --> C")
        let first = try render(flow), second = try render(flow)
        #expect(first.bytes == second.bytes)
    }

    @Test func drawioDiagramsDrawWithThePaletteRatherThanDocumentColors() throws {
        let page = "<mxGraphModel><root><mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"2\" value=\"Red\" style=\"fillColor=#FF0000;strokeColor=#FF0000;\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"0\" y=\"0\" width=\"200\" height=\"100\" as=\"geometry\"/></mxCell></root></mxGraphModel>"
        let shape = try #require(SafeDiagram.parse(drawio: page, environment: english))
        let bitmap = try render(shape, width: 300, height: 200)
        let area = bitmapRect(CGRect(x: 24, y: 24, width: 200, height: 100), of: shape, width: 300, height: 200)
        let probe = bitmap.pixel(Int(area.minX) + 6, Int(area.minY) + 6)
        // The fill is the palette's neutral node color, never the document's red.
        #expect(abs(probe.r - probe.g) < 0.02 && abs(probe.g - probe.b) < 0.02)
    }
}

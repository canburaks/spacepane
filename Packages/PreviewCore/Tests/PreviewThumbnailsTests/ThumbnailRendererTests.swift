import CoreGraphics
import Foundation
import Testing
import PreviewContracts
@testable import PreviewThumbnails

/// Bitmap smoke tests: each presentation shape draws something, inside its page, off the main thread.
@Suite("Thumbnail rendering")
struct ThumbnailRendererTests {
    private func pixelRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// The rectangle of the sheet in top-down pixel rows, as `Canvas.pixel` indexes them.
    private func topDown(_ rect: CGRect, canvas: Canvas, scale: CGFloat) -> CGRect {
        let pixels = pixelRect(rect, scale: scale)
        return CGRect(x: pixels.minX, y: CGFloat(canvas.height) - pixels.maxY, width: pixels.width, height: pixels.height)
    }

    private func scene(_ content: ThumbnailContent, _ geometry: ThumbnailGeometry, usesColor: Bool = true) -> ThumbnailScene {
        ThumbnailScene(content: content, metrics: ThumbnailMetrics(geometry: geometry), usesColor: usesColor)
    }

    private func textPage(_ geometry: ThumbnailGeometry) throws -> ThumbnailContent {
        let m = ThumbnailMetrics(geometry: geometry)
        let source = """
        // Greeting
        func greet(name: String) -> String {
            let count = 42
            return "Hello, \\(name)" + String(count)
        }
        """
        return .text(try #require(ThumbnailExcerpt.page(from: source, syntax: .sourceCode, metrics: m)))
    }

    @Test func theGlyphDrawsAPageWithThreeRules() {
        let g = geometry(128)
        let canvas = Canvas(g)
        ThumbnailRenderer.drawGlyph(in: canvas.context, size: g.size)
        canvas.dumpIfRequested("glyph")
        #expect(canvas.opaqueCount > 0)
        #expect(canvas.pixel(x: 1, y: 1).a == 0)
        let page = topDown(ThumbnailPage.rect(in: g.size, fractions: ThumbnailPage.glyph), canvas: canvas, scale: g.scale)
        #expect(canvas.inkCount(in: page) > 100)
        // The sheet is filled with the light page color between the rules.
        let sample = canvas.pixel(x: Int(page.minX) + 12, y: Int(page.minY) + 14)
        #expect(sample.a == 255 && sample.r > 230)
    }

    @Test func textDrawsInkInsideThePageAndNothingOutsideIt() throws {
        let g = geometry(256)
        let canvas = Canvas(g)
        let content = try textPage(g)
        ThumbnailRenderer.draw(scene(content, g), in: canvas.context)
        canvas.dumpIfRequested("source")
        let metrics = ThumbnailMetrics(geometry: g)
        let textArea = topDown(metrics.textArea, canvas: canvas, scale: g.scale)
        #expect(canvas.inkCount(in: textArea) > 200)
        // Corners lie outside the sheet and stay transparent; so do the canvas margins.
        for corner in [(0, 0), (canvas.width - 1, 0), (0, canvas.height - 1), (canvas.width - 1, canvas.height - 1)] {
            #expect(canvas.pixel(x: corner.0, y: corner.1).a == 0)
        }
        let page = topDown(metrics.page, canvas: canvas, scale: g.scale)
        for y in 0..<canvas.height {
            for x in [0, canvas.width - 1] { #expect(canvas.pixel(x: x, y: y).a == 0) }
        }
        #expect(page.minX > 0 && page.maxX < CGFloat(canvas.width))
    }

    @Test func colorsAppearOnlyWhenTheStyleAllowsThem() throws {
        let g = geometry(256)
        func coloredPixels(_ usesColor: Bool) throws -> Int {
            let canvas = Canvas(g)
            ThumbnailRenderer.draw(scene(try textPage(g), g, usesColor: usesColor), in: canvas.context)
            var count = 0
            for y in 0..<canvas.height {
                for x in 0..<canvas.width {
                    let p = canvas.pixel(x: x, y: y)
                    if p.a == 255, abs(Int(p.r) - Int(p.b)) > 40 || abs(Int(p.g) - Int(p.b)) > 40 { count += 1 }
                }
            }
            return count
        }
        #expect(try coloredPixels(true) > 20)
        #expect(try coloredPixels(false) == 0)
    }

    @Test func markdownHeadingsDrawLargerThanBody() throws {
        let g = geometry(384)
        let m = ThumbnailMetrics(geometry: g)
        let page = try #require(ThumbnailMarkdown.page(from: "# Title\n\nbody text here\n", syntax: .markdown, metrics: m))
        let canvas = Canvas(g)
        ThumbnailRenderer.draw(scene(.text(page), g), in: canvas.context)
        canvas.dumpIfRequested("markdown")
        #expect(canvas.inkCount(in: topDown(m.textArea, canvas: canvas, scale: g.scale)) > 100)
    }

    @Test func tablesDrawHeaderRulesAndStripes() throws {
        let g = geometry(384)
        let m = ThumbnailMetrics(geometry: g)
        let grid = try #require(ThumbnailGrid(headers: ["id", "name", "city"], columnKinds: [.numeric, .text, .text],
            rowCount: 3, columnCount: 3, rowsAreLowerBound: false, sampleRowCount: 3, locale: Locale(identifier: "en_US")))
        let canvas = Canvas(g)
        ThumbnailRenderer.draw(scene(.grid(grid), g), in: canvas.context)
        canvas.dumpIfRequested("table")
        let area = topDown(m.textArea, canvas: canvas, scale: g.scale)
        #expect(canvas.inkCount(in: area) > 100)
        // Alternate body rows carry the stripe fill, darker than the sheet.
        var stripePixels = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            let p = canvas.pixel(x: Int(area.minX) + 1, y: y)
            if p.a == 255, p.r >= 225, p.r <= 238 { stripePixels += 1 }
        }
        #expect(stripePixels > 4)
    }

    @Test func coverAndPagePicturesFillTheCanvasAspectFit() throws {
        let g = geometry(128)
        let m = ThumbnailMetrics(geometry: g)
        let image = try #require(ThumbnailImageDecoder.decode(
            PreviewImage(data: syntheticImage(width: 200, height: 400), pixelWidth: 200, pixelHeight: 400, role: .cover),
            maximumPixelExtent: g.maximumPixelExtent, limits: .standard))
        let canvas = Canvas(g)
        ThumbnailRenderer.draw(ThumbnailScene(content: .picture(ThumbnailPicture(image: image, role: .cover)), metrics: m), in: canvas.context)
        canvas.dumpIfRequested("cover")
        // A 1:2 cover in a square canvas leaves transparent side margins and fills the height.
        #expect(canvas.pixel(x: 2, y: canvas.height / 2).a == 0)
        #expect(canvas.pixel(x: canvas.width / 2, y: canvas.height / 2).a == 255)
        #expect(canvas.pixel(x: canvas.width / 2, y: 14).a == 255)
    }

    @Test func iconsAreInsetAndFiguresSitOnAPage() throws {
        let g = geometry(128)
        let m = ThumbnailMetrics(geometry: g)
        let picture = { (role: PreviewImage.Role) throws -> ThumbnailPicture in
            ThumbnailPicture(image: try #require(ThumbnailImageDecoder.decode(
                PreviewImage(data: syntheticImage(width: 64, height: 64), pixelWidth: 64, pixelHeight: 64, role: role),
                maximumPixelExtent: g.maximumPixelExtent, limits: .standard)), role: role)
        }
        let icon = Canvas(g)
        ThumbnailRenderer.draw(ThumbnailScene(content: .picture(try picture(.icon)), metrics: m), in: icon.context)
        icon.dumpIfRequested("icon")
        #expect(icon.pixel(x: icon.width / 2, y: icon.height / 2).a == 255)
        #expect(icon.pixel(x: 3, y: icon.height / 2).a == 0)
        let figure = Canvas(g)
        ThumbnailRenderer.draw(ThumbnailScene(content: .picture(try picture(.figure)), metrics: m), in: figure.context)
        figure.dumpIfRequested("figure")
        // The sheet shows around the figure: a filled pixel at the page edge that the icon lacks.
        let page = topDown(m.page, canvas: figure, scale: g.scale)
        #expect(figure.pixel(x: Int(page.minX) + 6, y: Int(page.minY) + 20).a == 255)
    }

    @Test(arguments: [16, 48, 64, 128, 512])
    func everyShapeDrawsAtEverySizeWithoutTrapping(side: Int) throws {
        for scale in [CGFloat(1), 2] {
            guard let g = ThumbnailGeometry(maximumSize: CGSize(width: side, height: side), scale: scale) else { continue }
            let m = ThumbnailMetrics(geometry: g)
            var contents: [ThumbnailContent] = [try textPage(g)]
            let grid = try #require(ThumbnailGrid(headers: [], columnKinds: [.numeric, .text], rowCount: 2,
                columnCount: 2, rowsAreLowerBound: false, sampleRowCount: 2))
            contents.append(.grid(grid))
            for (index, content) in contents.enumerated() {
                let canvas = Canvas(g)
                ThumbnailRenderer.draw(scene(content, g), in: canvas.context)
                canvas.dumpIfRequested("size-\(side)@\(Int(scale))x-\(index)")
                #expect(canvas.opaqueCount > 0)
            }
        }
    }

    @Test func nonSquareCanvasesCenterTheSheet() throws {
        let g = try #require(ThumbnailGeometry(maximumSize: CGSize(width: 300, height: 128), scale: 1))
        let canvas = Canvas(g)
        ThumbnailRenderer.draw(scene(try textPage(g), g), in: canvas.context)
        canvas.dumpIfRequested("wide")
        #expect(canvas.pixel(x: 2, y: 64).a == 0 && canvas.pixel(x: 297, y: 64).a == 0)
        #expect(canvas.pixel(x: 150, y: 64).a == 255)
    }

    @Test func drawingRunsOffTheMainThreadAndConcurrently() async throws {
        let g = geometry(128)
        let content = try textPage(g)
        let scene = scene(content, g)
        let counts = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    #expect(pthread_main_np() == 0)
                    let canvas = Canvas(g)
                    ThumbnailRenderer.draw(scene, in: canvas.context)
                    return canvas.opaqueCount
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(counts).count == 1 && counts[0] > 0)
    }

    @Test func aWordWrappedUnicodePageRenders() throws {
        let g = geometry(256)
        let m = ThumbnailMetrics(geometry: g)
        let page = try #require(ThumbnailExcerpt.page(from: "日本語のテキストと English words mixed مرحبا بالعالم together\nsecond", syntax: .plain, metrics: m))
        let canvas = Canvas(g)
        ThumbnailRenderer.draw(scene(.text(page), g), in: canvas.context)
        canvas.dumpIfRequested("unicode")
        #expect(canvas.inkCount(in: topDown(m.textArea, canvas: canvas, scale: g.scale)) > 100)
    }
}

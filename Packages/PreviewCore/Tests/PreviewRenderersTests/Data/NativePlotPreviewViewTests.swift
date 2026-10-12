import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native plot preview", .serialized)
@MainActor
struct NativePlotPreviewViewTests {
    private func modes(paths: [[SafePlot.Position]], points: [SafePlot.Position] = [], simplified: Bool = false) -> SafePreviewModes {
        let json = "{}"
        var result = SafePreviewModes(TextPresentation(formatID: .gpx, text: json, lineCount: 1, byteCount: 2,
                                                       encoding: .utf8, redactionCount: 0, syntax: .json), locale: .current)
        result.plot = SafePlot(paths: paths, points: points, simplified: simplified)
        return result
    }

    private let walk: [SafePlot.Position] = [.init(longitude: 12.49, latitude: 41.89), .init(longitude: 12.50, latitude: 41.90),
                                             .init(longitude: 12.51, latitude: 41.91)]

    private func style(_ theme: PreviewTheme = .light, locale: Locale = .current) -> SafeModeStyle {
        SafeModeStyle(typography: .init(), palette: .init(theme: theme, isDark: theme == .dark, increasedContrast: false),
                      syntaxStyle: .init(), locale: locale)
    }

    private func makeView() -> NativePlotPreviewView {
        let view = NativePlotPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    @Test func displayShowsTheExtentAnAccessibleImageAndTheSimplificationNotice() throws {
        let view = makeView()
        view.display(modes(paths: [walk], points: [.init(longitude: 12.4964, latitude: 41.9028)], simplified: true),
                     mode: .plot, style: style())
        let plot = SafePlot(paths: [walk], points: [.init(longitude: 12.4964, latitude: 41.9028)], simplified: true)
        let extent = NativePlotPreviewView.extentText(plot, locale: .current)
        #expect(view.captionLabel.stringValue.hasPrefix(extent))
        #expect(view.captionLabel.stringValue == extent)
        #expect(view.canvas.accessibilityRole() == .image)
        #expect(view.canvas.isAccessibilityElement())
        #expect(view.canvas.accessibilityLabel() == PreviewStrings.format(.dataPlotAccessibility, arguments: [Int64(1), Int64(1)], locale: .current))
        #expect(view.canvas.accessibilityValue() as? String == extent)
        #expect(view.canvas.accessibilityHelp() == PreviewStrings.text(.dataPlotHelp))
        // Without simplification the notice is absent.
        view.display(modes(paths: [walk]), mode: .plot, style: style())
        #expect(!view.captionLabel.stringValue.contains(PreviewStrings.text(.dataPlotSimplified)))
    }

    @Test func extentTextFollowsThePresentationLocale() throws {
        let plot = SafePlot(paths: [walk], points: [], simplified: false)
        let english = NativePlotPreviewView.extentText(plot, locale: Locale(identifier: "en_US"))
        let german = NativePlotPreviewView.extentText(plot, locale: Locale(identifier: "de_DE"))
        #expect(english.contains("12.4900") && german.contains("12,4900"))
        #expect(english != german)
    }

    @Test func clearRemovesEveryTraceOfThePreviousFile() {
        let view = makeView()
        view.display(modes(paths: [walk]), mode: .plot, style: style())
        view.clear()
        #expect(view.captionLabel.stringValue.isEmpty)
        #expect(view.canvas.accessibilityLabel() == nil && view.canvas.accessibilityValue() == nil && view.canvas.accessibilityHelp() == nil)
        // Another mode, or a presentation without a plot, shows nothing stale either.
        view.display(modes(paths: [walk]), mode: .plot, style: style())
        view.display(modes(paths: [walk]), mode: .summary, style: style())
        #expect(view.captionLabel.stringValue.isEmpty)
    }

    @Test func projectionKeepsProportionsCentersAndStaysInsideTheArea() {
        let area = CGRect(x: 24, y: 24, width: 352, height: 252)
        let extent = (west: 10.0, south: 40.0, east: 12.0, north: 41.0)
        let project = PlotCanvas.projection(extent: extent, in: area)
        let corners = [SafePlot.Position(longitude: 10, latitude: 41), .init(longitude: 12, latitude: 41),
                       .init(longitude: 10, latitude: 40), .init(longitude: 12, latitude: 40)].map(project)
        // North is up; the box is as wide as 2 degrees of longitude scaled by cos(40.5 degrees) allows.
        #expect(corners[0].y == corners[1].y && corners[2].y == corners[3].y && corners[0].y < corners[2].y)
        let width = corners[1].x - corners[0].x, height = corners[2].y - corners[0].y
        let expectedRatio = 2 * cos(40.5 * Double.pi / 180) / 1
        #expect(abs(Double(width / height) - expectedRatio) < 1e-9)
        for corner in corners { #expect(area.insetBy(dx: -0.001, dy: -0.001).contains(corner)) }
        // The drawing is centered in the area on the axis it does not fill.
        #expect(abs((corners[0].x + corners[1].x) / 2 - area.midX) < 1e-9 || abs((corners[0].y + corners[2].y) / 2 - area.midY) < 1e-9)
    }

    @Test func aSinglePointAndAStraightLineHaveNoDivisionByZero() {
        let area = CGRect(x: 0, y: 0, width: 100, height: 80)
        let point = PlotCanvas.projection(extent: (5, 5, 5, 5), in: area)(.init(longitude: 5, latitude: 5))
        #expect(point.x.isFinite && point.y.isFinite && abs(point.x - 50) < 1e-9 && abs(point.y - 40) < 1e-9)
        let vertical = PlotCanvas.projection(extent: (5, 0, 5, 10), in: area)
        let top = vertical(.init(longitude: 5, latitude: 10)), bottom = vertical(.init(longitude: 5, latitude: 0))
        #expect(abs(top.y - 0) < 1e-9 && abs(bottom.y - 80) < 1e-9 && abs(top.x - 50) < 1e-9)
        // Near the poles the longitude scale never collapses to zero.
        let polar = PlotCanvas.projection(extent: (0, 89.9, 180, 90), in: area)(.init(longitude: 180, latitude: 90))
        #expect(polar.x.isFinite && polar.y.isFinite)
    }

    @Test func drawingUsesThePaletteAndChangesWithTheContent() throws {
        let view = makeView()
        view.display(modes(paths: [walk], points: [.init(longitude: 12.5, latitude: 41.9)]), mode: .plot, style: style(.light))
        let withPlot = try render(view)
        // A pixel in the canvas corner shows the palette background.
        let corner = try #require(withPlot.colorAt(x: 2, y: withPlot.pixelsHigh - 2)?.usingColorSpace(.sRGB))
        #expect(corner.redComponent > 0.97 && corner.greenComponent > 0.97 && corner.blueComponent > 0.97)
        view.display(modes(paths: []), mode: .plot, style: style(.light))
        let empty = try render(view)
        #expect(withPlot.representation(using: .png, properties: [:]) != empty.representation(using: .png, properties: [:]))
        // A dark theme repaints the background and the strokes.
        view.appearance = NSAppearance(named: .darkAqua)
        view.display(modes(paths: [walk]), mode: .plot, style: style(.dark))
        let dark = try render(view)
        let darkCorner = try #require(dark.colorAt(x: 2, y: dark.pixelsHigh - 2)?.usingColorSpace(.sRGB))
        #expect(darkCorner.redComponent < 0.2 && darkCorner.greenComponent < 0.2)
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    @Test func theRegistryCreatesThePlotViewOnlyForThePlotMode() {
        #expect(SafeModeViewRegistry.makeView(for: .plot) is NativePlotPreviewView)
        #expect(SafeModeViewRegistry.makeView(for: .summary) == nil)
        #expect(SafeModeViewRegistry.makeView(for: .table) == nil)
    }
}

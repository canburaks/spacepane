import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Decision 027, Q-77 and review DM-31: the plot's "long paths show only some points" notice belongs to the one
/// limits strip, not to the view's caption, and no path is ever drawn as a line across the whole map. The notice is
/// read through the strip's own entry point (`ModePresentationNotices`), so that test fails until the hook that asks
/// `DrawnModeNotices` is in place as well as the wording. The file name carries the workstream slug ("documents") for
/// the ownership check.
@Suite("Q77 plot notice and antimeridian drawing", .serialized)
@MainActor
struct Q77DocumentsPlotLimitsTests {
    private let english = Locale(identifier: "en_US")
    private let simplifiedNotice = "Long paths show only some points. Source lists the drawn points."

    private func presentation() -> TextPresentation {
        TextPresentation(formatID: .gpx, text: "{}", lineCount: 1, byteCount: 2, encoding: .utf8, redactionCount: 0, syntax: .json)
    }

    private func modes(paths: [[SafePlot.Position]], points: [SafePlot.Position] = [], simplified: Bool = false) -> SafePreviewModes {
        var result = SafePreviewModes(presentation(), locale: english)
        result.plot = SafePlot(paths: paths, points: points, simplified: simplified)
        return result
    }

    private func style() -> SafeModeStyle {
        SafeModeStyle(typography: .init(), palette: .init(theme: .light, isDark: false, increasedContrast: false),
                      syntaxStyle: .init(), locale: english)
    }

    private func makeView() -> NativePlotPreviewView {
        let view = NativePlotPreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    private func position(_ longitude: Double, _ latitude: Double) -> SafePlot.Position {
        SafePlot.Position(longitude: longitude, latitude: latitude)
    }

    // MARK: The notice

    @Test func theSimplificationNoticeLeavesTheCaptionAndGoesToTheLimitsStrip() {
        let walk = [position(12.49, 41.89), position(12.51, 41.91)]
        let plot = modes(paths: [walk], simplified: true)
        let view = makeView()
        view.display(plot, mode: .plot, style: style())
        // The caption is the extent alone; what the preview left out is the strip's to say.
        let extent = NativePlotPreviewView.extentText(SafePlot(paths: [walk], points: [], simplified: true), locale: english)
        #expect(view.captionLabel.stringValue == extent)
        #expect(!view.captionLabel.stringValue.contains(simplifiedNotice))
        #expect(ModePresentationNotices.notices(for: presentation(), modes: plot, mode: .plot, locale: english)
                == [PresentationNotice(kind: .limit, text: simplifiedNotice)])
    }

    @Test func aPlotThatWasNotThinnedOrAnotherModeHasNoPlotNotice() {
        let whole = modes(paths: [[position(12.49, 41.89), position(12.51, 41.91)]])
        #expect(ModePresentationNotices.notices(for: presentation(), modes: whole, mode: .plot, locale: english).isEmpty)
        let thinned = modes(paths: [[position(12.49, 41.89), position(12.51, 41.91)]], simplified: true)
        #expect(ModePresentationNotices.notices(for: presentation(), modes: thinned, mode: .summary, locale: english).isEmpty)
    }

    // MARK: Nothing streaks across the map

    @Test func aPathCrossingTheAntimeridianIsNeverDrawnAcrossTheWholeMap() throws {
        // Two outlying points keep the frame as wide as the world, so the ferry's 2-degree hop over the
        // antimeridian must not become a line the full width of the drawing.
        let ferry = [position(-179, 25), position(179, 25)]
        let view = makeView()
        view.display(modes(paths: [ferry], points: [position(0, 0), position(0, 50)]), mode: .plot, style: style())
        view.layoutSubtreeIfNeeded()
        let canvas = view.canvas
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        // The ferry runs along the vertical middle of the drawing; sample the rows around it between the
        // frame's side borders. Every pixel there must be the palette background.
        let factor = CGFloat(bitmap.pixelsWide) / canvas.bounds.width
        let middle = Int(canvas.bounds.midY * factor)
        let first = Int((24 + 30) * factor)
        let last = Int((canvas.bounds.width - 24 - 30) * factor)
        try #require(last > first)
        for row in (middle - 1)...(middle + 1) {
            for column in stride(from: first, through: last, by: 3) {
                let color = try #require(bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB))
                #expect(color.redComponent > 0.9 && color.greenComponent > 0.9 && color.blueComponent > 0.9,
                        "ink at column \(column), row \(row)")
            }
        }
    }
}

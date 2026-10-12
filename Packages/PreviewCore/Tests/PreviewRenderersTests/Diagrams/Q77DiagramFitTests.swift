import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The pure fit rule behind the legibility floor (decision 027, Q-77). Written against numbers worked out by hand, not
/// against the production formula: the default font is 13 points, so secondary text is 11.05 points and the floor is
/// 7 / 11.05 of the natural size.
@Suite("Q77 diagram fit rule")
struct Q77DiagramFitTests {
    private let font = DiagramFont(size: 13)
    private let readable: CGFloat = 7 / 11.05
    private func fit(_ width: CGFloat, _ height: CGFloat, in bounds: CGSize = CGSize(width: 640, height: 420),
                     font customFont: DiagramFont? = nil, minimum: CGFloat = 0.005, maximum: CGFloat = 16) -> DiagramFit {
        DiagramFit.make(content: CGSize(width: width, height: height), bounds: bounds, padding: 8,
                        font: customFont ?? font, minimumScale: minimum, maximumScale: maximum)
    }

    // MARK: The font and the floor

    @Test func secondaryTextIsEightyFivePercentOfTheLabelSizeAndNeverUnderSixPoints() {
        #expect(abs(DiagramFont(size: 13).smallPointSize - 11.05) < 1e-9)
        #expect(DiagramFont(size: 6).smallPointSize == 6)
        #expect(abs(DiagramFont(size: 72).smallPointSize - 61.2) < 1e-9)
    }

    @Test func theFloorKeepsTheSmallestTextAtSevenPointsAndNeverMagnifies() {
        #expect(abs(DiagramFit.floorScale(for: font, minimumScale: 0.005) - readable) < 1e-9)
        #expect(abs(DiagramFit.floorScale(for: DiagramFont(size: 72), minimumScale: 0.005) - 7 / 61.2) < 1e-9)
        // Text already at or under seven points cannot be made legible by enlarging: the floor is the natural size.
        #expect(DiagramFit.floorScale(for: DiagramFont(size: 6), minimumScale: 0.005) == 1)
        // The zoom lower bound is a lower bound for the floor too.
        #expect(DiagramFit.floorScale(for: DiagramFont(size: 72), minimumScale: 0.2) == 0.2)
    }

    // MARK: Fitting

    @Test func smallContentIsEnlargedAtMostTwiceAndCentered() {
        let result = fit(100, 50)
        #expect(result.outcome == .natural)
        #expect(result.scale == 2)
        #expect(abs(result.offset.x - 220) < 1e-9 && abs(result.offset.y - 160) < 1e-9)
    }

    @Test func contentAboveTheFloorIsShownWholeAndOnlyShrunk() {
        let result = fit(800, 400)
        #expect(result.outcome == .shrunk)
        #expect(abs(result.scale - 0.78) < 1e-9)
        #expect(abs(result.offset.x - 8) < 1e-9 && abs(result.offset.y - 54) < 1e-9)
    }

    @Test func contentThatWouldFallUnderTheFloorIsDrawnAtTheFloorFromTheLeadingTop() {
        let wide = fit(4_000, 300)
        #expect(wide.outcome == .floored)
        #expect(abs(wide.scale - readable) < 1e-9)
        #expect(abs(wide.offset.x - 8) < 1e-9)
        // It still fits vertically, so it is centered on that axis.
        #expect(abs(wide.offset.y - (420 - 300 * readable) / 2) < 1e-6)
        let both = fit(4_000, 6_000)
        #expect(both.outcome == .floored && abs(both.scale - readable) < 1e-9)
        #expect(both.offset == CGPoint(x: 8, y: 8))
    }

    @Test func aTallNarrowDrawingIsNeverMagnifiedToFillTheWidth() {
        let narrow = fit(300, 6_000)
        #expect(narrow.outcome == .floored)
        #expect(narrow.scale == 1)
        #expect(abs(narrow.offset.x - 170) < 1e-9 && abs(narrow.offset.y - 8) < 1e-9)
    }

    @Test func aTallDrawingIsDrawnExactlyAsWideAsTheViewWhenThatIsAboveTheFloor() {
        let result = fit(900, 6_000)
        #expect(result.outcome == .floored)
        #expect(abs(result.scale - 624.0 / 900.0) < 1e-9)
        #expect(abs(result.offset.x - 8) < 1e-6 && abs(result.offset.y - 8) < 1e-9)
    }

    @Test func theZoomBoundsStillApply() {
        #expect(fit(100, 50, maximum: 1.5).scale == 1.5)
        let tiny = fit(4_000_000, 300, minimum: 0.7)
        #expect(tiny.scale == 0.7 && tiny.outcome == .floored)
    }

    @Test func degenerateSizesStayFinite() {
        for result in [fit(0, 0), fit(1, 1, in: .zero), fit(-5, 9, in: CGSize(width: 3, height: 3)), fit(1e12, 1e12)] {
            #expect(result.scale.isFinite && result.scale > 0)
            #expect(result.offset.x.isFinite && result.offset.y.isFinite)
        }
    }

    @Test func wheneverTheWholeDrawingIsShownTheFitIsTheOldFitExactly() {
        // The rule the canvas used before the floor, written out: scale to fit, at most twice, centered.
        for content in [CGSize(width: 200, height: 100), CGSize(width: 500, height: 300), CGSize(width: 800, height: 400),
                        CGSize(width: 640, height: 420), CGSize(width: 1_000, height: 900)] {
            for bounds in [CGSize(width: 640, height: 420), CGSize(width: 1_280, height: 840), CGSize(width: 400, height: 300)] {
                let available = CGSize(width: bounds.width - 16, height: bounds.height - 16)
                let whole = min(available.width / content.width, available.height / content.height, 2)
                guard whole >= readable else { continue }
                let result = DiagramFit.make(content: content, bounds: bounds, padding: 8, font: font, minimumScale: 0.005, maximumScale: 16)
                #expect(result.outcome != .floored)
                #expect(abs(result.scale - whole) < 1e-9)
                #expect(abs(result.offset.x - (bounds.width - content.width * whole) / 2) < 1e-6)
                #expect(abs(result.offset.y - (bounds.height - content.height * whole) / 2) < 1e-6)
            }
        }
    }
}

/// The wording of the diagram notices (the fit note and the selection receipt), from the presentation locale
/// (decision 027, Q-77).
@Suite("Q77 diagram notices")
struct Q77DiagramNoticeTests {
    private let english = Locale(identifier: "en_US")

    @Test func theReadableNoteNamesTheScaleInTheLocalesPercentFormat() {
        let notice = DiagramNotice.readable(scale: 0.633)
        #expect(notice.text(locale: english) == PreviewStrings.format(.diagramNoticeReadable, arguments: ["63%"], locale: english))
        #expect(PreviewStrings.format(.diagramNoticeReadable, arguments: ["63%"], locale: english, languagePreferences: ["en"])
                == "Drawn at 63% to stay readable. Scroll or drag for the rest.")
        #expect(DiagramNotice.percentText(0.633, locale: english) == "63%")
        #expect(DiagramNotice.percentText(0.633, locale: Locale(identifier: "tr_TR")).hasPrefix("%"))
        let german = DiagramNotice.percentText(0.633, locale: Locale(identifier: "de_DE"))
        #expect(german.contains("63") && german.contains("%") && german != "63%")
    }

    @Test func aNoticeBecomesTheLimitsStripsTypedNotice() {
        let readable = DiagramNotice.readable(scale: 0.5).presentationNotice(locale: english)
        #expect(readable.kind == .limit && readable.text == DiagramNotice.readable(scale: 0.5).text(locale: english))
        let drawn = MarkdownDiagramFences.Receipt(selectedIndex: 2, total: 3).presentationNotice(locale: english)
        #expect(drawn == PresentationNotice(kind: .limit, text: "Diagram 2 of 3 is drawn."))
    }

    @Test func theDrawnNoticeFormatsBothNumbersForTheLocaleAndPrintsNoFormatDirective() {
        for locale in [english, Locale(identifier: "de_DE"), Locale(identifier: "hi_IN"), Locale(identifier: "ru_RU")] {
            let text = MarkdownDiagramFences.Receipt(selectedIndex: 12, total: 1_204).text(locale: locale)
            #expect(text.contains(12.formatted(.number.locale(locale))) && text.contains(1_204.formatted(.number.locale(locale))), "\(text)")
            #expect(!text.contains("%"), "\(text)")
        }
    }
}

/// How the diagram view shows the legibility floor (decision 027, Q-77): a quiet note under the canvas, and nothing
/// while the whole drawing is readable.
@Suite("Q77 diagram fit note", .serialized)
@MainActor
struct Q77DiagramFitNoteTests {
    private let english = Locale(identifier: "en_US")

    private func chain(_ count: Int) -> String {
        "flowchart LR\n" + (0..<(count - 1)).map { "N\($0) --> N\($0 + 1)" }.joined(separator: "\n")
    }

    private func style(locale: Locale? = nil) -> SafeModeStyle {
        SafeModeStyle(typography: PreviewTypography(), palette: NativeTextPalette(theme: .system, isDark: false, increasedContrast: false),
                      syntaxStyle: PreviewSyntaxStyle(usesColor: true), locale: locale ?? english)
    }

    private func show(_ text: String, width: CGFloat, height: CGFloat, locale: Locale? = nil) -> NativeDiagramView {
        let presentation = TextPresentation(formatID: .mermaid, text: text, lineCount: text.split(separator: "\n", omittingEmptySubsequences: false).count,
                                            byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .mermaid)
        let view = NativeDiagramView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.display(SafePreviewModes(presentation, locale: locale ?? english), mode: .diagram, style: style(locale: locale))
        settle(view)
        return view
    }

    private func settle(_ view: NativeDiagramView) {
        view.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
    }

    @Test func aFlooredDrawingShowsTheScaleItIsDrawnAtUnderTheCanvas() throws {
        let view = show(chain(40), width: 640, height: 420)
        try #require(view.canvas.fitOutcome == .floored)
        let expected = DiagramNotice.readable(scale: Double(view.canvas.scale))
        #expect(view.canvas.fitNotice == expected)
        #expect(!view.noteLabel.isHidden)
        #expect(view.noteLabel.stringValue == expected.text(locale: english))
        #expect(view.noteLabel.toolTip == view.noteLabel.stringValue)
        #expect(view.presentationNotices == [expected.presentationNotice(locale: english)])
        // The note takes its own room under the canvas, so it never covers the drawing.
        #expect(view.noteLabel.frame.height > 0)
        #expect(abs(view.canvas.frame.height + view.noteLabel.frame.height - view.bounds.height) < 1e-6)
        #expect(view.noteLabel.textColor == style().palette.muted)
    }

    @Test func aDrawingShownWholeSaysNothingAndTakesNoRoom() {
        let view = show("flowchart LR\nA --> B", width: 640, height: 420)
        #expect(view.canvas.fitNotice == nil)
        #expect(view.noteLabel.isHidden && view.noteLabel.stringValue.isEmpty && view.noteLabel.toolTip == nil)
        #expect(view.presentationNotices.isEmpty)
        #expect(view.noteLabel.frame.height == 0)
        #expect(abs(view.canvas.frame.height - view.bounds.height) < 1e-6)
    }

    @Test func theNoteFollowsTheViewSizeAndTheReadersControl() throws {
        let view = show(chain(40), width: 640, height: 420)
        let content = try #require(view.canvas.diagram).contentSize
        try #require(!view.noteLabel.isHidden)
        // Room for the whole drawing at a readable scale: the note goes away.
        view.setFrameSize(NSSize(width: content.width * 3, height: content.height * 3))
        settle(view)
        #expect(view.noteLabel.isHidden && view.presentationNotices.isEmpty)
        view.setFrameSize(NSSize(width: 640, height: 420))
        settle(view)
        #expect(!view.noteLabel.isHidden)
        // The reader pans: the note has done its job and goes; fitting again brings it back.
        view.canvas.pan(by: CGPoint(x: -40, y: 0))
        #expect(view.noteLabel.isHidden && view.presentationNotices.isEmpty)
        view.canvas.zoomToFit()
        #expect(!view.noteLabel.isHidden)
        view.clear()
        #expect(view.noteLabel.isHidden && view.noteLabel.stringValue.isEmpty)
    }

    @Test func theNoteUsesThePresentationLocaleForThePercentage() throws {
        let german = Locale(identifier: "de_DE")
        let view = show(chain(40), width: 640, height: 420, locale: german)
        try #require(!view.noteLabel.isHidden)
        #expect(view.noteLabel.stringValue == DiagramNotice.readable(scale: Double(view.canvas.scale)).text(locale: german))
        #expect(view.noteLabel.stringValue.contains(DiagramNotice.percentText(Double(view.canvas.scale), locale: german)))
    }
}

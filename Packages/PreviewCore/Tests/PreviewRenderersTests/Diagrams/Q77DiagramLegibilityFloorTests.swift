import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Decision 027, Q-77 and review DM-24: a diagram is never fitted so small that its text cannot be read. The
/// expectations spell out the floor independently (7 points over the secondary text size, 85% of 13 points by
/// default), so a wrong production constant fails here.
@Suite("Q77 diagram legibility floor", .serialized)
@MainActor
struct Q77DiagramLegibilityFloorTests {
    private let english = Locale(identifier: "en_US")
    /// The default preview font is 13 points; secondary diagram text is 85% of it.
    private let defaultFloor: CGFloat = 7 / (13 * 0.85)

    /// One row of `count` nodes: wide, and one node tall.
    private func chain(_ count: Int) -> String {
        "flowchart LR\n" + (0..<(count - 1)).map { "N\($0) --> N\($0 + 1)" }.joined(separator: "\n")
    }

    private func presentation(_ text: String) -> TextPresentation {
        TextPresentation(formatID: .mermaid, text: text, lineCount: text.split(separator: "\n", omittingEmptySubsequences: false).count,
                         byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .mermaid)
    }

    private func style(fontSize: Double = 13, dark: Bool = false) -> SafeModeStyle {
        SafeModeStyle(typography: PreviewTypography(fontSize: fontSize),
                      palette: NativeTextPalette(theme: .system, isDark: dark, increasedContrast: false),
                      syntaxStyle: PreviewSyntaxStyle(usesColor: true), locale: english)
    }

    /// Shows `text` in a view of the given size and settles layout (twice: a note under the canvas changes its height).
    private func show(_ text: String, width: CGFloat, height: CGFloat, style: SafeModeStyle? = nil) -> (NativeDiagramView, SafePreviewModes) {
        let view = NativeDiagramView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let modes = SafePreviewModes(presentation(text), locale: english)
        view.display(modes, mode: .diagram, style: style ?? self.style())
        view.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        return (view, modes)
    }

    private func resize(_ view: NativeDiagramView, width: CGFloat, height: CGFloat) {
        view.setFrameSize(NSSize(width: width, height: height))
        view.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
    }

    // MARK: The floor

    @Test func aDiagramThatCannotBeShownWholeIsDrawnAtTheFloorFromItsLeadingTopCorner() throws {
        let (view, _) = show(chain(40), width: 640, height: 420)
        let canvas = view.canvas
        let content = try #require(canvas.diagram).contentSize
        // Precondition: showing it whole would need a scale under the floor.
        try #require((canvas.bounds.width - 16) / content.width < defaultFloor)
        #expect(abs(canvas.scale - defaultFloor) < 1e-9)
        #expect(canvas.fitsToView)
        // It begins at the leading edge, so the reader starts at the beginning and drags toward the rest.
        #expect(abs(canvas.offset.x - 8) < 1e-9)
        // One node tall, it still fits vertically and stays centered on that axis.
        #expect(abs(canvas.offset.y - (canvas.bounds.height - content.height * canvas.scale) / 2) < 1e-6)
    }

    @Test func aDiagramThatFitsAboveTheFloorIsShownWholeAsBefore() throws {
        let (view, _) = show(chain(40), width: 640, height: 420)
        let content = try #require(view.canvas.diagram).contentSize
        // Wide enough for 80% of the natural size: above the floor, so the whole drawing fits exactly. The host
        // aligns the view's frame to whole pixels, so the scale it yields is within a pixel's worth of 80%.
        resize(view, width: content.width * 0.8 + 16, height: 2_000)
        let canvas = view.canvas
        #expect(abs(canvas.scale - 0.8) < 1e-3, "\(canvas.scale)")
        #expect(abs(canvas.offset.x - 8) < 1e-3, "\(canvas.offset.x)")
        // Wide enough for more than natural size: enlarged, but never past twice.
        resize(view, width: content.width * 5, height: content.height * 5)
        #expect(abs(canvas.scale - 2) < 1e-9)
        #expect(canvas.scale * content.width <= canvas.bounds.width)
    }

    @Test func aTallDiagramInAWideViewIsDrawnAsWideAsItAllowsNotShrunkToItsHeight() throws {
        // Many rows, one column: the height would need a scale far under the floor.
        let source = "flowchart TD\n" + (0..<60).map { "N\($0) --> N\($0 + 1)" }.joined(separator: "\n")
        let (view, _) = show(source, width: 640, height: 420)
        let canvas = view.canvas
        let content = try #require(canvas.diagram).contentSize
        try #require((canvas.bounds.height - 16) / content.height < defaultFloor)
        // The width fits comfortably, so the drawing is shown at its natural size and scrolled down, never enlarged.
        try #require((canvas.bounds.width - 16) / content.width >= 1)
        #expect(abs(canvas.scale - 1) < 1e-9)
        #expect(abs(canvas.offset.y - 8) < 1e-9)
    }

    @Test func theFloorFollowsTheConfiguredFontSize() throws {
        let (view, _) = show(chain(40), width: 640, height: 420, style: style(fontSize: 26))
        let canvas = view.canvas
        let content = try #require(canvas.diagram).contentSize
        try #require((canvas.bounds.width - 16) / content.width < 7 / (26 * 0.85))
        #expect(abs(canvas.scale - 7 / (26 * 0.85)) < 1e-9)
        // A font smaller than the floor can never be made legible by enlarging, so the drawing stays natural.
        let (small, _) = show(chain(40), width: 640, height: 420, style: style(fontSize: 8))
        #expect(abs(small.canvas.scale - 1) < 1e-9)
    }

    // MARK: Reader control and appearance

    @Test func zoomingOutPastTheFloorIsTheReadersChoiceAndFitReturnsToTheFloor() {
        let (view, _) = show(chain(40), width: 640, height: 420)
        let canvas = view.canvas
        canvas.zoom(by: 0.1)
        #expect(abs(canvas.scale - defaultFloor * 0.1) < 1e-9)
        #expect(!canvas.fitsToView)
        canvas.zoomToFit()
        #expect(abs(canvas.scale - defaultFloor) < 1e-9)
        #expect(canvas.fitsToView)
    }

    @Test func resizingReevaluatesTheFloorUntilTheReaderTakesControl() throws {
        let (view, _) = show(chain(40), width: 640, height: 420)
        let canvas = view.canvas
        let content = try #require(canvas.diagram).contentSize
        resize(view, width: content.width * 3, height: content.height * 3)
        #expect(canvas.scale > defaultFloor)
        resize(view, width: 640, height: 420)
        #expect(abs(canvas.scale - defaultFloor) < 1e-9)
    }

    @Test func anAppearanceChangeKeepsTheFloorWithoutRelayout() throws {
        let (view, modes) = show(chain(40), width: 640, height: 420)
        let before = try #require(view.canvas.diagram)
        view.display(modes, mode: .diagram, style: style(dark: true))
        view.layoutSubtreeIfNeeded()
        // The same laid-out diagram: an appearance change restyles it without measuring it again.
        #expect(view.canvas.diagram?.generation == before.generation)
        #expect(abs(view.canvas.scale - defaultFloor) < 1e-9)
    }
}

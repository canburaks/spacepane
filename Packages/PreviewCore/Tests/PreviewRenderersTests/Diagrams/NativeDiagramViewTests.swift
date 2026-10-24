import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native diagram view", .serialized)
@MainActor
struct NativeDiagramViewTests {
    private let english = Locale(identifier: "en_US")
    private let flowchart = "flowchart TD\nA[Start] -->|go| B{Decide}\nB --> C[Finish]\nB --> D[Retry]"

    private func presentation(_ text: String, format: FormatID = .mermaid, syntax: TextSyntax = .mermaid,
                              sourceRecordCount: Int? = nil) -> TextPresentation {
        TextPresentation(formatID: format, text: text, lineCount: text.split(separator: "\n", omittingEmptySubsequences: false).count,
                         byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax,
                         sourceRecordCount: sourceRecordCount)
    }

    private func style(dark: Bool = false, contrast: Bool = false, usesColor: Bool = true, locale: Locale? = nil,
                       typography: PreviewTypography = PreviewTypography()) -> SafeModeStyle {
        SafeModeStyle(typography: typography, palette: NativeTextPalette(theme: .system, isDark: dark, increasedContrast: contrast),
                      syntaxStyle: PreviewSyntaxStyle(usesColor: usesColor), locale: locale ?? english)
    }

    private func makeView(width: CGFloat = 640, height: CGFloat = 420) -> NativeDiagramView {
        NativeDiagramView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    }

    private func show(_ text: String, in view: NativeDiagramView, style: SafeModeStyle? = nil) -> SafePreviewModes {
        let modes = SafePreviewModes(presentation(text), locale: english)
        view.display(modes, mode: .diagram, style: style ?? self.style())
        view.layoutSubtreeIfNeeded()
        return modes
    }

    // MARK: Modes

    @Test func aSupportedDiagramOffersTheDiagramModeAndOpensIt() {
        let modes = SafePreviewModes(presentation(flowchart), locale: english)
        #expect(modes.available == [.source, .diagram])
        #expect(modes.initialMode(for: .mermaid) == .diagram)
        #expect(!modes.hasStructureFallback)
        #expect(modes.diagram?.kind == .flowchart)
    }

    @Test func anUnsupportedDiagramKeepsSourceAndTheStructureFallbackNotice() {
        for source in ["gantt\n  title Schedule\n  section A\n  Task :a1, 2024-01-01, 3d", "flowchart TD\nA -->", ""] {
            let modes = SafePreviewModes(presentation(source), locale: english)
            #expect(modes.diagram == nil)
            #expect(modes.available == [.source])
            #expect(modes.initialMode(for: .mermaid) == .source)
            #expect(modes.hasStructureFallback)
        }
    }

    @Test func drawioDocumentsOpenInTheDiagramModeWithAPageNotice() {
        let model = "<mxGraphModel><root><mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"2\" value=\"Only shape\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"0\" y=\"0\" width=\"90\" height=\"40\" as=\"geometry\"/></mxCell></root></mxGraphModel>"
        let several = presentation(model, format: .drawio, syntax: .drawio, sourceRecordCount: 3)
        let modes = SafePreviewModes(several, locale: english)
        #expect(modes.available == [.source, .diagram])
        #expect(modes.initialMode(for: .drawio) == .diagram)
        let notices = PresentationNotices.lines(for: several, locale: english)
        #expect(notices == [PreviewStrings.format(.diagramDrawioPage, arguments: [Int64(3)], locale: english)])
        #expect(notices[0].contains("3"))
        #expect(PresentationNotices.lines(for: presentation(model, format: .drawio, syntax: .drawio, sourceRecordCount: 1), locale: english).isEmpty)
    }

    @Test func otherFormatsNeverGetADiagram() {
        let json = presentation("{\"a\": 1}", format: .json, syntax: .json)
        #expect(SafePreviewModes(json, locale: english).diagram == nil)
        #expect(SafePreviewModes(presentation("plain"), locale: english).initialMode(for: .plainText) == .source)
    }

    // MARK: Display and clear

    @Test func displayDrawsTheDiagramAndClearDropsIt() {
        let view = makeView()
        _ = show(flowchart, in: view)
        #expect(view.canvas.diagram?.kind == .flowchart)
        #expect(view.canvas.fitsToView)
        #expect(view.canvas.scale > 0)
        view.clear()
        #expect(view.canvas.diagram == nil)
        #expect(view.canvas.accessibilityChildren()?.isEmpty == true)
        #expect(!view.canvas.isAccessibilityElement())
    }

    @Test func displayingAnotherModeOrAnUnsupportedPresentationClears() {
        let view = makeView()
        let modes = show(flowchart, in: view)
        view.display(modes, mode: .source, style: style())
        #expect(view.canvas.diagram == nil)
        _ = show(flowchart, in: view)
        view.display(SafePreviewModes(presentation("gantt\n title x"), locale: english), mode: .diagram, style: style())
        #expect(view.canvas.diagram == nil)
    }

    @Test func theHostingPreviewOpensTheDiagramAndReplacementsClearIt() {
        let host = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        host.display(.ready(presentation(flowchart)), locale: english)
        host.layoutSubtreeIfNeeded()
        let diagramView = descendants(of: NativeDiagramView.self, in: host).first
        #expect(diagramView != nil && diagramView?.isHidden == false)
        #expect(diagramView?.canvas.diagram?.kind == .flowchart)
        // A different format replaces the content: the diagram is hidden and holds nothing.
        host.display(.ready(presentation("plain words", format: .plainText, syntax: .plain)), locale: english)
        #expect(diagramView?.isHidden == true && diagramView?.canvas.diagram == nil)
        host.display(.ready(presentation(flowchart)), locale: english)
        #expect(diagramView?.isHidden == false && diagramView?.canvas.diagram != nil)
        host.display(.disabledByUser(.mermaid), locale: english)
        #expect(diagramView?.isHidden == true && diagramView?.canvas.diagram == nil)
        host.display(.ready(presentation("gantt\n title x")), locale: english)
        #expect(diagramView?.isHidden == true)
    }

    @Test func theRegistryCreatesTheViewForTheDiagramMode() {
        #expect(SafeModeViewRegistry.makeView(for: .diagram) is NativeDiagramView)
        #expect(SafeModeViewRegistry.makeView(for: .source) == nil)
    }

    // MARK: Zoom and pan

    @Test func zoomPanAndFitBehaveAndAreBounded() {
        let view = makeView()
        _ = show(flowchart, in: view)
        let canvas = view.canvas
        let fitted = canvas.scale
        let diagram = canvas.diagram!
        // Fit centers the diagram inside the view with room to spare.
        #expect(diagram.contentSize.width * fitted <= canvas.bounds.width + 0.001)
        #expect(diagram.contentSize.height * fitted <= canvas.bounds.height + 0.001)
        #expect(abs((canvas.offset.x + diagram.contentSize.width * fitted / 2) - canvas.bounds.midX) < 0.001)
        canvas.zoom(by: 2)
        #expect(abs(canvas.scale - fitted * 2) < 1e-9)
        #expect(!canvas.fitsToView)
        let before = canvas.offset
        canvas.pan(by: CGPoint(x: 30, y: -12))
        #expect(canvas.offset == CGPoint(x: before.x + 30, y: before.y - 12))
        canvas.zoomToFit()
        #expect(abs(canvas.scale - fitted) < 1e-9 && canvas.fitsToView)
        canvas.zoom(by: 1e9)
        #expect(canvas.scale == DiagramCanvasView.maximumScale)
        canvas.zoom(by: 1e-12)
        #expect(canvas.scale == DiagramCanvasView.minimumScale)
        canvas.zoom(by: .nan)
        #expect(canvas.scale == DiagramCanvasView.minimumScale)
    }

    @Test func zoomingAroundAPointKeepsThatPointStill() {
        let view = makeView()
        _ = show(flowchart, in: view)
        let canvas = view.canvas
        let anchor = CGPoint(x: 200, y: 150)
        let scenePoint = CGPoint(x: (anchor.x - canvas.offset.x) / canvas.scale, y: (anchor.y - canvas.offset.y) / canvas.scale)
        canvas.zoom(by: 1.7, around: anchor)
        let after = CGPoint(x: scenePoint.x * canvas.scale + canvas.offset.x, y: scenePoint.y * canvas.scale + canvas.offset.y)
        #expect(abs(after.x - anchor.x) < 1e-6 && abs(after.y - anchor.y) < 1e-6)
    }

    @Test func appearanceChangesKeepZoomAndPanButNewContentResetsThem() {
        let view = makeView()
        let modes = show(flowchart, in: view)
        view.canvas.zoom(by: 3)
        view.canvas.pan(by: CGPoint(x: 5, y: 9))
        let scale = view.canvas.scale, offset = view.canvas.offset
        view.display(modes, mode: .diagram, style: style(dark: true))
        #expect(view.canvas.scale == scale && view.canvas.offset == offset && !view.canvas.fitsToView)
        view.display(modes, mode: .diagram, style: style(contrast: true, usesColor: false))
        #expect(view.canvas.scale == scale && view.canvas.offset == offset)
        view.display(modes, mode: .diagram, style: style(typography: PreviewTypography(fontSize: 20)))
        #expect(view.canvas.diagram?.environment.font.size == 20)
        #expect(view.canvas.scale == scale)
        _ = show("flowchart LR\nX --> Y", in: view)
        #expect(view.canvas.fitsToView)
    }

    @Test func theDiagramUsesThePreviewFontFamilyOrFallsBackToTheSystemFont() {
        let view = makeView()
        let modes = SafePreviewModes(presentation(flowchart), locale: english)
        view.display(modes, mode: .diagram, style: style(typography: PreviewTypography(fontFamily: "Menlo")))
        #expect(view.canvas.font.name != nil)
        view.display(modes, mode: .diagram, style: style(typography: PreviewTypography(fontFamily: "No Such Font Family 12345")))
        #expect(view.canvas.font.name == nil)
        view.display(modes, mode: .diagram, style: style(typography: PreviewTypography(fontSize: 18)))
        #expect(view.canvas.font == DiagramFont(name: nil, size: 18))
    }

    @Test func resizingKeepsRefittingUntilTheUserZooms() {
        let view = makeView()
        _ = show(flowchart, in: view)
        let small = view.canvas.scale
        view.setFrameSize(NSSize(width: 1_280, height: 840))
        view.layoutSubtreeIfNeeded()
        #expect(view.canvas.scale > small)
        view.canvas.zoom(by: 0.5)
        let manual = view.canvas.scale
        view.setFrameSize(NSSize(width: 400, height: 300))
        view.layoutSubtreeIfNeeded()
        #expect(view.canvas.scale == manual)
    }

    @Test func commandKeysZoomOnlyWhileTheDiagramHasFocus() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled], backing: .buffered, defer: true)
        let view = makeView()
        window.contentView = view
        _ = show(flowchart, in: view)
        func event(_ characters: String, flags: NSEvent.ModifierFlags = .command) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                          context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                          isARepeat: false, keyCode: 0))
        }
        let canvas = view.canvas
        let fitted = canvas.scale
        // Without focus the shortcuts are left for other responders.
        #expect(!canvas.performKeyEquivalent(with: try event("+")))
        #expect(canvas.scale == fitted)
        window.makeFirstResponder(canvas)
        #expect(window.firstResponder === canvas)
        #expect(canvas.performKeyEquivalent(with: try event("+")))
        #expect(canvas.scale > fitted)
        #expect(canvas.performKeyEquivalent(with: try event("-")))
        #expect(abs(canvas.scale - fitted) < 1e-9)
        canvas.zoom(by: 4)
        #expect(canvas.performKeyEquivalent(with: try event("0")))
        #expect(abs(canvas.scale - fitted) < 1e-9 && canvas.fitsToView)
        #expect(!canvas.performKeyEquivalent(with: try event("+", flags: [.command, .shift, .option])))
        #expect(!canvas.performKeyEquivalent(with: try event("c")))
    }

    @Test func arrowKeysPanAndPlainKeysZoom() throws {
        let view = makeView()
        _ = show(flowchart, in: view)
        let canvas = view.canvas
        func event(_ characters: String) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                          context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                          isARepeat: false, keyCode: 0))
        }
        let origin = canvas.offset
        canvas.keyDown(with: try event(String(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        #expect(canvas.offset.x > origin.x)
        canvas.keyDown(with: try event(String(UnicodeScalar(NSDownArrowFunctionKey)!)))
        #expect(canvas.offset.y < origin.y)
        let scale = canvas.scale
        canvas.keyDown(with: try event("="))
        #expect(canvas.scale > scale)
        canvas.keyDown(with: try event("0"))
        #expect(canvas.fitsToView)
        canvas.keyDown(with: try event(String(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        #expect(!canvas.fitsToView)
        canvas.keyDown(with: try event(String(UnicodeScalar(NSHomeFunctionKey)!)))
        #expect(canvas.fitsToView)

        let fittedMenu = try #require(canvas.contextMenu())
        #expect(fittedMenu.items.map(\.title) == [
            PreviewStrings.text(.interactionZoomIn),
            PreviewStrings.text(.interactionZoomOut),
            PreviewStrings.text(.geometryReset)
        ])
        #expect(!fittedMenu.items[2].isEnabled)
        canvas.zoom(by: 1.5)
        #expect(!canvas.fitsToView)
        let zoomedMenu = try #require(canvas.contextMenu())
        #expect(zoomedMenu.items[2].isEnabled)
        #expect(NSApplication.shared.sendAction(try #require(zoomedMenu.items[2].action), to: zoomedMenu.items[2].target, from: zoomedMenu.items[2]))
        #expect(canvas.fitsToView)
    }

    // MARK: Accessibility

    @Test func theCanvasIsAnAccessibilityGroupWithNodeChildrenAndAConnectionSummary() throws {
        let view = makeView()
        _ = show(flowchart, in: view)
        let canvas = view.canvas
        #expect(canvas.isAccessibilityElement())
        #expect(canvas.accessibilityRole() == .group)
        let label = try #require(canvas.accessibilityLabel())
        #expect(label == PreviewStrings.format(.diagramSummary, arguments: [PreviewStrings.text(.diagramKindFlowchart), Int64(4), Int64(3)], locale: english))
        #expect(label.contains("Flowchart") && !label.contains("preview.diagram"))
        #expect(canvas.accessibilityHelp() == PreviewStrings.text(.diagramInteractionHelp))
        let children = try #require(canvas.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children.count == 5)
        #expect(children.prefix(4).map { $0.accessibilityLabel() } == ["Start", "Decide", "Finish", "Retry"])
        #expect(children.prefix(4).allSatisfy { $0.accessibilityRoleDescription() == PreviewStrings.text(.diagramRoleNode) })
        #expect(children.prefix(4).allSatisfy { ($0.accessibilityParent() as? NSView) === canvas && !$0.accessibilityFrameInParentSpace().isEmpty })
        let summary = children[4]
        #expect(summary.accessibilityLabel() == PreviewStrings.text(.diagramConnections))
        let value = try #require(summary.accessibilityValue() as? String)
        #expect(value.contains(PreviewStrings.format(.diagramConnectionLabeled, arguments: ["Start", "Decide", "go"], locale: english)))
        #expect(value.contains(PreviewStrings.format(.diagramConnection, arguments: ["Decide", "Finish"], locale: english)))
    }

    @Test func accessibilityFramesFollowZoomAndPan() throws {
        let view = makeView()
        _ = show(flowchart, in: view)
        let canvas = view.canvas
        let first = try #require((canvas.accessibilityChildren() as? [NSAccessibilityElement])?.first)
        let before = first.accessibilityFrameInParentSpace()
        canvas.zoom(by: 2, around: .zero)
        let afterElement = try #require((canvas.accessibilityChildren() as? [NSAccessibilityElement])?.first)
        #expect(afterElement === first)
        let after = afterElement.accessibilityFrameInParentSpace()
        #expect(abs(after.width - before.width * 2) < 1e-6)
        _ = show("flowchart LR\nX --> Y", in: view)
        let newFirst = try #require((canvas.accessibilityChildren() as? [NSAccessibilityElement])?.first)
        #expect(newFirst !== first)
    }

    @Test func accessibilityTextIsLocalizedAndLongConnectionListsAreSummarized() throws {
        let view = makeView()
        let source = "flowchart LR\n" + (0..<(DiagramLimits.maximumAccessibilityConnections + 7)).map { "N\($0) --> M\($0)" }.joined(separator: "\n")
        let german = Locale(identifier: "de_DE")
        view.display(SafePreviewModes(presentation(source), locale: german), mode: .diagram, style: style(locale: german))
        let canvas = view.canvas
        let children = try #require(canvas.accessibilityChildren() as? [NSAccessibilityElement])
        let value = try #require(children.last?.accessibilityValue() as? String)
        #expect(value.components(separatedBy: "\n").count == DiagramLimits.maximumAccessibilityConnections + 1)
        #expect(value.hasSuffix(PreviewStrings.format(.diagramMoreConnections, arguments: [Int64(7)], locale: german)))
        let deutsch = PreviewStrings.text(.diagramKindFlowchart, languagePreferences: ["de"])
        #expect(deutsch == "Flussdiagramm")
        #expect(canvas.locale == german)
    }

    @Test func nodeLimitsKeepTheAccessibilityTreeBounded() throws {
        let view = makeView()
        let source = "flowchart LR\n" + (0..<(DiagramLimits.maximumAccessibilityNodes + 40)).map { "N\($0)" }.joined(separator: "\n")
        _ = show(source, in: view)
        #expect(view.canvas.accessibilityChildren()?.count == DiagramLimits.maximumAccessibilityNodes)
    }

    // MARK: Localization

    @Test func everyDiagramStringIsTranslatedInEveryLanguage() {
        let keys: [PreviewStrings.Key] = [.diagramInteractionHelp, .diagramSummary, .diagramKindFlowchart, .diagramKindState, .diagramKindSequence,
                                          .diagramKindPie, .diagramKindDrawio, .diagramRoleNode, .diagramRoleState, .diagramRoleParticipant,
                                          .diagramRoleSlice, .diagramRoleShape, .diagramConnections, .diagramConnection, .diagramConnectionLabeled,
                                          .diagramMoreConnections, .diagramSliceLabel, .diagramDrawioPage]
        for language in ["tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"] {
            for key in keys {
                let text = PreviewStrings.text(key, languagePreferences: [language])
                #expect(!text.isEmpty && text != key.rawValue)
                if ![.diagramConnection, .diagramConnectionLabeled, .diagramSliceLabel, .diagramKindDrawio].contains(key) {
                    let sharedWithEnglish = (key == .diagramRoleNode && language == "ha") || (key == .diagramRoleParticipant && language == "fr")
                    #expect(text != PreviewStrings.text(key, languagePreferences: ["en"]) || sharedWithEnglish,
                            "\(key.rawValue) is still English in \(language)")
                }
                // Positional placeholders survive translation.
                let placeholders = ["%1$", "%2$", "%3$"].filter { PreviewStrings.text(key, languagePreferences: ["en"]).contains($0) }
                for placeholder in placeholders { #expect(text.contains(placeholder), "\(key.rawValue) lost \(placeholder) in \(language)") }
            }
        }
    }
}

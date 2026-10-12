import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q53 visible provenance and live geometry help", .serialized)
@MainActor
struct Q53InfoPanelLayoutAndGeometryTests {
    private let english = Locale(identifier: "en_US")

    @Test func theFirstProvenanceRowIsVisibleOnOpenAndAfterResizeAndReopen() throws {
        let host = InteractionHarness(width: 800, height: 300)
        defer { host.release() }
        let source = plainPresentation(#"{"safe":[1,2]}"#, format: .json, syntax: .json)
        host.view.display(.ready(source), locale: english, resetsContentState: true)
        host.view.layoutSubtreeIfNeeded()
        let button = try infoButton(host.view)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        var scroll = try panelScroll(host.view)
        try expectProvenanceVisible(scroll)
        let document = try #require(scroll.documentView)
        #expect(document.frame.height > scroll.contentView.bounds.height, "The first-row assertion exercises a scrolling document")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        let first = try provenanceLabel(in: document)
        #expect(!document.convert(first.bounds, from: first).intersects(scroll.contentView.bounds))
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        expectNoNegativeClosedFrames(host.view)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        try expectProvenanceVisible(scroll)

        for (width, height) in [(PreviewChrome.compactWidth - PreviewChrome.compactHysteresis - 1, CGFloat(240)),
                                (CGFloat(800), CGFloat(480))] {
            host.view.setFrameSize(NSSize(width: width, height: height))
            host.view.needsLayout = true
            host.view.layoutSubtreeIfNeeded()
            scroll = try panelScroll(host.view)
            try expectProvenanceVisible(scroll)
            #expect(host.view.infoPanelView.bounds.height <= host.view.safeAreaLayoutGuide.frame.height * 0.25 + 1)
            #expect(host.view.headerGuide.frame.height <= PreviewChrome.headerHeight)
            #expect(!host.view.hasAmbiguousLayout && !host.view.infoPanelView.hasAmbiguousLayout)
        }
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        expectNoNegativeClosedFrames(host.view)
    }

    @Test func geometryFailureRefreshesAnOpenPanelsCommandsAndAReplacementRestoresThem() throws {
        let host = InteractionHarness(width: 800)
        defer { host.release() }
        let probe = Q53InfoGeometryProbe()
        let geometry = NativeGeometryPreviewView(frame: .zero, backendFactory: { _ in probe })
        host.view.geometryViewFactory = { geometry }
        host.view.resourceVisibility = .hostManaged
        host.view.display(.geometryReady(try geometryPresentation()), locale: english, resetsContentState: true)
        host.view.resumeResources()
        host.view.layoutSubtreeIfNeeded()
        #expect(geometry.hasGPUResources && geometry.failure == nil)
        let button = try infoButton(host.view)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        let expected = PreviewCommand.allCases.filter { $0.scope == .viewport }
        #expect(host.view.infoPanelIsOpen && host.view.displayedInfoCommands == expected)
        let previousHelp = expected.map { command in
            PreviewStrings.format(.previewInfoCommand, arguments: [command.localizedTitle(locale: english),
                command.shortcutDescription], locale: english)
        }
        for line in previousHelp { #expect(host.view.displayedInfoLines.contains(line)) }

        let fail = try #require(probe.failureHandler)
        fail() // Uses the existing backend signal; no timer, GPU or asynchronous wait is needed.
        host.view.layoutSubtreeIfNeeded()
        #expect(geometry.failure == .unavailable && !geometry.hasGPUResources)
        #expect(host.view.infoPanelIsOpen && host.view.displayedInfoCommands.isEmpty)
        for line in previousHelp { #expect(!host.view.displayedInfoLines.contains(line)) }
        #expect(host.view.infoPanelView.accessibilityValue() as? String == host.view.displayedInfoLines.joined(separator: "\n"))

        host.view.display(.geometryReady(try geometryPresentation()), locale: english, resetsContentState: true)
        host.view.resumeResources()
        host.view.layoutSubtreeIfNeeded()
        #expect(!host.view.infoPanelIsOpen && geometry.failure == nil)
        button.performClick(nil)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.displayedInfoCommands == expected)
    }

    private func infoButton(_ view: NativePreviewView) throws -> NSButton {
        try #require((view.infoBadge as NSView) as? NSButton)
    }
    private func panelScroll(_ view: NativePreviewView) throws -> NSScrollView {
        try #require(descendants(of: NSScrollView.self, in: view.infoPanelView).first)
    }
    private func provenanceLabel(in document: NSView) throws -> NSTextField {
        try #require(descendants(of: NSTextField.self, in: document).first {
            $0.stringValue == PreviewStrings.text(.readOnly)
        })
    }
    private func expectProvenanceVisible(_ scroll: NSScrollView) throws {
        let document = try #require(scroll.documentView)
        let first = try provenanceLabel(in: document)
        let frame = document.convert(first.bounds, from: first)
        let viewport = scroll.contentView.bounds
        #expect(document.isFlipped)
        #expect(viewport.height > 0 && frame.height > 0)
        #expect(frame.intersects(viewport))
        #expect(frame.minY >= viewport.minY - 1 && frame.maxY <= viewport.maxY + 1,
            "Read-only provenance must be fully visible at the top, not merely present in the scroll document")
    }
    private func expectNoNegativeClosedFrames(_ view: NativePreviewView) {
        let panel = view.infoPanelView
        #expect(!view.infoPanelIsOpen && panel.isHidden && panel.frame.height == 0)
        for child in [panel] + descendants(of: panel) {
            #expect(child.frame.width >= 0 && child.frame.height >= 0)
            #expect(child.bounds.width >= 0 && child.bounds.height >= 0)
        }
        #expect(!view.hasAmbiguousLayout && !panel.hasAmbiguousLayout)
    }
    private func geometryPresentation() throws -> GeometryPresentation {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: .zero, maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1,
            unitProvenance: .declared(.millimetre))
        return GeometryPresentation(formatID: .step, mesh: mesh, byteCount: 100)
    }
}

@MainActor
private final class Q53InfoGeometryProbe: GeometryRenderingBackend {
    let surface = NSView()
    var failureHandler: (@MainActor () -> Void)?
    func update(camera: GeometryCamera, style: GeometryRenderStyle) {}
    func suspend() {}
}

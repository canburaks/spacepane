import AppKit
import Foundation
import PreviewContracts
import Testing
@testable import PreviewRenderers

@MainActor
private final class SpokenLog {
    var texts: [String] = []
}

@MainActor
private final class AnnouncementProbe: GeometryRenderingBackend {
    let surface = NSView()
    var failureHandler: (@MainActor () -> Void)?
    func update(camera: GeometryCamera, style: GeometryRenderStyle) {}
    func suspend() {}
}

@Suite("Geometry announcements", .serialized)
@MainActor
struct GeometryAnnouncementTests {
    private let english = Locale(identifier: "en")

    private func presentation(_ formatID: FormatID = .meshSTL) throws -> GeometryPresentation {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1)
        return GeometryPresentation(formatID: formatID, mesh: mesh, byteCount: 100)
    }

    private func makeView(factory: @escaping NativeGeometryPreviewView.BackendFactory = { _ in AnnouncementProbe() })
        -> (view: NativeGeometryPreviewView, log: SpokenLog) {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), backendFactory: factory)
        let log = SpokenLog()
        view.announcer?.handler = { log.texts.append($0) }
        return (view, log)
    }

    private func viewport(of view: NativeGeometryPreviewView) throws -> NSView {
        try #require(descendants(of: NSView.self, in: view).first { $0.accessibilityLabel() == PreviewStrings.text(.geometryViewportLabel) })
    }

    private func key(_ character: String, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode))
    }

    @Test func presetsFitResetAndTheUpAxisSpeakAsTheTitleOfTheControlThatDoesTheSame() throws {
        let (view, log) = makeView()
        view.show(try presentation(), theme: .light, locale: english)
        // Continuous gestures never speak.
        view.navigate(.orbit(SIMD2<Float>(10, 5)))
        view.navigate(.pan(SIMD2<Float>(4, 4)))
        view.navigate(.zoom(0.8))
        #expect(log.texts.isEmpty)
        // An STL starts Z up, so the toggle says Y is up now.
        let expectations: [(GeometryNavigation, String)] = [
            (.preset(.front), PreviewStrings.text(.geometryFront)),
            (.preset(.side), PreviewStrings.text(.geometrySide)),
            (.preset(.top), PreviewStrings.text(.geometryTop)),
            (.fit, PreviewStrings.text(.geometryFit)),
            (.reset, PreviewStrings.text(.geometryReset)),
            (.toggleUpAxis, PreviewStrings.format(.geometryUpAxis, arguments: [GeometryUpAxis.y.letter]))]
        for (action, spoken) in expectations {
            view.navigate(action)
            #expect(log.texts.last == spoken, "\(spoken)")
        }
        #expect(log.texts.count == expectations.count)
    }

    @Test func theKeyboardSpeaksLikeTheButtonsItMatches() throws {
        let (view, log) = makeView()
        view.show(try presentation(), theme: .light, locale: english)
        let target = try viewport(of: view)
        target.keyDown(with: try key("1", keyCode: 18))
        target.keyDown(with: try key("2", keyCode: 19))
        target.keyDown(with: try key("3", keyCode: 20))
        target.keyDown(with: try key("f", keyCode: 3))
        target.keyDown(with: try key("r", keyCode: 15))
        #expect(log.texts == [PreviewStrings.text(.geometryFront), PreviewStrings.text(.geometrySide), PreviewStrings.text(.geometryTop),
                              PreviewStrings.text(.geometryFit), PreviewStrings.text(.geometryReset)])
        // Zoom keys are steps of a continuous gesture and stay silent, like the arrows.
        target.keyDown(with: try key("+", keyCode: 24))
        #expect(log.texts.count == 5)
    }

    @Test func aViewWithoutAModelSaysNothing() {
        let (view, log) = makeView()
        view.navigate(.preset(.front))
        view.navigate(.toggleUpAxis)
        view.navigate(.reset)
        #expect(log.texts.isEmpty)
    }

    @Test func aFailureAtStartBecomesTheViewportValueAndIsSpokenOnce() throws {
        for (error, messageKey) in [(GeometryRenderFailure.unavailable, PreviewStrings.Key.geometryMetalUnavailable),
                                    (.invalidGeometry, .geometryInvalidGeometry)] {
            let (view, log) = makeView(factory: { _ in throw error })
            view.show(try presentation(), theme: .light, locale: english)
            let model = view.accessibilitySummary
            #expect(!model.isEmpty)
            view.resume()
            let message = PreviewStrings.text(messageKey)
            #expect(view.failure == error)
            #expect(log.texts == [message])
            let target = try viewport(of: view)
            #expect(target.accessibilityValue() as? String == message)
            // Restyling the failed view says nothing again and keeps the failure as the value.
            view.syntaxStyle = PreviewSyntaxStyle(usesColor: false)
            #expect(log.texts == [message] && target.accessibilityValue() as? String == message)
            // A failed view has no controls to act on, so its keys and buttons stay silent.
            view.navigate(.preset(.front))
            #expect(log.texts == [message])
            // A replacement model starts from the model summary again.
            view.suspend()
            view.show(try presentation(.meshOBJ), theme: .light, locale: english)
            #expect(target.accessibilityValue() as? String == view.accessibilitySummary)
        }
    }

    @Test func aGPUFailureAfterStartIsSpokenAndReplacesTheValueToo() throws {
        let probe = AnnouncementProbe()
        let (view, log) = makeView(factory: { _ in probe })
        view.show(try presentation(), theme: .light, locale: english)
        view.resume()
        #expect(view.hasGPUResources && log.texts.isEmpty)
        let target = try viewport(of: view)
        #expect(target.accessibilityValue() as? String == view.accessibilitySummary)
        probe.failureHandler?()
        let message = PreviewStrings.text(.geometryMetalUnavailable)
        #expect(view.failure == .unavailable && !view.hasGPUResources)
        #expect(log.texts == [message])
        #expect(target.accessibilityValue() as? String == message)
    }
}

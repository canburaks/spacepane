import AppKit
import Foundation
import PreviewContracts
import Testing
@testable import PreviewRenderers

@MainActor
private final class ViewportKeyProbe: GeometryRenderingBackend {
    let surface = NSView()
    var failureHandler: (@MainActor () -> Void)?
    func update(camera: GeometryCamera, style: GeometryRenderStyle) {}
    func suspend() {}
}

/// The parent of the viewport under test. It records the key positions the viewport hands on, so a test can see that
/// Space, Escape and every chord the viewport does not own travel up the responder chain untouched.
@MainActor
private final class ViewportKeyCatcher: NSView {
    private(set) var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}

@MainActor
private final class ViewportSpeech {
    var texts: [String] = []
}

/// The 3D viewport's plain keys come from the shared command table (decision 027, Q-38), so they follow the key
/// position on a layout that types no Latin letter or digit there. Events are synthetic.
@Suite("Geometry viewport keys", .serialized)
@MainActor
struct GeometryViewportKeyTests {
    private struct Fixture {
        let view: NativeGeometryPreviewView
        let viewport: NSView
        let catcher: ViewportKeyCatcher
        let speech: ViewportSpeech
    }

    private func makeFixture() throws -> Fixture {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                             backendFactory: { _ in ViewportKeyProbe() })
        let catcher = ViewportKeyCatcher(frame: view.frame)
        catcher.addSubview(view)
        let speech = ViewportSpeech()
        view.announcer?.handler = { speech.texts.append($0) }
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1)
        view.show(GeometryPresentation(formatID: .meshSTL, mesh: mesh, byteCount: 100), theme: .light,
                  locale: Locale(identifier: "en"))
        let viewport = try #require(descendants(of: NSView.self, in: view).first {
            $0.accessibilityLabel() == PreviewStrings.text(.cadViewportLabel)
        })
        return Fixture(view: view, viewport: viewport, catcher: catcher, speech: speech)
    }

    private func key(_ keyCode: UInt16, typed: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: typed, charactersIgnoringModifiers: typed,
                                      isARepeat: false, keyCode: keyCode))
    }

    @Test func theStandardViewsFitAndResetAnswerTheirKeysOnOtherLayouts() throws {
        let fixture = try makeFixture()
        // French AZERTY types punctuation on the number row, so only the key position says which view it is.
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.numberRow[1], typed: "&"))
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.numberRow[2], typed: "é"))
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.numberRow[3], typed: "\""))
        // The keypad's 1 is the same view as the number row's.
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.keypad[1], typed: "1"))
        // A Russian layout types Cyrillic letters on the F and R keys; they are found by position.
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.ansiF, typed: "а"))
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.ansiR, typed: "к"))
        #expect(fixture.speech.texts == [PreviewStrings.text(.cadFront), PreviewStrings.text(.cadSide),
                                         PreviewStrings.text(.cadTop), PreviewStrings.text(.cadFront),
                                         PreviewStrings.text(.cadFit), PreviewStrings.text(.cadReset)])
        #expect(fixture.catcher.received.isEmpty)
    }

    @Test func theLatinKeysStillWorkWithCapsLockShiftAndTheKeypad() throws {
        let fixture = try makeFixture()
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.ansiF, typed: "F", modifiers: .shift))
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.ansiR, typed: "r", modifiers: .capsLock))
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.numberRow[2], typed: "2"))
        fixture.viewport.keyDown(with: try key(PreviewKeyCode.keypad[3], typed: "3"))
        #expect(fixture.speech.texts == [PreviewStrings.text(.cadFit), PreviewStrings.text(.cadReset),
                                         PreviewStrings.text(.cadSide), PreviewStrings.text(.cadTop)])
        #expect(fixture.catcher.received.isEmpty)
    }

    @Test func theZoomKeysStepTheDistanceWithOrWithoutShiftAndStaySilent() throws {
        let fixture = try makeFixture()
        let start = fixture.view.camera.distance
        // The equals key zooms in, and so does the plus it types with Shift; likewise the minus and the underscore.
        fixture.viewport.keyDown(with: try key(24, typed: "="))
        #expect(abs(fixture.view.camera.distance - start * 0.8) < 1e-4)
        fixture.viewport.keyDown(with: try key(24, typed: "+", modifiers: .shift))
        #expect(abs(fixture.view.camera.distance - start * 0.64) < 1e-4)
        fixture.viewport.keyDown(with: try key(27, typed: "-"))
        fixture.viewport.keyDown(with: try key(27, typed: "_", modifiers: .shift))
        #expect(abs(fixture.view.camera.distance - start) < 1e-3)
        // Zoom is a step of a continuous gesture: it never speaks, and it is never handed on.
        #expect(fixture.speech.texts.isEmpty)
        #expect(fixture.catcher.received.isEmpty)
    }

    @Test func aChordOrAKeyTheViewportDoesNotOwnIsHandedOnUntouched() throws {
        let fixture = try makeFixture()
        let start = fixture.view.camera.distance
        let handedOn: [(UInt16, String, NSEvent.ModifierFlags)] = [
            // Find and the mode keys are the preview's, not the viewport's.
            (PreviewKeyCode.ansiF, "f", .command),
            (PreviewKeyCode.numberRow[1], "1", .option),
            // Quick Look owns Space and Escape.
            (PreviewKeyCode.space, " ", []),
            (PreviewKeyCode.escape, "\u{1B}", []),
            // G is no viewport key.
            (PreviewKeyCode.ansiG, "g", [])]
        for (keyCode, typed, modifiers) in handedOn {
            fixture.viewport.keyDown(with: try key(keyCode, typed: typed, modifiers: modifiers))
        }
        #expect(fixture.catcher.received == handedOn.map { $0.0 })
        #expect(fixture.speech.texts.isEmpty)
        #expect(fixture.view.camera.distance == start)
    }
}

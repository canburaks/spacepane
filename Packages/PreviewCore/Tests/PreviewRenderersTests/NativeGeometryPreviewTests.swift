import AppKit
import PreviewContracts
import Testing
import PreviewTestSupport
@testable import PreviewRenderers

@Suite("Native geometry resource lifecycle", .serialized)
@MainActor
struct NativeGeometryPreviewTests {
    @Test func geometryIsLazyAndSuspensionRecreatesResourcesWithoutLosingCamera() throws {
        var backends: [GeometryBackendProbe] = []
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), backendFactory: { mesh in
            let backend = GeometryBackendProbe(mesh: mesh)
            backends.append(backend)
            return backend
        })
        let first = try presentation()
        view.show(first, theme: .light, locale: Locale(identifier: "en"))
        #expect(backends.isEmpty)
        view.resume()
        #expect(backends.count == 1)
        let firstBackend = try #require(backends.first)
        view.navigate(.orbit(SIMD2<Float>(30, 20)))
        let camera = view.camera
        view.show(first, theme: .dark, locale: Locale(identifier: "en"))
        #expect(backends.count == 1)
        #expect(view.camera == camera)
        view.suspend()
        #expect(firstBackend.suspensions == 1)
        #expect(!view.hasGPUResources)
        view.resume()
        #expect(backends.count == 2)
        let secondBackend = try #require(backends.last)
        #expect(view.camera == camera)
        let replacement = try presentation()
        view.show(replacement, theme: .light, locale: Locale(identifier: "en"))
        #expect(secondBackend.suspensions == 1)
        #expect(view.camera == camera)
        view.resume()
        #expect(backends.count == 3)
        #expect(backends.last?.mesh == replacement.mesh)
        #expect(view.camera == camera)
        view.clear()
        #expect(!view.hasGPUResources)
        view.resume()
        #expect(backends.count == 3)
    }

    @Test func sameBoundsReloadPreservesUserAxisPanAndZoomButExplicitResetDoesNot() throws {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                             backendFactory: { GeometryBackendProbe(mesh: $0) })
        view.show(try presentation(), theme: .light, locale: Locale(identifier: "en"))
        view.layoutSubtreeIfNeeded()
        view.navigate(.toggleUpAxis)
        view.navigate(.orbit(SIMD2<Float>(30, 20)))
        view.navigate(.pan(SIMD2<Float>(10, 10)))
        view.navigate(.zoom(0.7))
        let chosen = view.camera
        let replacement = try presentation()
        view.show(replacement, theme: .dark, locale: Locale(identifier: "tr"))
        view.layoutSubtreeIfNeeded()
        #expect(view.camera == chosen)
        view.show(replacement, theme: .dark, locale: Locale(identifier: "tr"), resetsCamera: true)
        #expect(view.camera != chosen)
        #expect(view.camera.upAxis == .y)
    }

    @Test func changedBoundsFormatOrClearedSessionResetsTheCamera() throws {
        for change in 0..<4 {
            let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                                 backendFactory: { GeometryBackendProbe(mesh: $0) })
            view.show(try presentation(), theme: .light, locale: Locale(identifier: "en"))
            view.layoutSubtreeIfNeeded()
            view.navigate(.orbit(SIMD2<Float>(30, 20)))
            let previous = view.camera
            let replacement: GeometryPresentation
            switch change {
            case 0: replacement = try presentation(bounds: GeometryBounds(minimum: .zero, maximum: SIMD3<Double>(40, 20, 1)))
            case 1: replacement = try presentation(bounds: GeometryBounds(minimum: SIMD3<Double>(10, 10, 0), maximum: SIMD3<Double>(30, 30, 1)))
            case 2: replacement = try presentation(formatID: .meshSTL)
            default:
                view.clear()
                replacement = try presentation()
            }
            view.show(replacement, theme: .light, locale: Locale(identifier: "en"))
            #expect(view.camera != previous)
            #expect(view.camera.upAxis == (change == 2 ? .z : .y))
        }
    }

    @Test func unavailableMetalIsAnHonestLocalizedStateAndCanRetryAfterSuspension() throws {
        var attempts = 0
        let view = NativeGeometryPreviewView(frame: .zero, backendFactory: { _ in
            attempts += 1
            throw GeometryRenderFailure.unavailable
        })
        view.show(try presentation(), theme: .dark, locale: Locale(identifier: "en"))
        view.resume()
        #expect(attempts == 1)
        #expect(view.failure == .unavailable)
        #expect(!view.hasGPUResources)
        #expect(view.accessibilitySummary.contains("1"))
        view.suspend()
        view.resume()
        #expect(attempts == 2)
    }

    @Test func navigationAndPresetControlsChangeOnlyCameraAndRetainRequestIdentity() throws {
        let backend = GeometryBackendProbe(mesh: try presentation().mesh)
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), backendFactory: { _ in backend })
        let geometry = try presentation()
        view.show(geometry, theme: .light, locale: Locale(identifier: "en"))
        view.resume()
        let initial = view.camera
        for action in [GeometryNavigation.orbit(SIMD2<Float>(10, 15)), .pan(SIMD2<Float>(12, -9)), .zoom(0.8)] { view.navigate(action) }
        #expect(view.camera != initial)
        #expect(backend.updates >= 4)
        view.navigate(.preset(.side))
        #expect(abs(view.camera.yaw - .pi / 2) < 0.0001)
        view.navigate(.reset)
        #expect(view.camera == initial)
        #expect(view.presentationID == geometry.id)
        #expect(view.accessibilitySummary.contains("1"))
    }

    @Test func nativeKeyboardButtonsAndTextReplacementUseTheSameViewerState() throws {
        let backend = GeometryBackendProbe(mesh: try presentation().mesh)
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), backendFactory: { _ in backend })
        view.show(try presentation(), theme: .light, locale: Locale(identifier: "en"))
        let viewport = try #require(descendants(of: view).first { $0.accessibilityLabel() == PreviewStrings.text(.geometryViewportLabel) })
        #expect(viewport.isAccessibilityElement())
        #expect(viewport.acceptsFirstResponder)
        #expect(viewport.accessibilityRole() == .image)
        let focusWindow = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: true)
        focusWindow.isReleasedWhenClosed = false
        defer { focusWindow.close() }
        focusWindow.contentView = view // An unordered test window only; no app window is opened.
        viewport.setAccessibilityFocused(true)
        #expect(focusWindow.firstResponder === viewport)
        #expect(viewport.isAccessibilityFocused())
        let sideKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
        viewport.keyDown(with: sideKey)
        #expect(abs(view.camera.yaw - .pi / 2) < 0.0001)
        let reset = try #require(descendants(of: view).compactMap { $0 as? NSButton }.first { $0.title == PreviewStrings.text(.geometryReset) })
        reset.performClick(nil)
        #expect(abs(view.camera.yaw - .pi / 4) < 0.0001 && abs(view.camera.pitch - .pi / 6) < 0.0001)
        let front = try #require(descendants(of: view).compactMap { $0 as? NSButton }.first { $0.title == PreviewStrings.text(.geometryFront) })
        front.performClick(nil)
        #expect(view.camera.yaw == 0 && view.camera.pitch == 0)
        let summaryField = try #require(descendants(of: NSTextField.self, in: view).first { $0.stringValue == view.accessibilitySummary })
        #expect(summaryField.isSelectable)
        let fittedDistance = view.camera.distance
        view.navigate(.zoom(0.8))
        #expect(view.camera.distance != fittedDistance)
        let doubleClick = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 40, y: 40),
            modifierFlags: [], timestamp: 0, windowNumber: focusWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        viewport.mouseDown(with: doubleClick)
        #expect(view.camera.distance == fittedDistance)
        view.navigate(.zoom(0.8))
        #expect(view.camera.distance != fittedDistance)
        let homeKey = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: String(UnicodeScalar(NSHomeFunctionKey)!),
            charactersIgnoringModifiers: String(UnicodeScalar(NSHomeFunctionKey)!), isARepeat: false, keyCode: 115))
        viewport.keyDown(with: homeKey)
        #expect(view.camera.distance == fittedDistance)
        let menu = try #require(view.contextMenu())
        #expect(menu.items.count == 9)
        #expect(menu.items[4].isSeparatorItem)
        view.navigate(.zoom(0.8))
        #expect(view.camera.distance != fittedDistance)
        _ = menu.items[0].target?.perform(menu.items[0].action, with: menu.items[0])
        #expect(view.camera.distance == fittedDistance)
        _ = menu.items[7].target?.perform(menu.items[7].action, with: menu.items[7])
        #expect(view.camera.yaw == 0 && abs(view.camera.pitch - (.pi / 2 - 0.01)) < 0.0001)

        let host = NativePreviewView(frame: .zero)
        let safe = TextPresentation(formatID: .plainText, text: "safe source", lineCount: 1, byteCount: 11, encoding: .utf8, redactionCount: 0)
        host.display(.ready(safe))
        #expect(descendants(of: NativeGeometryPreviewView.self, in: host).isEmpty)
        host.display(.geometryReady(try presentation()))
        let geometryView = try #require(descendants(of: NativeGeometryPreviewView.self, in: host).first)
        #expect(!geometryView.hasGPUResources)
        host.display(.ready(safe))
        #expect(geometryView.presentationID == nil && geometryView.isHidden)
        #expect(!geometryView.hasGPUResources)
        let source = try #require(host.scrollView.documentView as? NSTextView)
        #expect(source.string == "safe source")
    }

    @Test func asynchronousGPUFailureAndOwnerReleaseDisposeTheBackend() async throws {
        let backend = GeometryBackendProbe(mesh: try presentation().mesh)
        let weakView = try autoreleasepool {
            let view = NativeGeometryPreviewView(frame: .zero, backendFactory: { _ in backend })
            view.show(try presentation(), theme: .light, locale: Locale(identifier: "en"))
            view.resume()
            backend.failureHandler?()
            #expect(view.failure == .unavailable)
            #expect(!view.hasGPUResources)
            #expect(backend.suspensions == 1)
            view.suspend(); view.resume()
            return WeakGeometryViewReference(view)
        }
        await Task.yield() // An isolated deinit may be scheduled on its actor.
        #expect(weakView.value == nil)
        #expect(backend.suspensions == 2)
        #expect(backend.failureHandler == nil)
    }

    @Test func hostManagedVisibilityRendersInAnOccludedRemoteWindowAndRetainsLifecycle() async throws {
        var backends: [GeometryBackendProbe] = []
        let host = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        host.geometryViewFactory = {
            NativeGeometryPreviewView(frame: .zero, backendFactory: { mesh in
                let backend = GeometryBackendProbe(mesh: mesh)
                backends.append(backend)
                return backend
            })
        }
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        #expect(!window.occlusionState.contains(.visible)) // No ordered app window or real GPU is needed.
        let safe = TextPresentation(formatID: .plainText, text: "safe", lineCount: 1, byteCount: 4,
                                    encoding: .utf8, redactionCount: 0)
        host.display(.ready(safe))
        window.contentView = host
        host.resumeResources()
        #expect(backends.isEmpty)
        host.display(.geometryReady(try presentation()))
        #expect(backends.isEmpty) // The companion's default still respects window occlusion.
        let geometry = try #require(descendants(of: NativeGeometryPreviewView.self, in: host).first)

        host.resourceVisibility = .hostManaged
        #expect(backends.isEmpty) // A mode change does not authorize resource activation.
        window.contentView = nil
        host.resumeResources() // Hosts can announce appearance before AppKit attaches the view.
        #expect(backends.isEmpty)
        window.contentView = host
        #expect(backends.count == 1)
        let firstBackend = try #require(backends.first)
        geometry.navigate(.orbit(SIMD2<Float>(10, 20)))
        let camera = geometry.camera
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        await Task.yield()
        #expect(geometry.hasGPUResources)
        #expect(firstBackend.suspensions == 0)

        host.suspendResources()
        #expect(!geometry.hasGPUResources)
        #expect(firstBackend.suspensions == 1)
        window.contentView = nil
        window.contentView = host
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        await Task.yield()
        #expect(backends.count == 1) // Reattachment and notifications cannot reactivate a hidden host.
        host.resumeResources()
        #expect(backends.count == 2)
        #expect(geometry.camera == camera)
        let secondBackend = try #require(backends.last)
        window.contentView = nil
        #expect(secondBackend.suspensions == 1)
        #expect(!geometry.hasGPUResources)
        window.contentView = host
        #expect(backends.count == 3) // Detachment releases GPU state, retaining the host's active intent.
        #expect(geometry.camera == camera)
        host.display(.ready(safe))
        #expect(!geometry.hasGPUResources)
    }

    @Test func viewportOwnsFocusAndUsesPointerLocationsForDragGestures() throws {
        let backend = GeometryBackendProbe(mesh: try presentation().mesh)
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 450), backendFactory: { _ in backend })
        view.show(try presentation(), theme: .light, locale: Locale(identifier: "en"))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.resume()
        let viewport = try #require(descendants(of: view).first { $0.accessibilityLabel() == PreviewStrings.text(.geometryViewportLabel) })
        #expect(viewport.bounds.width > 0 && viewport.bounds.height > 0)
        #expect(!viewport.mouseDownCanMoveWindow)
        #expect(viewport.needsPanelToBecomeKey)
        let start = NSPoint(x: viewport.bounds.midX, y: viewport.bounds.midY)
        let pointInParent = viewport.convert(start, to: viewport.superview)
        #expect(viewport.hitTest(pointInParent) === viewport) // AppKit supplies superview coordinates.
        let outside = viewport.convert(NSPoint(x: -10, y: -10), to: viewport.superview)
        #expect(viewport.hitTest(outside) == nil)

        func mouse(_ type: NSEvent.EventType, _ point: NSPoint, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            let location = viewport.convert(point, to: nil)
            return try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let down = try mouse(.leftMouseDown, start)
        #expect(viewport.acceptsFirstMouse(for: down))
        viewport.mouseDown(with: down)
        #expect(window.firstResponder === viewport)
        let dragged = try mouse(.leftMouseDragged, NSPoint(x: start.x + 40, y: start.y + 15))
        #expect(dragged.deltaX == 0 && dragged.deltaY == 0)
        var expected = view.camera
        expected.orbit(delta: SIMD2<Float>(40, -15))
        viewport.mouseDragged(with: dragged)
        #expect(view.camera == expected)
        expected.orbit(delta: SIMD2<Float>(10, -5))
        viewport.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: start.x + 50, y: start.y + 20)))
        #expect(view.camera == expected) // Each update uses the previous gesture point.
        viewport.mouseUp(with: try mouse(.leftMouseUp, start))
        viewport.mouseDragged(with: try mouse(.leftMouseDragged, start))
        #expect(view.camera == expected) // A completed gesture cannot reuse an old anchor.

        viewport.mouseDown(with: try mouse(.leftMouseDown, start, flags: .shift))
        expected.pan(delta: SIMD2<Float>(12, -9), viewport: viewport.bounds.size)
        viewport.mouseDragged(with: try mouse(.leftMouseDragged, NSPoint(x: start.x + 12, y: start.y + 9), flags: .shift))
        #expect(view.camera == expected)
        viewport.mouseUp(with: try mouse(.leftMouseUp, start))
        viewport.rightMouseDown(with: try mouse(.rightMouseDown, start))
        expected.pan(delta: SIMD2<Float>(-8, 6), viewport: viewport.bounds.size)
        viewport.rightMouseDragged(with: try mouse(.rightMouseDragged, NSPoint(x: start.x - 8, y: start.y - 6)))
        #expect(view.camera == expected)
        viewport.rightMouseUp(with: try mouse(.rightMouseUp, start))
        viewport.rightMouseDragged(with: try mouse(.rightMouseDragged, start))
        #expect(view.camera == expected)
        viewport.isHidden = true
        #expect(viewport.hitTest(pointInParent) == nil)
    }

    private func presentation(measurements: GeometryMeasurements? = nil, formatID: FormatID = CADTestFormatIDs.step,
                              bounds: GeometryBounds = GeometryBounds(minimum: .zero, maximum: SIMD3<Double>(20, 20, 1))) throws -> GeometryPresentation {
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: bounds, faceCount: 1,
            measurements: measurements, unitProvenance: .declared(.millimetre))
        return GeometryPresentation(formatID: formatID, mesh: mesh, byteCount: 100)
    }

    private func measurements(area: Double = 2_200, volume: Double? = 6_000, bodies: Int = 1) throws -> GeometryMeasurements {
        try #require(GeometryMeasurements(surfaceAreaSquareMillimetres: area, volumeCubicMillimetres: volume, bodyCount: bodies,
                                          unitProvenance: .declared(.millimetre)))
    }

    private func lines(_ geometry: GeometryPresentation, locale: String = "en", language: String = "en") -> [String] {
        NativeGeometryPreviewView.summaryLines(for: geometry.mesh, locale: Locale(identifier: locale), languagePreferences: [language])
    }

    @Test func summaryAddsALocalizedMeasurementLine() throws {
        let geometry = try presentation(measurements: try measurements())
        let english = lines(geometry)
        #expect(english.count == 2)
        #expect(english[0].hasPrefix("Faces: 1 · Triangles: 1 · 20 × 20 × 1 mm"))
        #expect(english[1] == "Surface area: 2,200 mm² · Volume: 6,000 mm³ · Bodies: 1")
        // Another locale: numbers follow the locale's grouping and no placeholder or resource key leaks.
        let german = lines(geometry, locale: "de", language: "de")
        #expect(german.count == 2)
        #expect(german[1].contains("2.200") && german[1].contains("6.000"))
        #expect(german[1].contains("mm²") && german[1].contains("mm³"))
        for line in german { #expect(!line.contains("%") && !line.contains("geometry.")) }
        let french = lines(geometry, locale: "fr", language: "fr")
        #expect(french[1].contains("2\u{202F}200") || french[1].contains("2\u{00A0}200")) // Locale-specific grouping space.
    }

    @Test func anOpenMeshOmitsTheVolumeAndSaysWhy() throws {
        let geometry = try presentation(measurements: try measurements(area: 180, volume: nil, bodies: 3))
        let result = lines(geometry)
        #expect(result.count == 2)
        #expect(result[1] == "Surface area: 180 mm² · Volume unavailable (surface not closed) · Bodies: 3")
        #expect(!result[1].contains("mm³"))
        let german = lines(geometry, locale: "de", language: "de")
        #expect(german.count == 2 && !german[1].contains("mm³"))
    }

    @Test func measurementsUseFourSignificantDigits() throws {
        let rounded = lines(try presentation(measurements: try measurements(area: 2_507.697, volume: 9_377.001)))
        #expect(rounded[1] == "Surface area: 2,508 mm² · Volume: 9,377 mm³ · Bodies: 1")
        let small = lines(try presentation(measurements: try measurements(area: 0.123456, volume: 0.00123456)))
        #expect(small[1] == "Surface area: 0.1235 mm² · Volume: 0.001235 mm³ · Bodies: 1")
        let large = lines(try presentation(measurements: try measurements(area: 12_345_678, volume: 2.5e10)))
        #expect(large[1].contains("12,350,000 mm²") && large[1].contains("25,000,000,000 mm³"))
    }

    @Test func viewShowsTheLinesAndExposesThemInTheViewportAccessibilityValue() throws {
        let view = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), backendFactory: { GeometryBackendProbe(mesh: $0) })
        let geometry = try presentation(measurements: try measurements())
        view.show(geometry, theme: .light, locale: Locale(identifier: "en"))
        let expected = NativeGeometryPreviewView.summaryLines(for: geometry.mesh, locale: Locale(identifier: "en")).joined(separator: "\n")
        #expect(view.accessibilitySummary == expected)
        // The process language may differ from English; numbers and technical names are language independent.
        #expect(view.accessibilitySummary.components(separatedBy: "\n").count == 2)
        #expect(view.accessibilitySummary.contains("6,000 mm³") && view.accessibilitySummary.contains("2,200 mm²"))
        let viewport = try #require(descendants(of: view).first { $0.accessibilityLabel() == PreviewStrings.text(.geometryViewportLabel) })
        #expect(viewport.accessibilityValue() as? String == expected)
        // Controls and camera behave as before.
        let camera = view.camera
        view.navigate(.orbit(SIMD2<Float>(10, 10)))
        #expect(view.camera != camera)
        #expect(view.accessibilitySummary == expected)
        view.clear()
        #expect(view.accessibilitySummary.isEmpty)
        #expect(viewport.accessibilityValue() as? String == "")
    }
}

@MainActor private final class WeakGeometryViewReference {
    weak var value: NativeGeometryPreviewView?
    init(_ value: NativeGeometryPreviewView) { self.value = value }
}

@MainActor
private final class GeometryBackendProbe: GeometryRenderingBackend {
    let surface = NSView()
    let mesh: PreviewMesh
    var updates = 0
    var suspensions = 0
    var failureHandler: (@MainActor () -> Void)?
    init(mesh: PreviewMesh) { self.mesh = mesh }
    func update(camera: GeometryCamera, style: GeometryRenderStyle) { updates += 1 }
    func suspend() { suspensions += 1 }
}

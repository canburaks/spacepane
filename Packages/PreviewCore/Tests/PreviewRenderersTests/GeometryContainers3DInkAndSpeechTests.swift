import AppKit
import Foundation
import PreviewContracts
import Testing
@testable import PreviewRenderers

@MainActor
private final class ContainerSpeech {
    var texts: [String] = []
}

/// The MIDI strip and the listing tree draw their quiet ink from the preview's palette and speak through the
/// preview's announcer instead of a system ink and silence (decision 027, Q-34 and Q-36). The tree, the Files table
/// and the package icon also take the shared key and host contracts of the modes work (Q-38): Command-C by the
/// command table, the preview's announcer and copy reporting passed on to the hosted table, and no text zoom for a
/// picture.
@Suite("Container views: quiet ink, speech and shared contracts", .serialized)
@MainActor
struct GeometryContainers3DInkAndSpeechTests {
    private let english = Locale(identifier: "en")

    private func midiStatusLabel(in view: NativeMIDIPreviewView) throws -> NSTextField {
        try #require(descendants(of: NSTextField.self, in: view).first { $0.stringValue == PreviewStrings.text(.midiNoAutoplay) })
    }

    private func palette(_ scheme: PreviewColorSchemeID) -> NativeTextPalette {
        NativeTextPalette(theme: .light, isDark: false, increasedContrast: false,
                          style: PreviewSyntaxStyle(lightScheme: scheme, darkScheme: .standard))
    }

    @Test func aMIDIPlaybackFailureIsSpokenAsTheStatusLineChanges() throws {
        let view = NativeMIDIPreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 90))
        let speech = ContainerSpeech()
        view.announcer?.handler = { speech.texts.append($0) }
        // A playable file says nothing: playback never starts by itself and nothing has failed.
        view.show(MIDIPresentation(format: 0, trackCount: 1, ticksPerQuarter: 96, durationSeconds: 1, events: []))
        #expect(speech.texts.isEmpty)
        // A presentation the player rejects changes the status line, and the same sentence is spoken once.
        view.show(MIDIPresentation(format: 2, trackCount: 1, ticksPerQuarter: 96, durationSeconds: 1, events: []))
        let message = PreviewStrings.text(.midiPlaybackUnavailable)
        #expect(speech.texts == [message])
        let status = descendants(of: NSTextField.self, in: view).first { $0.stringValue == message }
        #expect(status != nil)
    }

    @Test func theMIDIStatusLineUsesTheSchemesMutedInkAndTheSizeCueOnlyWhereTheSchemeNeedsIt() throws {
        let view = NativeMIDIPreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 90))
        let status = try midiStatusLabel(in: view)
        // Solarized Light's body ink leaves no room for a lighter muted ink, so the size is the second cue.
        let solarized = palette(.solarizedLight)
        #expect(solarized.mutedUsesSizeCue)
        view.apply(palette: solarized)
        #expect(status.textColor == solarized.muted)
        #expect(status.font?.pointSize == PreviewChrome.mutedPointSize)
        // Standard light has headroom, so the quiet ink is enough and the size stays regular.
        let standard = palette(.standard)
        #expect(!standard.mutedUsesSizeCue)
        view.apply(palette: standard)
        #expect(status.textColor == standard.muted)
        #expect(status.font?.pointSize == NSFont.systemFontSize)
        // A later appearance change keeps the preview's palette instead of falling back to the system default.
        view.apply(palette: solarized)
        view.viewDidChangeEffectiveAppearance()
        #expect(status.textColor == solarized.muted)
    }

    private func listingView(syntaxStyle: PreviewSyntaxStyle = PreviewSyntaxStyle()) throws -> (NativePreviewView, NativeListingTreeView) {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        view.appearance = NSAppearance(named: .aqua)
        view.display(.ready(listingPresentation(archiveListingJSON, format: .zip)), theme: .light,
                     syntaxStyle: syntaxStyle, locale: english)
        let control = view.modeControl
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == PreviewStrings.text(.previewModeTree) })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
        return (view, try #require(descendants(of: NativeListingTreeView.self, in: view).first))
    }

    @Test func aTreeCopyIsConfirmedThroughThePreviewWhenItListensAndSpokenByTheTreeWhenNot() throws {
        let (_, tree) = try listingView()
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        tree.outlineView.pasteboard = pasteboard
        tree.outlineView.selectRowIndexes(IndexSet([1, 4]), byExtendingSelection: false)
        let speech = ContainerSpeech()
        tree.announcer?.handler = { speech.texts.append($0) }

        // Nobody listens: the tree confirms the copy itself, once.
        tree.copyHandler = nil
        tree.outlineView.copy(nil)
        #expect(speech.texts == [PreviewStrings.text(.chipCopied)])
        #expect(pasteboard.string(forType: .string) != nil)

        // The preview listens: it hears the copy with its row count and the tree stays quiet, so one copy is never
        // confirmed twice.
        var events: [PreviewCopyEvent] = []
        tree.copyHandler = { events.append($0) }
        tree.outlineView.copy(nil)
        #expect(events == [.rows(2)])
        #expect(speech.texts.count == 1)

        // Nothing selected copies nothing and confirms nothing.
        tree.outlineView.deselectAll(nil)
        tree.outlineView.copy(nil)
        #expect(events.count == 1 && speech.texts.count == 1)
    }

    @Test func theTreeIconsAreDrawnInTheSchemesMutedInkNotASystemInk() throws {
        let syntaxStyle = PreviewSyntaxStyle(lightScheme: .solarizedLight, darkScheme: .standard)
        let (_, tree) = try listingView(syntaxStyle: syntaxStyle)
        let expected = NativeTextPalette(theme: .light, isDark: false,
                                         increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                                         style: syntaxStyle).muted
        let outline = tree.outlineView
        for row in 0..<min(outline.numberOfRows, 3) {
            let item = try #require(outline.item(atRow: row))
            let cell = try #require(outline.delegate?.outlineView?(outline, viewFor: outline.tableColumns[0], item: item) as? NSTableCellView)
            #expect(cell.imageView?.contentTintColor == expected, "row \(row)")
        }
    }

    // MARK: Shared key and host contracts

    private func commandKey(_ keyCode: UInt16, typed: String, modifiers: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                      context: nil, characters: typed, charactersIgnoringModifiers: typed,
                                      isARepeat: false, keyCode: keyCode))
    }

    @Test func theTreeCopiesOnCommandCWhateverTheLayoutTypesWhileItHasFocus() throws {
        let (host, tree) = try listingView()
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        tree.outlineView.pasteboard = pasteboard
        tree.outlineView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        var events: [PreviewCopyEvent] = []
        tree.copyHandler = { events.append($0) }
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: true)
        defer { withExtendedLifetime(window) {} }
        window.contentView = host
        // A Russian layout types Cyrillic es on the C key: only its position says this is Command-C.
        let russianC = try commandKey(PreviewKeyCode.ansiC, typed: "с")
        // Without keyboard focus the tree leaves the chord to the rest of the preview.
        #expect(!tree.outlineView.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(events.isEmpty)
        #expect(window.makeFirstResponder(tree.outlineView))
        #expect(tree.outlineView.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) != nil)
        #expect(events == [.rows(1)])
        // Shift-Command-C is Copy Concealed Text, which the preview answers; the tree does not take it.
        events.removeAll()
        pasteboard.clearContents()
        let shiftedC = try commandKey(PreviewKeyCode.ansiC, typed: "c", modifiers: [.command, .shift])
        #expect(!tree.outlineView.performKeyEquivalent(with: shiftedC))
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(events.isEmpty)
    }

    @Test func theFilesViewPassesThePreviewsAnnouncerAndCopyReportingToItsTable() {
        let files = NativeListingFilesView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let shared = PreviewAnnouncer()
        files.announcer = shared
        #expect(files.table.announcer === shared)
        var events: [PreviewCopyEvent] = []
        files.copyHandler = { events.append($0) }
        files.table.copyHandler?(.rows(2))
        #expect(events == [.rows(2)])
        // Taking them away reaches the table too.
        files.announcer = nil
        files.copyHandler = nil
        #expect(files.table.announcer == nil)
        #expect(files.table.copyHandler == nil)
    }

    @Test func thePackageIconIgnoresTheTextZoomShortcutsWhileTheTreeFollowsThem() {
        let icon = PackageIconView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        #expect(!icon.respondsToTextZoom)
        for shortcut in [PreviewShortcut.zoomIn, .zoomOut, .zoomReset] {
            #expect(icon.zoomDecision(for: shortcut) == false, "\(shortcut)")
        }
        // A view drawn in the preview's typography leaves the decision to the preview, which restyles the text.
        let tree = NativeListingTreeView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        #expect(tree.respondsToTextZoom)
        #expect(tree.zoomDecision(for: .zoomIn) == nil)
    }

    @Test func theViewsTakeThePreviewsAnnouncerThroughTheSharedContract() throws {
        let shared = PreviewAnnouncer()
        let speech = ContainerSpeech()
        shared.handler = { speech.texts.append($0) }
        let midi = NativeMIDIPreviewView(frame: NSRect(x: 0, y: 0, width: 500, height: 90))
        let geometry = NativeGeometryPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let (_, tree) = try listingView()
        let hosted: [any PreviewAnnouncing] = [midi, geometry, tree]
        for view in hosted { view.announcer = shared }
        #expect(hosted.allSatisfy { $0.announcer === shared })

        // Each view now speaks through the preview's announcer: a MIDI playback failure, a 3D view preset, a tree copy.
        midi.show(MIDIPresentation(format: 2, trackCount: 1, ticksPerQuarter: 96, durationSeconds: 1, events: []))
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1)
        geometry.show(GeometryPresentation(formatID: .meshSTL, mesh: mesh, byteCount: 100), theme: .light, locale: english)
        geometry.navigate(.fit)
        let pasteboard = NSPasteboard(name: .init(UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        tree.outlineView.pasteboard = pasteboard
        tree.outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tree.copyHandler = nil
        tree.outlineView.copy(nil)
        #expect(speech.texts == [PreviewStrings.text(.midiPlaybackUnavailable), PreviewStrings.text(.cadFit),
                                 PreviewStrings.text(.chipCopied)])
    }
}

import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// A preview inside an off-screen window, so key equivalents, first responders and menus behave as in a host.
@MainActor
struct InteractionHarness {
    let view: NativePreviewView
    let window: NSWindow
    let pasteboard: NSPasteboard
    /// Spoken confirmations the preview asked for, in order.
    let announcements: Announcements

    @MainActor final class Announcements {
        var texts: [String] = []
    }

    init(width: CGFloat = 640, height: CGFloat = 420) {
        view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        // Never the user's clipboard: every test writes to its own private pasteboard.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("interaction-\(UUID().uuidString)"))
        announcements = Announcements()
        view.pasteboard = pasteboard
        let recorder = announcements
        view.announcementHandler = { recorder.texts.append($0) }
        view.appearance = NSAppearance(named: .aqua)
    }

    func release() { pasteboard.releaseGlobally() }

    @discardableResult
    func show(_ presentation: TextPresentation, typography: PreviewTypography = .init(),
              resetsContentState: Bool = false) -> Self {
        view.display(.ready(presentation), typography: typography, resetsContentState: resetsContentState)
        view.layoutSubtreeIfNeeded()
        return self
    }

    var textView: NSTextView { view.textView }

    func keyEvent(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0)!
    }

    /// Sends a key equivalent the way the window does.
    @discardableResult
    func press(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> Bool {
        view.performKeyEquivalent(with: keyEvent(characters, modifiers))
    }

    /// The status text through the `displayedStatus` seam, so no test depends on which view holds it. Still
    /// `throws` so the existing `try host.status()` call sites stay free of "no throwing call" warnings.
    func status() throws -> String {
        view.displayedStatus
    }
}

func plainPresentation(_ text: String, format: FormatID = .plainText, syntax: TextSyntax = .plain,
                       redactions: Int = 0) -> TextPresentation {
    TextPresentation(formatID: format, text: text, lineCount: max(1, text.components(separatedBy: "\n").count),
                     byteCount: text.utf8.count, encoding: .utf8, redactionCount: redactions, syntax: syntax)
}

/// Lines "line 1" … "line n" separated by LF.
func numberedLines(_ count: Int) -> String { (1...count).map { "line \($0)" }.joined(separator: "\n") }

/// Every descendant of `view`, depth first, for tests that filter by a predicate. To find a view of a known type
/// use `descendants(of:in:)` in `ViewLookupSupport.swift`.
@MainActor
func descendants(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants(of: $0) } }

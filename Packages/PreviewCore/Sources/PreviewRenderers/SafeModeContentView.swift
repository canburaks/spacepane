import AppKit
import PreviewContracts

/// Resolved styling shared by every derived mode view.
struct SafeModeStyle {
    let typography: PreviewTypography
    let palette: NativeTextPalette
    let syntaxStyle: PreviewSyntaxStyle
    let locale: Locale
}

/// A view for one derived safe mode. It consumes only `SafePreviewModes`, whose models are
/// derived from already-concealed text, and never reads files, preferences or storage.
/// `NativePreviewView` creates each view lazily, at most once per mode, and owns its layout.
@MainActor
protocol SafeModeContentView: NSView {
    /// Shows the models for `mode`. Called after every content, mode, appearance or locale change.
    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle)
    /// Drops all content so a replacement request never shows stale data.
    func clear()
    /// Set by the hosting preview: shows `mode` (Source or Rendered) and selects `range` in its text.
    var navigate: ((NativePreviewMode, NSRange) -> Void)? { get set }
    /// Whether the preview's text-zoom shortcuts (Command-Plus, Command-Minus, Command-0) restyle anything in
    /// this view: true for views drawn in the preview's typography, the default. A view of pictures that do not
    /// scale with the text size returns false, so the shortcut changes nothing and no zoom status appears. A
    /// view that scales its own content adopts `SafeModeZoomable` instead.
    var respondsToTextZoom: Bool { get }
    /// The view inside this one that takes keyboard focus when the preview moves focus into the content, for example
    /// after a mode switch from the keyboard. Most mode views are containers, not responders (a table sits in a scroll
    /// view, a canvas in a host view), so a view that holds one names it here. The default is the view itself when it
    /// accepts first responder status and nil otherwise, which leaves focus where it is.
    var keyboardFocusTarget: NSView? { get }
}

extension SafeModeContentView {
    var respondsToTextZoom: Bool { true }

    var keyboardFocusTarget: NSView? {
        guard acceptsFirstResponder else { return nil }
        return self
    }

    /// What the preview does with a zoom shortcut while this view is the visible mode. A view that adopts
    /// `SafeModeZoomable` decides for itself (true means it zoomed). Otherwise nil means "restyle the text as
    /// usual" and false means "nothing here zooms, leave the typography and the status line alone".
    func zoomDecision(for shortcut: PreviewShortcut) -> Bool? {
        if let zoomable = self as? any SafeModeZoomable { return zoomable.handleZoom(shortcut) }
        return respondsToTextZoom ? nil : false
    }
}

/// A mode view that scales its own content (a diagram canvas, a page column) and so takes the preview's zoom
/// shortcuts before the preview restyles its text. Without it Command-Plus enlarges a diagram's labels while the
/// canvas the help promises to zoom stays put.
@MainActor
protocol SafeModeZoomable: SafeModeContentView {
    /// Applies a zoom shortcut (`.zoomIn`, `.zoomOut` or `.zoomReset`). Returns true when the view handled it,
    /// including at a zoom bound, so the key never falls through to another handler; false for anything else.
    func handleZoom(_ shortcut: PreviewShortcut) -> Bool
}

/// A mode view that hosts the shared native table (the Files and Rows modes). Naming the hosted `table` is all it
/// takes to pass the preview's announcer (`PreviewAnnouncing`) and copy reporting (`PreviewCopyReporting`) on to it.
@MainActor
protocol PreviewHostsTable: SafeModeContentView, PreviewAnnouncing, PreviewCopyReporting, PreviewSafeCopying {
    var table: NativeTablePreviewView { get }
}

extension NativeTablePreviewView {
    var keyboardFocusTarget: NSView? { tableView }
}

extension PreviewHostsTable {
    var keyboardFocusTarget: NSView? { table.keyboardFocusTarget }

    var pasteboard: NSPasteboard {
        get { table.pasteboard }
        set { table.pasteboard = newValue }
    }
    var tagCopyPolicy: (() -> Bool)? {
        get { table.tagCopyPolicy }
        set { table.tagCopyPolicy = newValue }
    }

    var announcer: PreviewAnnouncer? {
        get { table.announcer }
        set { table.announcer = newValue }
    }

    var copyHandler: ((PreviewCopyEvent) -> Void)? {
        get { table.copyHandler }
        set { table.copyHandler = newValue }
    }
}

/// One factory per derived mode. Modes without a factory use the shared text, outline or table views.
@MainActor
enum SafeModeViewRegistry {
    static func makeView(for mode: NativePreviewMode) -> (any SafeModeContentView)? {
        switch mode {
        // [workstream views] Return your view for your mode, one `case` line below your marker.
        // [markup]
        case .contents: return MarkupContentsView()
        case .references: return MarkupReferencesView()
        // [diagrams]
        case .diagram: return NativeDiagramView(frame: .zero)
        // [listings]
        case .files: return NativeListingFilesView(frame: .zero)
        case .tree: return NativeListingTreeView(frame: .zero)
        // [ebooks]
        case .pages: return NativeImagePagesView(frame: .zero)
        // [data]
        case .plot: return NativePlotPreviewView(frame: .zero)
        case .rows: return NativeRowsPreviewView(frame: .zero)
        // [openapi]
        case .endpoints: return NativeEndpointsPreviewView(frame: .zero)
        // [packages]
        case .icon: return PackageIconView()
        default: return nil
        }
    }
}

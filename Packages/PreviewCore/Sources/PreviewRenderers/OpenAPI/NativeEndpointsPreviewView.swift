import AppKit
import PreviewContracts

/// The Endpoints mode: the shared native table (Method, Path, Summary and Deprecated columns, click-to-sort headers, a
/// filter field) over the endpoint list, which `SafePreviewModes.endpoints` derives from concealed text. It adds nothing
/// of its own to what the table shows or copies, and it passes the preview's announcer and copy reporting on to that
/// table (`PreviewHostsTable`).
@MainActor
final class NativeEndpointsPreviewView: NSView, SafeModeContentView, PreviewHostsTable {
    let table = NativeTablePreviewView(frame: .zero)
    var navigate: ((NativePreviewMode, NSRange) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        table.translatesAutoresizingMaskIntoConstraints = false
        addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: leadingAnchor),
            table.trailingAnchor.constraint(equalTo: trailingAnchor),
            table.topAnchor.constraint(equalTo: topAnchor),
            table.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        guard mode == .endpoints, let endpoints = modes.endpoints else { clear(); return }
        table.display(endpoints.table, typography: style.typography, palette: style.palette,
                      syntaxStyle: style.syntaxStyle, locale: style.locale)
    }

    func clear() { table.clear() }
}

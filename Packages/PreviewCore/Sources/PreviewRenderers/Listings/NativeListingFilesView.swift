import AppKit

/// The Files mode of every listing: the shared native table (Name, Kind, Size and Modified columns,
/// click-to-sort headers, alternating rows, a filter field) over the already-concealed listing. It passes the
/// preview's announcer and copy reporting on to that table (`PreviewHostsTable`).
@MainActor
final class NativeListingFilesView: NSView, SafeModeContentView, PreviewHostsTable {
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
        guard mode == .files, let files = modes.files else { clear(); return }
        table.display(files, typography: style.typography, palette: style.palette,
                      syntaxStyle: style.syntaxStyle, locale: style.locale)
    }

    func clear() { table.clear() }
}

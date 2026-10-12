import AppKit
import PreviewContracts

/// Hosts the shared native table for a second, optional table of a presentation: the first rows of a
/// columnar file. It adds nothing of its own to what the table shows or copies; everything comes from
/// `SafePreviewModes.sampleRows`, which is derived from concealed text.
@MainActor
final class NativeRowsPreviewView: NSView, SafeModeContentView, PreviewHostsTable {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    let table = NativeTablePreviewView(frame: .zero)

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
        guard mode == .rows, let rows = modes.sampleRows else { clear(); return }
        table.display(rows, typography: style.typography, palette: style.palette,
                      syntaxStyle: style.syntaxStyle, locale: style.locale)
    }

    func clear() { table.clear() }
}

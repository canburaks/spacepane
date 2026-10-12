import AppKit

/// The strip between the mode control and the content. It shows one inline bar at a time (the outline filter
/// or Go to Line) and collapses to nothing otherwise; the preview owns its height.
@MainActor
final class PreviewAccessoryBar: NSView {
    enum Content: Equatable { case none, filter, goToLine }

    static let height = PreviewChrome.accessoryHeight

    let filterBar = OutlineFilterBar()
    let goToLineBar = GoToLineBar()
    private(set) var content = Content.none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        for bar in [filterBar, goToLineBar] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.isHidden = true
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor),
                bar.topAnchor.constraint(equalTo: topAnchor),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    /// The height the strip needs for what it shows.
    var requiredHeight: CGFloat { content == .none ? 0 : Self.height }

    func show(_ content: Content) {
        self.content = content
        filterBar.isHidden = content != .filter
        goToLineBar.isHidden = content != .goToLine
        isHidden = content == .none
    }

    func apply(palette: NativeTextPalette) {
        filterBar.apply(palette: palette)
        goToLineBar.apply(palette: palette)
    }
}

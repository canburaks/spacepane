import AppKit
import PreviewContracts

/// The Contents list as a collapsible strip at the leading edge of a wide pane, beside the rendered text. A compact
/// pane keeps Contents as a mode (`MarkupContentsView`); this rail embeds that same list, so rows, copy and
/// accessibility behave identically in both places.
///
/// - The rail follows the reader's scroll position: `track` maps the on-screen characters to the nearest preceding
///   heading (`ContentsSectionTracker`) and selects that row. It never moves focus, never navigates and says nothing
///   aloud, and while the list itself holds focus the reader's own arrow-key selection is left alone.
/// - Choosing a row (click, or Return while the list has focus) asks the preview to reveal the heading through
///   `onReveal`; the row stays current while the heading is in view.
/// - Arrow keys act only while the list has focus, Space and Escape are handed on to Quick Look, and copy goes
///   through the list's injectable pasteboard and copy reporting, which the preview adopts as for any hosted view.
/// - Rows come only from headings derived from already-concealed text.
@MainActor
final class MarkupContentsRail: NSView, PreviewAnnouncing, PreviewCopyReporting, PreviewSafeCopying {
    /// Symbol names are string-only API; this is their one definition.
    private enum Symbol: String { case sidebar = "sidebar.leading" }

    /// What the preview last told the rail, so a width change can re-decide without the preview's help.
    private struct Inputs {
        let headings: [MarkupHeading]
        let mode: NativePreviewMode
        let isEligible: Bool
        let style: SafeModeStyle
    }

    /// The same list the Contents mode shows.
    let list = MarkupContentsView(frame: .zero)
    let toggleButton = ContentsRailToggleButton(frame: .zero)
    private let header = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let divider = NSView()
    private var widthConstraint: NSLayoutConstraint?
    private var inputs: Inputs?

    /// The reader chose a heading: show this range of the rendered text.
    var onReveal: ((NSRange) -> Void)?
    /// The preview's reading of the on-screen characters, asked for by `viewportChanged`. Nil while it has none.
    var viewport: (() -> ContentsViewport?)?

    /// Whether the reader folded the rail to its toggle. It lasts as long as this view and is never saved.
    private(set) var isCollapsed = false
    /// Whether the rail is shown: a wide pane in Rendered mode with enough headings.
    private(set) var isOffered = false
    private(set) var isWide = false
    private(set) var tracker = ContentsSectionTracker()

    /// The width the rail asks for now: nothing while hidden, the toggle's strip when collapsed.
    var railWidth: CGFloat { widthConstraint?.constant ?? 0 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
        setAccessibilityRole(.group)
        list.indentPerLevel = ContentsRailPolicy.indentPerLevel
        list.maximumPointSize = ContentsRailPolicy.maximumRowPointSize
        list.selectsFirstRow = false
        list.navigate = { [weak self] _, range in self?.revealed(range) }
        configureHeader()
        divider.wantsLayer = true
        for view in [header, list, divider] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        installInnerLayout()
        localize()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Forwarded services

    var pasteboard: NSPasteboard {
        get { list.pasteboard }
        set { list.pasteboard = newValue }
    }
    var tagCopyPolicy: (() -> Bool)? {
        get { list.tagCopyPolicy }
        set { list.tagCopyPolicy = newValue }
    }
    var announcer: PreviewAnnouncer? {
        get { list.announcer }
        set { list.announcer = newValue }
    }
    var copyHandler: ((PreviewCopyEvent) -> Void)? {
        get { list.copyHandler }
        set { list.copyHandler = newValue }
    }

    // MARK: Layout

    /// Pins the rail to the leading edge of `host`, between `top` and `bottom`. The view beside it constrains its
    /// leading edge to this view's trailing edge: the rail is zero wide while hidden, so that view then starts at
    /// the host's leading edge exactly as it did before the rail existed. The width yields to the host's trailing
    /// edge, so a host narrower than the rail never has conflicting constraints.
    func install(in host: NSView, top: NSLayoutYAxisAnchor, bottom: NSLayoutYAxisAnchor) {
        host.addSubview(self)
        let width = widthAnchor.constraint(equalToConstant: 0)
        width.priority = NSLayoutConstraint.Priority(999)
        widthConstraint = width
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor),
            topAnchor.constraint(equalTo: top),
            bottomAnchor.constraint(equalTo: bottom),
            width
        ])
    }

    private func configureHeader() {
        toggleButton.isBordered = false
        toggleButton.imagePosition = .imageOnly
        toggleButton.image = NSImage(systemSymbolName: Symbol.sidebar.rawValue, accessibilityDescription: nil)
        toggleButton.target = self
        toggleButton.action = #selector(toggleCollapsed)
        toggleButton.setAccessibilityRole(.button)
        toggleButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = PreviewChrome.factsFont()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The list is labelled Contents already; the visible title is the same words.
        titleLabel.setAccessibilityElement(false)
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = PreviewChrome.rowGap
        header.addArrangedSubview(toggleButton)
        header.addArrangedSubview(titleLabel)
    }

    /// Everything inside the rail gives way before the rail's own width: a hidden or folded rail is narrower than
    /// its parts, so only the leaf sizes are required.
    private func installInnerLayout() {
        let flexible: [NSLayoutConstraint] = [
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            header.trailingAnchor.constraint(lessThanOrEqualTo: divider.leadingAnchor, constant: -4),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: PreviewChrome.accessoryHeight),
            list.leadingAnchor.constraint(equalTo: leadingAnchor),
            list.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            list.topAnchor.constraint(equalTo: header.bottomAnchor),
            list.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        for constraint in flexible { constraint.priority = .defaultHigh }
        let fixed: [NSLayoutConstraint] = [
            divider.widthAnchor.constraint(equalToConstant: 1),
            toggleButton.widthAnchor.constraint(equalToConstant: 22),
            toggleButton.heightAnchor.constraint(equalToConstant: 22)
        ]
        NSLayoutConstraint.activate(flexible + fixed)
    }

    // MARK: Showing

    /// Brings the rail in line with what the preview shows. Called after every display, restyle and mode change.
    /// `isEligible` is false while the preview shows a state, a 3D view or a host-fixed density (the Theme page's
    /// sample). Restyling an unchanged document keeps the selection and scroll position; a different document
    /// starts with no current section until the next reading.
    func sync(headings: [MarkupHeading], mode: NativePreviewMode, hostWidth: CGFloat, isEligible: Bool,
              style: SafeModeStyle) {
        inputs = Inputs(headings: headings, mode: mode, isEligible: isEligible, style: style)
        isWide = ContentsRailPolicy.isWide(forWidth: hostWidth, previous: isWide)
        apply()
    }

    /// The host's width changed: re-decide with the last inputs. Does nothing inside the hysteresis band.
    func hostWidthChanged(_ width: CGFloat) {
        let next = ContentsRailPolicy.isWide(forWidth: width, previous: isWide)
        guard next != isWide else { return }
        isWide = next
        apply()
    }

    private func apply() {
        guard let inputs, inputs.isEligible,
              ContentsRailPolicy.offers(mode: inputs.mode, headingCount: inputs.headings.count, isWide: isWide) else {
            withdraw()
            return
        }
        isOffered = true
        isHidden = false
        let before = list.headings
        list.display(headings: inputs.headings, style: inputs.style)
        if list.headings != before { tracker.reset() }
        applyPalette(inputs.style.palette)
        applyCollapsedState()
        if !list.hasKeyboardFocus { list.showCurrent(row: tracker.current) }
    }

    /// Hides the rail and forgets the document, so a later one starts clean. Focus inside it is released first.
    private func withdraw() {
        guard isOffered else { return }
        if list.hasKeyboardFocus || window?.firstResponder === toggleButton { window?.makeFirstResponder(nil) }
        isOffered = false
        isHidden = true
        widthConstraint?.constant = 0
        list.clear()
        tracker.reset()
    }

    private func applyPalette(_ palette: NativeTextPalette) {
        layer?.backgroundColor = palette.background.cgColor
        divider.layer?.backgroundColor = palette.hairline.cgColor
        titleLabel.textColor = palette.muted
        toggleButton.contentTintColor = palette.muted
    }

    private func applyCollapsedState() {
        list.isHidden = isCollapsed
        titleLabel.isHidden = isCollapsed
        widthConstraint?.constant = ContentsRailPolicy.width(offered: isOffered, collapsed: isCollapsed)
        localize()
    }

    private func localize() {
        titleLabel.stringValue = PreviewStrings.text(.previewModeContents)
        titleLabel.toolTip = titleLabel.stringValue
        let label = PreviewStrings.text(isCollapsed ? .markupContentsRailShow : .markupContentsRailHide)
        toggleButton.toolTip = label
        toggleButton.setAccessibilityLabel(label)
        toggleButton.setAccessibilityHelp(PreviewStrings.text(.markupContentsRailHelp))
    }

    // MARK: Folding

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inHeaderStrip = point.x >= 0
            && point.x <= max(bounds.width, ContentsRailPolicy.expandedWidth)
            && point.y >= 0 && point.y <= PreviewChrome.accessoryHeight
        if event.clickCount == 2, isOffered, header.frame.contains(point) || inHeaderStrip {
            toggleCollapsed()
            return
        }
        super.mouseDown(with: event)
    }

    /// Folds the rail to its toggle, or opens it again. Focus in the list moves to the toggle first, so it never
    /// stays on a hidden view.
    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        if collapsed, list.hasKeyboardFocus, window?.makeFirstResponder(toggleButton) != true {
            window?.makeFirstResponder(nil)
        }
        isCollapsed = collapsed
        applyCollapsedState()
        if !collapsed, !list.hasKeyboardFocus { list.showCurrent(row: tracker.current) }
    }

    @objc private func toggleCollapsed() { setCollapsed(!isCollapsed) }

    // MARK: Following the reader

    /// Reads the on-screen characters from `viewport` and follows them. The preview calls this when the rendered
    /// text scrolls or is replaced; a rail that is not shown reads nothing.
    func viewportChanged() {
        guard isOffered, let reading = viewport?() else { return }
        track(reading)
    }

    /// Moves the current section to the nearest preceding heading of `reading` and shows it in the list. It only
    /// selects a row: no navigation, no announcement and no focus change. While the list holds focus the tracker
    /// still follows, but the reader's own selection is left where they put it.
    func track(_ reading: ContentsViewport) {
        guard isOffered else { return }
        tracker.update(visible: reading.visible, textLength: reading.textLength, headings: list.headings)
        guard !list.hasKeyboardFocus else { return }
        list.showCurrent(row: tracker.current)
    }

    /// A row was chosen in the list. It becomes the current section and stays so while its heading is in view.
    private func revealed(_ range: NSRange) {
        if let row = list.headings.firstIndex(where: { $0.range == range }) {
            tracker.pin(row)
            list.showCurrent(row: row)
        }
        onReveal?(range)
    }
}

/// The rail's toggle. Space and Escape belong to Quick Look, so a focused toggle hands them on untouched; Return and
/// keypad Enter press it, as on the code-block copy buttons.
@MainActor
final class ContentsRailToggleButton: NSButton {
    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode) {
            nextResponder?.keyDown(with: event)
        } else if [PreviewKeyCode.returnKey, PreviewKeyCode.keypadEnter].contains(event.keyCode),
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            performClick(nil)
        } else { super.keyDown(with: event) }
    }
}

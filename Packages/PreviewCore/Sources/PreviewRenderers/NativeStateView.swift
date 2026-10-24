import AppKit
import PreviewContracts

/// A centered symbol, title and body for every state that has no content: loading, empty, unavailable, disabled and
/// the two settings states. It is one accessibility element (the title and body read as one sentence), so
/// VoiceOver no longer lands on an empty text area. A loading state draws nothing until its grace period has
/// passed, and nothing at all when the preview arrives first.
@MainActor
final class NativeStateView: NSView {
    /// SF Symbol names are string-only API values; this is their single owner.
    private enum Symbol {
        static func name(for kind: NativeStateContent.Kind) -> String? {
            switch kind {
            case .loading: nil
            case .empty: "doc"
            case .unavailable: "exclamationmark.circle"
            case .disabled: "nosign"
            case .settingsUnavailable, .configurationUnavailable: "gearshape"
            }
        }
    }

    /// Receives the state's action. Nil, the default, in the Finder extension.
    var onAction: ((StateAction) -> Void)?
    /// Called when a loading state's grace period ends and it becomes visible, so the host can announce it.
    var onReveal: ((NativeStateContent) -> Void)?
    /// The language of the loading state's words (`showLoading` has no content of its own to present).
    var locale = Locale.current
    /// Waits for the grace period; tests substitute a scheduler they run by hand.
    var scheduler: any ChromeScheduler = TaskChromeScheduler()

    /// The current state, whether or not it is visible yet.
    private(set) var content: NativeStateContent?
    /// False while a loading state is still inside its grace period: nothing is drawn.
    private(set) var isRevealed = false

    private var palette = NativeTextPalette(theme: .system, isDark: false, increasedContrast: false)
    private var pending: ChromeScheduledAction?
    private var pendingGeneration: UUID?

    private let stack = NSStackView()
    private let symbolView = NSImageView()
    private let spinner = StateSpinner(frame: .zero)
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = PreviewChrome.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setAccessibilityElement(false)
        symbolView.imageScaling = .scaleProportionallyDown
        symbolView.setAccessibilityElement(false)
        titleLabel.font = PreviewChrome.stateTitleFont()
        bodyLabel.font = PreviewChrome.stateBodyFont()
        for label in [titleLabel, bodyLabel] {
            label.alignment = .center
            label.isSelectable = false
            label.preferredMaxLayoutWidth = PreviewChrome.stateMaximumWidth
            label.setAccessibilityElement(false)
        }
        actionButton.bezelStyle = .push
        actionButton.target = self
        actionButton.action = #selector(performAction)
        for view in [symbolView, spinner, titleLabel, bodyLabel, actionButton] {
            stack.addArrangedSubview(view)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: PreviewChrome.inset * 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -PreviewChrome.inset * 2),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: PreviewChrome.stateMaximumWidth)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityChildren([])
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    isolated deinit { pending?.cancel() }

    // MARK: Showing

    /// Shows `content` now. The same content again only restyles it.
    func show(_ content: NativeStateContent, palette: NativeTextPalette) {
        self.palette = palette
        guard content != self.content || !isRevealed else {
            render()
            return
        }
        cancelPending()
        self.content = content
        isRevealed = true
        render()
    }

    /// Starts a loading state that stays invisible for `delay`. Content arriving first (`clear`, `show`) cancels it,
    /// and an action that fires for an older generation does nothing.
    func showLoading(generation: UUID, after delay: Duration) {
        cancelPending()
        content = NativeStateContent.content(for: .loading, locale: locale)
        isRevealed = false
        pendingGeneration = generation
        render()
        pending = scheduler.schedule(after: delay) { [weak self] in
            self?.reveal(generation: generation)
        }
    }

    /// Removes the state and cancels a loading state that has not appeared.
    func clear() {
        cancelPending()
        content = nil
        isRevealed = false
        render()
    }

    /// Restyles whatever is shown, and what a later `showLoading` will show, with a new palette.
    func apply(palette: NativeTextPalette) {
        self.palette = palette
        render()
    }

    private func reveal(generation: UUID) {
        guard pendingGeneration == generation, let content, content.kind == .loading else { return }
        pending = nil
        pendingGeneration = nil
        isRevealed = true
        render()
        onReveal?(content)
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
        pendingGeneration = nil
    }

    // MARK: Reading, for tests and the preview's status

    var titleText: String { titleLabel.stringValue }
    var bodyText: String { bodyLabel.stringValue }
    var actionTitle: String { actionButton.title }
    var isActionVisible: Bool { !actionButton.isHidden }
    var isSpinnerRunning: Bool { spinner.isRunning }
    var actionButtonControlSize: NSControl.ControlSize { actionButton.controlSize }
    var stackSpacing: CGFloat { stack.spacing }

    // MARK: Drawing

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        updateChromeForWidth(bounds.width)
        super.layout()
    }

    private func updateChromeForWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let isCompact = width < PreviewChrome.compactWidth - PreviewChrome.compactHysteresis
        stack.spacing = isCompact ? PreviewChrome.rowGap : PreviewChrome.gap
        actionButton.controlSize = isCompact ? .small : .regular
        let pointSize: CGFloat = isCompact ? 22 : PreviewChrome.stateSymbolPointSize
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    }

    private func render() {
        guard let content, isRevealed else {
            isHidden = true
            spinner.setRunning(false)
            return
        }
        isHidden = false
        let isLoading = content.kind == .loading
        spinner.isHidden = !isLoading
        spinner.setRunning(isLoading)
        let image = Symbol.name(for: content.kind).flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        symbolView.image = image
        let isCompact = bounds.width > 0 && bounds.width < PreviewChrome.compactWidth - PreviewChrome.compactHysteresis
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: isCompact ? 22 : PreviewChrome.stateSymbolPointSize,
                                                                     weight: .regular)
        symbolView.isHidden = image == nil
        titleLabel.stringValue = content.title
        titleLabel.isHidden = content.title.isEmpty
        bodyLabel.stringValue = content.body
        bodyLabel.isHidden = content.body.isEmpty
        if let action = content.action {
            actionButton.title = Self.title(for: action)
            actionButton.isHidden = false
            setAccessibilityChildren([actionButton])
        } else {
            actionButton.title = ""
            actionButton.isHidden = true
            setAccessibilityChildren([])
        }
        titleLabel.textColor = palette.foreground
        bodyLabel.textColor = palette.muted
        symbolView.contentTintColor = palette.muted
        // The title and body read as one sentence, like a finding row.
        setAccessibilityLabel([content.title, content.body].filter { !$0.isEmpty }.joined(separator: ". "))
        updateChromeForWidth(bounds.width)
    }

    private static func title(for action: StateAction) -> String {
        switch action {
        case .openFile: PreviewStrings.text(.openFile)
        case .enableFormat: PreviewStrings.text(.stateActionEnableFormat)
        case .showSource: PreviewStrings.text(.stateActionShowSource)
        }
    }

    @objc private func performAction() {
        guard let action = content?.action else { return }
        onAction?(action)
    }
}

/// The repository's only progress indicator, behind the two calls the state view needs. It is not an accessibility
/// element: the state view's label already says what is happening.
@MainActor
private final class StateSpinner: NSProgressIndicator {
    private(set) var isRunning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .spinning
        isIndeterminate = true
        controlSize = .regular
        isDisplayedWhenStopped = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        if running { startAnimation(nil) } else { stopAnimation(nil) }
    }
}

import AppKit

/// The inline Go to Line bar: a labelled number field, the valid range or an error, and a close button.
/// It lives inside the preview (no panel or window), and only reports what was typed; the preview resolves
/// it against the displayed text.
@MainActor
final class GoToLineBar: NSView, NSTextFieldDelegate {
    /// Symbol names are string-only API; this is their one definition.
    private enum Symbol: String { case close = "xmark.circle.fill" }

    let titleLabel = NSTextField(labelWithString: "")
    let field = NSTextField()
    let messageLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var fieldLeadingToTitle: NSLayoutConstraint?
    private var fieldLeadingToEdge: NSLayoutConstraint?
    private var fieldWidthConstraint: NSLayoutConstraint?
    private var palette: NativeTextPalette?
    private var showsError = false

    /// Return pressed with the field's text.
    var onSubmit: ((String) -> Void)?
    /// Escape or the close button.
    var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        setAccessibilityRole(.group)
        titleLabel.font = .preferredFont(forTextStyle: .callout)
        messageLabel.font = .preferredFont(forTextStyle: .caption1)
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = self
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.alignment = .natural
        field.target = self
        field.action = #selector(submit)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(dismiss)
        closeButton.image = NSImage(systemSymbolName: Symbol.close.rawValue, accessibilityDescription: nil)
        for view in [titleLabel, field, messageLabel, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let toTitle = field.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: PreviewChrome.gap)
        toTitle.isActive = true
        let toEdge = field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewChrome.inset)
        toEdge.isActive = false
        let fieldWidth = field.widthAnchor.constraint(equalToConstant: 96)
        fieldWidth.isActive = true
        fieldLeadingToTitle = toTitle
        fieldLeadingToEdge = toEdge
        fieldWidthConstraint = fieldWidth
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewChrome.inset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: PreviewChrome.gap),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: messageLabel.trailingAnchor, constant: PreviewChrome.gap),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewChrome.inset),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20)
        ])
        localize()
    }

    required init?(coder: NSCoder) { nil }

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
        titleLabel.isHidden = isCompact
        field.controlSize = isCompact ? .small : .regular
        fieldLeadingToTitle?.isActive = !isCompact
        fieldLeadingToEdge?.isActive = isCompact
        fieldWidthConstraint?.constant = isCompact ? 72 : 96
    }

    /// The text of the message line: the valid range, or the reason the last entry was rejected.
    var message: String { messageLabel.stringValue }
    var isShowingError: Bool { showsError }

    func apply(palette: NativeTextPalette) {
        self.palette = palette
        titleLabel.textColor = palette.foreground
        updateMessageColor()
    }

    /// Shows the valid range and, if `error` is given, that instead.
    func show(lineCount: Int, error: String? = nil) {
        localize()
        if let error {
            messageLabel.stringValue = error
            showsError = true
        } else {
            messageLabel.stringValue = lineCount > 0
                ? PreviewStrings.format(.interactionGoToLineRange, arguments: [Int64(lineCount)])
                : ""
            showsError = false
        }
        messageLabel.toolTip = messageLabel.stringValue.isEmpty ? nil : messageLabel.stringValue
        updateMessageColor()
        field.setAccessibilityHelp(error ?? PreviewStrings.text(.interactionGoToLineHelp))
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func localize() {
        titleLabel.stringValue = PreviewStrings.text(.interactionGoToLine)
        field.placeholderString = PreviewStrings.text(.interactionGoToLinePlaceholder)
        field.setAccessibilityLabel(PreviewStrings.text(.interactionGoToLine))
        closeButton.setAccessibilityLabel(PreviewStrings.text(.interactionClose))
        closeButton.toolTip = PreviewStrings.text(.interactionClose)
        setAccessibilityLabel(PreviewStrings.text(.interactionGoToLine))
    }

    private func updateMessageColor() {
        guard let palette else { return }
        messageLabel.textColor = showsError ? palette.color(for: .deletion) : palette.muted
    }

    @objc private func submit() { onSubmit?(field.stringValue) }
    @objc private func dismiss() { onDismiss?() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { onDismiss?(); return true }
        return false
    }
}

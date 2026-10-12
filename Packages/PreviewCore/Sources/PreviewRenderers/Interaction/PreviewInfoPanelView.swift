import AppKit

/// An inline scroll group. The facade places it below chrome and caps its height against the host safe area;
/// this component owns safe text, natural height and disclosure state without a window or keyboard binding.
@MainActor
final class PreviewInfoPanelView: NSView {
    let scrollView: NSScrollView = InfoPanelScrollView()
    private let stack = InfoPanelDocumentStack()
    private var labelWidths: [NSLayoutConstraint] = []
    private var labels: [NSTextField] = []
    private var measuredNaturalHeight: CGFloat = 0
    private(set) var lines: [String] = []
    private(set) var commands: [PreviewCommand] = []
    private(set) var isExpanded = false
    var onExpansionChanged: ((Bool) -> Void)?
    var onNaturalHeightChanged: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PreviewChrome.rowGap
        scrollView.documentView = stack
        addSubview(scrollView)
        let bottom = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PreviewChrome.rowGap)
        bottom.priority = .defaultHigh // A collapsed facade slot must not require negative scroll height.
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: PreviewChrome.rowGap),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0), bottom
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(PreviewStrings.text(.previewInfoButtonLabel))
        setAccessibilityValue("")
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func display(lines: [String], commands: [PreviewCommand], palette: NativeTextPalette) {
        if self.lines != lines || self.commands != commands {
            removeLabels()
            self.lines = lines
            self.commands = commands
            for line in lines {
                let label = NSTextField(wrappingLabelWithString: line)
                label.font = PreviewChrome.factsFont()
                label.isEditable = false
                label.isSelectable = false // Information stays static; selection belongs to the preview content.
                label.setAccessibilityElement(false) // The group exposes one full, coherent text value.
                stack.addArrangedSubview(label)
                let width = label.widthAnchor.constraint(equalToConstant: 1)
                width.isActive = true
                labelWidths.append(width)
                labels.append(label)
            }
        }
        apply(palette: palette)
        setAccessibilityLabel(PreviewStrings.text(.previewInfoButtonLabel))
        setAccessibilityValue(lines.joined(separator: "\n"))
        if lines.isEmpty { setExpanded(false) }
        needsLayout = true
    }

    func apply(palette: NativeTextPalette) {
        for label in labels { label.textColor = palette.foreground }
    }

    /// Programmatic disclosure only; the facade posts one structural announcement for the user's button action.
    func setExpanded(_ expanded: Bool) {
        let next = expanded && !lines.isEmpty
        guard next != isExpanded else { return }
        isExpanded = next
        isHidden = !next
        if next {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        needsLayout = true
        onExpansionChanged?(next)
    }

    func clear() {
        setExpanded(false)
        lines = []; commands = []
        removeLabels()
        if measuredNaturalHeight != 0 {
            measuredNaturalHeight = 0
            onNaturalHeightChanged?(0)
        }
        setAccessibilityValue("")
        isHidden = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(1, scrollView.contentSize.width)
        for constraint in labelWidths { constraint.constant = width }
        for label in labels { label.preferredMaxLayoutWidth = width }
        stack.setFrameSize(NSSize(width: width, height: stack.frame.height))
        let height = stack.fittingSize.height
        stack.setFrameSize(NSSize(width: width, height: height))
        let natural = lines.isEmpty ? 0 : height + PreviewChrome.rowGap * 2
        if measuredNaturalHeight != natural {
            measuredNaturalHeight = natural
            onNaturalHeightChanged?(natural)
        }
    }

    /// Natural content height; the facade combines it with the quarter-safe-area maximum and a collapsed zero.
    var naturalHeight: CGFloat { measuredNaturalHeight }

    private func removeLabels() {
        NSLayoutConstraint.deactivate(labelWidths)
        for label in labels { stack.removeArrangedSubview(label); label.removeFromSuperview() }
        labelWidths.removeAll(); labels.removeAll()
    }
}

/// Matches FindingsDetailStack: scroll origin zero must expose the first provenance row.
@MainActor
private final class InfoPanelDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}

/// Keep Quick Look's reserved keys ahead of the native scroll view's page-scrolling behavior.
@MainActor
private final class InfoPanelScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
    // NSScrollView otherwise redirects focus to its document. Our static rows have no text editor;
    // retain native scrolling focus here so closing the panel can return it to a visible control.
    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode) {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }
}

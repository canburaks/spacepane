import AppKit

/// The native disclosure button for safe preview information. The facade owns its action and panel state.
@MainActor
final class PreviewInfoBadge: NSButton {
    private enum Symbol: String { case info = "info.circle" }
    static let side = PreviewChrome.infoButtonSide
    private(set) var captions = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        keyEquivalent = ""
        configureImage()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(PreviewStrings.text(.previewInfoButtonLabel))
        setExpanded(false)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    /// A borderless icon has no bezel overflow: its 22 pt alignment box is also its hit target.
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }

    func show(providerName: String?, color: NSColor, locale: Locale) {
        var lines = [PreviewStrings.text(.readOnly)]
        if let providerName, !providerName.isEmpty {
            lines.append(PreviewStrings.format(.interactionProviderBadge, arguments: [providerName], locale: locale))
        }
        captions = lines.joined(separator: "\n")
        toolTip = captions
        setAccessibilityLabel(PreviewStrings.text(.previewInfoButtonLabel))
        contentTintColor = color
        isHidden = false
    }

    func setExpanded(_ expanded: Bool) { setAccessibilityValue(expanded ? 1 : 0) }

    func hide() {
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        isHidden = true
        captions = ""
        toolTip = nil
        setAccessibilityLabel(nil)
        setExpanded(false)
    }

    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode) {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }

    /// Configures the NSImage itself; NSImageView.symbolConfiguration does not belong to NSButton.
    private func configureImage() {
        let symbol = NSImage(systemSymbolName: Symbol.info.rawValue, accessibilityDescription: nil)
        image = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
    }
}

/// A small outlined note in the header's reserved slot, beside the info badge: the temporary zoom level for as long
/// as it applies, or "Copied" for a moment. The slot is reserved by the preview (`PreviewChrome.chipSlotWidth`)
/// while the row has room, so showing or hiding the chip moves nothing; in a row too narrow for the slot the chip
/// keeps its own width and overlaps the end of the row while it shows. It fades in, unless Reduce Motion is on, and
/// never fades out.
@MainActor
final class PreviewChip: NSView {
    private let label = NSTextField(labelWithString: "")

    /// Reads the Reduce Motion setting each time the chip appears; tests substitute it.
    var reducesMotion: @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Whether the last change faded the chip in. Always false under Reduce Motion.
    private(set) var changedWithMotion = false
    /// What the tooltip and VoiceOver say; it can be longer than the text the chip shows.
    private(set) var spokenText = ""
    /// The text the chip shows.
    var text: String { label.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = PreviewChrome.chipCornerRadius
        layer?.borderWidth = 1
        label.font = PreviewChrome.factsFont()
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        // Lowest priority, so any bound later put on the chip's width truncates the text instead of breaking a constraint.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewChrome.chipPadding),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewChrome.chipPadding),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    /// Shows `text`; `spoken` replaces it in the tooltip and for VoiceOver when the text alone says too little.
    func show(_ text: String, spoken: String? = nil) {
        let wasHidden = isHidden
        label.stringValue = text
        let announced = spoken ?? text
        spokenText = announced
        toolTip = announced
        setAccessibilityLabel(announced)
        isHidden = false
        // Only an appearing chip moves; a chip whose text changes in place does not.
        changedWithMotion = wasHidden && !reducesMotion()
        if changedWithMotion {
            alphaValue = 0
            animator().alphaValue = 1
        } else {
            alphaValue = 1
        }
    }

    func hide() {
        isHidden = true
        alphaValue = 1
        changedWithMotion = false
        label.stringValue = ""
        spokenText = ""
        toolTip = nil
        setAccessibilityLabel(nil)
    }

    func apply(palette: NativeTextPalette) {
        label.textColor = palette.foreground
        layer?.borderColor = palette.hairline.cgColor
    }
}

import AppKit
import PreviewContracts

/// Owns the single facts/control row, its optional notes and the bottom limits slot.
@MainActor
final class PreviewHeaderView: NSView {
    struct Model {
        let notes: String
        let limits: String
        let providerName: String?
        let showsInfoBadge: Bool
        let locale: Locale
    }

    let factsLabel = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let limitsLabel = NSTextField(wrappingLabelWithString: "")
    let infoBadge = PreviewInfoBadge(frame: .zero)
    let chip = PreviewChip(frame: .zero)
    private let modeSelector = PreviewModeControlView(frame: .zero)
    var modeControl: NSSegmentedControl { modeSelector.segmentedControl }
    var modePullDown: NSPopUpButton { modeSelector.pullDownControl }
    var visibleModeControl: NSControl? { modeSelector.visibleControl }
    let headerGuide = NSLayoutGuide()
    var onSelectMode: ((NativePreviewMode) -> Void)?

    private let chipSlotGuide = NSLayoutGuide()
    private var headerTopConstraint: NSLayoutConstraint?
    private var notesTopConstraint: NSLayoutConstraint?
    private var limitsGapConstraint: NSLayoutConstraint?
    private var limitsBottomConstraint: NSLayoutConstraint?
    private var factsGapConstraint: NSLayoutConstraint?
    private var modeGapConstraint: NSLayoutConstraint?
    private var controlRow: [NSLayoutConstraint] = []
    private var badgeRow: [NSLayoutConstraint] = []
    private var factsRow: [NSLayoutConstraint] = []
    private var collapsedControl: [NSLayoutConstraint] = []
    private var collapsedNotes: [NSLayoutConstraint] = []
    private var collapsedLimits: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        factsLabel.font = PreviewChrome.factsFont()
        factsLabel.lineBreakMode = .byTruncatingMiddle
        factsLabel.maximumNumberOfLines = 1
        factsLabel.setContentCompressionResistancePriority(PreviewChrome.notesNaturalWidthPriority, for: .horizontal)
        factsLabel.isHidden = true
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(999), for: .vertical)
        limitsLabel.font = PreviewChrome.factsFont()
        limitsLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(999), for: .vertical)
        limitsLabel.isHidden = true
        modeSelector.onSelectMode = { [weak self] mode in self?.onSelectMode?(mode) }
        for view in [factsLabel, statusLabel, infoBadge, modeSelector, limitsLabel, chip] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        addLayoutGuide(headerGuide)
        addLayoutGuide(chipSlotGuide)
    }

    required init?(coder: NSCoder) { nil }

    func installLayout(in host: NSView, contentGuide: NSLayoutGuide) {
        let safeArea = host.safeAreaLayoutGuide
        let headerTop = headerGuide.topAnchor.constraint(equalTo: safeArea.topAnchor)
        headerTopConstraint = headerTop
        let notesTop = statusLabel.topAnchor.constraint(equalTo: headerGuide.bottomAnchor)
        notesTopConstraint = notesTop
        let rowHeight = headerGuide.heightAnchor.constraint(equalToConstant: 0)
        rowHeight.priority = .defaultLow
        controlRow = [headerGuide.heightAnchor.constraint(equalTo: modeSelector.heightAnchor)]
        badgeRow = [headerGuide.heightAnchor.constraint(greaterThanOrEqualTo: infoBadge.heightAnchor)]
        factsRow = [headerGuide.heightAnchor.constraint(greaterThanOrEqualTo: factsLabel.heightAnchor)]
        collapsedControl = [modeSelector.widthAnchor.constraint(equalToConstant: 0)]
        collapsedNotes = [statusLabel.heightAnchor.constraint(equalToConstant: 0)]
        collapsedLimits = [limitsLabel.heightAnchor.constraint(equalToConstant: 0)]
        let factsGap = modeSelector.leadingAnchor.constraint(equalTo: factsLabel.trailingAnchor)
        factsGapConstraint = factsGap
        let modeGap = modeSelector.trailingAnchor.constraint(equalTo: chipSlotGuide.leadingAnchor)
        modeGapConstraint = modeGap
        let limitsGap = contentGuide.bottomAnchor.constraint(equalTo: limitsLabel.topAnchor)
        limitsGapConstraint = limitsGap
        let limitsBottom = limitsLabel.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        limitsBottomConstraint = limitsBottom
        let chipSlotWidth = chipSlotGuide.widthAnchor.constraint(equalToConstant: PreviewChrome.chipSlotWidth)
        chipSlotWidth.priority = PreviewChrome.chipSlotPriority
        NSLayoutConstraint.activate(collapsedControl + collapsedNotes + collapsedLimits)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor), trailingAnchor.constraint(equalTo: host.trailingAnchor),
            topAnchor.constraint(equalTo: host.topAnchor), bottomAnchor.constraint(equalTo: host.bottomAnchor),
            headerGuide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewChrome.inset),
            headerGuide.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewChrome.inset),
            headerTop, rowHeight, headerGuide.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            factsLabel.leadingAnchor.constraint(equalTo: headerGuide.leadingAnchor),
            factsLabel.centerYAnchor.constraint(equalTo: headerGuide.centerYAnchor),
            factsLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 0), factsGap,
            modeSelector.centerYAnchor.constraint(equalTo: headerGuide.centerYAnchor), modeGap,
            chipSlotWidth, chipSlotGuide.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            chipSlotGuide.trailingAnchor.constraint(equalTo: infoBadge.leadingAnchor, constant: -PreviewChrome.rowGap),
            chipSlotGuide.topAnchor.constraint(equalTo: headerGuide.topAnchor),
            chipSlotGuide.heightAnchor.constraint(equalToConstant: PreviewInfoBadge.side),
            chip.trailingAnchor.constraint(equalTo: chipSlotGuide.trailingAnchor),
            chip.centerYAnchor.constraint(equalTo: headerGuide.centerYAnchor),
            infoBadge.centerYAnchor.constraint(equalTo: headerGuide.centerYAnchor),
            infoBadge.trailingAnchor.constraint(equalTo: headerGuide.trailingAnchor),
            infoBadge.widthAnchor.constraint(equalToConstant: PreviewInfoBadge.side),
            infoBadge.heightAnchor.constraint(equalToConstant: PreviewInfoBadge.side),
            notesTop, statusLabel.leadingAnchor.constraint(equalTo: headerGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: headerGuide.trailingAnchor),
            limitsGap, limitsLabel.leadingAnchor.constraint(equalTo: headerGuide.leadingAnchor),
            limitsLabel.trailingAnchor.constraint(equalTo: headerGuide.trailingAnchor), limitsBottom
        ])
    }

    func displayFacts(_ lines: [String]) {
        let text = lines.joined(separator: PreviewStrings.text(.previewFactsSeparator))
        factsLabel.stringValue = text
        factsLabel.toolTip = text.isEmpty ? nil : text
        factsLabel.setAccessibilityValue(text.isEmpty ? nil : text)
        factsLabel.isHidden = text.isEmpty
        updateChrome()
    }

    func apply(palette: NativeTextPalette) {
        chip.apply(palette: palette)
        factsLabel.textColor = palette.muted
        statusLabel.textColor = palette.foreground
        limitsLabel.textColor = palette.muted
    }

    func display(_ model: Model, palette: NativeTextPalette) {
        statusLabel.stringValue = model.notes
        limitsLabel.stringValue = model.limits
        if model.showsInfoBadge {
            infoBadge.show(providerName: model.providerName, color: palette.foreground, locale: model.locale)
        } else { infoBadge.hide() }
        updateChrome()
    }

    func displayModes(_ available: [NativePreviewMode], selected: NativePreviewMode,
                      density: PreviewChrome.Density = .regular) {
        modeSelector.display(available, selected: selected, density: density)
        updateChrome()
    }

    func setDensity(_ density: PreviewChrome.Density) {
        modeSelector.setDensity(density)
        updateChrome()
    }

    func clearModes() {
        modeSelector.clear()
        updateChrome()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    private func updateChrome() {
        let hasControl = visibleModeControl != nil
        let hasBadge = !infoBadge.isHidden
        let hasFacts = !factsLabel.isHidden
        let hasNotes = !statusLabel.stringValue.isEmpty
        let hasLimits = !limitsLabel.stringValue.isEmpty
        NSLayoutConstraint.deactivate(controlRow + badgeRow + factsRow + collapsedControl + collapsedNotes + collapsedLimits)
        NSLayoutConstraint.activate(hasControl ? controlRow : collapsedControl)
        if hasBadge { NSLayoutConstraint.activate(badgeRow) }
        if hasFacts { NSLayoutConstraint.activate(factsRow) }
        if !hasNotes { NSLayoutConstraint.activate(collapsedNotes) }
        if !hasLimits { NSLayoutConstraint.activate(collapsedLimits) }
        headerTopConstraint?.constant = hasControl || hasBadge || hasFacts || hasNotes ? PreviewChrome.gap : 0
        factsGapConstraint?.constant = hasControl && hasFacts ? PreviewChrome.gap : 0
        modeGapConstraint?.constant = hasControl ? -PreviewChrome.gap : 0
        notesTopConstraint?.constant = hasNotes ? PreviewChrome.rowGap : 0
        statusLabel.isHidden = !hasNotes
        limitsLabel.isHidden = !hasLimits
        limitsGapConstraint?.constant = hasLimits ? -PreviewChrome.rowGap : 0
        limitsBottomConstraint?.constant = hasLimits ? -PreviewChrome.rowGap : 0
    }
}

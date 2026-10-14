import AppKit
import PreviewContracts

/// One summary owns the count and copying policy. Details stay inside a native scroll view;
/// the host supplies the expanded height cap, without resizing its window or re-reading a file.
///
/// Two copy actions share the controls row. Copy Concealed Text is offered when the presentation concealed
/// anything; Copy Findings Report (decision 029) whenever the banner lists a finding. Both leave the writing,
/// the confirmation chip and the announcement to the hosting preview.
@MainActor
final class NativeFindingsBanner: NSView {
    var onCopyConcealedText: (() -> Void)?
    /// Copy Findings Report. Left unset, the action asks the preview that hosts the banner (`copyFindingsReport`
    /// in `FindingsReportCopying.swift`), so the action works wherever the banner sits in a preview.
    var onCopyFindingsReport: (() -> Void)?
    var onExpansionChanged: ((Bool) -> Void)?
    /// Only native disclosure presses notify the host to publish an accessibility layout change.
    var onDisclosureActivated: (() -> Void)?

    private let stack = NSStackView()
    private let controls = NSStackView()
    private let summaryIcon = NSImageView()
    private let detailStack = FindingsDetailStack()
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let reportButton = NSButton(title: "", target: nil, action: nil)
    private var collapsedHeight: NSLayoutConstraint?
    private var preferredDetailHeight: NSLayoutConstraint?
    private var rowWidths: [NSLayoutConstraint] = []
    private var textWidths: [NSLayoutConstraint] = []
    private var detailIcons: [NSImageView] = []
    private var rendered: (findings: [PreviewFinding], concealed: Int, offersCopy: Bool, locale: Locale)?

    let summaryLabel = NSTextField(wrappingLabelWithString: "")
    let detailsButton = NSButton(title: "", target: nil, action: nil)
    let detailScrollView = NSScrollView()
    private(set) var rowLabels: [NSTextField] = []
    private(set) var detailLabels: [NSTextField] = []
    private(set) var orderedDetailKinds: [PreviewFindingKind] = []
    private(set) var isExpanded = false
    private(set) var offersConcealedCopy = false
    /// Whether Copy Findings Report is on offer: true exactly while at least one finding is listed.
    private(set) var offersFindingsReport = false
    var copyActionButton: NSButton { copyButton }
    var findingsReportActionButton: NSButton { reportButton }
    var hasContent: Bool { rendered.map { !$0.findings.isEmpty || $0.concealed > 0 || $0.offersCopy } ?? false }
    var summarySymbolName: String? { summaryIcon.identifier?.rawValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PreviewChrome.rowGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        summaryLabel.font = NSFont.preferredFont(forTextStyle: .callout)
        summaryLabel.isSelectable = true
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryIcon.symbolConfiguration = .init(textStyle: .callout)
        summaryIcon.setAccessibilityElement(false)
        let summaryRow = NSStackView(views: [summaryIcon, summaryLabel])
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .firstBaseline
        summaryRow.spacing = PreviewChrome.rowGap
        stack.addArrangedSubview(summaryRow)
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = PreviewChrome.rowGap
        // The row never sets the banner's minimum width: `layout()` stacks the buttons when they do not fit.
        controls.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        for button in [detailsButton, copyButton, reportButton] {
            button.target = self
            button.bezelStyle = .push
            button.controlSize = .small
            controls.addArrangedSubview(button)
        }
        detailsButton.action = #selector(toggleDetails)
        copyButton.action = #selector(copyConcealedText)
        reportButton.action = #selector(copyFindingsReportPressed)
        stack.addArrangedSubview(controls)
        detailScrollView.hasVerticalScroller = true
        detailScrollView.hasHorizontalScroller = false
        detailScrollView.autohidesScrollers = true
        detailScrollView.drawsBackground = false
        detailScrollView.borderType = .noBorder
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false
        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = PreviewChrome.rowGap
        detailScrollView.documentView = detailStack
        stack.addArrangedSubview(detailScrollView)
        detailScrollView.isHidden = true
        let preferredHeight = detailScrollView.heightAnchor.constraint(equalToConstant: 0)
        preferredHeight.priority = .defaultLow
        preferredDetailHeight = preferredHeight
        let collapsed = heightAnchor.constraint(equalToConstant: 0)
        collapsedHeight = collapsed
        let bottom = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PreviewChrome.gap)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: PreviewChrome.gap),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewChrome.inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewChrome.inset),
            summaryRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailScrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            summaryIcon.widthAnchor.constraint(equalToConstant: 20),
            preferredHeight, bottom, collapsed
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(PreviewStrings.text(.findingBannerLabel))
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func display(_ findings: [PreviewFinding], concealedValueCount: Int = 0,
                 offersConcealedCopy offersCopy: Bool, palette: NativeTextPalette, locale: Locale) {
        let concealed = max(0, concealedValueCount)
        if let rendered, rendered.findings == findings, rendered.concealed == concealed,
           rendered.offersCopy == offersCopy, rendered.locale == locale {
            applyColors(palette)
            return
        }
        rendered = (findings, concealed, offersCopy, locale)
        summaryLabel.stringValue = concealed > 0
            ? PreviewStrings.count(.findingSummaryConcealed, concealed, locale: locale)
            : PreviewStrings.count(.findingSummary, findings.count, locale: locale)
        summaryLabel.setAccessibilityLabel(summaryLabel.stringValue)
        let first = findings.first
        let summarySymbol = concealed > 0 ? FindingsSymbol.concealed : first.map(FindingsSymbol.name) ?? FindingsSymbol.neutral
        summaryIcon.image = NSImage(systemSymbolName: summarySymbol, accessibilityDescription: nil)
        summaryIcon.identifier = NSUserInterfaceItemIdentifier(summarySymbol)
        offersConcealedCopy = offersCopy
        copyButton.isHidden = !offersCopy
        copyButton.title = PreviewStrings.text(.findingActionCopyConcealed)
        copyButton.toolTip = PreviewStrings.text(.findingActionCopyConcealedHelp)
        copyButton.setAccessibilityHelp(PreviewStrings.text(.findingActionCopyConcealedHelp))
        offersFindingsReport = !findings.isEmpty
        reportButton.isHidden = findings.isEmpty
        let reportTitle = PreviewStrings.text(.findingsReportCopy)
        reportButton.title = reportTitle
        reportButton.setAccessibilityLabel(reportTitle)
        reportButton.toolTip = PreviewStrings.text(.findingsReportCopyHint)
        reportButton.setAccessibilityHelp(PreviewStrings.text(.findingsReportCopyHint))
        removeRows()
        // The cloud-folder caution comes first. Every other producer order remains unchanged. The copied report
        // lists findings in this same order.
        let ordered = FindingsReport.inBannerOrder(findings)
        for finding in ordered { addRow(finding, locale: locale) }
        orderedDetailKinds = ordered.map(\.kind)
        detailsButton.isHidden = findings.isEmpty
        controls.isHidden = findings.isEmpty && !offersCopy
        if findings.isEmpty { setExpanded(false) }
        updateDisclosure()
        isHidden = !hasContent
        collapsedHeight?.isActive = !hasContent
        applyColors(palette)
        needsLayout = true
    }

    func setExpanded(_ expanded: Bool) {
        let next = expanded && !orderedDetailKinds.isEmpty
        guard next != isExpanded else { return }
        isExpanded = next
        detailScrollView.isHidden = !next
        if next {
            detailScrollView.contentView.scroll(to: .zero)
            detailScrollView.reflectScrolledClipView(detailScrollView.contentView)
        }
        updateDisclosure()
        needsLayout = true
        onExpansionChanged?(next)
    }

    func collapseDetails() { setExpanded(false) }

    func clear() {
        collapseDetails()
        rendered = nil
        removeRows()
        summaryLabel.stringValue = ""
        summaryLabel.setAccessibilityLabel(nil)
        offersConcealedCopy = false
        offersFindingsReport = false
        copyButton.isHidden = true
        reportButton.isHidden = true
        detailsButton.isHidden = true
        controls.isHidden = true
        isHidden = true
        collapsedHeight?.isActive = true
    }

    override func layout() {
        super.layout()
        updateControlsOrientation()
        // The document keeps its natural height. Only its viewport yields to the host's cap.
        let width = max(20 + PreviewChrome.rowGap + 1, detailScrollView.contentSize.width)
        for constraint in rowWidths { constraint.constant = width }
        let textWidth = max(1, width - 20 - PreviewChrome.rowGap)
        for constraint in textWidths { constraint.constant = textWidth }
        for label in rowLabels + detailLabels { label.preferredMaxLayoutWidth = textWidth }
        detailStack.setFrameSize(NSSize(width: width, height: detailStack.frame.height))
        let naturalHeight = detailStack.fittingSize.height
        detailStack.setFrameSize(NSSize(width: width, height: naturalHeight))
        if preferredDetailHeight?.constant != naturalHeight { preferredDetailHeight?.constant = naturalHeight }
    }

    /// The action buttons share one row while they fit the banner's width and stack when they do not, so a narrow
    /// preview or a longer translation never widens the banner past its host or cuts a title short.
    private func updateControlsOrientation() {
        guard bounds.width > 0 else { return }
        let buttons = controls.arrangedSubviews.filter { !$0.isHidden }
        let rowWidth = buttons.reduce(0) { $0 + $1.intrinsicContentSize.width }
            + controls.spacing * CGFloat(max(0, buttons.count - 1))
        let orientation: NSUserInterfaceLayoutOrientation = rowWidth <= bounds.width - 2 * PreviewChrome.inset ? .horizontal : .vertical
        guard controls.orientation != orientation else { return }
        controls.orientation = orientation
        controls.alignment = orientation == .horizontal ? .centerY : .leading
        needsLayout = true
    }

    @objc private func toggleDetails() {
        guard !orderedDetailKinds.isEmpty else { return }
        setExpanded(!isExpanded)
        onDisclosureActivated?()
    }
    @objc private func copyConcealedText() { if offersConcealedCopy { onCopyConcealedText?() } }
    @objc private func copyFindingsReportPressed() {
        guard offersFindingsReport else { return }
        if let onCopyFindingsReport { onCopyFindingsReport() } else { (superview as? NativePreviewView)?.copyFindingsReport() }
    }

    private func updateDisclosure() {
        let title = PreviewStrings.text(isExpanded ? .findingActionHideDetails : .findingActionShowDetails)
        detailsButton.title = title
        detailsButton.setAccessibilityLabel(title)
        detailsButton.setAccessibilityValue(isExpanded ? 1 : 0)
    }

    private func removeRows() {
        NSLayoutConstraint.deactivate(rowWidths + textWidths)
        for row in detailStack.arrangedSubviews {
            detailStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowLabels.removeAll(); detailLabels.removeAll(); detailIcons.removeAll()
        rowWidths.removeAll(); textWidths.removeAll(); orderedDetailKinds.removeAll()
    }

    private func addRow(_ finding: PreviewFinding, locale: Locale) {
        let message = FindingText.message(for: finding, locale: locale)
        let detail = FindingText.detail(for: finding, locale: locale)
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = NSFont.preferredFont(forTextStyle: .callout)
        label.isSelectable = true
        label.setAccessibilityLabel([FindingText.severityDescription(finding.severity), message, detail].compactMap { $0 }.joined(separator: ". "))
        let text = NSStackView(views: [label])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 0
        label.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        if let detail {
            let secondary = NSTextField(wrappingLabelWithString: detail)
            secondary.font = NSFont.preferredFont(forTextStyle: .caption1)
            secondary.isSelectable = true
            secondary.setAccessibilityElement(false) // The message announces one coherent item, including all safe detail.
            if case .decodedText = finding.detail {
                secondary.maximumNumberOfLines = 2
                secondary.lineBreakMode = .byWordWrapping
                secondary.cell?.truncatesLastVisibleLine = true
            }
            text.addArrangedSubview(secondary)
            secondary.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
            detailLabels.append(secondary)
        }
        let icon = NSImageView()
        let symbol = FindingsSymbol.name(finding)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.identifier = NSUserInterfaceItemIdentifier(symbol)
        icon.symbolConfiguration = .init(textStyle: .callout)
        icon.setAccessibilityElement(false)
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = PreviewChrome.rowGap
        detailStack.addArrangedSubview(row)
        let rowWidth = row.widthAnchor.constraint(equalToConstant: 20 + PreviewChrome.rowGap + 1)
        let textWidth = text.widthAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([rowWidth, textWidth, icon.widthAnchor.constraint(equalToConstant: 20)])
        rowWidths.append(rowWidth); textWidths.append(textWidth)
        rowLabels.append(label); detailIcons.append(icon)
    }

    private func applyColors(_ palette: NativeTextPalette) {
        for label in [summaryLabel] + rowLabels + detailLabels { label.textColor = palette.foreground }
        summaryIcon.contentTintColor = palette.foreground
        for (index, icon) in detailIcons.enumerated() {
            let severity = rendered?.findings.first { $0.kind == orderedDetailKinds[index] }?.severity
            icon.contentTintColor = severity == .warning ? palette.color(for: .number) : palette.foreground
        }
    }
}

@MainActor
private final class FindingsDetailStack: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
private enum FindingsSymbol {
    static let concealed = "eye.slash"
    static let neutral = "circle"

    static func name(_ finding: PreviewFinding) -> String {
        switch finding.kind {
        case .secretPrivateKey, .secretCloudAccessKey, .secretCodeHostingToken, .secretAPIKey,
             .secretWebToken, .secretAuthorizationHeader, .secretSensitiveField, .secretSyncedFolder:
            return concealed
        default:
            switch finding.severity {
            case .warning: return "exclamationmark.triangle.fill"
            case .caution: return "exclamationmark.circle"
            case .info: return neutral
            }
        }
    }
}

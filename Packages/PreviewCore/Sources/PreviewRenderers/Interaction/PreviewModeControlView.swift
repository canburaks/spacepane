import AppKit

/// Native presentations of one supplied mode list. The facade owns capabilities, current mode and dispatch.
@MainActor
final class PreviewModeControlView: NSView {
    let segmentedControl: NSSegmentedControl = ModeSegmentedControl()
    let pullDownControl: NSPopUpButton = ModePullDownControl(frame: .zero, pullsDown: true)
    var onSelectMode: ((NativePreviewMode) -> Void)?
    private var availableModes: [NativePreviewMode] = []
    private var selectedMode = NativePreviewMode.source
    private var density = PreviewChrome.Density.regular
    private var segmentConstraints: [NSLayoutConstraint] = []
    private var menuConstraints: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        segmentedControl.trackingMode = .selectOne
        segmentedControl.target = self
        segmentedControl.action = #selector(selectSegment)
        let label = PreviewStrings.text(.previewModeControlLabel)
        for control in [segmentedControl, pullDownControl] as [NSControl] {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.setAccessibilityLabel(label)
            control.isHidden = true
            addSubview(control)
        }
        segmentConstraints = constraints(for: segmentedControl)
        menuConstraints = constraints(for: pullDownControl)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    var visibleControl: NSControl? {
        guard availableModes.count > 1 else { return nil }
        return density == .compact ? pullDownControl : segmentedControl
    }

    override var intrinsicContentSize: NSSize { visibleControl?.intrinsicContentSize ?? .zero }

    func display(_ available: [NativePreviewMode], selected: NativePreviewMode,
                 density: PreviewChrome.Density, languagePreferences: [String]? = nil) {
        availableModes = available
        selectedMode = available.contains(selected) ? selected : available.first ?? .source
        self.density = density
        let label = PreviewStrings.text(.previewModeControlLabel, languagePreferences: languagePreferences)
        segmentedControl.setAccessibilityLabel(label)
        pullDownControl.setAccessibilityLabel(label)
        segmentedControl.segmentCount = available.count
        for (index, mode) in available.enumerated() {
            segmentedControl.setLabel(PreviewStrings.text(mode.title, languagePreferences: languagePreferences), forSegment: index)
            segmentedControl.setToolTip(shortcut(for: index), forSegment: index)
        }
        segmentedControl.selectedSegment = available.firstIndex(of: selectedMode) ?? -1
        if available.isEmpty {
            pullDownControl.menu = nil
            segmentedControl.setAccessibilityValue(nil)
            pullDownControl.setAccessibilityValue(nil)
        } else {
            let currentTitle = PreviewStrings.text(selectedMode.title, languagePreferences: languagePreferences)
            let menu = NSMenu()
            menu.autoenablesItems = false
            // As in the existing native Sort pull-down, the first inert item is the closed button's title.
            let title = menu.addItem(withTitle: currentTitle, action: nil, keyEquivalent: "")
            title.isEnabled = false
            title.tag = -1
            for (index, mode) in available.enumerated() {
                let item = NSMenuItem(title: PreviewStrings.text(mode.title, languagePreferences: languagePreferences),
                    action: #selector(selectMenuItem(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.state = mode == selectedMode ? .on : .off
                item.toolTip = shortcut(for: index)
                menu.addItem(item)
            }
            pullDownControl.menu = menu
            // Installing a native pull-down supplies a private action to nil-action rows. This hidden title
            // supplies the closed button's text only; restore its explicitly inert state after installation.
            title.action = nil
            title.target = nil
            title.isEnabled = false
            segmentedControl.setAccessibilityValue(currentTitle)
            pullDownControl.setAccessibilityValue(currentTitle)
        }
        applyDensity()
    }

    /// Density changes reuse supplied labels and items. No mode callback or accessibility announcement.
    func setDensity(_ density: PreviewChrome.Density) {
        guard self.density != density else { return }
        self.density = density
        applyDensity()
    }

    func clear() { display([], selected: .source, density: density) }

    @objc private func selectSegment() {
        guard availableModes.indices.contains(segmentedControl.selectedSegment) else { return }
        onSelectMode?(availableModes[segmentedControl.selectedSegment])
    }

    @objc private func selectMenuItem(_ item: NSMenuItem) {
        // Retained menu rows from a replaced document cannot select a mode in the new capability list.
        guard pullDownControl.menu?.items.contains(where: { $0 === item }) == true,
              availableModes.indices.contains(item.tag) else { return }
        onSelectMode?(availableModes[item.tag])
    }

    private func shortcut(for index: Int) -> String? {
        PreviewCommand.modeNumbers.contains(index + 1) ? PreviewCommand.mode(index + 1).shortcutDescription : nil
    }

    private func constraints(for control: NSControl) -> [NSLayoutConstraint] {
        [control.leadingAnchor.constraint(equalTo: leadingAnchor),
         control.trailingAnchor.constraint(equalTo: trailingAnchor),
         control.topAnchor.constraint(equalTo: topAnchor),
         control.bottomAnchor.constraint(equalTo: bottomAnchor)]
    }

    private func applyDensity() {
        let focused = window?.firstResponder as? NSView
        let replacesFocusedControl = focused?.isDescendant(of: self) == true
        let visible = visibleControl
        NSLayoutConstraint.deactivate(segmentConstraints + menuConstraints)
        segmentedControl.isHidden = visible !== segmentedControl
        pullDownControl.isHidden = visible !== pullDownControl
        isHidden = visible == nil
        if visible === segmentedControl { NSLayoutConstraint.activate(segmentConstraints) }
        if visible === pullDownControl { NSLayoutConstraint.activate(menuConstraints) }
        invalidateIntrinsicContentSize()
        needsLayout = true
        if replacesFocusedControl, focused !== visible {
            if let visible, window?.makeFirstResponder(visible) == true { return }
            window?.makeFirstResponder(nil)
        }
    }
}

/// The native bezel stays intact; the alignment box matches the row's actual control bounds.
@MainActor
private final class ModePullDownControl: NSPopUpButton {
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode) {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class ModeSegmentedControl: NSSegmentedControl {
    override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode) {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }
}

import AppKit

/// Inline information shares actual surface capabilities with dispatch. No source reads, parsing, or lazy
/// content-model access are needed to describe the current preview.
extension NativePreviewView {
    var commandAvailability: PreviewCommandAvailability {
        let custom = shownModeView
        let hasText = showsTextMode
        let hasOutline = showsOutlineMode
        let hasTable = showsTableMode || custom is any PreviewHostsTable
        return .init(hasContent: hasDisplayableContent || geometryPresentation != nil,
            selectionCopy: hasText || hasOutline || hasTable || custom is any PreviewSafeCopying,
            wholeTextCopy: copyAllText?.isEmpty == false,
            search: hasText || hasOutline ? .full : (hasTable ? .filter : .none),
            sourceLineNavigation: hasText && selectedMode != .rendered,
            zoom: hasDisplayableContent && geometryPresentation == nil
                && (custom == nil || custom?.respondsToTextZoom == true || custom is any SafeModeZoomable),
            geometryNavigation: geometrySupportsNavigation, modeCount: displayedModes.count)
    }

    func installInfoPanel() {
        infoPanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoPanel)
        infoBadge.target = self
        infoBadge.action = #selector(toggleInfoPanel)
        let collapsed = infoPanel.heightAnchor.constraint(equalToConstant: 0)
        let preferred = infoPanel.heightAnchor.constraint(equalToConstant: 0)
        preferred.priority = .defaultLow
        infoPanelCollapsedHeight = collapsed
        infoPanelPreferredHeight = preferred
        NSLayoutConstraint.activate([
            infoPanel.leadingAnchor.constraint(equalTo: headerGuide.leadingAnchor),
            infoPanel.trailingAnchor.constraint(equalTo: headerGuide.trailingAnchor),
            infoPanel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor),
            infoPanel.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            infoPanel.heightAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.heightAnchor,
                multiplier: PreviewChrome.infoMaximumFraction), preferred, collapsed
        ])
        infoPanel.onExpansionChanged = { [weak self] expanded in
            guard let self else { return }
            if !expanded, let focused = self.window?.firstResponder as? NSView,
               focused.isDescendant(of: self.infoPanel) {
                if self.infoBadge.isHidden || self.window?.makeFirstResponder(self.infoBadge) != true {
                    self.window?.makeFirstResponder(nil)
                }
            }
            self.infoPanelCollapsedHeight?.isActive = !expanded
            self.infoBadge.setExpanded(expanded)
            self.needsLayout = true
        }
        infoPanel.onNaturalHeightChanged = { [weak self] height in
            self?.infoPanelPreferredHeight?.constant = height
            self?.needsLayout = true
        }
    }

    @objc private func toggleInfoPanel() {
        guard hasDisplayableContent || geometryPresentation != nil else { return }
        let shouldOpen = !infoPanel.isExpanded
        if shouldOpen { refreshInfoPanel(forOpening: true) }
        infoPanel.setExpanded(shouldOpen)
        layoutSubtreeIfNeeded()
        announcer.layoutChanged(from: self)
    }

    func refreshInfoPanel(forOpening: Bool = false) {
        guard stateContent == nil, hasDisplayableContent || geometryPresentation != nil else {
            clearInfoPanel()
            return
        }
        guard forOpening || infoPanel.isExpanded else { return }
        let commands = commandAvailability.commands
        let lines = PreviewInfoPanelCopy.lines(providerName: providerName,
            concealedCount: safePresentation?.redactionCount ?? 0, commands: commands, locale: presentationLocale)
        infoPanel.display(lines: lines, commands: commands, palette: currentPalette())
    }

    func clearInfoPanel() {
        // A new request/state must not retain focus in a now-hidden information scroll view.
        if let focused = window?.firstResponder as? NSView, focused.isDescendant(of: infoPanel) {
            window?.makeFirstResponder(nil)
        }
        infoPanel.clear()
    }
}

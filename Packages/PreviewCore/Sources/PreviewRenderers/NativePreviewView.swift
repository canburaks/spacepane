import AppKit
import PreviewContracts

/// Selectable native text is shared by the companion and the Finder-hosted controller.
@MainActor
public final class NativePreviewView: NSView {
    /// Measurement is an explicit composition choice; ordinary previews create no stage intervals.
    private var stageObserver: PreviewStageObserver?

    /// Remote Quick Look hosts own visibility because their windows can report occluded while displayed.
    public enum ResourceVisibility: Sendable { case window, hostManaged }

    public var resourceVisibility: ResourceVisibility = .window {
        didSet {
            if resourceVisibility != oldValue { suspendResources() }
        }
    }

    // Keep renderer creation lazy and owned by this preview instance.
    var geometryViewFactory: @MainActor () -> NativeGeometryPreviewView = {
        NativeGeometryPreviewView(frame: .zero)
    }

    // Members without `private` are shared with the reading tools in `Interaction/` and with tests.
    private let headerView = PreviewHeaderView(frame: .zero)
    /// Named controls stay available to the facade's reading commands and tests across composition changes.
    var statusLabel: NSTextField { headerView.statusLabel }
    private(set) var displayedFacts: [String] = []
    var factsLabel: NSTextField { headerView.factsLabel }
    private var presentationFacts: PresentationFacts = .none
    var limitsLabel: NSTextField { headerView.limitsLabel }
    var infoBadge: PreviewInfoBadge { headerView.infoBadge }
    let infoPanel = PreviewInfoPanelView(frame: .zero)
    var infoPanelCollapsedHeight: NSLayoutConstraint?
    var infoPanelPreferredHeight: NSLayoutConstraint?
    var infoPanelIsOpen: Bool { infoPanel.isExpanded }
    var displayedInfoLines: [String] { infoPanel.lines }
    var displayedInfoCommands: [PreviewCommand] { infoPanel.commands }
    var infoPanelView: NSView { infoPanel }

    var chip: PreviewChip { headerView.chip }
    var modeControl: NSSegmentedControl { headerView.modeControl }
    var modePullDown: NSPopUpButton { headerView.modePullDown }
    var visibleModeControl: NSControl? { headerView.visibleModeControl }
    var headerGuide: NSLayoutGuide { headerView.headerGuide }
    /// Every state that has no content: loading, empty, unavailable, disabled and the two settings states.
    let stateView = NativeStateView(frame: .zero)
    /// The area every content view fills, between the chrome and the limits slot.
    let contentGuide = NSLayoutGuide()
    /// Typed findings and the Copy Concealed Text action; collapses when empty.
    let findingsBanner = NativeFindingsBanner(frame: .zero)
    private var findingsExpandedHeightConstraint: NSLayoutConstraint?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var concealedTextPasteboard = NSPasteboard.general
    /// Reports actual write success; tests replace it without touching the user's clipboard.
    var plainTextCopyWriter: (String, NSPasteboard) -> Bool = { text, pasteboard in
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    private let textContent = PreviewTextContentView(frame: .zero)
    /// The Contents list beside the Rendered text of a wide pane (decision 027, Q-74); zero wide while hidden.
    private let contentsRail = MarkupContentsRail(frame: .zero)
    var scrollView: NSScrollView { textContent.scrollView }
    private let midiContainer = NSView()
    private let midiView = NativeMIDIPreviewView(frame: .zero)
    private var midiHeightConstraint: NSLayoutConstraint?
    let outlineView = NativeOutlinePreviewView(frame: .zero)
    private let tableView = NativeTablePreviewView(frame: .zero)
    /// Lazily created views for derived modes registered in `SafeModeViewRegistry`.
    private var modeViews: [NativePreviewMode: any SafeModeContentView] = [:]
    private var geometryView: NativeGeometryPreviewView?
    private(set) var geometryPresentation: GeometryPresentation?
    private var resourcesAreActive = true
    private(set) var safePresentation: TextPresentation?
    private var modes: SafePreviewModes?
    private var mode = NativePreviewMode.source
    /// The modes the mode control lists, in segment order; `[.source]` while nothing is displayed.
    private(set) var displayedModes: [NativePreviewMode] = [.source]
    private var syntaxStyle = PreviewSyntaxStyle()
    private(set) var presentationLocale = Locale.current
    var textView: PreviewTextView { textContent.textView }
    var lineNumberGutter: LogicalLineNumberGutter { textContent.lineNumberGutter }
    private(set) var hasDisplayableContent = false
    private(set) var typography = PreviewTypography()
    private var theme = PreviewTheme.system
    /// Every notice of the displayed presentation in the order its family produced them, as one string; the notes
    /// and the limits slot each show their own kinds of it.
    private var noticesText = ""
    private var statusText = ""
    private var limitsText = ""
    /// The provenance notes of the displayed content. They are drawn in the information panel, not the status line.
    var provenanceLines: [String] = []
    /// The page column's "Page n of m" position (Q-76), shown in the limits slot while Pages is the mode.
    private var positionLimitText = ""
    private var displayedLimits: String {
        [limitsText, positionLimitText].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    /// Whether the font the reader asked for was replaced, which adds a hint to the notes.
    private var showsTypographyHint = false
    /// The state on screen (or about to be, for a loading state still inside its grace period); nil while a preview
    /// is displayed.
    private(set) var stateContent: NativeStateContent?
    /// The semantic hierarchy last published to accessibility, independent of text reloads or appearance. A
    /// pending loading state does not replace it until revealed; a quick replacement therefore stays quiet.
    private enum AccessibilityLayout: Equatable {
        case presentation(mode: NativePreviewMode, availableModes: [NativePreviewMode])
        case geometry
        case state(NativeStateContent)
    }
    private var publishedAccessibilityLayout: AccessibilityLayout?
    private var isApplyingStyle = false
    private weak var observedWindow: NSWindow?
    let accessoryBar = PreviewAccessoryBar()
    var accessoryHeightConstraint: NSLayoutConstraint?
    var goToLineIsOpen = false
    /// Temporary zoom for this preview only: never saved, reset by a new request.
    var zoom = PreviewZoom()
    /// The "Copied" confirmation on screen and the pending end of its life; see `reportCopy`.
    var copyChipText: String?
    var copyChipTimer: ChromeScheduledAction?
    /// How much room the host gives this preview, decided from this view's own width.
    private(set) var density = PreviewChrome.Density.regular
    /// A host that must not follow its width (the Theme page's sample) fixes the density here.
    var forcedDensity: PreviewChrome.Density? {
        didSet { if forcedDensity != oldValue { updateDensity() } }
    }
    /// Waits for the loading grace period and the chip's lifetime; tests substitute one they run by hand.
    var chromeScheduler: any ChromeScheduler = TaskChromeScheduler() {
        didSet { stateView.scheduler = chromeScheduler }
    }

    /// Names the app that made the preview in the info badge's tooltip ("Preview by …"). Hosts pass the
    /// configured display name; nil, the default, leaves only the read-only caption, as in the Theme page's sample.
    public var providerName: String? {
        didSet { if providerName != oldValue { applyStyling() } }
    }
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general {
        didSet {
            for view in [textView, outlineView, tableView, contentsRail] as [NSView] {
                (view as? any PreviewSafeCopying)?.pasteboard = pasteboard
            }
            for view in modeViews.values {
                (view as? any PreviewSafeCopying)?.pasteboard = pasteboard
            }
        }
    }
    /// The one owner of what this preview says aloud (Go to Line, copy, filter counts, states).
    let announcer = PreviewAnnouncer()
    /// Receives spoken confirmations in place of speaking them; tests substitute a recorder. It is the announcer's
    /// handler, so one assignment replaces every announcement this preview makes.
    var announcementHandler: ((String) -> Void)? {
        get { announcer.handler }
        set { announcer.handler = newValue }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        // Behind the content and state views, with the facade's full bounds and no chrome background.
        addSubview(headerView)
        headerView.onSelectMode = { [weak self] mode in self?.selectPreviewMode(mode) }
        textView.delegate = self
        textContent.performCodeBlockCopy = { [weak self] target in self?.copyCodeBlock(target) ?? false }
        adoptPreviewServices(textView)
        textContent.onGutterWidthChange = { [weak self] in
            self?.needsLayout = true
            self?.layoutSubtreeIfNeeded()
        }
        stateView.translatesAutoresizingMaskIntoConstraints = false
        textContent.translatesAutoresizingMaskIntoConstraints = false
        findingsBanner.translatesAutoresizingMaskIntoConstraints = false
        findingsBanner.onCopyConcealedText = { [weak self] in self?.copyConcealedText() }
        findingsBanner.onCopyFindingsReport = { [weak self] in self?.copyFindingsReport() }
        addSubview(findingsBanner)
        addSubview(textContent)
        outlineView.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        midiContainer.translatesAutoresizingMaskIntoConstraints = false
        midiView.translatesAutoresizingMaskIntoConstraints = false
        midiContainer.addSubview(midiView)
        midiContainer.isHidden = true
        let midiHeight = midiContainer.heightAnchor.constraint(equalToConstant: 0)
        midiHeightConstraint = midiHeight
        outlineView.isHidden = true
        tableView.isHidden = true
        addSubview(outlineView)
        addSubview(tableView)
        addSubview(midiContainer)
        accessoryBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessoryBar)
        let accessoryHeight = accessoryBar.heightAnchor.constraint(equalToConstant: 0)
        accessoryHeightConstraint = accessoryHeight
        stateView.scheduler = chromeScheduler
        stateView.onReveal = { [weak self] content in self?.stateRevealed(content) }
        addSubview(stateView)
        wireInteractionBars()
        adoptPreviewServices(outlineView)
        adoptPreviewServices(tableView)
        adoptPreviewServices(midiView)
        addLayoutGuide(contentGuide)
        headerView.installLayout(in: self, contentGuide: contentGuide)
        installInfoPanel()
        contentsRail.install(in: self, top: contentGuide.topAnchor, bottom: contentGuide.bottomAnchor)
        contentsRail.viewport = { [weak self] in self?.contentsViewport() }
        contentsRail.onReveal = { [weak self] range in self?.revealHeading(range) }
        textContent.onViewportChange = { [weak self] in self?.contentsRail.viewportChanged() }
        adoptPreviewServices(contentsRail)
        let safeArea = safeAreaLayoutGuide
        findingsExpandedHeightConstraint = findingsBanner.heightAnchor.constraint(
            lessThanOrEqualTo: safeArea.heightAnchor, multiplier: PreviewChrome.findingsMaximumFraction)
        findingsBanner.onExpansionChanged = { [weak self] expanded in
            self?.findingsExpandedHeightConstraint?.isActive = expanded
            self?.needsLayout = true
        }
        findingsBanner.onDisclosureActivated = { [weak self] in
            guard let self else { return }
            self.layoutSubtreeIfNeeded()
            self.announcer.layoutChanged(from: self)
        }
        NSLayoutConstraint.activate([
            findingsBanner.leadingAnchor.constraint(equalTo: leadingAnchor),
            findingsBanner.trailingAnchor.constraint(equalTo: trailingAnchor),
            findingsBanner.topAnchor.constraint(equalTo: infoPanel.bottomAnchor),
            midiContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            midiContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            midiContainer.topAnchor.constraint(equalTo: findingsBanner.bottomAnchor),
            midiHeight,
            midiView.leadingAnchor.constraint(equalTo: midiContainer.leadingAnchor),
            midiView.trailingAnchor.constraint(equalTo: midiContainer.trailingAnchor),
            midiView.topAnchor.constraint(equalTo: midiContainer.topAnchor),
            midiView.heightAnchor.constraint(equalToConstant: PreviewChrome.midiStripHeight),
            accessoryBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            accessoryBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            accessoryBar.topAnchor.constraint(equalTo: midiContainer.bottomAnchor, constant: PreviewChrome.gap),
            accessoryHeight,
            contentGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentGuide.topAnchor.constraint(equalTo: accessoryBar.bottomAnchor),
            textContent.leadingAnchor.constraint(equalTo: contentsRail.trailingAnchor),
            textContent.trailingAnchor.constraint(equalTo: trailingAnchor),
            textContent.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            outlineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outlineView.trailingAnchor.constraint(equalTo: trailingAnchor),
            outlineView.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            outlineView.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            textContent.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stateView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    public required init?(coder: NSCoder) { nil }

    /// Adds optional measurement without changing the standard AppKit initializer or content behavior.
    public convenience init(frame frameRect: NSRect, stageObserver: PreviewStageObserver?) {
        self.init(frame: frameRect)
        self.stageObserver = stageObserver
        textContent.stageObserver = stageObserver
    }

    /// Whether the data profile of the current presentation has been computed; tests observe laziness.
    var dataProfileIsComputed: Bool { modes?.profile?.isComputed ?? false }

    public func stopPlayback() { suspendResources() }

    public func suspendResources() {
        resourcesAreActive = false
        textContent.invalidateCodeBlockCopyTargets()
        textContent.setCodeBlockCopyControlsActive(false)
        midiView.stopPlayback()
        geometryView?.suspend()
        // A hidden preview keeps no confirmation: its timer is cancelled and the chip falls back to the zoom level.
        cancelCopyChip()
        refreshChip()
    }

    public func resumeResources() {
        resourcesAreActive = true
        textContent.setCodeBlockCopyControlsActive(true)
        if canRenderGeometry { geometryView?.resume() }
    }

    private var canRenderGeometry: Bool {
        guard resourcesAreActive, geometryPresentation != nil,
              !isHiddenOrHasHiddenAncestor, let window else { return false }
        switch resourceVisibility {
        case .window: return window.occlusionState.contains(.visible)
        case .hostManaged: return true
        }
    }

    /// A preview is on its way. The loading state draws nothing for `PreviewChrome.spinnerDelay`, and nothing at all
    /// when the preview arrives first.
    public func showLoading() {
        showState(NativeStateContent.content(for: .loading, locale: presentationLocale))
    }

    /// Loading with the appearance and language the preview will use, so the state already matches what follows it
    /// (a pane that is created while its first request is still running has no other way to learn them).
    func showLoading(typography: PreviewTypography, theme: PreviewTheme, syntaxStyle: PreviewSyntaxStyle, locale: Locale) {
        self.typography = typography
        self.theme = theme
        self.syntaxStyle = syntaxStyle
        presentationLocale = locale
        showLoading()
    }

    public func showSettingsUnavailable() {
        showState(NativeStateContent.content(for: .settingsUnavailable, locale: presentationLocale))
    }

    public func showSettingsConfigurationUnavailable() {
        showState(NativeStateContent.content(for: .configurationUnavailable, locale: presentationLocale))
    }

    /// The result keeps family-specific limits attached to the outcome, including failure states.
    public func display(_ result: PreviewResult, typography: PreviewTypography = .init(),
                        theme: PreviewTheme = .system, syntaxStyle: PreviewSyntaxStyle = .init(), locale: Locale = .current,
                        resetsContentState: Bool = false) {
        display(result.outcome, typography: typography, theme: theme, syntaxStyle: syntaxStyle, locale: locale,
                resetsContentState: resetsContentState, limits: result.effectiveBudget)
    }

    public func display(_ outcome: PreviewOutcome, typography: PreviewTypography = .init(),
                        theme: PreviewTheme = .system, syntaxStyle: PreviewSyntaxStyle = .init(), locale: Locale = .current,
                        resetsContentState: Bool = false, limits: PreviewBudget? = nil) {
        // Every early return has already installed its final state or content view. Never notify while clearing
        // the previous hierarchy, and use the published mode because a user action updates `mode` before display.
        defer { publishAccessibilityLayout() }
        self.typography = typography
        self.theme = theme
        self.syntaxStyle = syntaxStyle
        let localeChanged = self.presentationLocale != locale
        self.presentationLocale = locale
        stateView.locale = locale
        // Density is decided from this view's own width before anything is laid out, so it never adds a pass.
        updateDensity()
        // A new request starts from the saved size with no filter or Go to Line bar; a reload of the same
        // preview (resetsContentState false) keeps them.
        if resetsContentState {
            resetInteractionState()
            findingsBanner.collapseDetails()
            clearInfoPanel()
        }
        // An outcome with nothing to show becomes a state; the state view replaces every content view.
        if let state = PreviewStatePresenter.state(for: outcome, limits: limits, locale: locale) {
            showState(state.content, announces: state.announces)
            return
        }
        leaveState()
        if case .geometryReady(let presentation) = outcome {
            displayGeometry(presentation, resetsCamera: resetsContentState)
            return
        }
        guard case .ready(let presentation) = outcome else { return }
        geometryPresentation = nil
        geometryView?.clear()
        geometryView?.isHidden = true
        textContent.prepareTextAccessibility()
        // Swift String equality folds canonically equivalent Unicode spellings.
        // Safe source and derived modes must retain the exact supplied characters.
        let presentationChanged = resetsContentState || safePresentation != presentation
            || safePresentation?.text.utf8.elementsEqual(presentation.text.utf8) != true
        // Under one request, new content for the same format (the file changed on disk) keeps the reader's
        // selection and scroll position where they still exist, instead of jumping to the top.
        let keepsReadingPosition = !resetsContentState && presentationChanged
            && safePresentation?.formatID == presentation.formatID
        if resetsContentState { outlineView.clear(); tableView.clear() }
        if presentationChanged || localeChanged {
            // Revisions change for every replacement, even when its rendered body and metadata are identical.
            textContent.invalidateCodeBlockCopyTargets()
            let interval = stageObserver?.begin(.modes)
            modes = SafePreviewModes(presentation, locale: locale)
            // Offered modes are the derived capability count. Inspecting availability keeps Profile lazy, and
            // the nil-observer path does not calculate this extra count or create a timing interval.
            if let interval { interval.finish(count: modes?.available.count ?? 0) }
            if resetsContentState || safePresentation?.formatID != presentation.formatID {
                mode = modes?.initialMode(for: presentation.formatID) ?? .source
            }
        }
        if presentationChanged, let modes {
            presentationFacts = PresentationFactsProvider.facts(for: presentation, modes: modes)
        }
        if safePresentation?.midi != presentation.midi || resetsContentState {
            midiView.clear()
            if let midi = presentation.midi { midiView.show(midi) }
        }
        midiContainer.isHidden = presentation.midi == nil
        midiHeightConstraint?.constant = presentation.midi == nil ? 0 : PreviewChrome.midiStripHeight
        safePresentation = presentation
        configureModes()
        // Rendered and Invisibles show derived text; Source is always exactly the safe text.
        let derivedInvisibles = mode == .invisibles ? modes?.invisibles : nil
        let content = mode == .rendered ? modes?.markdown?.text ?? presentation.text : derivedInvisibles?.text ?? presentation.text
        let newSyntax: TextSyntax = mode == .rendered ? .plain : presentation.syntax
        // Only notices about this document; "Read-only preview" moved into the info badge. The privacy notice
        // stays visible because it changes what selection and copying return. Limits (what is not shown) go to
        // the slot at the bottom; everything else sits below the mode control.
        let notices = PreviewStatePresenter.notices(
            for: presentation, mode: mode, hasStructureFallback: modes?.hasStructureFallback == true,
            markupNotices: MarkupRendering.notices(for: presentation, document: modes?.markdown, mode: mode, locale: locale),
            profileNotices: mode == .profile ? modes?.profile?.value.statusLines ?? [] : [],
            hasRecords: modes?.records != nil,
            modeLimitNotices: modes.map {
                ModePresentationNotices.notices(for: presentation, modes: $0, mode: mode, locale: locale)
            } ?? [], locale: locale)
        noticesText = notices.map(\.text).joined(separator: "\n")
        let slots = PresentationNoticeSlots(notices)
        statusText = slots.status.joined(separator: "\n")
        limitsText = slots.limits.joined(separator: "\n")
        provenanceLines = slots.provenance
        if mode != .pages { positionLimitText = "" }
        if presentationChanged { clearModeViews() }
        let customView = modeView(for: mode)
        for view in modeViews.values where view !== customView { view.isHidden = true }
        customView?.isHidden = false
        let showsCustom = customView != nil
        let showsTable = !showsCustom && modes?.displayedTable(for: mode) != nil
        let showsOutline = !showsCustom && !showsTable && modes?.nodes(for: mode) != nil
        tableView.isHidden = !showsTable
        outlineView.isHidden = !showsOutline
        textContent.setContentHidden(showsOutline || showsTable || showsCustom)
        // Rendered prose has no source-line navigation; the filter belongs to outline modes.
        if mode == .rendered || showsOutline || showsTable || showsCustom { goToLineIsOpen = false }
        updateAccessoryBar(showsOutline: showsOutline)
        if showsOutline || showsTable || showsCustom {
            // Keep only the already-safe presentation as the source of truth. Hidden
            // text need not be materialized or restyled until Source is selected.
            if presentationChanged {
                textContent.clear(resetsReadingPosition: true)
            }
            hasDisplayableContent = true
            applyStyling()
            return
        }
        let replacement = textContent.replaceContent(
            content, syntax: newSyntax, language: mode == .rendered ? nil : safePresentation?.sourceLanguage,
            decorations: mode == .rendered ? modes?.markdown?.decorations ?? [] : [],
            codeBlocks: mode == .rendered ? modes?.markdown?.codeBlocks ?? [] : [],
            markerRanges: derivedInvisibles?.markerRanges ?? [], hasDisplayableContent: hasDisplayableContent,
            keepsReadingPosition: keepsReadingPosition, resetsContentState: resetsContentState)
        hasDisplayableContent = true
        applyStyling()
        textContent.finishReplacement(replacement)
        contentsRail.viewportChanged()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow { NotificationCenter.default.removeObserver(self, name: nil, object: observedWindow) }
        observedWindow = window
        guard let window else { midiView.stopPlayback(); geometryView?.suspend(); return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosing),
                                               name: NSWindow.willCloseNotification, object: window)
        if canRenderGeometry { geometryView?.resume() }
    }
    @objc nonisolated private func windowVisibilityChanged() {
        Task { @MainActor [weak self] in
            guard let self, self.resourceVisibility == .window, let window = self.window else { return }
            if window.occlusionState.contains(.visible) {
                if self.canRenderGeometry { self.geometryView?.resume() }
            } else { self.midiView.stopPlayback(); self.geometryView?.suspend() }
        }
    }
    @objc nonisolated private func windowClosing() {
        Task { @MainActor [weak self] in self?.stopPlayback() }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyling()
    }

    public override func layout() {
        // Density follows this view's own width and is settled before the text is laid out.
        updateDensity()
        contentsRail.hostWidthChanged(bounds.width)
        super.layout()
        textContent.configureDocumentSize()
    }

    /// VoiceOver reads the header, the findings, the mode control, the bars, the content and the limits in that
    /// order, however the views were added. Keep the system's actual elements, including the cells AppKit exposes
    /// for labels and segmented controls, ranked by their owning view in `navigationOrderViews`.
    public override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        let order = navigationOrderViews
        let children = (accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityElementProtocol }
        func rank(of child: any NSAccessibilityElementProtocol) -> Int {
            let view: NSView?
            if let cell = child as? NSCell {
                if let index = order.firstIndex(where: { ($0 as? NSControl)?.cell === cell }) { return index }
                view = cell.controlView
            } else {
                view = child as? NSView
            }
            guard let view else { return order.count }
            return order.firstIndex { view === $0 || view.isDescendant(of: $0) } ?? order.count
        }
        let ranked = children.enumerated()
            .map { (rank: rank(of: $0.element), index: $0.offset, element: $0.element) }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
        return ranked.map(\.element)
    }

    /// The mode chords, Go to Line, Copy All, find, and zoom. Other events, and these while focus is elsewhere in
    /// the window, continue to the system and the other views.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard ownsKeyboardFocus, let command = PreviewCommand(event: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if let number = command.modeNumber, selectMode(number: number) { return true }
        if let shortcut = PreviewShortcut(command: command), handleShortcut(shortcut) { return true }
        return super.performKeyEquivalent(with: event)
    }

    // Workspace notifications may arrive outside the actor. Only the UI update crosses to main.
    @objc nonisolated private func accessibilityOptionsChanged() {
        Task { @MainActor [weak self] in self?.applyStyling() }
    }

    /// Empties every content view and every piece of per-preview state; a state, or the next presentation, follows.
    /// The text view is hidden too, so nothing empty and focusable stands behind a state.
    private func clearContent() {
        clearInfoPanel()
        findingsBanner.clear()
        geometryPresentation = nil
        geometryView?.clear()
        geometryView?.isHidden = true
        safePresentation = nil; modes = nil; mode = .source
        presentationFacts = .none
        configureModes(); outlineView.clear(); outlineView.isHidden = true; tableView.clear(); tableView.isHidden = true
        clearModeViews()
        textContent.setContentHidden(true)
        midiView.clear(); midiContainer.isHidden = true; midiHeightConstraint?.constant = 0
        textContent.clear()
        hasDisplayableContent = false
        noticesText = ""
        statusText = ""
        limitsText = ""
        provenanceLines = []
        positionLimitText = ""
        resetInteractionState()
    }

    /// Shows a state in place of any content. The same state again only restyles; a state that is not a loading
    /// state is announced once (a loading state is announced when it appears, after its grace period).
    private func showState(_ content: NativeStateContent, announces: Bool = true) {
        let isRepeat = stateContent == content
        if !isRepeat {
            clearContent()
            stateContent = content
        }
        stateView.locale = presentationLocale
        applyStyling()
        guard !isRepeat else { return }
        if content.kind == .loading {
            stateView.showLoading(generation: UUID(), after: PreviewChrome.spinnerDelay)
        } else {
            stateView.show(content, palette: currentPalette())
            publishAccessibilityLayout()
            if announces { announceState(content) }
        }
    }

    /// Leaves a state when a preview arrives: a loading state that has not appeared never will.
    private func leaveState() {
        guard stateContent != nil else { return }
        stateContent = nil
        stateView.clear()
    }

    /// A loading state became visible: the first time a reader needs to hear that something is happening.
    private func stateRevealed(_ content: NativeStateContent) {
        publishAccessibilityLayout()
        announceState(content)
    }

    /// Publish only meaningful, visible changes. The snapshot contains modes and app-authored state copy, never
    /// document text, a filename or source values. Store it before posting so a callback cannot publish it twice.
    private func publishAccessibilityLayout() {
        let layout: AccessibilityLayout
        if let stateContent {
            guard stateView.isRevealed && !stateView.isHidden else { return }
            layout = .state(stateContent)
        } else if geometryPresentation != nil {
            layout = .geometry
        } else {
            guard safePresentation != nil && hasDisplayableContent else { return }
            layout = .presentation(mode: mode, availableModes: displayedModes)
        }
        guard publishedAccessibilityLayout != layout else { return }
        publishedAccessibilityLayout = layout
        announcer.layoutChanged(from: self)
    }

    private func announceState(_ content: NativeStateContent) {
        announce([content.title, content.body].filter { !$0.isEmpty }.joined(separator: ". "))
    }

    /// The palette the preview draws with now. A forced light or dark theme sets this view's appearance first.
    func currentPalette() -> NativeTextPalette {
        let requestedAppearance: NSAppearance?
        switch theme {
        case .light: requestedAppearance = NSAppearance(named: .aqua)
        case .dark: requestedAppearance = NSAppearance(named: .darkAqua)
        case .system, .highContrast: requestedAppearance = nil
        }
        if appearance?.name != requestedAppearance?.name { appearance = requestedAppearance }
        return NativeTextPalette(
            theme: theme,
            isDark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            style: syntaxStyle
        )
    }

    func applyStyling() {
        guard !isApplyingStyle else { return }
        isApplyingStyle = true
        defer { isApplyingStyle = false; refreshInfoPanel() }
        // Every renderer draws with the saved typography plus this preview's temporary zoom.
        let typography = effectiveTypography
        let palette = currentPalette()
        syncContentsRail(typography: typography, palette: palette)
        accessoryBar.apply(palette: palette)
        midiView.apply(palette: palette)
        headerView.apply(palette: palette)
        refreshFacts()
        stateView.apply(palette: palette)
        layer?.backgroundColor = palette.background.cgColor
        refreshChip()
        if stateContent != nil {
            // A state replaces the whole preview: no notes, badge, findings, bars or content.
            showsTypographyHint = false
            headerView.display(.init(notes: "", limits: "", providerName: providerName,
                                     showsInfoBadge: false, locale: presentationLocale), palette: palette)
            textContent.hideLineNumbers()
            return
        }
        if let geometryPresentation {
            showsTypographyHint = false
            // The CAD note says what the document metadata omits: a provenance note, so it is drawn in the panel.
            provenanceLines = [PreviewStrings.text(.cadPrivacyNotice)]
            headerView.display(.init(notes: "", limits: "", providerName: providerName, showsInfoBadge: true,
                                     locale: presentationLocale), palette: palette)
            // The viewport follows the chosen color schemes like every text view.
            geometryView?.syntaxStyle = syntaxStyle
            geometryView?.show(geometryPresentation, theme: theme, locale: presentationLocale)
            return
        }
        let resolved = NativeTextTypography(typography, syntaxStyle: syntaxStyle)
        showsTypographyHint = resolved.didUseFallback
        let notes = resolved.didUseFallback
            ? [statusText, PreviewStrings.text(.typographyFallbackHint)].filter { !$0.isEmpty }.joined(separator: "\n")
            : statusText
        // The badge describes a shown preview only: loading, unavailable and disabled states name nobody.
        let limitsShown = displayedLimits
        headerView.display(.init(notes: notes, limits: limitsShown, providerName: providerName,
                                 showsInfoBadge: hasDisplayableContent, locale: presentationLocale), palette: palette)
        if let safePresentation {
            findingsBanner.display(safePresentation.findings,
                                   concealedValueCount: safePresentation.redactionCount,
                                   offersConcealedCopy: safePresentation.redactionCount > 0
                                       && (mode == .rendered || mode == .invisibles),
                                   palette: palette, locale: presentationLocale)
        } else { findingsBanner.clear() }
        if let modes, let view = modeViews[mode], !view.isHidden {
            view.display(modes, mode: mode, style: SafeModeStyle(typography: typography, palette: palette,
                                                                 syntaxStyle: syntaxStyle, locale: presentationLocale))
            // The page column reports its top page while it is displayed; the header drawn above is then stale.
            if displayedLimits != limitsShown {
                headerView.display(.init(notes: notes, limits: displayedLimits, providerName: providerName,
                                         showsInfoBadge: hasDisplayableContent, locale: presentationLocale), palette: palette)
            }
            textContent.hideLineNumbers()
            return
        }
        if let table = modes?.displayedTable(for: mode) {
            tableView.display(table, typography: typography, palette: palette, syntaxStyle: syntaxStyle, locale: presentationLocale)
            textContent.hideLineNumbers()
            return
        }
        if let nodes = modes?.nodes(for: mode) {
            outlineView.display(nodes, typography: typography, palette: palette, syntaxStyle: syntaxStyle,
                                locale: presentationLocale, rootsAreDocuments: mode == .records)
            textContent.hideLineNumbers()
            return
        }
        textContent.apply(typography: typography, resolved: resolved, palette: palette, syntaxStyle: syntaxStyle,
                          showsLineNumbers: outlineView.isHidden && tableView.isHidden
                              && typography.showsLineNumbers && hasDisplayableContent,
                          isRendered: mode == .rendered, locale: presentationLocale)
    }

    /// Density follows this view's own width, never the scroll view's, unless a host forces one.
    /// Native chrome and gutter geometry consume it before the text is measured.
    private func updateDensity() {
        let next = forcedDensity ?? PreviewChrome.density(forWidth: bounds.width, previous: density)
        if next != density {
            density = next
            headerView.setDensity(next)
            refreshFacts()
            textContent.setDensity(next)
        }
    }

    /// The Contents rail follows what is shown: offered beside the Rendered text of a wide pane, hidden in every
    /// other case, including states, 3D views and a host-fixed density (the Theme page's sample).
    private func syncContentsRail(typography: PreviewTypography, palette: NativeTextPalette) {
        contentsRail.sync(
            headings: modes?.markdown?.headings ?? [], mode: mode, hostWidth: bounds.width,
            isEligible: stateContent == nil && geometryPresentation == nil && forcedDensity == nil
                && hasDisplayableContent,
            style: SafeModeStyle(typography: typography, palette: palette, syntaxStyle: syntaxStyle,
                                 locale: presentationLocale))
    }

    private func contentsViewport() -> ContentsViewport? {
        guard mode == .rendered, !textContent.isHidden else { return nil }
        return ContentsVisibleRange.viewport(of: textView)
    }

    /// A heading the reader chose in the rail: selects its title and scrolls it into view. Focus stays in the rail.
    private func revealHeading(_ range: NSRange) {
        guard mode == .rendered, !textView.isHidden, range.location >= 0,
              NSMaxRange(range) <= (textView.string as NSString).length else { return }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    private func refreshFacts() {
        displayedFacts = PresentationFactsFormatter.lines(for: presentationFacts, compact: density == .compact,
            locale: presentationLocale)
        headerView.displayFacts(displayedFacts)
    }

    private func configureModes() {
        let available = modes?.available ?? [.source]
        if !available.contains(mode) { mode = .source }
        if modes == nil { headerView.clearModes() }
        else { headerView.displayModes(available, selected: mode, density: density) }
        displayedModes = available
    }

    /// Rendered and Invisibles offer the whole concealed text. Source bytes are never read.
    func copyConcealedText() {
        guard mode == .rendered || mode == .invisibles,
              let text = safePresentation?.text, safePresentation?.redactionCount ?? 0 > 0 else { return }
        let copy = TagCopySanitizer(safeDisplayedText: text,
            safetyLensFoundTags: safetyLensFoundTags).wholeText()
        guard plainTextCopyWriter(copy.text, concealedTextPasteboard) else { return }
        reportCopy(.concealedSource.removingTags(copy.removedTagScalarCount))
    }

    private func selectPreviewMode(_ target: NativePreviewMode) {
        guard let presentation = safePresentation, modes?.available.contains(target) == true else { return }
        mode = target
        // Each mode lists different rows or text, so a filter or Go to Line entry no longer applies.
        goToLineIsOpen = false
        clearFilter()
        display(.ready(presentation), typography: typography, theme: theme, syntaxStyle: syntaxStyle,
                locale: presentationLocale)
    }

    /// The mode chord: shows the nth view of the mode control (Option-Command-1 to -9). Returns false when there is
    /// no such view or the control is hidden, so the key stays free for others. The switch says the new view's name
    /// aloud (the keyboard changed it, not the focused control), and focus that was inside the preview follows the
    /// content, so the reader lands in what they asked for instead of in a view that is now hidden.
    func selectMode(number: Int) -> Bool {
        guard commandAvailability.contains(.mode(number)),
              let target = PreviewCommand.mode(number).targetMode(among: displayedModes) else { return false }
        let focusWasInside = (window?.firstResponder as? NSView)?.isDescendant(of: self) == true
        if target != mode {
            modeControl.selectedSegment = number - 1
            selectPreviewMode(target)
            announce(PreviewStrings.text(target.title))
        }
        if focusWasInside { moveFocusToContent() }
        return true
    }

    /// Puts keyboard focus on what the current mode shows: the text, the outline, the table, or a registered view
    /// when it takes focus. A view that cannot take focus leaves it where it is.
    func moveFocusToContent() {
        let target: NSView?
        if !textView.isHidden {
            target = textView
        } else if !outlineView.isHidden {
            target = outlineView.documentView
        } else if !tableView.isHidden {
            target = tableView.tableView
        } else {
            // A mode view names the view that takes keyboard focus (a scroll view's document, for pages).
            let content = contentView(for: mode)
            target = (content as? any SafeModeContentView)?.keyboardFocusTarget ?? content
        }
        if let target, target.acceptsFirstResponder { window?.makeFirstResponder(target) }
    }

    /// Creates the registered view for a derived mode once, pinned where the outline and table views sit.
    private func modeView(for mode: NativePreviewMode) -> (any SafeModeContentView)? {
        guard modes?.available.contains(mode) == true else { return nil }
        if let existing = modeViews[mode] { return existing }
        guard let view = SafeModeViewRegistry.makeView(for: mode) else { return nil }
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: contentGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor)
        ])
        view.navigate = { [weak self] target, range in self?.navigate(to: target, selecting: range) }
        (view as? NativeImagePagesView)?.onPositionChange = { [weak self] notice in self?.showPositionLimit(notice) }
        adoptPreviewServices(view)
        modeViews[mode] = view
        return view
    }

    private func clearModeViews() {
        // Reset first: a cleared page column reports nil, which must find nothing to change.
        positionLimitText = ""
        for view in modeViews.values { view.clear(); view.isHidden = true }
    }

    /// The page column reports its top page; the limits slot shows it without any announcement (Q-76).
    private func showPositionLimit(_ notice: PresentationNotice?) {
        let text = mode == .pages ? (notice?.text ?? "") : ""
        guard text != positionLimitText else { return }
        positionLimitText = text
        // A column that reports while it is being restyled (a reused column showing its next document, or a new
        // locale) is read again by that same pass, which draws the header after the column; nothing is deferred.
        guard !isApplyingStyle else { return }
        applyStyling()
    }

    /// Switches to a text mode (Source or Rendered) and reveals a range of its safe text.
    private func navigate(to target: NativePreviewMode, selecting range: NSRange) {
        guard let presentation = safePresentation, modes?.available.contains(target) == true,
              target == .source || target == .rendered else { return }
        mode = target
        clearFilter()
        display(.ready(presentation), typography: typography, theme: theme, syntaxStyle: syntaxStyle,
                locale: presentationLocale)
        // A link, not the focused control, switched the mode, so nothing else says which mode is on screen.
        announce(PreviewStrings.text(target.title))
        guard !textView.isHidden, range.location >= 0, NSMaxRange(range) <= (textView.string as NSString).length else {
            moveFocusToContent()
            return
        }
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        moveFocusToContent()
    }

    private func displayGeometry(_ presentation: GeometryPresentation, resetsCamera: Bool) {
        findingsBanner.clear()
        safePresentation = nil; modes = nil; mode = .source
        resetInteractionState()
        configureModes()
        clearModeViews()
        outlineView.clear(); outlineView.isHidden = true; tableView.clear(); tableView.isHidden = true
        midiView.clear(); midiContainer.isHidden = true; midiHeightConstraint?.constant = 0
        textContent.clear()
        textContent.hideLineNumbers()
        textContent.setContentHidden(true)
        hasDisplayableContent = false
        if geometryView == nil {
            let view = geometryViewFactory()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: contentGuide.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentGuide.bottomAnchor)
            ])
            adoptPreviewServices(view)
            view.onCommandAvailabilityChanged = { [weak self] in self?.refreshInfoPanel() }
            geometryView = view
        }
        if geometryPresentation != presentation {
            presentationFacts = PresentationFactsProvider.facts(for: presentation)
        }
        geometryPresentation = presentation
        geometryView?.isHidden = false
        geometryView?.syntaxStyle = syntaxStyle
        geometryView?.show(presentation, theme: theme, locale: presentationLocale, resetsCamera: resetsCamera)
        applyStyling()
        if canRenderGeometry { geometryView?.resume() }
    }
}

// MARK: Test seams

/// Named, hierarchy-independent ways to read what the preview shows, so tests never depend on which container
/// holds a label or a control (decision 027, Q-30). Internal, like `dataProfileIsComputed`.
extension NativePreviewView {
    /// What the status area says, as one text: the notices, then the typography hint, then the zoom reminder, joined
    /// by newlines and empty when there is none. A state replaces all of it with its title and body. The notices
    /// include the limits, which sit in their own slot at the bottom, and the provenance notes, which the information
    /// panel draws. The zoom reminder is the chip's spoken text, so the text is the same wherever each part is drawn.
    var displayedStatus: String {
        var lines: [String]
        if let stateContent {
            lines = [stateContent.title, stateContent.body]
        } else if geometryPresentation != nil {
            lines = [statusLabel.stringValue]
        } else {
            lines = [noticesText]
            if showsTypographyHint { lines.append(PreviewStrings.text(.typographyFallbackHint)) }
            if let level = zoomChip { lines.append(level.spoken) }
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// A target for one explicit code body in the current reading document.
    func codeBlockCopyTarget(at characterIndex: Int) -> CodeBlockCopyTarget? {
        guard mode == .rendered, hasDisplayableContent, resourcesAreActive, !textContent.isHidden else { return nil }
        return textContent.codeBlockCopyTarget(at: characterIndex)
    }

    /// Keeps cached text/model ownership private while the shared copy service resolves an action.
    func currentCodeBlockRange(for target: CodeBlockCopyTarget) -> NSRange? {
        guard mode == .rendered, hasDisplayableContent, resourcesAreActive, !textContent.isHidden,
              let document = modes?.markdown,
              textView.string.utf16.elementsEqual(document.text.utf16) else { return nil }
        return textContent.currentCodeBlockRange(for: target)
    }

    /// The mode on screen.
    var selectedMode: NativePreviewMode { mode }

    /// The registered view that shows the current mode, when one is on screen; nil for the text, outline and table.
    var shownModeView: (any SafeModeContentView)? {
        guard let view = modeViews[mode], !view.isHidden else { return nil }
        return view
    }

    /// The view that shows `mode`, or nil when the preview does not offer it. Registered mode views exist only once
    /// they have been shown; asking never creates one and never computes a lazy model (Profile stays uncomputed).
    func contentView(for mode: NativePreviewMode) -> NSView? {
        guard displayedModes.contains(mode) else { return nil }
        if let view = modeViews[mode] { return view }
        switch mode {
        case .source, .rendered, .invisibles: return scrollView
        case .table, .profile: return tableView
        case .outline, .records, .summary, .cues: return outlineView
        default: return nil
        }
    }

    /// Actual installed surfaces used by command dispatch and the information panel.
    var showsTableMode: Bool { hasDisplayableContent && !tableView.isHidden }
    var geometrySupportsNavigation: Bool { geometryPresentation != nil && geometryView != nil && geometryView?.failure == nil }

    /// Reader order: header, information, findings, mode control, MIDI, bars, content and limits.
    /// Hidden views are left out.
    var navigationOrderViews: [NSView] {
        var views: [NSView] = [factsLabel, statusLabel, chip, infoBadge, infoPanel, findingsBanner]
        if let visibleModeControl { views.append(visibleModeControl) }
        views += [midiContainer, accessoryBar, lineNumberGutter, contentsRail, scrollView, outlineView, tableView]
        for view in modeViews.values { views.append(view) }
        if let geometryView { views.append(geometryView) }
        views.append(stateView)
        views.append(limitsLabel)
        return views.filter { !$0.isHidden }
    }
}

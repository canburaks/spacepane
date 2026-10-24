import AppKit
import PreviewContracts

/// The Diagram mode: a zoomable, pannable Core Graphics drawing of a `SafeDiagram`. It consumes
/// only the diagram parsed from concealed text, draws with the preview theme's colors and font,
/// and performs no file, network or link access. Zoom and pan persist across appearance changes
/// and reset when a different diagram is shown. A diagram that cannot be shown whole without its text falling
/// under the legibility floor (`DiagramFit`) is drawn at the floor, and a quiet note under the canvas says so.
@MainActor
final class NativeDiagramView: NSView, SafeModeContentView {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    let canvas = DiagramCanvasView(frame: .zero)
    /// The one-line note under the canvas: how the drawing was fitted. Hidden, and no taller than nothing, while
    /// the whole drawing is readable or the reader has zoomed or panned.
    let noteLabel = NSTextField(labelWithString: "")
    private var noteHeight: NSLayoutConstraint?
    private var noteColor = NSColor.textColor
    /// Layout cache: the parsed diagram measured with the current font and locale.
    private var sourceGeneration: UUID?
    private var cached: (environment: DiagramEnvironment, diagram: SafeDiagram)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.font = PreviewChrome.factsFont()
        noteLabel.isHidden = true
        addSubview(canvas)
        addSubview(noteLabel)
        let height = noteLabel.heightAnchor.constraint(equalToConstant: 0)
        noteHeight = height
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: noteLabel.topAnchor),
            noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewChrome.inset),
            noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewChrome.inset),
            noteLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            height
        ])
        canvas.onNoticeChange = { [weak self] _ in self?.refreshNote() }
    }

    required init?(coder: NSCoder) { nil }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        guard mode == .diagram, let parsed = modes.diagram else { clear(); return }
        let environment = DiagramEnvironment(font: Self.font(for: style), locale: style.locale)
        let diagram: SafeDiagram
        if sourceGeneration == parsed.generation, let cached, cached.environment == environment {
            diagram = cached.diagram
        } else {
            diagram = parsed.laidOut(with: environment) ?? parsed
            cached = (environment, diagram)
        }
        let isNew = sourceGeneration != parsed.generation
        sourceGeneration = parsed.generation
        let palette = Self.palette(for: style)
        layer?.backgroundColor = palette.background.cgColor
        noteColor = style.palette.muted
        canvas.show(diagram, palette: palette, font: environment.font, locale: style.locale, resetsView: isNew)
        refreshNote()
    }

    func clear() {
        sourceGeneration = nil
        cached = nil
        canvas.show(nil, palette: canvas.palette, font: canvas.font, locale: canvas.locale, resetsView: true)
        refreshNote()
    }

    /// The typed notices of what is on screen, for a host that shows them in its own limits slot. Empty while the
    /// whole drawing is readable. What the file holds (which of several fences is drawn) is not here but in
    /// `DrawnModeNotices`, because it does not depend on the size of the view.
    var presentationNotices: [PresentationNotice] {
        canvas.fitNotice.map { [$0.presentationNotice(locale: canvas.locale)] } ?? []
    }

    /// Shows how the drawing was fitted, or nothing. The note takes no height while it has nothing to say.
    private func refreshNote() {
        guard let notice = canvas.fitNotice else {
            noteLabel.stringValue = ""
            noteLabel.toolTip = nil
            noteLabel.isHidden = true
            noteHeight?.constant = 0
            return
        }
        let text = notice.text(locale: canvas.locale)
        noteLabel.stringValue = text
        noteLabel.toolTip = text
        noteLabel.textColor = noteColor
        noteLabel.isHidden = false
        noteHeight?.constant = noteLabel.intrinsicContentSize.height.rounded(.up) + PreviewChrome.gap
    }

    /// The preview font when one is chosen and installed; otherwise the system UI font.
    private static func font(for style: SafeModeStyle) -> DiagramFont {
        var name: String?
        if style.typography.fontFamily != nil {
            let resolved = NativeTextTypography(style.typography, syntaxStyle: style.syntaxStyle)
            if !resolved.didUseFallback { name = resolved.font.fontName }
        }
        return DiagramFont(name: name, size: CGFloat(style.typography.fontSize))
    }

    /// Diagram colors derive from the preview palette: its background, foreground and semantic
    /// roles, so every theme, High Contrast and Increase Contrast variant carries over.
    static func palette(for style: SafeModeStyle) -> DiagramPalette {
        func convert(_ color: NSColor) -> DiagramColor {
            let rgb = color.usingColorSpace(.sRGB) ?? color
            return DiagramColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent), alpha: 1)
        }
        let background = convert(style.palette.background)
        let foreground = convert(style.palette.foreground)
        let roles: [PreviewSyntaxRole] = [.key, .string, .number, .literal, .deletion, .comment]
        let accents = roles.map { convert(style.palette.color(for: $0, style: style.syntaxStyle)) }
        // The preview palettes use pure black or white text only for High Contrast and Increase Contrast.
        let highContrast = foreground.luminance < 0.01 || foreground.luminance > 0.99
        return DiagramPalette(background: background, foreground: foreground, accents: accents,
                              usesColor: style.syntaxStyle.usesColor, isHighContrast: highContrast)
    }
}

/// Draws the diagram and handles zoom, pan and keyboard focus.
@MainActor
final class DiagramCanvasView: NSView {
    static let minimumScale: CGFloat = 0.005
    static let maximumScale: CGFloat = 16
    private static let fitPadding: CGFloat = 8
    private static let keyboardStep: CGFloat = 48

    private(set) var diagram: SafeDiagram?
    private(set) var palette = DiagramPalette.standard(isDark: false)
    private(set) var font = DiagramFont.standard
    private(set) var locale = Locale.current
    /// A scene point `p` appears at `p * scale + offset` in this view's flipped coordinates.
    private(set) var scale: CGFloat = 1
    private(set) var offset = CGPoint.zero
    /// True until the user zooms or pans, so resizing keeps refitting the diagram.
    private(set) var fitsToView = true
    /// How the last fit came out: whole and natural, whole and smaller than natural, or held at the legibility floor.
    private(set) var fitOutcome = DiagramFit.Outcome.natural
    /// Called when the note about how the drawing is fitted changes, including when it goes away.
    var onNoticeChange: ((DiagramNotice?) -> Void)?
    private var reportedNotice: DiagramNotice?
    private var dragOrigin: NSPoint?
    private var cachedAccessibilityChildren: [NSAccessibilityElement]?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(rect: bounds).fill() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .exterior
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    // MARK: Content

    func show(_ diagram: SafeDiagram?, palette: DiagramPalette, font: DiagramFont, locale: Locale, resetsView: Bool) {
        if self.diagram != diagram || self.locale != locale {
            cachedAccessibilityChildren = nil
        }
        self.diagram = diagram
        self.palette = palette
        self.font = font
        self.locale = locale
        if resetsView { fitsToView = true }
        toolTip = diagram == nil ? nil : PreviewStrings.text(.diagramInteractionHelp)
        layer?.backgroundColor = palette.background.cgColor
        if fitsToView { zoomToFit() }
        reportNotice()
        NSAccessibility.post(element: self, notification: .layoutChanged)
        needsDisplay = true
    }

    /// The sentence about how the drawing was fitted: nil once the reader zooms or pans, and nil while the whole
    /// drawing is shown readable (natural, enlarged or shrunk but above the floor).
    var fitNotice: DiagramNotice? {
        guard diagram != nil, fitsToView, fitOutcome == .floored else { return nil }
        return .readable(scale: Double(scale))
    }

    private func reportNotice() {
        let notice = fitNotice
        // The wording is a whole percentage, so a live resize reports a change only when that number changes.
        guard Self.percent(of: notice) != Self.percent(of: reportedNotice) else { return }
        reportedNotice = notice
        onNoticeChange?(notice)
    }

    private static func percent(of notice: DiagramNotice?) -> Int? {
        guard case .readable(let scale)? = notice else { return nil }
        return Int((scale * 100).rounded())
    }

    override func layout() {
        super.layout()
        if fitsToView { zoomToFit() }
    }

    // MARK: Zoom and pan

    /// Fits the drawing to the view while its text stays above the legibility floor (`DiagramFit`). A drawing that
    /// cannot be shown whole at a readable scale is drawn at the floor from its leading top corner, and the rest
    /// is reached by panning.
    func zoomToFit() {
        fitsToView = true
        guard let diagram, bounds.width > 0, bounds.height > 0 else {
            fitOutcome = .natural
            needsDisplay = true
            reportNotice()
            return
        }
        let fit = DiagramFit.make(content: diagram.contentSize, bounds: bounds.size, padding: Self.fitPadding,
                                  font: font, minimumScale: Self.minimumScale, maximumScale: Self.maximumScale)
        scale = fit.scale
        offset = fit.offset
        fitOutcome = fit.outcome
        needsDisplay = true
        reportNotice()
    }

    func zoom(by factor: CGFloat, around anchor: CGPoint? = nil) {
        guard diagram != nil, factor.isFinite, factor > 0 else { return }
        let point = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let target = min(max(scale * factor, Self.minimumScale), Self.maximumScale)
        let applied = target / scale
        offset = CGPoint(x: point.x - (point.x - offset.x) * applied, y: point.y - (point.y - offset.y) * applied)
        scale = target
        fitsToView = false
        needsDisplay = true
        reportNotice()
    }

    func pan(by delta: CGPoint) {
        guard diagram != nil else { return }
        offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
        fitsToView = false
        needsDisplay = true
        reportNotice()
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(palette.background.cgColor)
        context.fill(dirtyRect)
        guard let diagram, scale > 0 else { return }
        context.saveGState()
        context.translateBy(x: offset.x, y: offset.y)
        context.scaleBy(x: scale, y: scale)
        let visible = CGRect(x: (dirtyRect.minX - offset.x) / scale, y: (dirtyRect.minY - offset.y) / scale,
                             width: dirtyRect.width / scale, height: dirtyRect.height / scale)
        DiagramDrawing.draw(diagram.scene, in: context, palette: palette, font: font, visibleRect: visible)
        context.restoreGState()
    }

    // MARK: Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { zoomToFit(); return }
        dragOrigin = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let current = convert(event.locationInWindow, from: nil)
        pan(by: CGPoint(x: current.x - origin.x, y: current.y - origin.y))
        dragOrigin = current
    }

    override func mouseUp(with event: NSEvent) { dragOrigin = nil }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            zoom(by: exp(event.scrollingDeltaY * 0.01), around: convert(event.locationInWindow, from: nil))
        } else {
            pan(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        }
    }

    /// Command-Plus, Command-Minus and Command-0 act only while the diagram has keyboard focus.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection([.command, .control, .option]) == .command,
              let characters = event.charactersIgnoringModifiers else { return super.performKeyEquivalent(with: event) }
        switch characters {
        case "+", "=": zoom(by: 1.25)
        case "-", "_": zoom(by: 0.8)
        case "0": zoomToFit()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.specialKey {
        case .leftArrow: pan(by: CGPoint(x: Self.keyboardStep, y: 0))
        case .rightArrow: pan(by: CGPoint(x: -Self.keyboardStep, y: 0))
        case .upArrow: pan(by: CGPoint(x: 0, y: Self.keyboardStep))
        case .downArrow: pan(by: CGPoint(x: 0, y: -Self.keyboardStep))
        case .home: zoomToFit()
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoom(by: 1.25)
            case "-", "_": zoom(by: 0.8)
            case "0": zoomToFit()
            default: super.keyDown(with: event)
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    func contextMenu() -> NSMenu? {
        guard diagram != nil else { return nil }
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let zoomIn = NSMenuItem(title: PreviewStrings.text(.interactionZoomIn), action: #selector(zoomInFromMenu(_:)), keyEquivalent: "")
        zoomIn.target = self
        let zoomOut = NSMenuItem(title: PreviewStrings.text(.interactionZoomOut), action: #selector(zoomOutFromMenu(_:)), keyEquivalent: "")
        zoomOut.target = self
        let reset = NSMenuItem(title: PreviewStrings.text(.geometryReset), action: #selector(resetZoomFromMenu(_:)), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = !fitsToView
        menu.addItem(zoomIn)
        menu.addItem(zoomOut)
        menu.addItem(reset)
        return menu
    }

    @objc private func zoomInFromMenu(_ sender: Any?) { zoom(by: 1.25) }
    @objc private func zoomOutFromMenu(_ sender: Any?) { zoom(by: 0.8) }
    @objc private func resetZoomFromMenu(_ sender: Any?) { zoomToFit() }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { diagram != nil }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityHelp() -> String? { PreviewStrings.text(.diagramInteractionHelp) }

    override func accessibilityLabel() -> String? {
        guard let diagram else { return nil }
        return PreviewStrings.format(.diagramSummary, arguments: [PreviewStrings.text(Self.kindKey(diagram.kind)),
                                                                  Int64(diagram.nodeCount), Int64(diagram.connectionCount)], locale: locale)
    }

    /// One child per node, with its label and role, then one text element summarizing the connections.
    override func accessibilityChildren() -> [Any]? {
        guard let diagram else { return [] }
        let elements: [NSAccessibilityElement]
        if let cached = cachedAccessibilityChildren {
            elements = cached
        } else {
            var built: [NSAccessibilityElement] = []
            for node in diagram.accessibilityNodes.prefix(DiagramLimits.maximumAccessibilityNodes) {
                let element = NSAccessibilityElement()
                element.setAccessibilityRole(.staticText)
                element.setAccessibilityLabel(node.label)
                element.setAccessibilityRoleDescription(PreviewStrings.text(Self.roleKey(node.role)))
                element.setAccessibilityParent(self)
                built.append(element)
            }
            if !diagram.connections.isEmpty {
                let summary = NSAccessibilityElement()
                summary.setAccessibilityRole(.staticText)
                summary.setAccessibilityLabel(PreviewStrings.text(.diagramConnections))
                summary.setAccessibilityValue(connectionSummary(diagram))
                summary.setAccessibilityParent(self)
                built.append(summary)
            }
            cachedAccessibilityChildren = built
            elements = built
        }
        updateAccessibilityFrames(for: diagram, in: elements)
        return elements
    }

    private func updateAccessibilityFrames(for diagram: SafeDiagram, in elements: [NSAccessibilityElement]) {
        let nodes = diagram.accessibilityNodes.prefix(DiagramLimits.maximumAccessibilityNodes)
        for (index, node) in nodes.enumerated() where elements.indices.contains(index) {
            elements[index].setAccessibilityFrameInParentSpace(viewRect(for: node.rect))
        }
        if !diagram.connections.isEmpty, let summary = elements.last {
            summary.setAccessibilityFrameInParentSpace(bounds)
        }
    }

    func connectionSummary(_ diagram: SafeDiagram) -> String {
        var lines: [String] = []
        for connection in diagram.connections.prefix(DiagramLimits.maximumAccessibilityConnections) {
            if let label = connection.label {
                lines.append(PreviewStrings.format(.diagramConnectionLabeled, arguments: [connection.source, connection.target, label], locale: locale))
            } else {
                lines.append(PreviewStrings.format(.diagramConnection, arguments: [connection.source, connection.target], locale: locale))
            }
        }
        let omitted = diagram.connections.count - lines.count
        if omitted > 0 { lines.append(PreviewStrings.format(.diagramMoreConnections, arguments: [Int64(omitted)], locale: locale)) }
        return lines.joined(separator: "\n")
    }

    private func viewRect(for rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * scale + offset.x, y: rect.minY * scale + offset.y, width: rect.width * scale, height: rect.height * scale)
    }

    static func kindKey(_ kind: SafeDiagram.Kind) -> PreviewStrings.Key {
        switch kind {
        case .flowchart: .diagramKindFlowchart
        case .state: .diagramKindState
        case .classDiagram: .diagramKindClass
        case .entityRelationship: .diagramKindEntityRelationship
        case .sequence: .diagramKindSequence
        case .pie: .diagramKindPie
        case .drawio: .diagramKindDrawio
        }
    }

    static func roleKey(_ role: DiagramNodeRole) -> PreviewStrings.Key {
        switch role {
        case .node: .diagramRoleNode
        case .state: .diagramRoleState
        case .classType: .diagramRoleClass
        case .entity: .diagramRoleEntity
        case .participant: .diagramRoleParticipant
        case .slice: .diagramRoleSlice
        case .shape: .diagramRoleShape
        }
    }
}

import AppKit
import PreviewContracts

enum GeometryRenderFailure: Error, Equatable { case unavailable, invalidGeometry }
enum GeometryNavigation {
    case orbit(SIMD2<Float>), pan(SIMD2<Float>), zoom(Float), fit, reset, preset(GeometryStandardView)
    /// Stands the model on its other axis (Y or Z up) for this view only; nothing is stored.
    case toggleUpAxis
}

struct GeometryRenderStyle {
    let background: SIMD4<Float>
    /// The model's albedo, never the text ink: the view chooses it from the background (`GeometryShading`).
    let material: SIMD4<Float>
    /// The light the shader applies, fixed to the view; a style that does not say uses the standard light.
    var lighting = GeometryLighting.standard
}

@MainActor
protocol GeometryRenderingBackend: AnyObject {
    var surface: NSView { get }
    var failureHandler: (@MainActor () -> Void)? { get set }
    func update(camera: GeometryCamera, style: GeometryRenderStyle)
    func suspend()
}

@MainActor
final class NativeGeometryPreviewView: NSView, PreviewAnnouncing {
    typealias BackendFactory = @MainActor (PreviewMesh) throws -> any GeometryRenderingBackend
    private let backendFactory: BackendFactory
    private let viewport = GeometryInteractionView()
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let failureLabel = NSTextField(wrappingLabelWithString: "")
    private let controls = NSStackView()
    private var buttons: [GeometryControl: NSButton] = [:]
    private var backend: (any GeometryRenderingBackend)?
    private var presentation: GeometryPresentation?
    private var theme = PreviewTheme.system
    /// The user's color-scheme choice. The host sets it before `show`; a model drawn without it uses Standard.
    var syntaxStyle = PreviewSyntaxStyle() { didSet { if oldValue != syntaxStyle { updateAppearance() } } }
    private var locale = Locale.current
    private var needsInitialFit = true
    /// What the view says aloud (the standard views, fit, reset, the up axis and a failure). The preview hands its own
    /// announcer in (`PreviewAnnouncing`); a view used alone keeps this one.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    private(set) var camera = GeometryCamera()
    private(set) var failure: GeometryRenderFailure?
    /// Safe help follows final operability; teardown's transient state never publishes.
    var onCommandAvailabilityChanged: (() -> Void)?
    private(set) var presentationID: UUID?
    var hasGPUResources: Bool { backend != nil }
    var accessibilitySummary: String { summaryLabel.stringValue }
    init(frame: NSRect, backendFactory: @escaping BackendFactory = { try GeometryMetalRenderer(mesh: $0) }) {
        self.backendFactory = backendFactory
        super.init(frame: frame)
        wantsLayer = true
        controls.orientation = .vertical
        controls.spacing = 6
        controls.alignment = .leading
        for rowControls in [[GeometryControl.fit, .reset, .zoomIn, .zoomOut], [.front, .side, .top, .upAxis]] {
            let row = NSStackView()
            row.orientation = .horizontal; row.spacing = 6; row.distribution = .fillEqually
            for control in rowControls {
                let button = NSButton(title: "", target: self, action: #selector(activateControl))
                button.bezelStyle = .rounded
                button.tag = control.rawValue
                button.font = .systemFont(ofSize: 13)
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.cell?.lineBreakMode = .byTruncatingTail
                buttons[control] = button
                row.addArrangedSubview(button)
            }
            controls.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        }
        summaryLabel.font = .preferredFont(forTextStyle: .caption1)
        summaryLabel.setContentHuggingPriority(.required, for: .vertical)
        failureLabel.alignment = .center
        failureLabel.isHidden = true
        for view in [controls, viewport, summaryLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        failureLabel.translatesAutoresizingMaskIntoConstraints = false
        viewport.addSubview(failureLabel)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            controls.topAnchor.constraint(equalTo: topAnchor),
            viewport.leadingAnchor.constraint(equalTo: leadingAnchor),
            viewport.trailingAnchor.constraint(equalTo: trailingAnchor),
            viewport.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 6),
            viewport.bottomAnchor.constraint(equalTo: summaryLabel.topAnchor, constant: -6),
            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            summaryLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            failureLabel.centerYAnchor.constraint(equalTo: viewport.centerYAnchor),
            failureLabel.leadingAnchor.constraint(equalTo: viewport.leadingAnchor, constant: 16),
            failureLabel.trailingAnchor.constraint(equalTo: viewport.trailingAnchor, constant: -16)
        ])
        viewport.onNavigation = { [weak self] action in self?.navigate(action) }
        localizeControls()
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { backend?.failureHandler = nil; backend?.suspend() }

    func show(_ presentation: GeometryPresentation, theme: PreviewTheme, locale: Locale, resetsCamera: Bool = false) {
        if presentationID != presentation.id || resetsCamera {
            // A same-session reload replaces GPU resources but retains the chosen view when the coordinate
            // frame is unchanged. An explicit host generation reset, changed format/bounds or cleared session
            // starts from the format's conventional axis again.
            let preservesCamera = !resetsCamera && self.presentation.map {
                $0.formatID == presentation.formatID && $0.mesh.bounds == presentation.mesh.bounds
            } == true
            suspend()
            if !preservesCamera {
                let extents = presentation.mesh.bounds.maximum - presentation.mesh.bounds.minimum
                let longest = max(extents.x, extents.y, extents.z)
                let normalizedRadius = longest > 0 ? Float(sqrt(extents.x * extents.x + extents.y * extents.y + extents.z * extents.z) / longest) : sqrt(3)
                camera = GeometryCamera(boundingRadius: normalizedRadius, upAxis: GeometryUpAxis.conventional(for: presentation.formatID))
                camera.reset(viewport: renderingSize)
                needsInitialFit = true
            }
        }
        self.presentation = presentation
        presentationID = presentation.id
        self.theme = theme
        self.locale = locale
        localizeControls()
        refreshSummary()
        updateAppearance()
        onCommandAvailabilityChanged?()
    }

    /// Writes the summary lines of the shown model: the model's own summary, then (for the print formats) the Mesh Print
    /// Check, whose width, depth and height follow the axis that is up now, so the up-axis button rewrites them.
    private func refreshSummary() {
        guard let presentation else { return }
        summaryLabel.stringValue = Self.summaryLines(for: presentation, upAxis: camera.upAxis, locale: locale)
            .joined(separator: "\n")
        viewport.setAccessibilityValue(failure == nil ? summaryLabel.stringValue : failureLabel.stringValue)
    }

    /// Every line the view shows for a model: `summaryLines(for:)` and, for the STL, OBJ, PLY and 3MF formats, the
    /// lines of the Mesh Print Check (`GeometryPrintCheck`). CAD models keep their summary as it was.
    static func summaryLines(for presentation: GeometryPresentation, upAxis: GeometryUpAxis, locale: Locale,
                             languagePreferences: [String]? = nil) -> [String] {
        var lines = summaryLines(for: presentation.mesh, locale: locale, languagePreferences: languagePreferences)
        if let check = GeometryPrintCheck(presentation: presentation, upAxis: upAxis) {
            lines += check.lines(locale: locale, languagePreferences: languagePreferences)
        }
        return lines
    }

    /// The model summary, then optional approximate measurements, then optional file-header facts.
    /// Every line is a complete localized template; no translated fragments are concatenated. Values come
    /// from the displayed tessellation and the file header, never from preferences or the source file again.
    /// Lengths, areas and volumes are shown in the unit the file declared, with the symbol Foundation localizes;
    /// a model whose unit nothing states shows plain numbers and says "unit not declared". A face count that
    /// stopped at the contract's cap reads "100,000+". `languagePreferences` exists for tests; hosts use the
    /// process language.
    static func summaryLines(for mesh: PreviewMesh, locale: Locale, languagePreferences: [String]? = nil) -> [String] {
        func countText(_ value: Int) -> String { GeometryNumberText.count(value, locale: locale) }
        func lengthText(_ value: Double) -> String { GeometryNumberText.length(value, locale: locale) }
        func measureText(_ value: Double) -> String { GeometryNumberText.measure(value, locale: locale) }
        let preferences = languagePreferences
        let units = GeometrySummaryUnits(mesh.unitProvenance)
        let millimetresPerUnit = units?.millimetresPerUnit ?? 1
        let extents = mesh.bounds.maximum - mesh.bounds.minimum
        let width = lengthText(extents.x / millimetresPerUnit)
        let height = lengthText(extents.y / millimetresPerUnit)
        let depth = lengthText(extents.z / millimetresPerUnit)
        let faces = mesh.faceCountIsCapped
            ? PreviewStrings.format(.cadFaceCountAtLeast, arguments: [countText(mesh.faceCount)], locale: locale,
                                    languagePreferences: preferences)
            : countText(mesh.faceCount)
        let triangles = countText(mesh.indices.count / 3)
        var lines: [String]
        if let units {
            lines = [PreviewStrings.format(.cadSummaryDimensions,
                arguments: [faces, triangles, width, height, depth, units.lengthSymbol(locale: locale)],
                locale: locale, languagePreferences: preferences)]
        } else {
            lines = [PreviewStrings.format(.cadSummaryDimensionsUnitless, arguments: [faces, triangles, width, height, depth],
                                           locale: locale, languagePreferences: preferences)]
        }
        if let measurements = mesh.measurements {
            let measuredUnits = GeometrySummaryUnits(measurements.unitProvenance)
            let measuredPerUnit = measuredUnits?.millimetresPerUnit ?? 1
            let area = measureText(measurements.surfaceAreaSquareMillimetres / (measuredPerUnit * measuredPerUnit))
            let bodies = countText(measurements.bodyCount)
            if let cubicMillimetres = measurements.volumeCubicMillimetres {
                let volume = measureText(cubicMillimetres / (measuredPerUnit * measuredPerUnit * measuredPerUnit))
                if let measuredUnits {
                    lines.append(PreviewStrings.format(.cadMeasurementsSolidUnits,
                        arguments: [area, measuredUnits.areaSymbol(locale: locale), volume, measuredUnits.volumeSymbol(locale: locale), bodies],
                        locale: locale, languagePreferences: preferences))
                } else {
                    lines.append(PreviewStrings.format(.cadMeasurementsSolidUnitless, arguments: [area, volume, bodies],
                                                       locale: locale, languagePreferences: preferences))
                }
            } else if let measuredUnits {
                lines.append(PreviewStrings.format(.cadMeasurementsOpenUnits,
                    arguments: [area, measuredUnits.areaSymbol(locale: locale), bodies],
                    locale: locale, languagePreferences: preferences))
            } else {
                lines.append(PreviewStrings.format(.cadMeasurementsOpenUnitless, arguments: [area, bodies],
                                                   locale: locale, languagePreferences: preferences))
            }
        }
        if let facts = mesh.headerFacts {
            switch (facts.schema?.displayName, facts.originatingSystem) {
            case (let schema?, let system?):
                lines.append(PreviewStrings.format(.cadHeaderSchemaAndSystem, arguments: [schema, system],
                                                   locale: locale, languagePreferences: preferences))
            case (let schema?, nil):
                lines.append(PreviewStrings.format(.cadHeaderSchema, arguments: [schema], locale: locale, languagePreferences: preferences))
            case (nil, let system?):
                lines.append(PreviewStrings.format(.cadHeaderSystem, arguments: [system], locale: locale, languagePreferences: preferences))
            case (nil, nil): break
            }
        }
        return lines
    }

    /// Hosts explicitly resume an active geometry presentation. Ordinary text never reaches this boundary.
    func resume() {
        guard backend == nil, failure == nil, let presentation, !isHidden else { return }
        do {
            let newBackend = try backendFactory(presentation.mesh)
            newBackend.failureHandler = { [weak self] in self?.renderingFailed() }
            backend = newBackend
            newBackend.surface.frame = viewport.bounds
            newBackend.surface.autoresizingMask = [.width, .height]
            viewport.addSubview(newBackend.surface, positioned: .below, relativeTo: failureLabel)
            updateAppearance()
        } catch {
            failure = (error as? GeometryRenderFailure) ?? .unavailable
            updateAppearance()
            announceFailure()
        }
        onCommandAvailabilityChanged?()
    }

    func suspend() {
        viewport.endDrag()
        backend?.failureHandler = nil
        backend?.suspend()
        backend?.surface.removeFromSuperview()
        backend = nil
        failure = nil
        failureLabel.isHidden = true
        // With the failure gone, the viewport's value describes the model again.
        viewport.setAccessibilityValue(summaryLabel.stringValue)
    }

    func clear() {
        suspend()
        presentation = nil; presentationID = nil
        summaryLabel.stringValue = ""
        viewport.setAccessibilityValue("")
        for button in buttons.values { button.isEnabled = false }
    }

    func navigate(_ action: GeometryNavigation) {
        guard presentation != nil, failure == nil else { return }
        needsInitialFit = false
        switch action {
        case .orbit(let delta): camera.orbit(delta: delta)
        case .pan(let delta): camera.pan(delta: delta, viewport: renderingSize)
        case .zoom(let factor): camera.zoom(by: factor)
        case .fit: camera.fit(viewport: renderingSize)
        case .reset: camera.reset(viewport: renderingSize)
        case .preset(let standardView): camera.preset(standardView, viewport: renderingSize)
        case .toggleUpAxis:
            camera.setUpAxis(camera.upAxis.toggled, viewport: renderingSize)
            updateUpAxisControl()
            refreshSummary()
        }
        updateBackend()
        if let spoken = spokenResult(of: action) { announcer?.announce(spoken, from: viewport) }
    }

    /// What a navigation says aloud, as the title of the control that does the same thing: the standard views, fit,
    /// reset and the up axis (`PreviewAnnouncer`'s policy: a 3D preset is announced). Orbit, pan and zoom are
    /// continuous gestures and never speak.
    private func spokenResult(of action: GeometryNavigation) -> String? {
        switch action {
        case .orbit, .pan, .zoom:
            return nil
        case .fit:
            return PreviewStrings.text(.cadFit)
        case .reset:
            return PreviewStrings.text(.cadReset)
        case .preset(let standardView):
            switch standardView {
            case .front: return PreviewStrings.text(.cadFront)
            case .side: return PreviewStrings.text(.cadSide)
            case .top: return PreviewStrings.text(.cadTop)
            }
        case .toggleUpAxis:
            return PreviewStrings.format(.cadUpAxis, arguments: [camera.upAxis.letter], locale: locale)
        }
    }

    override func layout() {
        super.layout()
        if needsInitialFit, viewport.bounds.width > 0, viewport.bounds.height > 0 {
            camera.fit(viewport: viewport.bounds.size)
            needsInitialFit = false
        }
        updateBackend()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { suspend() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private var renderingSize: CGSize {
        viewport.bounds.width > 0 && viewport.bounds.height > 0 ? viewport.bounds.size : bounds.size
    }

    private var palette: NativeTextPalette {
        NativeTextPalette(theme: theme,
            isDark: effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast, style: syntaxStyle)
    }

    private func updateAppearance() {
        let palette = palette
        layer?.backgroundColor = palette.background.cgColor
        summaryLabel.textColor = palette.foreground
        failureLabel.textColor = palette.foreground
        failureLabel.stringValue = failure == .invalidGeometry ? PreviewStrings.text(.cadInvalidGeometry) : PreviewStrings.text(.cadMetalUnavailable)
        failureLabel.isHidden = failure == nil
        // A failure is what VoiceOver reads for the viewport: the model summary no longer describes anything drawn there.
        viewport.setAccessibilityValue(failure == nil ? summaryLabel.stringValue : failureLabel.stringValue)
        for button in buttons.values { button.isEnabled = presentation != nil && failure == nil }
        updateBackend()
    }

    private func updateBackend() {
        guard let backend else { return }
        let palette = palette
        let background = rgba(palette.background)
        // The material depends on the background, never on the text ink, so the model is legible in every scheme.
        let profile = GeometryShading.profile(forBackground: SIMD3<Float>(background.x, background.y, background.z))
        let material = SIMD4<Float>(profile.material.x, profile.material.y, profile.material.z, 1)
        backend.update(camera: camera, style: GeometryRenderStyle(background: background, material: material,
                                                                   lighting: profile.lighting))
    }

    private func rgba(_ color: NSColor) -> SIMD4<Float> {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return SIMD4<Float>(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), 1)
    }

    private func localizeControls() {
        for (control, button) in buttons where control != .upAxis {
            let title = PreviewStrings.text(control.title)
            button.title = title
            button.toolTip = title
            button.setAccessibilityLabel(title)
            if let symbol = control.symbol {
                button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                button.imagePosition = .imageOnly
            }
        }
        updateUpAxisControl()
        viewport.setAccessibilityElement(true)
        viewport.setAccessibilityRole(.image)
        viewport.setAccessibilityLabel(PreviewStrings.text(.cadViewportLabel))
        viewport.setAccessibilityHelp(PreviewStrings.text(.cadInteractionHelp))
        viewport.toolTip = PreviewStrings.text(.cadInteractionHelp)
    }

    /// The up-axis button names the axis that is up now. Its tooltip and help say what it does and that the choice is
    /// per view and never saved; the axis letter is a technical name and is not translated.
    private func updateUpAxisControl() {
        guard let button = buttons[.upAxis] else { return }
        let title = PreviewStrings.format(.cadUpAxis, arguments: [camera.upAxis.letter], locale: locale)
        let help = PreviewStrings.text(.cadUpAxisHelp)
        button.title = title
        button.toolTip = help
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(help)
    }

    private func renderingFailed() {
        suspend()
        failure = .unavailable
        updateAppearance()
        announceFailure()
        onCommandAvailabilityChanged?()
    }

    /// Says the failure once, when it begins: the label that already shows it, from the viewport it replaces.
    private func announceFailure() {
        guard failure != nil else { return }
        announcer?.announce(failureLabel.stringValue, from: viewport)
    }

    @objc private func activateControl(_ sender: NSButton) {
        guard let control = GeometryControl(rawValue: sender.tag) else { return }
        navigate(control.action)
    }
}

/// The unit a geometry summary is shown in (decision 027, Q-11). Importers store millimetres. A model whose file
/// declared another unit is shown in it; one that declared none has no unit at all (the initializer returns nil),
/// so no number is presented as millimetres on the strength of an assumption. Symbols come from Foundation's
/// locale data, never from a literal, so a Russian reader sees the Russian symbol.
struct GeometrySummaryUnits {
    let length: UnitLength
    let area: UnitArea
    let volume: UnitVolume
    /// Millimetres in one unit of `length`.
    let millimetresPerUnit: Double

    init?(_ provenance: GeometryUnitProvenance) {
        switch provenance {
        case .undeclared:
            return nil
        case .assumedMillimetres:
            self.init(length: .millimeters, area: .squareMillimeters, volume: .cubicMillimeters, millimetresPerUnit: 1)
        case .declared(let unit):
            switch unit {
            // Foundation has no cubic micrometre, so a model declared in micrometres is shown in millimetres: the
            // same quantities in a unit that all three lines can use.
            case .micrometre, .millimetre:
                self.init(length: .millimeters, area: .squareMillimeters, volume: .cubicMillimeters, millimetresPerUnit: 1)
            case .centimetre:
                self.init(length: .centimeters, area: .squareCentimeters, volume: .cubicCentimeters,
                          millimetresPerUnit: unit.millimetres)
            case .metre:
                self.init(length: .meters, area: .squareMeters, volume: .cubicMeters, millimetresPerUnit: unit.millimetres)
            case .inch:
                self.init(length: .inches, area: .squareInches, volume: .cubicInches, millimetresPerUnit: unit.millimetres)
            case .foot:
                self.init(length: .feet, area: .squareFeet, volume: .cubicFeet, millimetresPerUnit: unit.millimetres)
            }
        }
    }

    private init(length: UnitLength, area: UnitArea, volume: UnitVolume, millimetresPerUnit: Double) {
        self.length = length
        self.area = area
        self.volume = volume
        self.millimetresPerUnit = millimetresPerUnit
    }

    func lengthSymbol(locale: Locale) -> String { Self.symbol(of: length, locale: locale) }
    func areaSymbol(locale: Locale) -> String { Self.symbol(of: area, locale: locale) }
    func volumeSymbol(locale: Locale) -> String { Self.symbol(of: volume, locale: locale) }

    /// The localized short symbol of a unit ("mm", "мм", "in"). Foundation localizes a unit next to a number, so one
    /// measurement of a single unit is formatted as provided (never converted to the locale's own units) and the
    /// number is taken away; what is left is the symbol the way the language writes it. A formatter that gives
    /// nothing back falls back to the unit's own technical symbol, so a unit is never shown as an empty string.
    static func symbol<UnitType: Unit>(of unit: UnitType, locale: Locale) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.locale = locale
        let number = formatter.numberFormatter.string(from: NSNumber(value: 1)) ?? "1"
        let text = formatter.string(from: Measurement(value: 1, unit: unit))
        let symbol = text.replacingOccurrences(of: number, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return symbol.isEmpty ? unit.symbol : symbol
    }
}

/// The number formats of the geometry summary, one definition for every line, so a size and a measurement read alike.
private enum GeometryNumberText {
    static func count(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }
    /// Up to three fraction digits, for extents.
    static func length(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.locale(locale).precision(.fractionLength(0...3)))
    }
    /// Four significant digits: the values approximate the tessellation, so more digits would overstate them.
    static func measure(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.locale(locale).precision(.significantDigits(1...4)))
    }
}

/// The Mesh Print Check of a model (decision 029) as numbers, before any wording, so tests read it without a localized
/// resource. It belongs to the four triangle-mesh formats that people print from; a CAD model has none. Everything
/// comes from the mesh the reader built: the bounds, and the measurements of the displayed tessellation. Nothing is
/// a certified dimension, and the estimate is an upper bound for a part printed solid.
struct GeometryPrintCheck {
    /// The formats that show the check.
    static let formats: Set<FormatID> = [.meshSTL, .meshOBJ, .meshPLY, .mesh3MF]

    /// The model's extents in `units` (plain numbers when the file declares none). Slicers read X as the width and Y as
    /// the depth of a part that stands on Z; a model that stands on Y has its depth along Z.
    let width: Double, depth: Double, height: Double
    /// The unit the extents are shown in; `nil` when the model's unit is undeclared.
    let units: GeometrySummaryUnits?
    /// Zero when the surface has no gap or when nothing could be measured; the line is shown only above zero.
    let openEdgeCount: Int
    let nonManifoldEdgeCount: Int
    /// Present only when the volume is known and the unit is declared or assumed millimetres.
    let estimate: GeometryPrintEstimate?

    init?(presentation: GeometryPresentation, upAxis: GeometryUpAxis) {
        guard Self.formats.contains(presentation.formatID) else { return nil }
        let mesh = presentation.mesh
        let units = GeometrySummaryUnits(mesh.unitProvenance)
        let extents = (mesh.bounds.maximum - mesh.bounds.minimum) / (units?.millimetresPerUnit ?? 1)
        width = extents.x
        switch upAxis {
        case .z: depth = extents.y; height = extents.z
        case .y: depth = extents.z; height = extents.y
        }
        self.units = units
        openEdgeCount = mesh.measurements?.openEdgeCount ?? 0
        nonManifoldEdgeCount = mesh.measurements?.nonManifoldEdgeCount ?? 0
        estimate = mesh.measurements.flatMap { GeometryPrintEstimate($0) }
    }

    /// The size line, then the open-edge and non-manifold lines when they are above zero, then the estimate when there
    /// is one. Each line is a complete localized template; counts go through the plural machinery.
    func lines(locale: Locale, languagePreferences: [String]? = nil) -> [String] {
        let preferences = languagePreferences
        let sizes = [width, depth, height].map { GeometryNumberText.length($0, locale: locale) }
        var lines: [String]
        if let units {
            lines = [PreviewStrings.format(.meshPrintSize, arguments: sizes + [units.lengthSymbol(locale: locale)],
                                           locale: locale, languagePreferences: preferences)]
        } else {
            lines = [PreviewStrings.format(.meshPrintSizeUnitless, arguments: sizes, locale: locale, languagePreferences: preferences)]
        }
        if openEdgeCount > 0 {
            lines.append(PreviewStrings.count(.meshPrintOpenEdges, openEdgeCount, locale: locale, languagePreferences: preferences))
        }
        if nonManifoldEdgeCount > 0 {
            lines.append(PreviewStrings.count(.meshPrintNonManifoldEdges, nonManifoldEdgeCount,
                                              locale: locale, languagePreferences: preferences))
        }
        if let estimate {
            let mass = GeometryNumberText.measure(estimate.massGrams, locale: locale)
            let filament = GeometryNumberText.measure(estimate.filamentLengthMetres, locale: locale)
            let diameter = GeometryNumberText.measure(GeometryPrintEstimate.filamentDiameterMillimetres, locale: locale)
            lines.append(PreviewStrings.format(.meshPrintEstimate, arguments: [
                mass, GeometrySummaryUnits.symbol(of: UnitMass.grams, locale: locale),
                filament, GeometrySummaryUnits.symbol(of: UnitLength.meters, locale: locale),
                diameter, GeometrySummaryUnits.symbol(of: UnitLength.millimeters, locale: locale)],
                locale: locale, languagePreferences: preferences))
        }
        return lines
    }
}

private enum GeometryControl: Int {
    case fit, reset, zoomIn, zoomOut, front, side, top, upAxis
    /// The up-axis title is a template with the axis in it, so the view formats it itself (`updateUpAxisControl`).
    var title: PreviewStrings.Key {
        switch self {
        case .fit: .cadFit
        case .reset: .cadReset
        case .zoomIn: .cadZoomIn
        case .zoomOut: .cadZoomOut
        case .front: .cadFront
        case .side: .cadSide
        case .top: .cadTop
        case .upAxis: .cadUpAxis
        }
    }
    var symbol: String? {
        switch self {
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        default: nil
        }
    }
    var action: GeometryNavigation {
        switch self {
        case .fit: .fit
        case .reset: .reset
        case .zoomIn: .zoom(0.8)
        case .zoomOut: .zoom(1.25)
        case .front: .preset(.front)
        case .side: .preset(.side)
        case .top: .preset(.top)
        case .upAxis: .toggleUpAxis
        }
    }
}

@MainActor
private final class GeometryInteractionView: NSView {
    var onNavigation: (@MainActor (GeometryNavigation) -> Void)?
    private var lastDragLocation: NSPoint?
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityFocused() -> Bool { window?.firstResponder === self }
    override func setAccessibilityFocused(_ focused: Bool) {
        if focused { window?.makeFirstResponder(self) }
        else if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHiddenOrHasHiddenAncestor && bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        lastDragLocation = convert(event.locationInWindow, from: nil)
        window?.makeFirstResponder(self)
    }
    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) {
        guard let delta = dragDelta(for: event) else { return }
        onNavigation?(event.modifierFlags.contains(.shift) ? .pan(delta) : .orbit(delta))
    }
    override func rightMouseDragged(with event: NSEvent) {
        guard let delta = dragDelta(for: event) else { return }
        onNavigation?(.pan(delta))
    }
    override func mouseUp(with event: NSEvent) { endDrag() }
    override func rightMouseUp(with event: NSEvent) { endDrag() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endDrag() }
    }
    func endDrag() { lastDragLocation = nil }
    private func dragDelta(for event: NSEvent) -> SIMD2<Float>? {
        guard let previous = lastDragLocation else { return nil }
        let current = convert(event.locationInWindow, from: nil)
        lastDragLocation = current
        // Camera navigation uses positive Y downward; AppKit view coordinates can point upward.
        return SIMD2<Float>(Float(current.x - previous.x),
                            Float(isFlipped ? current.y - previous.y : previous.y - current.y))
    }
    override func scrollWheel(with event: NSEvent) { onNavigation?(.zoom(exp(Float(-event.scrollingDeltaY) * 0.025))) }
    override func magnify(with event: NSEvent) { onNavigation?(.zoom(Float(1 / max(0.1, 1 + event.magnification)))) }
    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            super.keyDown(with: event)
            return
        }
        let delta: SIMD2<Float>?
        switch event.specialKey {
        case .leftArrow: delta = SIMD2<Float>(-12, 0)
        case .rightArrow: delta = SIMD2<Float>(12, 0)
        case .upArrow: delta = SIMD2<Float>(0, -12)
        case .downArrow: delta = SIMD2<Float>(0, 12)
        default: delta = nil
        }
        if let delta {
            onNavigation?(event.modifierFlags.contains(.shift) ? .pan(delta) : .orbit(delta))
            return
        }
        // The plain keys of the viewport come from the shared command table, so a layout that types no Latin letter
        // or digit on these keys (Cyrillic, French AZERTY's number row) still reaches them by key position.
        switch PreviewCommand(event: event, scope: .viewport) {
        case .cameraZoomIn?: onNavigation?(.zoom(0.8))
        case .cameraZoomOut?: onNavigation?(.zoom(1.25))
        case .fitModel?: onNavigation?(.fit)
        case .resetView?: onNavigation?(.reset)
        case .viewFront?: onNavigation?(.preset(.front))
        case .viewSide?: onNavigation?(.preset(.side))
        case .viewTop?: onNavigation?(.preset(.top))
        default: super.keyDown(with: event)
        }
    }
}

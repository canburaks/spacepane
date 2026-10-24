import AppKit
import PreviewContracts

/// A native drawing of the paths and points of a GeoJSON, GPX or KML file in an equirectangular
/// projection (longitude scaled by the cosine of the mid latitude, latitude unscaled). It draws
/// only `SafePlot`, which is derived from concealed text; it has no map tiles, makes no network
/// request and reads no file. The drawing is one accessible image with a localized summary, and
/// its colors come from the preview palette, so appearance, contrast and theme changes apply.
///
/// A plot that crosses the antimeridian is framed the short way around (`PlotFraming`), and no line is drawn across
/// the whole map. That long paths show only some of their points is a limit of the preview and goes to the limits
/// strip as a typed notice (`DrawnModeNotices`), not into the view.
@MainActor
final class NativePlotPreviewView: NSView, SafeModeContentView, PreviewSafeCopying, PreviewCopyReporting, PreviewAnnouncing {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    /// The plot is a projected vector drawing with a fixed caption and does not scale with text zoom.
    var respondsToTextZoom: Bool { false }
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?
    var selectionWriter: (String, NSPasteboard) -> Bool = { text, pasteboard in
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    var copyHandler: ((PreviewCopyEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    let captionLabel = NSTextField(wrappingLabelWithString: "")
    let canvas = PlotCanvas()
    private var plot: SafePlot?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        captionLabel.font = .preferredFont(forTextStyle: .caption1)
        captionLabel.isSelectable = true
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.setContentHuggingPriority(.required, for: .vertical)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        addSubview(captionLabel)
        addSubview(canvas)
        NSLayoutConstraint.activate([
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            captionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 8),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) else {
            return super.performKeyEquivalent(with: event)
        }
        if PreviewKeyPolicy.answerFindUnavailable(event, using: announcer, from: self) { return true }
        if PreviewCommand(event: event) == .copy {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func copy(_ sender: Any?) {
        let text = captionLabel.stringValue
        guard !text.isEmpty else { return }
        let copied = TagCopySanitizer(safeDisplayedText: text, safetyLensFoundTags: tagCopyPolicy?() ?? false).wholeText()
        guard selectionWriter(copied.text, pasteboard) else { return }
        let event = PreviewCopyEvent.text.removingTags(copied.removedTagScalarCount)
        if let copyHandler {
            copyHandler(event)
        } else {
            announcer?.announce(PreviewStrings.text(event.confirmationKey), from: self)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu()
    }

    func contextMenu() -> NSMenu? {
        guard !captionLabel.stringValue.isEmpty else { return nil }
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let item = NSMenuItem(title: PreviewStrings.text(.interactionCopy), action: #selector(copy(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

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
        captionLabel.maximumNumberOfLines = isCompact ? 1 : 0
        captionLabel.lineBreakMode = isCompact ? .byTruncatingTail : .byWordWrapping
        captionLabel.toolTip = isCompact && !captionLabel.stringValue.isEmpty ? captionLabel.stringValue : nil
    }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        guard mode == .plot, let plot = modes.plot else { clear(); return }
        self.plot = plot
        layer?.backgroundColor = style.palette.background.cgColor
        captionLabel.textColor = style.palette.foreground
        let extentText = Self.extentText(plot, locale: style.locale)
        captionLabel.stringValue = extentText
        canvas.show(plot, palette: style.palette)
        canvas.setAccessibilityLabel(PreviewStrings.format(
            .dataPlotAccessibility, arguments: [Int64(plot.paths.count), Int64(plot.points.count)], locale: style.locale))
        canvas.setAccessibilityValue(extentText)
        canvas.setAccessibilityHelp(PreviewStrings.text(.dataPlotHelp))
        updateChromeForWidth(bounds.width)
    }

    func clear() {
        plot = nil
        captionLabel.stringValue = ""
        canvas.show(nil, palette: nil)
        canvas.setAccessibilityLabel(nil)
        canvas.setAccessibilityValue(nil)
        canvas.setAccessibilityHelp(nil)
        updateChromeForWidth(bounds.width)
    }

    /// The longitude and latitude ranges, formatted for the presentation locale. A plot framed across the
    /// antimeridian reads west to east, so its west value is the larger one ("179.0000 to -179.0000").
    static func extentText(_ plot: SafePlot, locale: Locale) -> String {
        guard let framing = PlotFraming.framing(for: plot) else { return "" }
        func number(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(4)).locale(locale))
        }
        return PreviewStrings.format(.dataPlotExtent, arguments: [number(framing.west), number(framing.displayEast),
                                                                  number(framing.south), number(framing.north)],
                                     locale: locale)
    }
}

/// How the longitudes of a plot are laid out. The frame is the narrowest arc of longitude that holds every
/// position: normally the span from the smallest to the largest longitude, but for a track across the antimeridian
/// (a ferry from Fiji to Samoa, a flight over the Pacific) the arc that crosses it, so such a plot is not stretched
/// over the whole world. `place(_:)` moves a position to where the frame draws it. A frame wider than half the
/// world keeps the ordinary span, and `pieces(of:)` then cuts any line that would cross the map the long way at the
/// edges of the frame, as RFC 7946 section 3.1.9 asks of a line crossing the antimeridian.
///
/// Longitudes are first normalized to (-180, 180], so 0 and 360 are one meridian and -180 and 180 are one line.
/// Latitude is not wrapped: at the poles the equirectangular map has a whole edge for one point, which is a limit
/// of the projection, not of the framing.
struct PlotFraming: Equatable, Sendable {
    /// The longitude at the west edge of the frame, in (-180, 180].
    let west: Double
    /// The longitude at the east edge, from `west` up to `west + 360`; more than 180 when the frame crosses it.
    let east: Double
    let south: Double
    let north: Double

    /// The longest step in longitude a drawn line may take. A longer step would cross the map the wrong way.
    static let maximumStep = 180.0

    var width: Double { east - west }
    var crossesAntimeridian: Bool { east > 180 }
    /// `east` as a longitude, in (-180, 180].
    var displayEast: Double { east > 180 ? east - 360 : east }

    /// A longitude in (-180, 180]: 360 is 0, and -180 is 180, so a track along the date line keeps one side.
    /// Values that are not finite are returned unchanged.
    static func normalized(_ longitude: Double) -> Double {
        guard longitude.isFinite else { return longitude }
        // The remainder keeps the sign of the dividend, in (-360, 360); fold it into (-180, 180].
        var value = longitude.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 } else if value <= -180 { value += 360 }
        return value
    }

    /// Where the frame draws `longitude`: itself, or itself plus 360 when it sits west of the frame's west edge.
    func unwrapped(_ longitude: Double) -> Double {
        let value = Self.normalized(longitude)
        return value < west ? value + 360 : value
    }

    /// `position` with its longitude moved to where the frame draws it.
    func place(_ position: SafePlot.Position) -> SafePlot.Position {
        SafePlot.Position(longitude: unwrapped(position.longitude), latitude: position.latitude)
    }

    /// The frame of every finite position of `plot`, or nil when there is none.
    static func framing(for plot: SafePlot) -> PlotFraming? {
        var longitudes: [Double] = []
        var south = Double.infinity
        var north = -Double.infinity
        for position in plot.positions where position.longitude.isFinite && position.latitude.isFinite {
            longitudes.append(normalized(position.longitude))
            south = min(south, position.latitude)
            north = max(north, position.latitude)
        }
        guard let smallest = longitudes.min(), let largest = longitudes.max() else { return nil }
        let ordinary = PlotFraming(west: smallest, east: largest, south: south, north: north)
        // The widest empty stretch between neighbouring longitudes, counting the one around the antimeridian.
        // The crossing frame starts after it and ends before it.
        let sorted = longitudes.sorted()
        var widestGap = sorted[0] + 360 - sorted[sorted.count - 1]
        var start = sorted[0]
        for index in 1..<sorted.count where sorted[index] - sorted[index - 1] > widestGap {
            widestGap = sorted[index] - sorted[index - 1]
            start = sorted[index]
        }
        let acrossWidth = 360 - widestGap
        guard acrossWidth + 0.000_001 < ordinary.width, acrossWidth <= maximumStep else { return ordinary }
        return PlotFraming(west: start, east: start + acrossWidth, south: south, north: north)
    }

    /// The lines to draw for `path`, as positions in the frame's longitudes (already placed). A path whose steps
    /// all stay within `maximumStep` is one line. A step that would run the long way across a wide frame really
    /// crosses the antimeridian the short way, so the line is cut there: one line ends at the frame's edge on the
    /// side it leaves by, and the next begins at the opposite edge, each on the true course of the step.
    func pieces(of path: [SafePlot.Position]) -> [[SafePlot.Position]] {
        var lines: [[SafePlot.Position]] = []
        var current: [SafePlot.Position] = []
        for position in path where position.longitude.isFinite && position.latitude.isFinite {
            let next = place(position)
            if let last = current.last, abs(next.longitude - last.longitude) > Self.maximumStep {
                let seam = crossing(from: last, to: next)
                current.append(seam.exit)
                lines.append(current)
                current = [seam.entry]
            }
            current.append(next)
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Where the short way between two placed positions leaves the frame and where it comes back in. The short way
    /// runs from the eastern endpoint on to the western endpoint plus 360 degrees, so the course is clipped to the
    /// east edge and, 360 degrees further, to the west edge.
    private func crossing(from last: SafePlot.Position, to next: SafePlot.Position)
        -> (exit: SafePlot.Position, entry: SafePlot.Position) {
        let leavesEast = last.longitude > next.longitude
        let eastern = leavesEast ? last : next
        let western = leavesEast ? next : last
        let span = western.longitude + 360 - eastern.longitude
        func courseLatitude(at longitude: Double) -> Double {
            guard span > 0 else { return eastern.latitude }
            let fraction = min(max((longitude - eastern.longitude) / span, 0), 1)
            return eastern.latitude + (western.latitude - eastern.latitude) * fraction
        }
        let atEast = SafePlot.Position(longitude: east, latitude: courseLatitude(at: east))
        let atWest = SafePlot.Position(longitude: west, latitude: courseLatitude(at: west + 360))
        return leavesEast ? (exit: atEast, entry: atWest) : (exit: atWest, entry: atEast)
    }
}

/// The drawing surface. Flipped, so projected y grows downward like the view's own coordinates.
@MainActor
final class PlotCanvas: NSView {
    private static let margin: CGFloat = 24
    private static let pointRadius: CGFloat = 3
    private var plot: SafePlot?
    /// The frame of the shown plot: computed once per plot, not per draw.
    private(set) var framing: PlotFraming?
    private var palette: NativeTextPalette?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    func show(_ plot: SafePlot?, palette: NativeTextPalette?) {
        self.plot = plot
        framing = plot.flatMap { PlotFraming.framing(for: $0) }
        self.palette = palette
        needsDisplay = true
    }

    /// The point of the drawing for a position, inside `bounds` inset by the margin. Exposed so a
    /// test can check the projection without inspecting pixels.
    func project(_ position: SafePlot.Position, extent: (west: Double, south: Double, east: Double, north: Double)) -> CGPoint {
        Self.projection(extent: extent, in: bounds.insetBy(dx: Self.margin, dy: Self.margin))(position)
    }

    /// Longitude is scaled by cos(mid latitude) so that distances keep their proportions near the
    /// middle of the drawing; the result is centered and scaled uniformly to fit.
    static func projection(extent: (west: Double, south: Double, east: Double, north: Double),
                           in area: CGRect) -> (SafePlot.Position) -> CGPoint {
        let scale = max(cos((extent.south + extent.north) / 2 * Double.pi / 180), 0.01)
        let width = (extent.east - extent.west) * scale
        let height = extent.north - extent.south
        // A single point or a perfectly straight line has no extent in one direction.
        let fit = min(width > 0 ? Double(area.width) / width : .infinity,
                      height > 0 ? Double(area.height) / height : .infinity)
        let factor = fit.isFinite ? fit : 0
        let offsetX = Double(area.minX) + (Double(area.width) - width * factor) / 2
        let offsetY = Double(area.minY) + (Double(area.height) - height * factor) / 2
        return { position in
            CGPoint(x: offsetX + (position.longitude - extent.west) * scale * factor,
                    y: offsetY + (extent.north - position.latitude) * factor)
        }
    }

    /// The projection of a plot's own frame, for positions already placed in it (`PlotFraming.place(_:)`, or a
    /// piece from `PlotFraming.pieces(of:)`): a plot across the antimeridian is one compact drawing.
    static func projection(framing: PlotFraming, in area: CGRect) -> (SafePlot.Position) -> CGPoint {
        projection(extent: (west: framing.west, south: framing.south, east: framing.east, north: framing.north), in: area)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette else { return }
        palette.background.setFill()
        bounds.fill()
        guard let plot, let framing else { return }
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        guard area.width > 1, area.height > 1 else { return }
        palette.hairline.setStroke()
        let frame = NSBezierPath(rect: area)
        frame.lineWidth = 1
        frame.stroke()
        let project = Self.projection(framing: framing, in: area)
        palette.color(for: .key).setStroke()
        for path in plot.paths {
            for piece in framing.pieces(of: path) {
                let line = NSBezierPath()
                line.lineWidth = 1.5
                line.lineJoinStyle = .round
                line.lineCapStyle = .round
                for (index, position) in piece.enumerated() {
                    index == 0 ? line.move(to: project(position)) : line.line(to: project(position))
                }
                line.stroke()
            }
        }
        palette.color(for: .number).setFill()
        for position in plot.points where position.longitude.isFinite && position.latitude.isFinite {
            let center = project(framing.place(position))
            NSBezierPath(ovalIn: CGRect(x: center.x - Self.pointRadius, y: center.y - Self.pointRadius,
                                        width: Self.pointRadius * 2, height: Self.pointRadius * 2)).fill()
        }
    }
}

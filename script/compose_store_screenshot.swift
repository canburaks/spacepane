// Tools for the App Store screenshots (docs/release/store-listing/screenshots.md).
//
//   swift script/compose_store_screenshot.swift windows
//       Lists on-screen windows as "id<TAB>owner<TAB>x,y,w,h<TAB>title<TAB>layer" (points, top-left origin),
//       front to back.
//
//   swift script/compose_store_screenshot.swift compose --headline "Line one|Line two" [--note "small line"]
//       [--background paper|aurora|night|stage|ink|ink-dots|brand|tile|sand|gradient|mesh]
//       [--colors "#4b3cff,#a64dff,#ff4f9a,#ffb547"] [--angle 135] [--accent "#2f7de1/#d3e5fb"] [--pixels-per-point 2]
//       [--eyebrow "JSON"] [--bleed] [--max-scale 1] --output shot.png back.png:x:y [front.png:x:y ...]
//       Places real window captures (taken with `screencapture -o -l <id>`) on a 2880 x 1800 canvas under a
//       headline. Each capture keeps its position relative to the others, so two windows overlap exactly as
//       they did on screen. Captures are never stretched; --max-scale above 1 exists for layout drafts only.
//       --eyebrow puts a small capsule label above the headline. --bleed fits the captures to the width only
//       and lets them run off the bottom edge, which shows the interface larger.
//       Backgrounds follow DESIGN.md in the spacepane-web repository: `paper` is the flat page color, `aurora` adds the brand glows to it,
//       `night` puts them on the dark section color, `stage` is a format tile's pastel with its dot grid.
//       The rest have no gradient: `ink` and `brand` are flat, `ink-dots`, `tile` (the --accent pastel) and
//       `sand` add only the dot grid. `gradient` is a vivid linear blend of --colors at --angle (degrees,
//       0 is left to right, 90 bottom to top); `mesh` fills with the first color and blooms the others over it.
//
//   swift script/compose_store_screenshot.swift click <x> <y>
//       Clicks the mouse at a screen point (points, top-left origin). The companion's color scheme tiles ignore an
//       accessibility press and need a real click.
//
// The canvas is opaque: App Store Connect rejects images with an alpha channel.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum Canvas {
    static let size = CGSize(width: 2880, height: 1800)
    static let paper = CGColor(srgbRed: 0xf4 / 255, green: 0xf1 / 255, blue: 0xea / 255, alpha: 1)
    static let ink = NSColor(srgbRed: 0x0b / 255, green: 0x0d / 255, blue: 0x1a / 255, alpha: 1)
    static let muted = NSColor(srgbRed: 0x6a / 255, green: 0x68 / 255, blue: 0x78 / 255, alpha: 1)
    static let headlineSize: CGFloat = 124
    static let noteSize: CGFloat = 46
    static let eyebrowSize: CGFloat = 30
    static let topMargin: CGFloat = 104
    static let gap: CGFloat = 76
    static let bottomMargin: CGFloat = 96
    static let sideMargin: CGFloat = 150
}

enum Background: String {
    case paper, aurora, night, stage, ink, inkDots = "ink-dots", brand, tile, sand, gradient, mesh

    var isDark: Bool { [.night, .ink, .inkDots, .brand, .gradient, .mesh].contains(self) }
}

struct Options {
    var headline = ""
    var note: String?
    var output = ""
    var background = Background.aurora
    var accent = hex("#4b3cff")
    var accentSoft = hex("#dcd8ff")
    var colors = [hex("#4b3cff"), hex("#a64dff"), hex("#ff4f9a"), hex("#ffb547")]
    var angle: CGFloat = 135
    var pixelsPerPoint: CGFloat = 2
    var maxScale: CGFloat = 1
    var eyebrow: String?
    var bleed = false
}

func hex(_ text: String, alpha: CGFloat = 1) -> CGColor {
    let value = UInt32(text.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0
    return CGColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                   blue: CGFloat(value & 0xff) / 255, alpha: alpha)
}

/// A soft round glow: `color` at `alpha` in the middle, fading to nothing at `radius`.
func glow(_ context: CGContext, _ color: CGColor, alpha: CGFloat, at center: CGPoint, radius: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let stops = [color.copy(alpha: alpha)!, color.copy(alpha: alpha * 0.45)!, color.copy(alpha: 0)!] as CFArray
    guard let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 0.45, 1]) else { return }
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func dots(_ context: CGContext, _ color: CGColor) {
    context.setFillColor(color)
    let step: CGFloat = 44
    var y = step / 2
    while y < Canvas.size.height {
        var x = step / 2
        while x < Canvas.size.width { context.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)); x += step }
        y += step
    }
}

func flat(_ context: CGContext, _ color: CGColor) {
    context.setFillColor(color)
    context.fill(CGRect(origin: .zero, size: Canvas.size))
}

func drawBackground(_ context: CGContext, _ options: Options) {
    let size = Canvas.size
    let indigo = hex("#4b3cff"), violet = hex("#a64dff"), magenta = hex("#ff4f9a"), amber = hex("#ffb547")
    switch options.background {
    case .paper:
        context.setFillColor(Canvas.paper)
        context.fill(CGRect(origin: .zero, size: size))
    case .aurora:
        context.setFillColor(Canvas.paper)
        context.fill(CGRect(origin: .zero, size: size))
        glow(context, indigo, alpha: 0.30, at: CGPoint(x: size.width * 0.10, y: size.height * 0.20), radius: 1500)
        glow(context, violet, alpha: 0.26, at: CGPoint(x: size.width * 0.42, y: -size.height * 0.10), radius: 1400)
        glow(context, magenta, alpha: 0.26, at: CGPoint(x: size.width * 0.80, y: size.height * 0.08), radius: 1400)
        glow(context, amber, alpha: 0.30, at: CGPoint(x: size.width * 1.02, y: size.height * 0.62), radius: 1300)
    case .night:
        context.setFillColor(hex("#07081a"))
        context.fill(CGRect(origin: .zero, size: size))
        glow(context, indigo, alpha: 0.62, at: CGPoint(x: size.width * 0.08, y: size.height * 0.10), radius: 1700)
        glow(context, violet, alpha: 0.50, at: CGPoint(x: size.width * 0.45, y: -size.height * 0.15), radius: 1500)
        glow(context, magenta, alpha: 0.46, at: CGPoint(x: size.width * 0.86, y: size.height * 0.05), radius: 1500)
        glow(context, amber, alpha: 0.34, at: CGPoint(x: size.width * 1.05, y: size.height * 0.70), radius: 1200)
    case .stage:
        flat(context, options.accentSoft)
        dots(context, options.accent.copy(alpha: 0.18)!)
        glow(context, options.accent, alpha: 0.30, at: CGPoint(x: size.width / 2, y: -size.height * 0.25), radius: 1900)
    case .ink:
        flat(context, hex("#0b0d1a"))
    case .inkDots:
        flat(context, hex("#0b0d1a"))
        dots(context, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09))
    case .brand:
        flat(context, hex("#4b3cff"))
    case .tile:
        flat(context, options.accentSoft)
        dots(context, options.accent.copy(alpha: 0.20)!)
    case .sand:
        flat(context, hex("#ebe7de"))
        dots(context, hex("#0b0d1a", alpha: 0.07))
    case .gradient:
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let gradient = CGGradient(colorsSpace: space, colors: options.colors as CFArray, locations: nil) else { return }
        // The line runs through the middle of the canvas and is long enough to reach both far corners.
        let radians = options.angle * .pi / 180
        let direction = CGPoint(x: cos(radians), y: sin(radians))
        let reach = (abs(direction.x) * size.width + abs(direction.y) * size.height) / 2
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        context.drawLinearGradient(gradient, start: CGPoint(x: middle.x - direction.x * reach, y: middle.y - direction.y * reach),
                                   end: CGPoint(x: middle.x + direction.x * reach, y: middle.y + direction.y * reach),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    case .mesh:
        flat(context, options.colors[0])
        let spots = [CGPoint(x: 0.95, y: 0.95), CGPoint(x: 1.0, y: 0.05), CGPoint(x: 0.05, y: 0.0), CGPoint(x: 0.5, y: 0.45)]
        for (color, spot) in zip(options.colors.dropFirst(), spots) {
            glow(context, color, alpha: 0.95, at: CGPoint(x: size.width * spot.x, y: size.height * spot.y), radius: 1750)
        }
    }
}

struct Placed {
    let image: CGImage
    let origin: CGPoint
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func listWindows() {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { fail("No window list.") }
    // Quick Look's panel floats above layer 0 while Finder is active, so list the low layers, not only the base one.
    for window in windows where (0...20).contains(window[kCGWindowLayer as String] as? Int ?? 99) {
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let rect = [bounds["X"], bounds["Y"], bounds["Width"], bounds["Height"]].map { String(Int($0 ?? 0)) }.joined(separator: ",")
        let fields = [String(window[kCGWindowNumber as String] as? Int ?? 0), window[kCGWindowOwnerName as String] as? String ?? "",
                      rect, window[kCGWindowName as String] as? String ?? "", String(window[kCGWindowLayer as String] as? Int ?? 0)]
        print(fields.joined(separator: "\t"))
    }
}

func load(_ argument: String) -> Placed {
    let parts = argument.split(separator: ":").map(String.init)
    guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { fail("Expected capture.png:x:y, got \(argument)") }
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: parts[0]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Cannot read \(parts[0])") }
    return Placed(image: image, origin: CGPoint(x: x, y: y))
}

func attributed(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineHeightMultiple = 1.02
    return NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        .paragraphStyle: paragraph, .kern: -size * 0.022,
    ])
}

func compose(_ options: Options, captures: [Placed]) {
    let headline = options.headline, note = options.note, output = options.output
    guard !captures.isEmpty else { fail("No captures given.") }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: Int(Canvas.size.width), height: Int(Canvas.size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("No context.") }
    drawBackground(context, options)
    let dark = options.background.isDark
    let ink = dark ? NSColor.white : Canvas.ink
    let muted = dark ? NSColor(white: 1, alpha: 0.88) : Canvas.muted

    // Text is laid out in a flipped AppKit context so lines run top to bottom.
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphics
    let title = attributed(headline.replacingOccurrences(of: "|", with: "\n"), size: Canvas.headlineSize, weight: .bold, color: ink)
    let textWidth = Canvas.size.width - 2 * Canvas.sideMargin
    let titleHeight = ceil(title.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height)
    var cursor = Canvas.size.height - Canvas.topMargin
    if let eyebrow = options.eyebrow, !eyebrow.isEmpty {
        // A capsule label: translucent fill, letterspaced capitals.
        let label = NSAttributedString(string: eyebrow.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: Canvas.eyebrowSize, weight: .semibold), .foregroundColor: ink,
            .kern: Canvas.eyebrowSize * 0.14,
        ])
        let labelSize = label.size()
        let capsule = CGRect(x: (Canvas.size.width - labelSize.width - 64) / 2, y: cursor - 66, width: labelSize.width + 64 - Canvas.eyebrowSize * 0.14, height: 66)
        context.setFillColor(dark ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.20) : CGColor(srgbRed: 0.04, green: 0.05, blue: 0.1, alpha: 0.08))
        context.addPath(CGPath(roundedRect: capsule, cornerWidth: 33, cornerHeight: 33, transform: nil))
        context.fillPath()
        label.draw(at: CGPoint(x: capsule.minX + 32, y: capsule.midY - labelSize.height / 2))
        cursor -= 66 + 34
    }
    cursor -= titleHeight
    context.saveGState()
    if dark { context.setShadow(offset: CGSize(width: 0, height: -6), blur: 34, color: CGColor(srgbRed: 0.05, green: 0.02, blue: 0.2, alpha: 0.28)) }
    title.draw(with: CGRect(x: Canvas.sideMargin, y: cursor, width: textWidth, height: titleHeight), options: [.usesLineFragmentOrigin])
    context.restoreGState()
    if let note, !note.isEmpty {
        let line = attributed(note, size: Canvas.noteSize, weight: .medium, color: muted)
        let height = ceil(line.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).height)
        cursor -= height + 22
        line.draw(with: CGRect(x: Canvas.sideMargin, y: cursor, width: textWidth, height: height), options: [.usesLineFragmentOrigin])
    }

    // The captures keep their relative screen positions (top-left origin) inside the area under the text.
    let frames = captures.map { CGRect(x: $0.origin.x * options.pixelsPerPoint, y: $0.origin.y * options.pixelsPerPoint,
                                       width: CGFloat($0.image.width), height: CGFloat($0.image.height)) }
    let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
    let area = CGRect(x: Canvas.sideMargin, y: Canvas.bottomMargin, width: Canvas.size.width - 2 * Canvas.sideMargin,
                      height: cursor - Canvas.gap - Canvas.bottomMargin)
    let scale = options.bleed ? min(options.maxScale, area.width / union.width)
        : min(options.maxScale, area.width / union.width, area.height / union.height)
    let drawn = CGSize(width: union.width * scale, height: union.height * scale)
    let origin = CGPoint(x: area.midX - drawn.width / 2, y: area.maxY - drawn.height)
    context.interpolationQuality = .high
    for (capture, frame) in zip(captures, frames) {
        let rect = CGRect(x: origin.x + (frame.minX - union.minX) * scale,
                          y: origin.y + drawn.height - (frame.maxY - union.minY) * scale,
                          width: frame.width * scale, height: frame.height * scale)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -44), blur: 120, color: CGColor(srgbRed: 0.03, green: 0.02, blue: 0.12, alpha: dark ? 0.50 : 0.30))
        context.draw(capture.image, in: rect)
        context.restoreGState()
    }
    NSGraphicsContext.current = nil

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("Cannot write \(output)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot write \(output)") }
    print("\(output): \(image.width) x \(image.height), scale \(String(format: "%.3f", scale))")
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("usage: windows | click X Y | compose --headline TEXT [--note TEXT] --output FILE capture.png:x:y ...") }
arguments.removeFirst()
switch command {
case "windows":
    listWindows()
case "click":
    guard arguments.count == 2, let x = Double(arguments[0]), let y = Double(arguments[1]) else { fail("click needs x and y") }
    let point = CGPoint(x: x, y: y)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(120_000)
    }
case "compose":
    var options = Options(), captures: [Placed] = []
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--headline": index += 1; options.headline = arguments[index]
        case "--note": index += 1; options.note = arguments[index]
        case "--output": index += 1; options.output = arguments[index]
        case "--background":
            index += 1
            guard let background = Background(rawValue: arguments[index]) else { fail("Unknown background \(arguments[index])") }
            options.background = background
        case "--accent":
            index += 1
            let pair = arguments[index].split(separator: "/").map(String.init)
            guard pair.count == 2 else { fail("--accent expects \"#saturated/#pastel\"") }
            options.accent = hex(pair[0]); options.accentSoft = hex(pair[1])
        case "--eyebrow": index += 1; options.eyebrow = arguments[index]
        case "--bleed": options.bleed = true
        case "--colors": index += 1; options.colors = arguments[index].split(separator: ",").map { hex(String($0)) }
        case "--angle": index += 1; options.angle = CGFloat(Double(arguments[index]) ?? 135)
        case "--pixels-per-point": index += 1; options.pixelsPerPoint = CGFloat(Double(arguments[index]) ?? 2)
        case "--max-scale": index += 1; options.maxScale = CGFloat(Double(arguments[index]) ?? 1)
        default: captures.append(load(argument))
        }
        index += 1
    }
    guard !options.headline.isEmpty, !options.output.isEmpty else { fail("compose needs --headline and --output") }
    compose(options, captures: captures)
default:
    fail("Unknown command \(command)")
}

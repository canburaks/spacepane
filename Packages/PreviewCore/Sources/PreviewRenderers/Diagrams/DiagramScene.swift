import CoreGraphics
import CoreText
import Foundation

// MARK: - Drawing primitives

/// Geometry of a node, as drawn by `DiagramDrawing`. Parsers choose a shape from the diagram
/// language; the drawing code never inspects the source.
enum DiagramNodeShape: Equatable, Sendable {
    case rectangle, rounded, stadium, circle, doubleCircle, diamond, subroutine, cylinder
    case asymmetric, hexagon, parallelogram, triangle, ellipse
    /// UML initial pseudo-state: a filled dot.
    case startMarker
    /// UML final pseudo-state: a ring around a dot.
    case endMarker
    /// A fork or join bar.
    case bar
    /// A swimlane container: a header band along the top (or left side) and a body.
    case swimlane(header: CGFloat, leftHeader: Bool)
    /// Text with neither fill nor outline.
    case textOnly
    /// A note with a folded corner.
    case note
    /// A UML class or an entity: a header compartment and one or more member compartments.
    case record
}

enum DiagramLineStyle: Equatable, Sendable { case solid, dashed, dotted, thick }
enum DiagramArrowhead: Equatable, Sendable {
    case none, arrow, open, circle, cross, diamond
    /// UML inheritance and realization.
    case hollowTriangle
    /// UML composition.
    case filledDiamond
    /// Entity-relationship cardinalities in crow's foot notation.
    case exactlyOne, zeroOrOne, oneOrMore, zeroOrMore
}
enum DiagramFill: Equatable, Sendable { case none, node, frame, note, solid }
enum DiagramTextAlignment: Equatable, Sendable { case leading, center, trailing }
enum DiagramVerticalAlignment: Equatable, Sendable { case top, middle, bottom }

struct DiagramShapeItem: Equatable, Sendable {
    var rect: CGRect
    var shape: DiagramNodeShape
    var fill: DiagramFill
    var lines: [String]
    var alignment: DiagramTextAlignment = .center
    var verticalAlignment: DiagramVerticalAlignment = .middle
    var isBold = false
    var isDashed = false
    /// False for shapes the document draws without a border (`strokeColor=none`).
    var hasOutline = true
    /// Line counts of a record's compartments: the header first (centered, bold), then members.
    var compartments: [Int] = []
}

struct DiagramFrameItem: Equatable, Sendable {
    var rect: CGRect
    var title: String?
    var isDashed: Bool
    var fill: DiagramFill
}

struct DiagramPathItem: Equatable, Sendable {
    var points: [CGPoint]
    var line: DiagramLineStyle
    var startHead: DiagramArrowhead
    var endHead: DiagramArrowhead
}

/// Free text such as an edge label or a note caption. `hasBackground` paints the label chip so a
/// line crossing it stays readable.
struct DiagramTextItem: Equatable, Sendable {
    var lines: [String]
    var rect: CGRect
    var alignment: DiagramTextAlignment = .center
    var verticalAlignment: DiagramVerticalAlignment = .middle
    var hasBackground = false
    var isBold = false
    var isSmall = false
}

struct DiagramSliceItem: Equatable, Sendable {
    var center: CGPoint
    var radius: CGFloat
    var startAngle: Double
    var endAngle: Double
    var colorIndex: Int
}

struct DiagramSwatchItem: Equatable, Sendable {
    var rect: CGRect
    var colorIndex: Int
}

enum DiagramPrimitive: Equatable, Sendable {
    case frame(DiagramFrameItem)
    case shape(DiagramShapeItem)
    case path(DiagramPathItem)
    case text(DiagramTextItem)
    case slice(DiagramSliceItem)
    case swatch(DiagramSwatchItem)

    /// Conservative bounds in scene coordinates, used for visibility culling.
    var bounds: CGRect {
        switch self {
        case .frame(let item): item.rect.insetBy(dx: -4, dy: -4)
        case .shape(let item): item.rect.insetBy(dx: -4, dy: -4)
        case .text(let item): item.rect.insetBy(dx: -4, dy: -4)
        case .swatch(let item): item.rect.insetBy(dx: -2, dy: -2)
        case .slice(let item):
            CGRect(x: item.center.x - item.radius - 4, y: item.center.y - item.radius - 4,
                   width: item.radius * 2 + 8, height: item.radius * 2 + 8)
        case .path(let item):
            item.points.reduce(into: CGRect.null) { $0 = $0.union(CGRect(origin: $1, size: .zero)) }.insetBy(dx: -12, dy: -12)
        }
    }
}

/// A drawable layout in scene coordinates (origin top-left, y down).
struct DiagramScene: Equatable, Sendable {
    var size: CGSize
    var primitives: [DiagramPrimitive]
    static let empty = DiagramScene(size: .zero, primitives: [])
}

// MARK: - Accessibility facts

enum DiagramNodeRole: String, Equatable, Sendable { case node, state, participant, slice, shape, classType, entity }

struct DiagramAccessibilityNode: Equatable, Sendable {
    var label: String
    var role: DiagramNodeRole
    var rect: CGRect
}

struct DiagramConnection: Equatable, Sendable {
    var source: String
    var target: String
    var label: String?
}

// MARK: - Fonts

/// A text face for diagrams. `name` is the preview font family or PostScript name; `nil`, or a
/// name Core Text cannot resolve, falls back to the system UI font.
public struct DiagramFont: Equatable, Sendable {
    public var name: String?
    public var size: CGFloat
    public init(name: String? = nil, size: CGFloat = 13) {
        self.name = name
        self.size = min(max(size, 6), 72)
    }
    public static let standard = DiagramFont()

    /// The size of secondary text (member rows, small notes): 85% of the label size, never under 6 points. One
    /// formula for drawing (`DiagramDrawing`) and for the legibility floor of a fitted drawing (`DiagramFit`).
    var smallPointSize: CGFloat { max(size * 0.85, 6) }

    func ctFont(size override: CGFloat? = nil, bold: Bool = false) -> CTFont {
        let pointSize = override ?? size
        var base: CTFont
        if let name, !name.isEmpty, Self.resolves(name) {
            base = CTFontCreateWithName(name as CFString, pointSize, nil)
            if bold, let styled = CTFontCreateCopyWithSymbolicTraits(base, pointSize, nil, .traitBold, .traitBold) {
                base = styled
            }
        } else if let system = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, pointSize, nil) {
            base = system
        } else {
            base = CTFontCreateWithName("Helvetica" as CFString, pointSize, nil)
        }
        return base
    }

    /// Core Text substitutes a default face for unknown names, which would hide the fallback, so a
    /// name only counts when the face it returns is named as requested.
    private static func resolves(_ name: String) -> Bool {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        let names = [CTFontCopyPostScriptName(font), CTFontCopyFullName(font), CTFontCopyFamilyName(font)] as [String]
        return names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// Everything a layout depends on besides the diagram itself.
public struct DiagramEnvironment: Equatable, Sendable {
    public var font: DiagramFont
    public var locale: Locale
    public init(font: DiagramFont = .standard, locale: Locale = .current) {
        self.font = font
        self.locale = locale
    }
}

// MARK: - Colors

public struct DiagramColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    public init(rgb: UInt32, alpha: Double = 1) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, alpha: alpha)
    }
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    /// Relative luminance of the sRGB components, enough to tell dark from light backgrounds.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    func mixed(with other: DiagramColor, amount: Double) -> DiagramColor {
        let t = min(max(amount, 0), 1)
        return DiagramColor(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                            blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t)
    }
}

/// The colors a diagram uses. Every role derives from a background and foreground, so a palette
/// built from the preview theme stays legible in light, dark, High Contrast and Increase
/// Contrast appearances; accents carry categories (pie slices) and are never the only cue.
public struct DiagramPalette: Equatable, Sendable {
    public var background: DiagramColor
    public var foreground: DiagramColor
    public var accents: [DiagramColor]
    public var usesColor: Bool
    public var isDark: Bool
    public var isHighContrast: Bool

    public init(background: DiagramColor, foreground: DiagramColor, accents: [DiagramColor] = [],
                usesColor: Bool = true, isHighContrast: Bool = false) {
        self.background = background
        self.foreground = foreground
        self.isDark = background.luminance < 0.5
        self.isHighContrast = isHighContrast
        self.usesColor = usesColor
        self.accents = accents.isEmpty ? Self.defaultAccents(dark: background.luminance < 0.5) : accents
    }

    /// Built-in palettes matching the preview theme's fixed colors.
    public static func standard(isDark: Bool, highContrast: Bool = false) -> DiagramPalette {
        if isDark {
            return DiagramPalette(background: DiagramColor(rgb: highContrast ? 0x000000 : 0x1B1B1B),
                                  foreground: DiagramColor(rgb: highContrast ? 0xFFFFFF : 0xF2F2F2),
                                  isHighContrast: highContrast)
        }
        return DiagramPalette(background: DiagramColor(rgb: 0xFFFFFF),
                              foreground: DiagramColor(rgb: highContrast ? 0x000000 : 0x1A1A1A),
                              isHighContrast: highContrast)
    }

    static func defaultAccents(dark: Bool) -> [DiagramColor] {
        (dark ? [0x8FC4FF, 0xA6D98F, 0xF0B47A, 0xD9ADF5, 0xFFA6A6, 0xBDBDBD]
              : [0x174E94, 0x236328, 0x90430A, 0x6E3288, 0xA02121, 0x626262]).map { DiagramColor(rgb: $0) }
    }

    var nodeFill: DiagramColor { background.mixed(with: foreground, amount: isDark ? 0.10 : 0.06) }
    var nodeStroke: DiagramColor { foreground.mixed(with: background, amount: isHighContrast ? 0 : 0.22) }
    var frameFill: DiagramColor { background.mixed(with: foreground, amount: 0.03) }
    var frameStroke: DiagramColor { foreground.mixed(with: background, amount: isHighContrast ? 0.1 : 0.5) }
    var edge: DiagramColor { foreground.mixed(with: background, amount: isHighContrast ? 0 : 0.18) }
    var labelBackground: DiagramColor { background }
    var noteFill: DiagramColor {
        (usesColor ? (accents.dropFirst(2).first ?? foreground) : foreground)
            .mixed(with: background, amount: isDark ? 0.82 : 0.86)
    }
    var strokeWidth: CGFloat { isHighContrast ? 2 : 1.25 }
    var secondaryText: DiagramColor { foreground.mixed(with: background, amount: isHighContrast ? 0 : 0.25) }

    /// Distinct colors for categories. Beyond the accents, tints continue the cycle; without
    /// color, graduated grays keep neighbouring slices apart.
    func sliceColor(index: Int) -> DiagramColor {
        guard usesColor, !accents.isEmpty else {
            let steps = 5
            return background.mixed(with: foreground, amount: 0.2 + 0.6 * Double(index % steps) / Double(steps - 1))
        }
        let base = accents[index % accents.count]
        let tier = index / accents.count
        return tier == 0 ? base : base.mixed(with: background, amount: min(0.25 * Double(tier), 0.75))
    }
}

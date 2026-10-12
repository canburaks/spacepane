import CoreGraphics
import Foundation

/// The size of a rendered heading, as a modular scale from the configured text size (decision 027, Q-72). Level 6
/// is the body size and each level above it is `ratio` times the one below, so the steps look even at every text
/// size and a reader's larger text enlarges every heading with it. Weight and ink set the lowest level apart.
///
/// Pure arithmetic with no AppKit dependency, so a test measures the whole scale at every size.
enum MarkupHeadingScale {
    /// The last heading level, which sets at the body size.
    static let lowestLevel = 6
    /// One step of the scale: a major second.
    static let ratio: CGFloat = 1.125
    /// No heading is set larger than this, whatever the body size, so a very large text size cannot overflow a pane.
    static let maximumPointSize: CGFloat = 72

    /// How many steps above the body a level sits: five for level 1, none for level 6.
    private static func steps(level: Int) -> Int {
        lowestLevel - min(max(level, 1), lowestLevel)
    }

    /// The size of a level as a multiple of the body size.
    static func multiple(level: Int) -> CGFloat {
        var value: CGFloat = 1
        for _ in 0..<steps(level: level) { value *= ratio }
        return value
    }

    /// The point size of a heading. It never drops below the body size and never exceeds the cap unless the body
    /// itself is larger.
    static func pointSize(level: Int, base: CGFloat) -> CGFloat {
        guard base.isFinite, base > 0 else { return 1 }
        return min(base * multiple(level: level), max(maximumPointSize, base))
    }

    /// Space above a heading, in points: more for the higher levels, so a document's outline reads as sections.
    static func spacingBefore(level: Int, base: CGFloat) -> CGFloat {
        guard base.isFinite, base > 0 else { return 0 }
        return base * (0.35 + 0.1 * CGFloat(steps(level: level)))
    }
}

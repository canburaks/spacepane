import CoreGraphics
import Foundation

/// How a drawing is fitted to the view that shows it, with a floor under the scale so a large diagram is never
/// shrunk into labels nobody can read (decision 027, Q-77). It is a pure function of sizes, so tests check it
/// without a view.
///
/// The whole drawing is shown while the scale that fits all of it keeps the smallest text at or above
/// `legibleLabelPoints`. Below that the drawing is drawn as wide as the view allows, never smaller than the floor
/// and never larger than its natural size, and the rest is reached by dragging or scrolling. In that case the
/// reader is told (`DiagramNotice.readable`): a diagram never shrinks, or stops fitting, without saying so.
struct DiagramFit: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// The whole drawing is shown at its natural size or larger. Nothing is said.
        case natural
        /// The whole drawing is shown, smaller than its natural size but still readable. Nothing is said.
        case shrunk
        /// The whole drawing would be too small to read. It is drawn at a readable scale and continues beyond the view.
        case floored
    }

    /// The smallest size, in points on screen, that the smallest text of a fitted diagram keeps (DM R15: about 7 pt).
    static let legibleLabelPoints: CGFloat = 7
    /// A drawing that fits is never enlarged past this multiple of its natural size.
    static let enlargementLimit: CGFloat = 2

    let scale: CGFloat
    let offset: CGPoint
    let outcome: Outcome

    /// The smallest scale that keeps text set at `font`'s secondary size at least `legibleLabelPoints` tall, and
    /// never more than the natural size: a font that is already that small cannot be kept legible by enlarging
    /// the drawing, so such a drawing is never shrunk at all.
    static func floorScale(for font: DiagramFont, minimumScale: CGFloat) -> CGFloat {
        let smallest = font.smallPointSize
        guard smallest.isFinite, smallest > 0 else { return 1 }
        return min(1, max(legibleLabelPoints / smallest, minimumScale))
    }

    /// Fits a drawing of `content` points into `bounds`, leaving `padding` on every side. A drawing that fits on an
    /// axis is centered on it; one that overflows starts at the leading or top padding, so the reader begins at the
    /// beginning.
    static func make(content: CGSize, bounds: CGSize, padding: CGFloat, font: DiagramFont,
                     minimumScale: CGFloat, maximumScale: CGFloat) -> DiagramFit {
        let width = max(content.width, 1)
        let height = max(content.height, 1)
        let availableWidth = max(bounds.width - padding * 2, 1)
        let availableHeight = max(bounds.height - padding * 2, 1)
        let widthFit = availableWidth / width
        let heightFit = availableHeight / height
        let wholeFit = min(widthFit, heightFit, enlargementLimit)
        let readable = floorScale(for: font, minimumScale: minimumScale)
        let scale: CGFloat
        let outcome: Outcome
        if wholeFit >= readable {
            scale = min(max(wholeFit, minimumScale), maximumScale)
            outcome = scale < 1 ? .shrunk : .natural
        } else {
            // As wide as the view allows, but never below the floor and never magnified.
            scale = min(max(min(max(widthFit, readable), 1), minimumScale), maximumScale)
            outcome = .floored
        }
        let drawnWidth = width * scale
        let drawnHeight = height * scale
        let x = drawnWidth <= availableWidth ? (bounds.width - drawnWidth) / 2 : padding
        let y = drawnHeight <= availableHeight ? (bounds.height - drawnHeight) / 2 : padding
        return DiagramFit(scale: scale, offset: CGPoint(x: x, y: y), outcome: outcome)
    }
}

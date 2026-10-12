import AppKit

/// Which side of the line-number gutter faces the text, for one user interface layout direction (decision 027, Q-161;
/// accessibility review AL18).
///
/// The gutter is pinned to its superview's leading edge and the text pane follows it, so in a left-to-right layout
/// the text is to the right of the gutter and in a right-to-left layout it is to the left. The numbers sit against the
/// text in both: right-aligned in the first and left-aligned in the second, with the hairline on the edge that touches
/// the text and the same padding between the numbers and that edge. Only the gutter's own placement follows the
/// layout direction. The digits stay Western digits in logical order and the source text is never mirrored, because
/// source code does not read right to left.
///
/// This file is the only place that reads `NSView.userInterfaceLayoutDirection`, a documented AppKit property since
/// macOS 10.12 that had no call site in the repository when this was written, so a compile problem with it has one
/// place to fix.
struct LineNumberPlacement: Equatable, Sendable {
    /// True when the text pane is to the left of the gutter.
    let isRightToLeft: Bool

    init(isRightToLeft: Bool) {
        self.isRightToLeft = isRightToLeft
    }

    /// The placement for a layout direction.
    init(_ direction: NSUserInterfaceLayoutDirection) {
        self.init(isRightToLeft: direction == .rightToLeft)
    }

    /// The placement of a gutter in its current layout. The direction that decides where the gutter sits is its
    /// superview's, the view whose leading edge the gutter is pinned to; a gutter that has no superview yet uses its
    /// own direction.
    @MainActor
    init(resolvedFor gutter: NSView) {
        self.init((gutter.superview ?? gutter).userInterfaceLayoutDirection)
    }

    /// The alignment of the numbers inside the gutter: toward the text.
    var alignment: NSTextAlignment { isRightToLeft ? .left : .right }

    /// The x of a number's left edge. `padding` stays between the number and the edge that touches the text, so the
    /// widest number sits exactly `padding` from the hairline in either direction.
    func numberOrigin(width: CGFloat, in bounds: NSRect, padding: CGFloat) -> CGFloat {
        alignment == .left ? bounds.minX + padding : bounds.maxX - padding - width
    }

    /// The hairline between the gutter and the text: `thickness` wide, on the edge that touches the text, as tall as
    /// the dirty rectangle that is being drawn.
    func ruleFrame(in bounds: NSRect, thickness: CGFloat, within dirty: NSRect) -> NSRect {
        let x = isRightToLeft ? bounds.minX : bounds.maxX - thickness
        return NSRect(x: x, y: dirty.minY, width: thickness, height: dirty.height)
    }
}

import SwiftUI

/// Two children side by side when there is room, stacked when there is not.
/// One layout keeps a single identity for each child across the change, so a
/// native preview or a focused control is never rebuilt by resizing the window.
struct AdaptiveColumns: Layout {
    var spacing = CompanionMetrics.columnSpacing
    var breakpoint = CompanionMetrics.columnBreakpoint
    /// Share of the width given to the first child when side by side.
    var leadingFraction: CGFloat = 0.5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = resolvedWidth(proposal.width)
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func resolvedWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return breakpoint }
        return max(proposed, 0)
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        func height(_ subview: LayoutSubview, _ width: CGFloat) -> CGFloat {
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        if subviews.count == 2, width >= breakpoint {
            let leading = ((width - spacing) * leadingFraction).rounded(.down)
            let trailing = width - spacing - leading
            return [CGRect(x: 0, y: 0, width: leading, height: height(subviews[0], leading)),
                    CGRect(x: leading + spacing, y: 0, width: trailing, height: height(subviews[1], trailing))]
        }
        var y: CGFloat = 0
        return subviews.map { subview in
            let frame = CGRect(x: 0, y: y, width: width, height: height(subview, width))
            y = frame.maxY + spacing
            return frame
        }
    }
}

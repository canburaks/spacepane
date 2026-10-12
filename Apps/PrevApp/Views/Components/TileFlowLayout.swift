import SwiftUI

/// Fixed-size tiles wrapped into rows from the leading edge, as many to a row as the width allows. Asked for its
/// ideal width it answers with the narrowest it is useful at, so a `ViewThatFits` can fall back to something
/// else below that. The arithmetic is `AppearanceTileFlow`'s.
struct TileFlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = resolvedWidth(proposal.width)
        return CGSize(width: width, height: AppearanceTileFlow.height(count: subviews.count, width: width))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, AppearanceTileFlow.frames(count: subviews.count, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func resolvedWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return AppearanceTileFlow.minimumWidth }
        return max(proposed, 0)
    }
}

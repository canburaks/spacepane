import SwiftUI

/// The Theme page's three parts, in the order VoiceOver reads them: the controls (which scroll), the sample, and
/// the notes under the sample. From the breakpoint the sample column sits beside the controls; below it the sample
/// is pinned on top and the controls scroll below it, so the sample is on screen at every width. One layout keeps a
/// single identity for each part across the change, so the native preview is never rebuilt by resizing the window.
/// The arithmetic is `AppearancePinnedLayout`'s.
struct PinnedSampleLayout: Layout {
    var spacing = CompanionMetrics.columnSpacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: resolved(proposal.width, ideal: AppearancePinnedLayout.breakpoint),
               height: resolved(proposal.height, ideal: AppearancePinnedLayout.idealHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        // The notes pick how much to say from the height they are offered, so they are asked at that height.
        let frames = AppearancePinnedLayout.frames(in: bounds.size, spacing: spacing) { width, budget in
            subviews[2].sizeThatFits(ProposedViewSize(width: width, height: budget)).height
        }
        let placements = [frames.controls, frames.sample, frames.notes]
        for (subview, frame) in zip(subviews, placements) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func resolved(_ proposed: CGFloat?, ideal: CGFloat) -> CGFloat {
        guard let proposed, proposed.isFinite else { return ideal }
        return max(proposed, 0)
    }
}

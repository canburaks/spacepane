import CoreGraphics

/// Where the Theme page puts its three parts: the controls, the sample and the notes under the sample.
/// From the breakpoint the sample column sits beside the controls; below it the sample is pinned on top and the
/// controls scroll below it. The numbers and the arithmetic live here, away from SwiftUI, so a check can place the
/// parts at any size without a window. `PinnedSampleLayout` is the thin SwiftUI side of this.
enum AppearancePinnedLayout {
    /// Content width, in points, from which the sample sits beside the controls.
    static let breakpoint: CGFloat = 720
    /// The share of the width the sample column takes when side by side. The sample is the wider column, as it
    /// was in the earlier two-column page.
    static let sampleFraction: CGFloat = 0.54
    /// Stacked, the sample region (sample and notes) takes this share of the height, within `stackedHeight`.
    static let stackedShare: CGFloat = 0.5
    static let stackedHeight: ClosedRange<CGFloat> = 200...320
    /// The least height the sample keeps whatever else is asked for: its heading, its two strips and enough
    /// lines to read. The notes under it only get what is left beyond this.
    static let minimumSampleHeight: CGFloat = 190
    /// The least height the scrolling controls keep when stacked.
    static let minimumControlsHeight: CGFloat = 120
    /// The height asked for when a container proposes none.
    static let idealHeight: CGFloat = 520

    /// Where each part goes, in the layout's own coordinates.
    struct Frames: Equatable, Sendable {
        var controls: CGRect
        var sample: CGRect
        var notes: CGRect
    }

    static func isSideBySide(width: CGFloat) -> Bool { width >= breakpoint }

    /// Places the parts in `size`. `notesHeight` answers how tall the notes want to be at a width when they may
    /// use at most a budget; it is asked only when there is a budget, and its answer is held to it.
    static func frames(in size: CGSize, spacing: CGFloat,
                       notesHeight: (_ width: CGFloat, _ budget: CGFloat) -> CGFloat) -> Frames {
        let width = max(size.width, 0)
        let height = max(size.height, 0)
        if isSideBySide(width: width) {
            let controlsWidth = ((width - spacing) * (1 - sampleFraction)).rounded(.down)
            let sampleWidth = width - spacing - controlsWidth
            let sampleX = controlsWidth + spacing
            let notesTall = heldNotes(width: sampleWidth, budget: height - minimumSampleHeight - spacing,
                                      ask: notesHeight)
            let notesBlock = notesTall > 0 ? notesTall + spacing : 0
            return Frames(
                controls: CGRect(x: 0, y: 0, width: controlsWidth, height: height),
                sample: CGRect(x: sampleX, y: 0, width: sampleWidth, height: height - notesBlock),
                notes: CGRect(x: sampleX, y: height - notesTall, width: sampleWidth, height: notesTall))
        }
        let preferred = min(max(height * stackedShare, stackedHeight.lowerBound), stackedHeight.upperBound)
        let region = min(preferred, max(height - minimumControlsHeight - spacing, 0))
        let notesTall = heldNotes(width: width, budget: region - minimumSampleHeight - spacing, ask: notesHeight)
        let notesBlock = notesTall > 0 ? notesTall + spacing : 0
        let sampleHeight = region - notesBlock
        let controlsY = min(region + spacing, height)
        return Frames(
            controls: CGRect(x: 0, y: controlsY, width: width, height: max(height - controlsY, 0)),
            sample: CGRect(x: 0, y: 0, width: width, height: sampleHeight),
            notes: CGRect(x: 0, y: sampleHeight + (notesTall > 0 ? spacing : 0), width: width, height: notesTall))
    }

    /// The notes' height held to its budget; nothing is asked when there is no budget.
    private static func heldNotes(width: CGFloat, budget: CGFloat,
                                  ask: (_ width: CGFloat, _ budget: CGFloat) -> CGFloat) -> CGFloat {
        guard budget > 0 else { return 0 }
        return min(max(ask(width, budget), 0), budget)
    }
}

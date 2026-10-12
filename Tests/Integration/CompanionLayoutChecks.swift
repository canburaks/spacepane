import CoreGraphics

private struct LayoutCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// Characterizes the pure arithmetic used by Theme's pinned sample and palette tiles. It creates no window
/// and cannot establish actual SwiftUI layout, accessibility order or translated label fit.
enum CompanionLayoutChecks {
    static func run() throws {
        try wideLayoutKeepsTheSampleBesideTheControls()
        try narrowLayoutPinsTheSampleAboveTheControls()
        try notesCannotConsumeTheSample()
        try framesStayInsideFiniteProposals()
        try tilesWrapAtTheirActualWidth()
        try emptyAndUnboundedTileProposalsAreSafe()
        print("Passed 6 companion layout checks (pure frames; no window or accessibility validation).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw LayoutCheckFailure(description: message) }
    }

    private static func wideLayoutKeepsTheSampleBesideTheControls() throws {
        var requested: [(CGFloat, CGFloat)] = []
        let frames = AppearancePinnedLayout.frames(in: CGSize(width: 1_000, height: 600), spacing: 20) {
            requested.append(($0, $1))
            return 80
        }
        try check(frames.controls == CGRect(x: 0, y: 0, width: 450, height: 600),
                  "Wide controls must use the smaller column and the full height")
        try check(frames.sample == CGRect(x: 470, y: 0, width: 530, height: 500),
                  "The sample must remain at the top of the wider column")
        try check(frames.notes == CGRect(x: 470, y: 520, width: 530, height: 80),
                  "Notes must be below the sample, with one gap")
        try check(requested.count == 1 && requested[0].0 == 530 && requested[0].1 == 390,
                  "Notes must be measured once at the sample width and their available height")
        try check(!AppearancePinnedLayout.isSideBySide(width: 719)
                  && AppearancePinnedLayout.isSideBySide(width: 720),
                  "The recorded Theme breakpoint must switch at 720 points")
    }

    private static func narrowLayoutPinsTheSampleAboveTheControls() throws {
        let frames = AppearancePinnedLayout.frames(in: CGSize(width: 500, height: 520), spacing: 20) { _, _ in 50 }
        try check(frames.sample == CGRect(x: 0, y: 0, width: 500, height: 190),
                  "At a narrow width the sample must remain pinned above the scrolling controls")
        try check(frames.notes == CGRect(x: 0, y: 210, width: 500, height: 50)
                  && frames.controls == CGRect(x: 0, y: 280, width: 500, height: 240),
                  "Notes and controls must follow the sample without overlapping it")
        let tall = AppearancePinnedLayout.frames(in: CGSize(width: 500, height: 1_000), spacing: 20) { _, _ in 0 }
        try check(tall.sample.height == 320 && tall.controls.minY == 340 && tall.controls.height == 660,
                  "A tall narrow page must cap the pinned region and leave the rest for controls")
    }

    private static func notesCannotConsumeTheSample() throws {
        var calls = 0
        let cramped = AppearancePinnedLayout.frames(in: CGSize(width: 500, height: 420), spacing: 20) { _, _ in
            calls += 1
            return 10_000
        }
        try check(calls == 0 && cramped.notes.height == 0 && cramped.sample.height == 210,
                  "Notes must not be measured or shown when they have no height budget")
        for width in [500, 1_000] as [CGFloat] {
            let height: CGFloat = width < 720 ? 440 : 211
            let capped = AppearancePinnedLayout.frames(in: CGSize(width: width, height: height), spacing: 20) { _, _ in 10_000 }
            try check(capped.sample.height == 190 && capped.notes.height > 0,
                      "Oversized notes must leave the sample's minimum height at width \(width)")
            let refused = AppearancePinnedLayout.frames(in: CGSize(width: width, height: 600), spacing: 20) { _, _ in -50 }
            try check(refused.notes.height == 0, "A negative note measurement must be treated as no notes")
        }
    }

    private static func framesStayInsideFiniteProposals() throws {
        for width in [-10, 0, 100, 480, 719, 720, 1_024] as [CGFloat] {
            for height in [-10, 0, 80, 260, 520, 900] as [CGFloat] {
                for notes in [-30, 0, 80, 10_000] as [CGFloat] {
                    let frames = AppearancePinnedLayout.frames(in: CGSize(width: width, height: height), spacing: 20) { _, _ in notes }
                    for frame in [frames.controls, frames.sample, frames.notes] {
                        try check(frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite,
                                  "Finite proposals must produce finite frames")
                        try check(frame.minX >= 0 && frame.minY >= 0 && frame.width >= 0 && frame.height >= 0
                                  && frame.maxX <= max(width, 0) && frame.maxY <= max(height, 0),
                                  "Every part must stay within the clamped proposal: \(width) × \(height), \(frame)")
                    }
                    if width >= 720 {
                        try check(frames.controls.maxX + 20 == frames.sample.minX,
                                  "Wide controls and sample must keep one horizontal gap")
                    } else {
                        try check(frames.controls.minY >= frames.sample.maxY && frames.controls.minY >= frames.notes.maxY,
                                  "Stacked controls must never cover the pinned sample or notes")
                    }
                }
            }
        }
    }

    private static func tilesWrapAtTheirActualWidth() throws {
        try check(AppearanceTileFlow.minimumWidth == 268,
                  "The narrow-menu fallback must reserve room for three 84-point tiles and their gaps")
        try check(AppearanceTileFlow.columns(forWidth: 267) == 2
                  && AppearanceTileFlow.columns(forWidth: 268) == 3,
                  "The third tile must fit exactly at the gallery's minimum width")
        let frames = AppearanceTileFlow.frames(count: 5, width: 268)
        try check(frames == [CGRect(x: 0, y: 0, width: 84, height: 76),
                            CGRect(x: 92, y: 0, width: 84, height: 76),
                            CGRect(x: 184, y: 0, width: 84, height: 76),
                            CGRect(x: 0, y: 84, width: 84, height: 76),
                            CGRect(x: 92, y: 84, width: 84, height: 76)],
                  "Tiles must wrap in presentation order from the leading edge")
        try check(AppearanceTileFlow.height(count: 5, width: 268) == 160
                  && AppearanceTileFlow.height(count: 5, width: 267) == 244,
                  "The proposed gallery height must include all rows and only the gaps between rows")
        for width in [84, 176, 268, 720] as [CGFloat] {
            let wrapped = AppearanceTileFlow.frames(count: 12, width: width)
            try check(wrapped.count == 12 && wrapped.allSatisfy { $0.maxX <= width },
                      "Every tile must fit a usable row width without dropping a tile")
            try check(wrapped.last?.maxY == AppearanceTileFlow.height(count: 12, width: width),
                      "The last row must end at the proposed height")
        }
    }

    private static func emptyAndUnboundedTileProposalsAreSafe() throws {
        for count in [-1, 0] {
            try check(AppearanceTileFlow.frames(count: count, width: 268).isEmpty
                      && AppearanceTileFlow.height(count: count, width: 268) == 0,
                      "An empty or invalid tile count must occupy no space")
        }
        for width in [-1, 0, .nan, .infinity, -.infinity] as [CGFloat] {
            try check(AppearanceTileFlow.columns(forWidth: width) == 1,
                      "A missing or invalid width must fall back to one column")
            let frames = AppearanceTileFlow.frames(count: 2, width: width)
            try check(frames.map(\.minX) == [0, 0] && frames.map(\.minY) == [0, 84],
                      "Fallback columns must retain finite, ordered tile positions")
        }
        try check(AppearanceTileFlow.columns(forWidth: .greatestFiniteMagnitude)
                  == AppearanceTileFlow.columns(forWidth: 100_000),
                  "A width beyond any screen must be capped before conversion to an integer")
    }
}

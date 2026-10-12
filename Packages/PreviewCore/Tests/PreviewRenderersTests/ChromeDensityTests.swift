import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Density is decided from the preview's own width with hysteresis (decision 027, Q-46). The threshold is a
/// placeholder until Wave 1 measures Finder panes, so these tests are written against `PreviewChrome`'s own constants
/// and never against a literal width.
@Suite("Chrome density", .serialized)
@MainActor
struct ChromeDensityTests {
    private var low: CGFloat { PreviewChrome.compactWidth - PreviewChrome.compactHysteresis }
    private var high: CGFloat { PreviewChrome.compactWidth + PreviewChrome.compactHysteresis }

    // MARK: The pure function

    @Test func aRegularViewBecomesCompactOnlyBelowTheLowerEdge() {
        #expect(PreviewChrome.density(forWidth: low, previous: .regular) == .regular)
        #expect(PreviewChrome.density(forWidth: low - 1, previous: .regular) == .compact)
        #expect(PreviewChrome.density(forWidth: PreviewChrome.compactWidth, previous: .regular) == .regular)
        #expect(PreviewChrome.density(forWidth: 1, previous: .regular) == .compact)
    }

    @Test func aCompactViewBecomesRegularOnlyFromTheUpperEdge() {
        #expect(PreviewChrome.density(forWidth: high - 1, previous: .compact) == .compact)
        #expect(PreviewChrome.density(forWidth: high, previous: .compact) == .regular)
        #expect(PreviewChrome.density(forWidth: PreviewChrome.compactWidth, previous: .compact) == .compact)
        #expect(PreviewChrome.density(forWidth: 4_000, previous: .compact) == .regular)
    }

    @Test func insideTheBandADensityIsKeptWhicheverWayTheWidthMoves() {
        // Every width between the edges keeps what the view already has, so a drag back and forth never flickers.
        var width = low
        while width < high {
            #expect(PreviewChrome.density(forWidth: width, previous: .regular) == .regular, "regular at \(width)")
            if width < high - 1 {
                #expect(PreviewChrome.density(forWidth: width, previous: .compact) == .compact, "compact at \(width)")
            }
            width += 4
        }
    }

    @Test func aViewWithoutAWidthKeepsItsDensity() {
        for previous in [PreviewChrome.Density.compact, .regular] {
            #expect(PreviewChrome.density(forWidth: 0, previous: previous) == previous)
            #expect(PreviewChrome.density(forWidth: -20, previous: previous) == previous)
        }
    }

    @Test func theBandIsWideEnoughToAbsorbAScrollerAndStillNarrowerThanTheThreshold() {
        #expect(PreviewChrome.compactHysteresis >= 16)
        #expect(low > 0 && high > PreviewChrome.compactWidth)
    }

    // MARK: The view

    private func makeView(width: CGFloat) -> NativePreviewView {
        NativePreviewView(frame: NSRect(x: 0, y: 0, width: width, height: 420))
    }

    /// Lays the view out as its host would, even when nothing has invalidated it yet.
    private func settle(_ view: NativePreviewView) {
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    private func resize(_ view: NativePreviewView, to width: CGFloat) {
        view.setFrameSize(NSSize(width: width, height: 420))
        settle(view)
    }

    @Test func aViewStartsRegularAndFollowsItsOwnWidthWithHysteresis() {
        let view = makeView(width: 800)
        settle(view)
        #expect(view.density == .regular)
        resize(view, to: low - 10)
        #expect(view.density == .compact)
        // Back inside the band: still compact.
        resize(view, to: PreviewChrome.compactWidth)
        #expect(view.density == .compact)
        resize(view, to: high + 10)
        #expect(view.density == .regular)
        // And inside the band again: still regular.
        resize(view, to: PreviewChrome.compactWidth)
        #expect(view.density == .regular)
    }

    @Test func aDisplayDecidesDensityBeforeAnyLayout() {
        let narrow = makeView(width: low - 30)
        narrow.display(.ready(plainPresentation("safe words")))
        #expect(narrow.density == .compact)
        let wide = makeView(width: high + 30)
        wide.display(.ready(plainPresentation("safe words")))
        #expect(wide.density == .regular)
        // A view with no size yet (a representable before its host lays it out) stays regular.
        let unsized = NativePreviewView(frame: .zero)
        unsized.display(.ready(plainPresentation("safe words")))
        #expect(unsized.density == .regular)
    }

    @Test func aHostCanForceADensityAndLetGoOfIt() {
        let view = makeView(width: low - 60)
        settle(view)
        #expect(view.density == .compact)
        view.forcedDensity = .regular
        #expect(view.density == .regular)
        // A forced density ignores every width.
        resize(view, to: 200)
        #expect(view.density == .regular)
        view.forcedDensity = nil
        #expect(view.density == .compact)
        view.forcedDensity = .compact
        resize(view, to: high + 200)
        #expect(view.density == .compact)
        view.forcedDensity = nil
        #expect(view.density == .regular)
    }

    @Test func theThemeSamplePaneCarriesTheForcedDensityAndTheOldEntryPointStillWorks() {
        let sample = NativePreviewPane(outcome: nil, isLoading: true, typography: .init(), generation: UUID(),
                                       forcedDensity: .regular)
        #expect(sample.forcedDensity == .regular && sample.outcome == nil && sample.isLoading)
        let earlier = NativePreviewPane(outcome: .cancelled, typography: .init(), generation: UUID())
        #expect(earlier.outcome == .cancelled && !earlier.isLoading && earlier.forcedDensity == nil)
        let named = NativePreviewPane(outcome: .cancelled, typography: .init(), generation: UUID(), providerName: "X",
                                      forcedDensity: .compact)
        #expect(named.providerName == "X" && named.forcedDensity == .compact)
    }

    // MARK: Metrics that other files must agree with

    @Test func theAccessoryBarAndTheChromeShareOneHeight() {
        #expect(PreviewAccessoryBar.height == PreviewChrome.accessoryHeight)
        #expect(PreviewChrome.inset > PreviewChrome.gap && PreviewChrome.gap > PreviewChrome.rowGap)
        #expect(PreviewChrome.spinnerDelay < PreviewChrome.chipDuration)
    }
}

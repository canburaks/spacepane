import AppKit

/// The one owner of the preview chrome's geometry, timing and type sizes. The header, the findings row, the bars,
/// the state view, the chip and the limits slot read their insets, gaps and delays from here instead of repeating
/// literals (decision 027, Q-33 and Q-46). Every value is a target until a Mac measures real Finder panes.
@MainActor
public enum PreviewChrome {
    /// How much room the host gives the preview: the full header at regular width, a reduced one when compact.
    public enum Density: Equatable, Sendable { case compact, regular }

    /// The side inset of every chrome row, and of the text container.
    static let inset: CGFloat = 12
    /// The standard gap between chrome bands, and the margin above the first one.
    static let gap: CGFloat = 8
    /// The gap between items of one row, and between stacked rows inside a band.
    static let rowGap: CGFloat = 6
    /// The height the header row, mode control included, is designed to stay within (gate 1). The row itself takes
    /// the control's intrinsic height, so this is a target a Mac checks, not a constraint.
    static let headerHeight: CGFloat = 28
    /// The Go to Line and outline filter bars.
    static let accessoryHeight: CGFloat = 30
    /// The MIDI transport strip that sits between the findings and the content.
    static let midiStripHeight: CGFloat = 90
    /// The most of the view the findings row may take when expanded (used by the findings row of Wave 3).
    static let findingsMaximumFraction: CGFloat = 0.25
    /// The information disclosure button and its maximum inline panel height.
    static let infoButtonSide: CGFloat = 22
    static let infoMaximumFraction: CGFloat = 0.25

    /// The width reserved beside the info badge for the chip, so the chip appearing or disappearing never moves
    /// the mode control. Wide enough for the longest shipped "Copied" at the chip's type size. It is a preference,
    /// not a floor: in a row too narrow to keep the mode control at its natural width or the notes at
    /// `notesMinimumWidth`, the slot gives way (see the priorities below) and a chip shown there overlaps the end of
    /// the row for as long as it shows.
    static let chipSlotWidth: CGFloat = 104
    /// The least width the notes keep when they share the first row with the info badge. A narrow preview would
    /// otherwise let the reserved slot squeeze the notes into a sliver, whose wrapped height pushes the content out
    /// of view.
    static let notesMinimumWidth: CGFloat = 140
    /// How hard each header item holds its width in the first row, strongest first: the notes floor, the mode
    /// control's natural width (the system's own 750), the chip's reserved slot, then the notes' natural width.
    /// The slot yields to the notes floor and to the control; the notes wrap before they push the slot away.
    static let notesFloorPriority = NSLayoutConstraint.Priority(900)
    static let chipSlotPriority = NSLayoutConstraint.Priority(500)
    static let notesNaturalWidthPriority = NSLayoutConstraint.Priority(200)
    /// The space between the chip's text and its outline.
    static let chipPadding: CGFloat = 6
    static let chipCornerRadius: CGFloat = 4
    /// How long the "Copied" chip stays before the zoom level, or nothing, takes its place.
    static let chipDuration: Duration = .milliseconds(1_500)
    /// How long a loading state waits before it draws anything, so a preview that is ready quickly never flashes it.
    static let spinnerDelay: Duration = .milliseconds(300)

    /// The widest a state's title and body grow before they wrap, so a long sentence stays readable on a wide pane.
    static let stateMaximumWidth: CGFloat = 360
    /// The point size of a state's symbol.
    static let stateSymbolPointSize: CGFloat = 28

    /// Narrower than this the view is compact. A placeholder: Wave 1 records the Finder preview widths (the panel's
    /// default and minimum size, the preview pane, the column and gallery views, full screen) and sets it.
    static var compactWidth: CGFloat { 480 }
    /// Half the width of the band around `compactWidth` in which a view keeps the density it already has.
    static let compactHysteresis: CGFloat = 24

    /// The density for a view `width` points wide. It becomes compact below `compactWidth - compactHysteresis` and
    /// regular again from `compactWidth + compactHysteresis`; in between it keeps `previous`, so a drag across the
    /// threshold, or a scroller appearing, never flickers the chrome. A view with no width yet (a representable
    /// before its host lays it out) says nothing about the host and keeps `previous`.
    static func density(forWidth width: CGFloat, previous: Density) -> Density {
        guard width > 0 else { return previous }
        switch previous {
        case .regular: return width < compactWidth - compactHysteresis ? .compact : .regular
        case .compact: return width >= compactWidth + compactHysteresis ? .regular : .compact
        }
    }

    /// The size of quiet text: notes, limits and the chip, and the line numbers where the scheme's muted ink cannot
    /// set them apart from the text by lightness alone (`NativeTextPalette.mutedUsesSizeCue`).
    static let mutedPointSize: CGFloat = 11

    /// Notes, limits and the chip.
    static func factsFont() -> NSFont { .systemFont(ofSize: mutedPointSize) }
    static func stateTitleFont() -> NSFont { .systemFont(ofSize: 15, weight: .semibold) }
    static func stateBodyFont() -> NSFont { .systemFont(ofSize: 13) }
}

/// The chrome's only source of delays: the loading state's grace period and the chip's lifetime. The default waits
/// with `Task.sleep`; tests substitute a scheduler that runs actions by hand, so no test waits on wall time.
@MainActor
protocol ChromeScheduler: AnyObject {
    /// Runs `action` once, on the main actor, after `delay`. Cancelling the returned handle first means it never runs.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ChromeScheduledAction
}

/// A scheduled action that can still be cancelled.
@MainActor
struct ChromeScheduledAction {
    private let cancelAction: @MainActor () -> Void

    init(cancel: @escaping @MainActor () -> Void) { cancelAction = cancel }

    func cancel() { cancelAction() }
}

/// The production scheduler: one sleeping task per action, cancelled with its handle.
@MainActor
final class TaskChromeScheduler: ChromeScheduler {
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ChromeScheduledAction {
        // The task holds the action through a main-actor object, so nothing non-Sendable crosses into it.
        let pending = PendingChromeAction(action)
        let task = Task { @MainActor in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            pending.run()
        }
        return ChromeScheduledAction(cancel: { task.cancel() })
    }
}

/// An action waiting for its delay; running it twice runs it once.
@MainActor
private final class PendingChromeAction {
    private var action: (@MainActor () -> Void)?

    init(_ action: @escaping @MainActor () -> Void) { self.action = action }

    func run() {
        let current = action
        action = nil
        current?()
    }
}

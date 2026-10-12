import AppKit
import Foundation
import PreviewContracts
@testable import PreviewRenderers

/// A scheduler the chrome tests run by hand: nothing is delayed and nothing waits on wall time. It records what
/// was scheduled, with its delay, and runs only what is still waiting when a test says the delay has passed.
@MainActor
final class ManualChromeScheduler: ChromeScheduler {
    /// One scheduled action.
    @MainActor
    final class Pending {
        let delay: Duration
        private let action: @MainActor () -> Void
        private(set) var isCancelled = false
        private(set) var hasRun = false

        init(delay: Duration, action: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.action = action
        }

        var isWaiting: Bool { !isCancelled && !hasRun }

        func cancel() { isCancelled = true }

        /// Runs the action as the clock would, unless it was cancelled or already ran.
        func run() {
            guard isWaiting else { return }
            hasRun = true
            action()
        }

        /// Runs the action even if it was cancelled, to stand in for a late timer that fires after a replacement.
        func runIgnoringCancellation() {
            hasRun = true
            action()
        }
    }

    private(set) var scheduled: [Pending] = []

    /// The actions that would still run.
    var waiting: [Pending] { scheduled.filter(\.isWaiting) }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> ChromeScheduledAction {
        let pending = Pending(delay: delay, action: action)
        scheduled.append(pending)
        return ChromeScheduledAction(cancel: { pending.cancel() })
    }

    /// Lets every waiting delay pass.
    func runWaiting() {
        for pending in waiting { pending.run() }
    }
}

/// The default palette of a light system appearance, for views that take a palette directly.
@MainActor
func chromeTestPalette() -> NativeTextPalette {
    NativeTextPalette(theme: .system, isDark: false, increasedContrast: false)
}

import AppKit

/// Answers the application's request to quit. SwiftUI offers no hook for Command-Q while the window is active, so
/// the quit asks the settings store to finish the save it has in flight first (bounded; see
/// `CompanionSettings.prepareToQuit`). `FlushSaveWhenInactive` covers the other ways the app stops being active.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    /// Handed over by the scene once the window exists. With none, a quit has nothing to wait for.
    var settings: CompanionSettings?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let settings else { return .terminateNow }
        let mayQuitNow = settings.prepareToQuit { sender.reply(toApplicationShouldTerminate: true) }
        return mayQuitNow ? .terminateNow : .terminateLater
    }
}

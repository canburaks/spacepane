import SwiftUI

/// Drains a pending settings save when the scene stops being the active one (another app comes forward, the window
/// is hidden or closed), so the last choice is on disk before the app can be quit. This is the repository's first
/// use of the scene phase, so it stays behind this one modifier. It does not run on a Command-Q made while the
/// window is active; `CompanionAppDelegate` holds that quit until the save has finished.
struct FlushSaveWhenInactive: ViewModifier {
    let settings: CompanionSettings
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) {
            if scenePhase != .active { Task { _ = await settings.flushPendingSave() } }
        }
    }
}

extension View {
    func flushesSaveWhenInactive(_ settings: CompanionSettings) -> some View {
        modifier(FlushSaveWhenInactive(settings: settings))
    }
}

import Foundation
import Observation

/// Companion-only choices. They never enter the shared extension snapshot, so
/// previews and thumbnails behave identically whatever is selected here.
@MainActor @Observable
final class CompanionPreferences {
    private enum Key: String {
        case developerMode = "companion.developerMode"
        case lastRoute = "companion.lastRoute"
    }

    /// Off by default. Reveals developer destinations such as Try Preview.
    private(set) var developerMode: Bool
    /// The page shown last, so the window opens where the user left it. Stored by the route's raw value.
    private(set) var lastRoute: CompanionRoute
    @ObservationIgnored private let defaults: UserDefaults

    /// Checks pass an isolated suite instead of the user's defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        developerMode = defaults.bool(forKey: Key.developerMode.rawValue)
        // A missing or unknown value opens the first page.
        lastRoute = defaults.string(forKey: Key.lastRoute.rawValue).flatMap(CompanionRoute.init(rawValue:)) ?? .general
    }

    func setDeveloperMode(_ enabled: Bool) {
        guard enabled != developerMode else { return }
        developerMode = enabled
        defaults.set(enabled, forKey: Key.developerMode.rawValue)
    }

    /// The page the window opens on: the last one shown, unless it is no longer offered.
    var restoredRoute: CompanionRoute { lastRoute.resolved(developerMode: developerMode) }

    func setLastRoute(_ route: CompanionRoute) {
        guard route != lastRoute else { return }
        lastRoute = route
        defaults.set(route.rawValue, forKey: Key.lastRoute.rawValue)
    }
}

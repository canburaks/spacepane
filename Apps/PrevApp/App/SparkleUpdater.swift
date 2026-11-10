import Foundation
import Observation
#if PREV_INCLUDE_SPARKLE
import Sparkle
#endif

/// Owns the Sparkle 2 updater controller for direct-distribution builds of the companion app.
@MainActor @Observable
final class SparkleUpdater {
    private(set) var canCheckForUpdates = false
    var automaticallyChecksForUpdates = false {
        didSet {
            #if PREV_INCLUDE_SPARKLE
            if controller.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
                controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
            #endif
        }
    }

    #if PREV_INCLUDE_SPARKLE
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var autoCheckObservation: NSKeyValueObservation?
    #endif

    init(startingUpdater: Bool = true) {
        #if PREV_INCLUDE_SPARKLE
        let controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        self.canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let newValue = change.newValue
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.canCheckForUpdates = newValue ?? self.controller.updater.canCheckForUpdates
            }
        }
        self.autoCheckObservation = controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let newValue = change.newValue
            Task { @MainActor [weak self] in
                guard let self else { return }
                let value = newValue ?? self.controller.updater.automaticallyChecksForUpdates
                if self.automaticallyChecksForUpdates != value {
                    self.automaticallyChecksForUpdates = value
                }
            }
        }
        #endif
    }

    func checkForUpdates() {
        #if PREV_INCLUDE_SPARKLE
        controller.checkForUpdates(nil)
        #endif
    }
}

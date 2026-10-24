import Foundation

/// The license-notice folders a build copies into the app's Resources, and where each one is in this run.
///
/// A folder name is a technical identifier written by the build, not display text: Xcode builds create the
/// folders in `script/embed_cad_worker.py` (declared in the file lists by `script/build_cad_worker.py`) and the
/// local prototype in `script/stage_companion.py`. `script/test_build_cad_worker.py` fails when these names and
/// the scripts drift apart. A run that was not staged, such as a development run, has no folder and reports it
/// as absent; the About page then leaves the row out instead of offering a button that cannot work.
struct BundledNotices: Sendable {
    enum Folder: String, CaseIterable, Sendable {
        /// Palette attributions for the built-in color schemes (`ThirdPartyNotices/ColorSchemes`).
        case colorSchemes = "ColorSchemes-Notices"
    }

    private let locations: [Folder: URL]

    /// A fixed set of locations, for checks that must not depend on the bundle they run in.
    init(locations: [Folder: URL]) { self.locations = locations }

    init(bundle: Bundle = .main) {
        var found: [Folder: URL] = [:]
        for folder in Folder.allCases {
            if let url = bundle.url(forResource: folder.rawValue, withExtension: nil) { found[folder] = url }
        }
        locations = found
    }

    /// Where `folder` is inside the bundle, or nil when this run does not carry it.
    func url(for folder: Folder) -> URL? { locations[folder] }
}

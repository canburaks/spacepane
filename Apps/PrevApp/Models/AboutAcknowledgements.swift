import Foundation

/// What the About page's Acknowledgements card shows in this run, decided by the notice folders the build carries.
///
/// The product links no third-party library, so the card names only the color-scheme palettes; their row appears
/// when that folder is present. Since 2026-10-24 the card has no Open CASCADE text, open-source link or license row
/// that a build with the 3D CAD helper would reveal: a section that only appears in another build is a hidden
/// feature in App Review's terms (Guidelines 2.5.19 and 5.6). Bringing CAD back adds them again (decision 028).
struct AboutAcknowledgements: Equatable, Sendable {
    /// Where the color-scheme attributions are, or nil when this run is not a staged build.
    let colorSchemeNotices: URL?

    init(notices: BundledNotices) {
        colorSchemeNotices = notices.url(for: .colorSchemes)
    }
}

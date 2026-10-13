import Foundation

/// What the About page's Acknowledgements card shows in this run, decided by the notice folders the build carries.
///
/// The Open CASCADE text, the "Open-source notices" link (which leads to the public source of the 3D import helper
/// and the written offer for the library source) and the Open CASCADE license row all describe one thing: a build
/// that links Open CASCADE. A build without it, such as version 1.0, carries no `OCCT-Notices` folder and shows
/// none of the four, so the card never promises a library the app does not contain. The color-scheme sentence is
/// true of every build; its row appears when that folder is present. The same code is right in both kinds of build.
struct AboutAcknowledgements: Equatable, Sendable {
    /// Where the Open CASCADE license texts are, or nil when this run carries no Open CASCADE.
    let openCascadeNotices: URL?
    /// Where the color-scheme attributions are, or nil when this run is not a staged build.
    let colorSchemeNotices: URL?

    init(notices: BundledNotices) {
        openCascadeNotices = notices.url(for: .openCascade)
        colorSchemeNotices = notices.url(for: .colorSchemes)
    }

    /// The Open CASCADE paragraphs, the open-source link and the license row appear together or not at all.
    var includesOpenCascade: Bool { openCascadeNotices != nil }
}

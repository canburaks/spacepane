import PreviewContracts

/// One color scheme reduced to the few colors a picker tile draws: the background, body ink, four of the syntax roles
/// and the muted ink (decision 027, Q-100; companion review C9). It is the public, read-only window onto the internal
/// palettes, so the companion draws a tile from the same sRGB values the preview resolves, never a copy that can drift
/// and never a live preview pane. Nothing here reads a file.
///
/// Values are `0xRRGGBB`, as the palettes store them. A swatch describes one scheme in one appearance: the palette
/// that `NativeColorSchemes.palette(for:dark:highContrast:)` returns for it, so a scheme that does not exist for the
/// appearance shows Standard's colors under Standard's id, and High Contrast (or the system Increase Contrast setting)
/// shows the two Standard High Contrast palettes whatever the scheme, with `isHighContrast` true so a tile can say so.
public struct PreviewSchemeSwatch: Equatable, Sendable, Identifiable {
    /// The scheme these colors belong to: the requested one, or `.standard` when the request is not available for
    /// the appearance. Under High Contrast it is still the requested scheme, so a picker keeps showing which scheme
    /// is selected even though every tile then draws the same two palettes.
    public let id: PreviewColorSchemeID
    public let background: UInt32
    public let foreground: UInt32
    public let keyword: UInt32
    public let string: UInt32
    public let number: UInt32
    public let comment: UInt32
    public let muted: UInt32
    /// True when the colors are the Standard High Contrast palette that replaces every scheme.
    public let isHighContrast: Bool

    /// The swatch of one scheme for a light (`dark` false) or dark appearance.
    public static func swatch(for id: PreviewColorSchemeID, dark: Bool, highContrast: Bool) -> PreviewSchemeSwatch {
        let palette = NativeColorSchemes.palette(for: id, dark: dark, highContrast: highContrast)
        let resolved = id.isAvailable(for: dark ? .dark : .light) ? id : .standard
        return PreviewSchemeSwatch(
            id: resolved, background: palette.background, foreground: palette.foreground,
            keyword: palette.keyword, string: palette.string, number: palette.number,
            comment: palette.comment, muted: palette.muted, isHighContrast: highContrast)
    }

    /// The schemes a picker offers for one appearance, Standard first and then in the order of
    /// `PreviewColorSchemeID.choices(for:)`: five for a light appearance and seven for a dark one, twelve tiles when
    /// a gallery shows both rows.
    public static func gallery(dark: Bool, highContrast: Bool) -> [PreviewSchemeSwatch] {
        PreviewColorSchemeID.choices(for: dark ? .dark : .light).map {
            swatch(for: $0, dark: dark, highContrast: highContrast)
        }
    }
}

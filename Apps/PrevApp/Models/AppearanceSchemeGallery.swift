import PreviewContracts
import PreviewRenderers

/// One tile of the color scheme gallery: the scheme, the key of its name, whether it is the scheme in use for
/// its appearance, and the few colors the tile draws, as 0xRRGGBB like the palettes store them.
struct AppearanceSchemeTile: Equatable, Sendable, Identifiable {
    let id: PreviewColorSchemeID
    let nameKey: PreviewStrings.Key
    let isSelected: Bool
    let background: UInt32
    let foreground: UInt32
    let keyword: UInt32
    let string: UInt32
    let number: UInt32
    let comment: UInt32
}

/// The color scheme gallery of the Theme page. It is the only place the companion reads `PreviewSchemeSwatch`, the
/// renderers' own colors for a scheme, so the tiles can never drift from what a preview draws. Nothing here reads
/// a file: a tile is a name and a handful of palette colors.
enum AppearanceSchemeGallery {
    /// The tiles for one appearance, Standard first, with `selected` marked. High Contrast is not shown: it always
    /// uses the Standard colors whatever scheme is chosen, which the note under the gallery says.
    @MainActor static func tiles(for polarity: PreviewColorSchemeID.Polarity,
                                 selected: PreviewColorSchemeID) -> [AppearanceSchemeTile] {
        PreviewSchemeSwatch.gallery(dark: polarity == .dark, highContrast: false).map { swatch in
            AppearanceSchemeTile(id: swatch.id, nameKey: AppearanceSchemeNames.key(for: swatch.id),
                                 isSelected: swatch.id == selected, background: swatch.background,
                                 foreground: swatch.foreground, keyword: swatch.keyword, string: swatch.string,
                                 number: swatch.number, comment: swatch.comment)
        }
    }

    /// The scheme `style` uses for one appearance.
    static func selected(for polarity: PreviewColorSchemeID.Polarity, in style: PreviewSyntaxStyle) -> PreviewColorSchemeID {
        switch polarity {
        case .light: style.lightScheme
        case .dark: style.darkScheme
        }
    }

    /// `style` with the scheme for one appearance replaced. A scheme that does not suit the appearance changes
    /// nothing, as `CompanionSettings.setLightScheme` and `setDarkScheme` do, so a light preview never selects a
    /// dark scheme.
    static func selecting(_ scheme: PreviewColorSchemeID, for polarity: PreviewColorSchemeID.Polarity,
                          in style: PreviewSyntaxStyle) -> PreviewSyntaxStyle {
        guard scheme.isAvailable(for: polarity) else { return style }
        var updated = style
        switch polarity {
        case .light: updated.lightScheme = scheme
        case .dark: updated.darkScheme = scheme
        }
        return updated
    }
}

/// The names of the built-in color schemes, one string key each. The raw values of the schemes are persisted and
/// never shown; these keys are what people read.
enum AppearanceSchemeNames {
    static func key(for scheme: PreviewColorSchemeID) -> PreviewStrings.Key {
        switch scheme {
        case .standard: .schemeStandard
        case .githubLight: .schemeGitHubLight
        case .githubDark: .schemeGitHubDark
        case .solarizedLight: .schemeSolarizedLight
        case .solarizedDark: .schemeSolarizedDark
        case .oneLight: .schemeOneLight
        case .oneDark: .schemeOneDark
        case .nord: .schemeNord
        case .dracula: .schemeDracula
        case .paper: .schemePaper
        case .midnight: .schemeMidnight
        case .aurora: .schemeAurora
        }
    }
}

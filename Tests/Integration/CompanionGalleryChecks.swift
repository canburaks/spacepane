import Foundation
import PreviewContracts
import PreviewRenderers

private struct GalleryCheckFailure: Error, CustomStringConvertible {
    let description: String
}

/// The separate executable used by test_companion_models.py: gallery colors come from the renderer's public
/// swatches, and selection changes only the chosen appearance. No settings, source file or UI is opened.
@main @MainActor
struct CompanionGalleryChecks {
    static func main() throws {
        try galleriesOfferOnlyTheirOwnAppearance()
        try selectionMarksExactlyTheChosenTile()
        try tileColorsComeFromTheRenderer()
        try selectionPreservesUnrelatedStyleChoices()
        try everySchemeHasALocalizedName()
        print("Passed 5 companion gallery checks (renderer swatches; no window or VoiceOver validation).")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw GalleryCheckFailure(description: message) }
    }

    private static func galleriesOfferOnlyTheirOwnAppearance() throws {
        let light = AppearanceSchemeGallery.tiles(for: .light, selected: .standard)
        let dark = AppearanceSchemeGallery.tiles(for: .dark, selected: .standard)
        try check(light.map(\.id) == [.standard, .githubLight, .solarizedLight, .oneLight, .paper],
                  "Light schemes must appear once, Standard first, in their recorded order")
        try check(dark.map(\.id) == [.standard, .githubDark, .solarizedDark, .oneDark, .nord, .dracula, .midnight, .aurora],
                  "Dark schemes must appear once, Standard first, in their recorded order")
        try check(Set(light.map(\.id)).intersection(Set(dark.map(\.id))) == [.standard]
                  && Set(light.map(\.id) + dark.map(\.id)) == Set(PreviewColorSchemeID.allCases),
                  "Standard is shared and every other built-in scheme belongs to exactly one appearance")
    }

    private static func selectionMarksExactlyTheChosenTile() throws {
        for polarity in PreviewColorSchemeID.Polarity.allCases {
            for choice in PreviewColorSchemeID.choices(for: polarity) {
                let tiles = AppearanceSchemeGallery.tiles(for: polarity, selected: choice)
                try check(tiles.filter(\.isSelected).map(\.id) == [choice],
                          "Exactly the selected \(polarity) scheme must carry the selected trait")
                try check(tiles.map(\.id) == PreviewColorSchemeID.choices(for: polarity),
                          "Selecting a scheme must not reorder the gallery")
            }
        }
        try check(!AppearanceSchemeGallery.tiles(for: .light, selected: .dracula).contains(where: \.isSelected)
                  && !AppearanceSchemeGallery.tiles(for: .dark, selected: .paper).contains(where: \.isSelected),
                  "An invalid stored choice must not mark a different scheme as selected")
    }

    private static func tileColorsComeFromTheRenderer() throws {
        for polarity in PreviewColorSchemeID.Polarity.allCases {
            for tile in AppearanceSchemeGallery.tiles(for: polarity, selected: .standard) {
                let swatch = PreviewSchemeSwatch.swatch(for: tile.id, dark: polarity == .dark, highContrast: false)
                try check(tile.background == swatch.background && tile.foreground == swatch.foreground
                          && tile.keyword == swatch.keyword && tile.string == swatch.string
                          && tile.number == swatch.number && tile.comment == swatch.comment,
                          "All six tile colors must come from the renderer's \(tile.id) palette")
                try check([tile.background, tile.foreground, tile.keyword, tile.string, tile.number, tile.comment]
                    .allSatisfy { $0 <= 0xFF_FFFF }, "Tile colors must remain inert 24-bit sRGB values")
                try check(tile.background != tile.foreground, "A swatch must retain visible body ink")
            }
        }
        let light = AppearanceSchemeGallery.tiles(for: .light, selected: .standard)[0]
        let dark = AppearanceSchemeGallery.tiles(for: .dark, selected: .standard)[0]
        try check(light.background != dark.background && light.foreground != dark.foreground,
                  "Standard must resolve independently for the two appearances")
    }

    private static func selectionPreservesUnrelatedStyleChoices() throws {
        let original = PreviewSyntaxStyle(usesColor: false, boldRoles: [.keyword, .heading],
                                          italicRoles: [.comment], lightScheme: .paper, darkScheme: .nord)
        try check(AppearanceSchemeGallery.selected(for: .light, in: original) == .paper
                  && AppearanceSchemeGallery.selected(for: .dark, in: original) == .nord,
                  "Each appearance must report its own saved selection")
        for polarity in PreviewColorSchemeID.Polarity.allCases {
            for candidate in PreviewColorSchemeID.allCases {
                let changed = AppearanceSchemeGallery.selecting(candidate, for: polarity, in: original)
                if !candidate.isAvailable(for: polarity) {
                    try check(changed == original, "A scheme from the other appearance must change nothing")
                    continue
                }
                try check(AppearanceSchemeGallery.selected(for: polarity, in: changed) == candidate,
                          "A valid tile selection must select its scheme")
                let other: PreviewColorSchemeID.Polarity = polarity == .light ? .dark : .light
                try check(AppearanceSchemeGallery.selected(for: other, in: changed)
                          == AppearanceSchemeGallery.selected(for: other, in: original),
                          "Choosing a tile must preserve the other appearance's selection")
                try check(changed.usesColor == original.usesColor && changed.boldRoles == original.boldRoles
                          && changed.italicRoles == original.italicRoles && changed.isValid,
                          "Gallery selection must preserve color enablement and semantic font traits")
            }
        }
        try check(original.lightScheme == .paper && original.darkScheme == .nord,
                  "The selection helper must not mutate its input value")
    }

    private static func everySchemeHasALocalizedName() throws {
        let expected: [PreviewColorSchemeID: PreviewStrings.Key] = [
            .standard: .schemeStandard, .githubLight: .schemeGitHubLight, .githubDark: .schemeGitHubDark,
            .solarizedLight: .schemeSolarizedLight, .solarizedDark: .schemeSolarizedDark,
            .oneLight: .schemeOneLight, .oneDark: .schemeOneDark, .nord: .schemeNord,
            .dracula: .schemeDracula, .paper: .schemePaper, .midnight: .schemeMidnight,
            .aurora: .schemeAurora,
        ]
        let languages = ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"]
        let unavailable = PreviewStrings.text(.resourceUnavailable, languagePreferences: ["en"])
        try check(expected.count == PreviewColorSchemeID.allCases.count && Set(expected.values).count == expected.count,
                  "Every scheme must own one distinct name key")
        for scheme in PreviewColorSchemeID.allCases {
            let key = AppearanceSchemeNames.key(for: scheme)
            try check(expected[scheme] == key, "A scheme must resolve its own name rather than its persisted raw value")
            for language in languages {
                let name = PreviewStrings.text(key, languagePreferences: [language])
                try check(!name.isEmpty && name != unavailable && name != key.rawValue && !name.contains("%"),
                          "\(language): \(scheme) must have a usable display name")
            }
        }
        for polarity in PreviewColorSchemeID.Polarity.allCases {
            let tiles = AppearanceSchemeGallery.tiles(for: polarity, selected: .standard)
            try check(tiles.allSatisfy { expected[$0.id] == $0.nameKey },
                      "Every tile must carry its own localized scheme name")
        }
    }
}

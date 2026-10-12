import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// WCAG 2.x contrast, computed here from raw sRGB values independently of the production palette code.
private func luminance(_ rgb: UInt32) -> Double {
    func channel(_ shift: UInt32) -> Double {
        let value = Double((rgb >> shift) & 0xFF) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
}

private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
    let (a, b) = (luminance(first), luminance(second))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

private func contrast(_ first: NSColor, _ second: NSColor) throws -> Double {
    func pack(_ input: NSColor) throws -> UInt32 {
        let color = try #require(input.usingColorSpace(.sRGB))
        func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent)
    }
    return contrast(try pack(first), try pack(second))
}

/// Every scheme in every appearance it can be chosen for.
private let allPalettes: [(id: PreviewColorSchemeID, dark: Bool)] = PreviewColorSchemeID.allCases.flatMap { id in
    [false, true].compactMap { dark in id.isAvailable(for: dark ? .dark : .light) ? (id, dark) : nil }
}

private func palette(_ id: PreviewColorSchemeID, dark: Bool) -> NativeSchemePalette {
    NativeColorSchemes.palette(for: id, dark: dark, highContrast: false)
}

/// The three schemes whose published foreground has under 1.5x headroom over AA (owner decision D11, 2026-10-06).
/// Their muted tier cannot look lighter than body text, so a size cue carries the hierarchy. Written out here and
/// not derived, so a change that moves a scheme into or out of the list fails a test.
private let sizeCueSchemes: Set<PreviewColorSchemeID> = [.solarizedLight, .solarizedDark, .oneDark]

/// One scheme to measure, named for failure messages: the thirteen normal palettes and the two High Contrast ones.
private struct MeasuredPalette {
    let name: String
    /// Nil for the High Contrast palettes, which replace whatever scheme was chosen.
    let id: PreviewColorSchemeID?
    let isHighContrast: Bool
    let scheme: NativeSchemePalette

    var isSizeCueScheme: Bool { id.map { sizeCueSchemes.contains($0) } ?? false }
}

private func measuredPalettes() -> [MeasuredPalette] {
    var result: [MeasuredPalette] = []
    for (id, dark) in allPalettes {
        result.append(MeasuredPalette(name: "\(id.rawValue) \(dark ? "dark" : "light")", id: id, isHighContrast: false,
                                      scheme: palette(id, dark: dark)))
    }
    for dark in [false, true] {
        result.append(MeasuredPalette(name: "high contrast \(dark ? "dark" : "light")", id: nil, isHighContrast: true,
                                      scheme: NativeColorSchemes.palette(for: .standard, dark: dark, highContrast: true)))
    }
    return result
}

private func hex(_ rgb: UInt32) -> String { String(format: "#%06X", rgb) }

private func ratioText(_ value: Double) -> String { String(format: "%.2f:1", value) }

/// 0xRRGGBB of an sRGB color, for exact comparison with a palette value.
private func packed(_ input: NSColor) throws -> UInt32 {
    let color = try #require(input.usingColorSpace(.sRGB))
    func byte(_ value: CGFloat) -> UInt32 { UInt32((value * 255).rounded()) }
    return byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent)
}

@Suite("Color schemes: contrast, overrides and rendering", .serialized)
@MainActor
struct ColorSchemeContrastTests {
    @Test func everySchemeRoleAndForegroundMeetsAA45OnItsOwnBackground() {
        #expect(allPalettes.count == 2 + 4 + 7, "Standard serves both appearances; each of the eleven schemes serves one")
        for (id, dark) in allPalettes {
            let scheme = palette(id, dark: dark)
            for color in scheme.textColors {
                #expect(contrast(color, scheme.background) >= 4.5,
                        "\(id.rawValue) \(dark ? "dark" : "light") #\(String(color, radix: 16)) on #\(String(scheme.background, radix: 16))")
            }
            for role in PreviewSyntaxRole.allCases {
                #expect(contrast(scheme.color(for: role), scheme.background) >= 4.5, "\(id.rawValue) \(role.rawValue)")
            }
        }
    }

    @Test func highContrastPalettesMeetAAA7ForEveryRole() {
        for dark in [false, true] {
            let scheme = NativeColorSchemes.palette(for: .standard, dark: dark, highContrast: true)
            for color in scheme.textColors { #expect(contrast(color, scheme.background) >= 7) }
        }
    }

    @Test func schemeBackgroundsMatchTheirPolarity() {
        for (id, dark) in allPalettes {
            let background = luminance(palette(id, dark: dark).background)
            #expect(dark ? background < 0.2 : background > 0.5, "\(id.rawValue) background must suit its appearance")
        }
    }

    @Test func standardIsUnchangedFromBeforeSchemesExisted() throws {
        // Independent literals: the values the product shipped with, so a regression in the table is caught.
        let lightExpected: [PreviewSyntaxRole: UInt32] = [
            .key: 0x174E94, .keyword: 0x174E94, .tag: 0x174E94, .type: 0x174E94,
            .string: 0x236328, .addition: 0x236328, .number: 0x90430A,
            .literal: 0x6E3288, .heading: 0x6E3288, .operator: 0x6E3288,
            .comment: 0x626262, .deletion: 0xA02121
        ]
        let darkExpected: [PreviewSyntaxRole: UInt32] = [
            .key: 0x8FC4FF, .keyword: 0x8FC4FF, .tag: 0x8FC4FF, .type: 0x8FC4FF,
            .string: 0xA6D98F, .addition: 0xA6D98F, .number: 0xF0B47A,
            .literal: 0xD9ADF5, .heading: 0xD9ADF5, .operator: 0xD9ADF5,
            .comment: 0xBDBDBD, .deletion: 0xFFA6A6
        ]
        let light = palette(.standard, dark: false)
        let dark = palette(.standard, dark: true)
        #expect(light.background == 0xFFFFFF && light.foreground == 0x1A1A1A)
        #expect(dark.background == 0x1B1B1B && dark.foreground == 0xF2F2F2)
        for role in PreviewSyntaxRole.allCases {
            #expect(light.color(for: role) == lightExpected[role], "light \(role.rawValue)")
            #expect(dark.color(for: role) == darkExpected[role], "dark \(role.rawValue)")
        }
        let highContrastLight = NativeColorSchemes.palette(for: .standard, dark: false, highContrast: true)
        let highContrastDark = NativeColorSchemes.palette(for: .standard, dark: true, highContrast: true)
        #expect(highContrastLight.foreground == 0x000000 && highContrastLight.comment == 0x404040
                && highContrastLight.key == 0x103B6B && highContrastLight.deletion == 0x711A1A)
        #expect(highContrastDark.background == 0x000000 && highContrastDark.foreground == 0xFFFFFF
                && highContrastDark.comment == 0xCCCCCC)
    }

    @Test func publishedSchemesKeepTheirCharacteristicBackgroundsAndForegrounds() {
        // Backgrounds and foregrounds are the schemes' published values; accents may be adjusted for contrast.
        let published: [(PreviewColorSchemeID, Bool, UInt32, UInt32)] = [
            (.githubLight, false, 0xFFFFFF, 0x1F2328), (.githubDark, true, 0x0D1117, 0xF0F6FC),
            (.solarizedLight, false, 0xFDF6E3, 0x586E75), (.solarizedDark, true, 0x002B36, 0x93A1A1),
            (.oneLight, false, 0xFAFAFA, 0x383A42), (.oneDark, true, 0x282C34, 0xABB2BF),
            (.nord, true, 0x2E3440, 0xD8DEE9), (.dracula, true, 0x282A36, 0xF8F8F2)
        ]
        for (id, dark, background, foreground) in published {
            let scheme = palette(id, dark: dark)
            #expect(scheme.background == background && scheme.foreground == foreground, "\(id.rawValue)")
        }
    }

    @Test func everySchemeDiffersFromStandardAndUsesSeveralDistinctColors() {
        for (id, dark) in allPalettes where id != .standard {
            let scheme = palette(id, dark: dark)
            #expect(scheme != palette(.standard, dark: dark))
            #expect(Set(PreviewSyntaxRole.allCases.map(scheme.color(for:))).count >= 6, "\(id.rawValue) must stay distinguishable")
            #expect(scheme.color(for: .comment) != scheme.foreground, "Comments must differ from body text")
        }
    }

    @Test func auroraIsTheWebsitePreviewPaletteWithOnlyItsCommentInkRaised() {
        // Independent literals from `.qv` in web/src/styles/preview-theme.css: the palette of the website's live
        // preview. The comment there is 0x6C7083, 3.47:1 on this background, so the scheme carries the smallest
        // step toward white that reaches 4.5:1.
        let website: [PreviewSyntaxRole: UInt32] = [
            .key: 0x8FB4FF, .string: 0x9FE3B0, .number: 0xF7C37B, .literal: 0xC7A6FF, .keyword: 0xFF8FC6,
            .type: 0x6FE0E8, .operator: 0xA6A9B6, .addition: 0x3FBF6F, .deletion: 0xF05F5F
        ]
        let scheme = palette(.aurora, dark: true)
        #expect(scheme.background == 0x1B1C21 && scheme.foreground == 0xE8E9EF && scheme.muted == 0x8E909C)
        for (role, value) in website { #expect(scheme.color(for: role) == value, "\(role.rawValue)") }
        #expect(contrast(0x6C7083, scheme.background) < 4.5, "The website's comment ink is below AA here")
        #expect(scheme.color(for: .comment) == 0x7F8393)
        #expect(contrast(scheme.color(for: .comment), scheme.background) >= 4.5)
        #expect(scheme.color(for: .heading) == scheme.color(for: .literal) && scheme.color(for: .tag) == scheme.color(for: .keyword))
        #expect(NativeColorSchemes.palette(for: .aurora, dark: false, highContrast: false) == NativeColorSchemes.standardLight)
    }

    @Test func aMismatchedSchemeFallsBackToStandardForTheAppearance() {
        #expect(NativeColorSchemes.palette(for: .nord, dark: false, highContrast: false) == NativeColorSchemes.standardLight)
        #expect(NativeColorSchemes.palette(for: .paper, dark: true, highContrast: false) == NativeColorSchemes.standardDark)
        #expect(NativeColorSchemes.palette(for: .githubDark, dark: false, highContrast: false) == NativeColorSchemes.standardLight)
    }

    // MARK: Chrome tiers: the muted ink and the hairline (decision 027, Q-34; owner decision D11)

    @Test func theMeasuredPalettesAreTheThirteenNormalOnesAndBothHighContrastOnes() {
        let measured = measuredPalettes()
        #expect(measured.count == 15)
        #expect(measured.filter { $0.isHighContrast }.count == 2)
        #expect(Set(measured.compactMap { $0.id }) == Set(PreviewColorSchemeID.allCases), "Every scheme is measured")
    }

    @Test func mutedInkMeetsAA45OnItsOwnBackgroundInEveryPalette() {
        for entry in measuredPalettes() {
            let ratio = contrast(entry.scheme.muted, entry.scheme.background)
            #expect(ratio >= 4.5, "\(entry.name) muted \(hex(entry.scheme.muted)) on \(hex(entry.scheme.background)) is \(ratioText(ratio))")
        }
    }

    @Test func mutedInkMeetsAAA7InBothHighContrastPalettes() {
        for entry in measuredPalettes() where entry.isHighContrast {
            let ratio = contrast(entry.scheme.muted, entry.scheme.background)
            #expect(ratio >= 7, "\(entry.name) muted \(hex(entry.scheme.muted)) is \(ratioText(ratio))")
        }
    }

    @Test func mutedInkIsATextColorSoEveryContrastTestAboveWalksIt() {
        for entry in measuredPalettes() {
            #expect(entry.scheme.textColors.contains(entry.scheme.muted), "\(entry.name)")
        }
    }

    @Test func mutedInkNeverReadsStrongerThanBodyText() {
        for entry in measuredPalettes() {
            let body = contrast(entry.scheme.foreground, entry.scheme.background)
            let muted = contrast(entry.scheme.muted, entry.scheme.background)
            #expect(muted <= body, "\(entry.name): muted \(ratioText(muted)) against body \(ratioText(body))")
        }
    }

    @Test func mutedInkDiffersFromBodyTextByAtLeast125WhereTheSchemeHasSevenToOneHeadroom() {
        for entry in measuredPalettes() where !entry.isSizeCueScheme {
            let body = contrast(entry.scheme.foreground, entry.scheme.background)
            let muted = contrast(entry.scheme.muted, entry.scheme.background)
            #expect(body >= 7, "\(entry.name) is outside the D11 list, so its body text needs 7:1; it has \(ratioText(body))")
            #expect(body / muted >= 1.25, "\(entry.name): body \(ratioText(body)) against muted \(ratioText(muted))")
            #expect(entry.scheme.muted != entry.scheme.foreground, "\(entry.name)")
        }
    }

    @Test func onlyTheThreeD11SchemesLackHeadroomAndOnlyTheyAskForTheSizeCue() {
        var withoutHeadroom: Set<PreviewColorSchemeID> = []
        for entry in measuredPalettes() {
            let body = contrast(entry.scheme.foreground, entry.scheme.background)
            if body < 7, let id = entry.id { withoutHeadroom.insert(id) }
            #expect(entry.scheme.mutedUsesSizeCue == entry.isSizeCueScheme, "\(entry.name)")
        }
        #expect(withoutHeadroom == sizeCueSchemes, "The schemes below 7:1 are exactly the D11 list")
    }

    @Test func theSizeCueFollowsTheForegroundHeadroomOverAAAtOnePointFive() {
        for entry in measuredPalettes() {
            let headroom = contrast(entry.scheme.foreground, entry.scheme.background) / 4.5
            #expect(entry.scheme.mutedUsesSizeCue == (headroom < 1.5), "\(entry.name) has \(ratioText(headroom)) headroom")
        }
    }

    @Test func theProductionContrastMathAgreesWithTheIndependentOneHere() {
        for entry in measuredPalettes() {
            let scheme = entry.scheme
            for (first, second) in [(scheme.foreground, scheme.background), (scheme.muted, scheme.background),
                                    (scheme.hairline, scheme.background), (scheme.comment, scheme.muted)] {
                let production = NativeSchemePalette.contrastRatio(first, second)
                #expect(abs(production - contrast(first, second)) < 1e-9, "\(entry.name) \(hex(first)) on \(hex(second))")
            }
        }
        #expect(abs(NativeSchemePalette.contrastRatio(0x000000, 0xFFFFFF) - 21) < 1e-9)
        #expect(NativeSchemePalette.contrastRatio(0x808080, 0x808080) == 1)
    }

    @Test func hairlineIsVisibleButQuietInEveryNormalPalette() {
        for entry in measuredPalettes() where !entry.isHighContrast {
            let ratio = contrast(entry.scheme.hairline, entry.scheme.background)
            let muted = contrast(entry.scheme.muted, entry.scheme.background)
            #expect(ratio >= 1.3, "\(entry.name) hairline \(hex(entry.scheme.hairline)) is \(ratioText(ratio)), under the decorative 1.3:1")
            #expect(ratio <= 2, "\(entry.name) hairline is \(ratioText(ratio)); a rule that dark is not quiet")
            #expect(ratio < muted, "\(entry.name): the rule \(ratioText(ratio)) must be quieter than muted text \(ratioText(muted))")
        }
    }

    @Test func hairlineMeets3To1InBothHighContrastPalettes() {
        for entry in measuredPalettes() where entry.isHighContrast {
            let ratio = contrast(entry.scheme.hairline, entry.scheme.background)
            #expect(ratio >= 3, "\(entry.name) hairline \(hex(entry.scheme.hairline)) is \(ratioText(ratio))")
            #expect(ratio < 4.5, "\(entry.name) hairline is \(ratioText(ratio)), as strong as text")
        }
    }

    @Test func hairlineIsABlendOfTheForegroundIntoTheBackgroundOnEveryChannel() {
        for entry in measuredPalettes() {
            for shift in [UInt32(16), 8, 0] {
                let background = (entry.scheme.background >> shift) & 0xFF
                let foreground = (entry.scheme.foreground >> shift) & 0xFF
                let hairline = (entry.scheme.hairline >> shift) & 0xFF
                #expect(hairline >= min(background, foreground) && hairline <= max(background, foreground),
                        "\(entry.name) channel at shift \(shift): \(background), \(hairline), \(foreground)")
            }
        }
    }

    // MARK: NativeTextPalette

    @Test func textPaletteAppliesTheSchemeOfTheEffectiveAppearance() throws {
        let style = PreviewSyntaxStyle(lightScheme: .solarizedLight, darkScheme: .dracula)
        let light = NativeTextPalette(theme: .light, isDark: true, increasedContrast: false, style: style)
        let dark = NativeTextPalette(theme: .dark, isDark: false, increasedContrast: false, style: style)
        let systemDark = NativeTextPalette(theme: .system, isDark: true, increasedContrast: false, style: style)
        let systemLight = NativeTextPalette(theme: .system, isDark: false, increasedContrast: false, style: style)
        let solarized = palette(.solarizedLight, dark: false)
        let dracula = palette(.dracula, dark: true)
        #expect(try contrast(light.background, NSColor(srgbRed: 0xFD / 255.0, green: 0xF6 / 255.0, blue: 0xE3 / 255.0, alpha: 1)) == 1)
        for (rendered, expected) in [(light, solarized), (systemLight, solarized), (dark, dracula), (systemDark, dracula)] {
            #expect(rendered.background == NSColor(srgbRed: CGFloat((expected.background >> 16) & 255) / 255,
                green: CGFloat((expected.background >> 8) & 255) / 255, blue: CGFloat(expected.background & 255) / 255, alpha: 1))
            for role in PreviewSyntaxRole.allCases {
                let color = rendered.color(for: role, style: style)
                let reference = expected.color(for: role)
                #expect(try contrast(color, NSColor(srgbRed: CGFloat((reference >> 16) & 255) / 255,
                    green: CGFloat((reference >> 8) & 255) / 255, blue: CGFloat(reference & 255) / 255, alpha: 1)) == 1,
                        "\(role.rawValue) must be the scheme's value")
            }
        }
    }

    @Test func highContrastThemeAndIncreasedContrastOverrideEverySchemeChoice() throws {
        for (light, dark) in [(PreviewColorSchemeID.githubLight, PreviewColorSchemeID.nord), (.paper, .midnight), (.standard, .standard)] {
            let style = PreviewSyntaxStyle(lightScheme: light, darkScheme: dark)
            for isDark in [false, true] {
                let reference = NativeTextPalette(theme: .highContrast, isDark: isDark, increasedContrast: false)
                for (theme, increased) in [(PreviewTheme.highContrast, false), (.highContrast, true), (.system, true),
                                           (isDark ? .dark : .light, true)] {
                    let overridden = NativeTextPalette(theme: theme, isDark: isDark, increasedContrast: increased, style: style)
                    #expect(overridden.background == reference.background && overridden.foreground == reference.foreground)
                    for role in PreviewSyntaxRole.allCases {
                        #expect(overridden.color(for: role) == reference.color(for: role), "\(theme) \(role.rawValue)")
                        #expect(try contrast(overridden.color(for: role), overridden.background) >= 7)
                    }
                }
            }
        }
    }

    @Test func defaultStyleIsStandardAndColorOptOutKeepsSchemeBackgroundButPlainText() {
        let plain = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        let explicit = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false, style: PreviewSyntaxStyle())
        #expect(plain.background == explicit.background && plain.foreground == explicit.foreground)
        for role in PreviewSyntaxRole.allCases { #expect(plain.color(for: role) == explicit.color(for: role)) }
        let colorless = PreviewSyntaxStyle(usesColor: false, lightScheme: .paper, darkScheme: .midnight)
        let paper = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false, style: colorless)
        #expect(paper.background != plain.background, "The chosen scheme still sets the background")
        for role in PreviewSyntaxRole.allCases {
            #expect(paper.color(for: role, style: colorless) == paper.foreground)
        }
    }

    @Test func stylePassCarriesSchemeColorsIntoRoleAttributes() throws {
        let style = PreviewSyntaxStyle(boldRoles: [.key], lightScheme: .oneLight, darkScheme: .oneDark)
        let palette = NativeTextPalette(theme: .dark, isDark: true, increasedContrast: false, style: style)
        let pass = NativeTextStylePass(typography: NativeTextTypography(PreviewTypography(), syntaxStyle: style),
                                       palette: palette, syntaxStyle: style)
        #expect(pass.baseAttributes[.foregroundColor] as? NSColor == palette.foreground)
        for role in PreviewSyntaxRole.allCases {
            #expect(pass.attributes(for: role)[.foregroundColor] as? NSColor == palette.color(for: role, style: style))
        }
        let standard = NativeTextStylePass(typography: NativeTextTypography(PreviewTypography()),
                                           palette: NativeTextPalette(theme: .dark, isDark: true, increasedContrast: false),
                                           syntaxStyle: PreviewSyntaxStyle())
        #expect(pass.attributes(for: .string)[.foregroundColor] as? NSColor != standard.attributes(for: .string)[.foregroundColor] as? NSColor)
    }

    @Test func selectingASchemeRestylesTheSameSafeTextWithoutChangingIt() throws {
        let text = #"{"password":"[REDACTED]","value":42}"#
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let outcome = PreviewOutcome.ready(TextPresentation(formatID: .json, text: text, lineCount: 1,
            byteCount: text.utf8.count, encoding: .utf8, redactionCount: 1, syntax: .json))
        view.display(outcome, theme: .light)
        let before = try renderedBackground(of: view)
        view.display(outcome, theme: .light, syntaxStyle: PreviewSyntaxStyle(lightScheme: .paper))
        let after = try renderedBackground(of: view)
        #expect(before != after, "A new scheme changes the pane's colors")
        let content = try textView(of: view)
        #expect(content.string == text, "The scheme never changes the displayed characters")
        let keyOffset = (text as NSString).range(of: #""password""#).location
        let color = try #require(content.textStorage?.attribute(.foregroundColor, at: keyOffset, effectiveRange: nil) as? NSColor)
        let paperKey = NSColor(srgbRed: 0x1F / 255.0, green: 0x5F / 255.0, blue: 0x8B / 255.0, alpha: 1)
        #expect(try contrast(color, paperKey) == 1, "JSON keys use the Paper key color")
    }

    @Test func textPaletteCarriesTheMutedAndHairlineInksOfTheChosenScheme() throws {
        for (id, dark) in allPalettes {
            let style = PreviewSyntaxStyle(lightScheme: dark ? .standard : id, darkScheme: dark ? id : .standard)
            let rendered = NativeTextPalette(theme: dark ? .dark : .light, isDark: dark, increasedContrast: false, style: style)
            let scheme = palette(id, dark: dark)
            #expect(try packed(rendered.muted) == scheme.muted, "\(id.rawValue) \(dark ? "dark" : "light") muted")
            #expect(try packed(rendered.hairline) == scheme.hairline, "\(id.rawValue) \(dark ? "dark" : "light") hairline")
            #expect(rendered.mutedUsesSizeCue == scheme.mutedUsesSizeCue, "\(id.rawValue) \(dark ? "dark" : "light") size cue")
            #expect(try contrast(rendered.muted, rendered.background) >= 4.5, "\(id.rawValue) muted on its rendered background")
        }
    }

    @Test func turningSyntaxColorsOffKeepsTheQuietChromeTier() throws {
        // "Use colors" drives the syntax roles; muted and the hairline are chrome tiers and keep their own inks.
        let style = PreviewSyntaxStyle(usesColor: false, lightScheme: .paper, darkScheme: .midnight)
        let rendered = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false, style: style)
        #expect(try packed(rendered.muted) == NativeColorSchemes.paper.muted)
        #expect(try packed(rendered.muted) != packed(rendered.foreground), "Muted stays a separate tier from body text")
        #expect(try packed(rendered.hairline) == NativeColorSchemes.paper.hairline)
        for role in PreviewSyntaxRole.allCases { #expect(rendered.color(for: role, style: style) == rendered.foreground) }
    }

    @Test func increasedContrastGivesTheHighContrastMutedInkAndHairlineWhateverSchemeIsChosen() throws {
        let style = PreviewSyntaxStyle(lightScheme: .githubLight, darkScheme: .nord)
        for isDark in [false, true] {
            let reference = NativeColorSchemes.palette(for: .standard, dark: isDark, highContrast: true)
            for (theme, increased) in [(PreviewTheme.highContrast, false), (.highContrast, true), (.system, true),
                                       (isDark ? .dark : .light, true)] {
                let rendered = NativeTextPalette(theme: theme, isDark: isDark, increasedContrast: increased, style: style)
                #expect(try packed(rendered.muted) == reference.muted, "\(theme) \(isDark ? "dark" : "light") muted")
                #expect(try packed(rendered.hairline) == reference.hairline, "\(theme) \(isDark ? "dark" : "light") hairline")
                #expect(try contrast(rendered.muted, rendered.background) >= 7, "\(theme) muted needs 7:1")
                #expect(try contrast(rendered.hairline, rendered.background) >= 3, "\(theme) hairline needs 3:1")
                #expect(!rendered.mutedUsesSizeCue, "High Contrast has headroom, so lightness alone separates the tiers")
            }
        }
    }

    private func renderedBackground(of view: NativePreviewView) throws -> NSColor {
        try #require(try textView(of: view).backgroundColor.usingColorSpace(.sRGB))
    }

    private func textView(of view: NativePreviewView) throws -> NSTextView {
        // The shared lookup helper (Interaction/ViewLookupSupport.swift) replaces the private walker.
        try #require(descendants(of: NSTextView.self, in: view).first)
    }
}

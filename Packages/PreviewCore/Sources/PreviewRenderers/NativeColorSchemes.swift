import Foundation
import PreviewContracts

/// Fixed sRGB values (0xRRGGBB) of one color scheme in one appearance. The type has no AppKit
/// dependency, so tests can measure WCAG contrast over every scheme, role and background.
///
/// Every named role is required, so a scheme cannot be added without choosing all twelve, the muted ink and the
/// hairline. Values for the third-party schemes come from their published palettes (see ThirdPartyNotices/ColorSchemes);
/// where a published value is below 4.5:1 against its own background it was moved toward black or white, in the
/// smallest step that reaches 4.5:1, and the original is recorded beside it.
///
/// Chrome tiers (decision 027, Q-34). `foreground` is body ink. `muted` is the quieter ink for secondary chrome text
/// (counts, hints, notes) and `hairline` the decorative rule between regions, so chrome never draws with an alpha or a
/// system ink that ignores the scheme. `muted` starts from the scheme's comment color, which already measures at least
/// 4.5:1, so it is AA in every scheme and at least 7:1 in the High Contrast palettes. Solarized Light, Solarized Dark and
/// One Dark publish a foreground with under 1.5x headroom over AA, so an ink that still meets AA cannot look clearly
/// lighter than their body text (owner decision D11, 2026-10-06): `mutedUsesSizeCue` asks chrome for a second cue there.
/// The hairline is the foreground blended into the background in the smallest whole percent that measures 1.4:1 against
/// it (3.2:1 in the High Contrast palettes), recorded beside each value; it is decorative and never the only cue.
struct NativeSchemePalette: Equatable, Sendable {
    let background: UInt32
    let foreground: UInt32
    let key: UInt32
    let string: UInt32
    let number: UInt32
    let literal: UInt32
    let keyword: UInt32
    let comment: UInt32
    let type: UInt32
    let `operator`: UInt32
    let addition: UInt32
    let deletion: UInt32
    let heading: UInt32
    let tag: UInt32
    /// The quieter ink for secondary chrome text, measured against `background`.
    let muted: UInt32
    /// The decorative 1 px rule between chrome regions, measured against `background`.
    let hairline: UInt32

    func color(for role: PreviewSyntaxRole) -> UInt32 {
        switch role {
        case .key: key
        case .string: string
        case .number: number
        case .literal: literal
        case .keyword: keyword
        case .comment: comment
        case .type: type
        case .operator: `operator`
        case .addition: addition
        case .deletion: deletion
        case .heading: heading
        case .tag: tag
        }
    }

    /// Foreground, the muted ink and every role, the colors that are drawn as text on `background`.
    var textColors: [UInt32] { [foreground, muted] + PreviewSyntaxRole.allCases.map(color(for:)) }
}

extension NativeSchemePalette {
    /// The text contrast every text color of a scheme meets: WCAG 2.x AA for normal-size text.
    static let minimumTextContrast = 4.5
    /// Below this multiple of `minimumTextContrast`, ink alone cannot set muted text apart from body text.
    static let sizeCueHeadroom = 1.5

    /// Whether muted text needs a second cue besides its ink. True when the foreground has under 1.5x headroom over
    /// AA, so a muted ink that still meets AA reads as the same ink as the body text. Chrome that sets muted text
    /// beside body-ink text then draws the muted text at 11 pt regular, below the body-ink size, so the size carries
    /// the hierarchy where the ink cannot. False wherever lightness alone is enough.
    var mutedUsesSizeCue: Bool {
        Self.contrastRatio(foreground, background) < Self.minimumTextContrast * Self.sizeCueHeadroom
    }

    /// The WCAG 2.x contrast ratio between two sRGB colors (0xRRGGBB), from 1 to 21.
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        func linear(_ rgb: UInt32, _ shift: UInt32) -> Double {
            let unit = Double((rgb >> shift) & 0xFF) / 255
            return unit <= 0.04045 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
        }
        func luminance(_ rgb: UInt32) -> Double {
            0.2126 * linear(rgb, 16) + 0.7152 * linear(rgb, 8) + 0.0722 * linear(rgb, 0)
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

enum NativeColorSchemes {
    /// The palette for a choice. High Contrast and the system Increase Contrast setting always use the
    /// Standard high-contrast palette, so no scheme can lower the text contrast the user asked for. A scheme
    /// whose background polarity does not match the appearance (possible only for unvalidated input) also
    /// falls back to Standard rather than drawing a dark scheme on a light preview.
    static func palette(for id: PreviewColorSchemeID, dark: Bool, highContrast: Bool) -> NativeSchemePalette {
        if highContrast { return dark ? standardHighContrastDark : standardHighContrastLight }
        guard id.isAvailable(for: dark ? .dark : .light) else { return standard(dark: dark) }
        return switch id {
        case .standard: standard(dark: dark)
        case .githubLight: githubLight
        case .githubDark: githubDark
        case .solarizedLight: solarizedLight
        case .solarizedDark: solarizedDark
        case .oneLight: oneLight
        case .oneDark: oneDark
        case .nord: nord
        case .dracula: dracula
        case .paper: paper
        case .midnight: midnight
        case .aurora: aurora
        }
    }

    static func standard(dark: Bool) -> NativeSchemePalette { dark ? standardDark : standardLight }

    // MARK: Standard — the product's own palettes, unchanged from before schemes existed.

    static let standardLight = NativeSchemePalette(
        background: 0xFFFFFF, foreground: 0x1A1A1A,
        key: 0x174E94, string: 0x236328, number: 0x90430A, literal: 0x6E3288, keyword: 0x174E94,
        comment: 0x626262, type: 0x174E94, operator: 0x6E3288, addition: 0x236328, deletion: 0xA02121,
        heading: 0x6E3288, tag: 0x174E94,
        muted: 0x626262, hairline: 0xD8D8D8 /* 17 % */)

    static let standardDark = NativeSchemePalette(
        background: 0x1B1B1B, foreground: 0xF2F2F2,
        key: 0x8FC4FF, string: 0xA6D98F, number: 0xF0B47A, literal: 0xD9ADF5, keyword: 0x8FC4FF,
        comment: 0xBDBDBD, type: 0x8FC4FF, operator: 0xD9ADF5, addition: 0xA6D98F, deletion: 0xFFA6A6,
        heading: 0xD9ADF5, tag: 0x8FC4FF,
        muted: 0xBDBDBD, hairline: 0x353535 /* 12 % */)

    static let standardHighContrastLight = NativeSchemePalette(
        background: 0xFFFFFF, foreground: 0x000000,
        key: 0x103B6B, string: 0x17451D, number: 0x63300C, literal: 0x512366, keyword: 0x103B6B,
        comment: 0x404040, type: 0x103B6B, operator: 0x512366, addition: 0x17451D, deletion: 0x711A1A,
        heading: 0x512366, tag: 0x103B6B,
        muted: 0x404040, hairline: 0x8F8F8F /* 44 %, 3.2:1 */)

    static let standardHighContrastDark = NativeSchemePalette(
        background: 0x000000, foreground: 0xFFFFFF,
        key: 0x8FC4FF, string: 0xA6D98F, number: 0xF0B47A, literal: 0xD9ADF5, keyword: 0x8FC4FF,
        comment: 0xCCCCCC, type: 0x8FC4FF, operator: 0xD9ADF5, addition: 0xA6D98F, deletion: 0xFFA6A6,
        heading: 0xD9ADF5, tag: 0x8FC4FF,
        muted: 0xCCCCCC, hairline: 0x5E5E5E /* 37 %, 3.2:1 */)

    // MARK: GitHub (Primer) — MIT, github-markdown-css / primer. Dark heading adjusted from 0x1F6FEB.

    static let githubLight = NativeSchemePalette(
        background: 0xFFFFFF, foreground: 0x1F2328,
        key: 0x0550AE, string: 0x0A3069, number: 0x953800, literal: 0x6639BA, keyword: 0xCF222E,
        comment: 0x59636E, type: 0x6639BA, operator: 0xCF222E, addition: 0x116329, deletion: 0x82071E,
        heading: 0x0550AE, tag: 0x116329,
        muted: 0x59636E, hairline: 0xD9DADA /* 17 % */)

    static let githubDark = NativeSchemePalette(
        background: 0x0D1117, foreground: 0xF0F6FC,
        key: 0x79C0FF, string: 0xA5D6FF, number: 0xFFA657, literal: 0xD2A8FF, keyword: 0xFF7B72,
        comment: 0x9198A1, type: 0xD2A8FF, operator: 0xFF7B72, addition: 0xAFF5B4, deletion: 0xFFDCD7,
        heading: 0x2F79EC /* 0x1F6FEB */, tag: 0x7EE787,
        muted: 0x9198A1, hairline: 0x2B2F35 /* 13 % */)

    // MARK: Solarized — MIT, Ethan Schoonover. Most accents are below 4.5:1 on the published backgrounds.
    // The muted ink of both Solarized schemes is the adjusted comment color, within 1.1x and 1.25x of the body
    // text's contrast, so the size cue carries the hierarchy (owner decision D11).

    static let solarizedLight = NativeSchemePalette(
        background: 0xFDF6E3, foreground: 0x586E75,
        key: 0x2075B0 /* 0x268BD2 */, string: 0x207C75 /* 0x2AA198 */, number: 0xC8337C /* 0xD33682 */,
        literal: 0x6469B6 /* 0x6C71C4 */, keyword: 0x687700 /* 0x859900 */, comment: 0x687272 /* 0x93A1A1 */,
        type: 0x8D6B00 /* 0xB58900 */, operator: 0x687700 /* 0x859900 */, addition: 0x687700 /* 0x859900 */,
        deletion: 0xD3302D /* 0xDC322F */, heading: 0xC34815 /* 0xCB4B16 */, tag: 0x2075B0 /* 0x268BD2 */,
        muted: 0x687272, hairline: 0xD2D3C6 /* 26 % */)

    static let solarizedDark = NativeSchemePalette(
        background: 0x002B36, foreground: 0x93A1A1,
        key: 0x3794D6 /* 0x268BD2 */, string: 0x2AA198, number: 0xDD649F /* 0xD33682 */,
        literal: 0x8488CD /* 0x6C71C4 */, keyword: 0x859900, comment: 0x809196 /* 0x586E75 */,
        type: 0xB58900, operator: 0x859900, addition: 0x859900,
        deletion: 0xE56563 /* 0xDC322F */, heading: 0xD67349 /* 0xCB4B16 */, tag: 0x3794D6 /* 0x268BD2 */,
        muted: 0x809196, hairline: 0x1F444C /* 21 % */)

    // MARK: One (Atom One Light / One Dark) — MIT, GitHub Inc. Values are the syntax themes' HSL definitions.
    // One Dark's foreground has 1.46x headroom over AA, so its muted ink also uses the size cue (owner decision D11).

    static let oneLight = NativeSchemePalette(
        background: 0xFAFAFA, foreground: 0x383A42,
        key: 0xC44A3F /* 0xE45649 */, string: 0x3F7F3E /* 0x50A14F */, number: 0xA86201 /* 0xB76B01 */,
        literal: 0x0179AD /* 0x0184BC */, keyword: 0xA626A4, comment: 0x696C77,
        type: 0xA66201 /* 0xCB7701 */, operator: 0x0179AD /* 0x0184BC */, addition: 0x3F7F3E /* 0x50A14F */,
        deletion: 0xCA1243, heading: 0x3A6DDC /* 0x4078F2 */, tag: 0xC44A3F /* 0xE45649 */,
        muted: 0x696C77, hairline: 0xD3D4D5 /* 20 % */)

    static let oneDark = NativeSchemePalette(
        background: 0x282C34, foreground: 0xABB2BF,
        key: 0xE1727B /* 0xE06C75 */, string: 0x98C379, number: 0xD19A66, literal: 0x56B6C2, keyword: 0xC678DD,
        comment: 0x8D94A0 /* 0x828997 */, type: 0xE5C07B, operator: 0x56B6C2, addition: 0x98C379,
        deletion: 0xE1727B /* 0xE06C75 */, heading: 0x61AFEF, tag: 0xE1727B /* 0xE06C75 */,
        muted: 0x8D94A0, hairline: 0x3E434C /* 17 % */)

    // MARK: Nord — MIT, Sven Greb / Arctic Ice Studio.

    static let nord = NativeSchemePalette(
        background: 0x2E3440, foreground: 0xD8DEE9,
        key: 0x88C0D0, string: 0xA3BE8C, number: 0xB691AF /* 0xB48EAD */, literal: 0xD18B74 /* 0xD08770 */,
        keyword: 0x81A1C1, comment: 0x959EAF /* 0x616E88 */, type: 0x8FBCBB, operator: 0x81A1C1,
        addition: 0xA3BE8C, deletion: 0xD08A91 /* 0xBF616A */, heading: 0x88C0D0, tag: 0x81A1C1,
        muted: 0x959EAF, hairline: 0x444A56 /* 13 % */)

    // MARK: Dracula — MIT, Dracula Theme.

    static let dracula = NativeSchemePalette(
        background: 0x282A36, foreground: 0xF8F8F2,
        key: 0x8BE9FD, string: 0xF1FA8C, number: 0xBD93F9, literal: 0xFFB86C, keyword: 0xFF79C6,
        comment: 0x8591B8 /* 0x6272A4 */, type: 0x8BE9FD, operator: 0xFF79C6, addition: 0x50FA7B,
        deletion: 0xFF5757 /* 0xFF5555 */, heading: 0xBD93F9, tag: 0xFF79C6,
        muted: 0x8591B8, hairline: 0x3F414B /* 11 % */)

    // MARK: Original schemes of this product.

    /// Warm paper background with ink-dark text.
    static let paper = NativeSchemePalette(
        background: 0xF6F1E7, foreground: 0x2A2723,
        key: 0x1F5F8B, string: 0x2F6B3A, number: 0x9A4E0C, literal: 0x7A3E8C, keyword: 0x9C2F3B,
        comment: 0x6B655B, type: 0x0F6B6B, operator: 0x7A5B1E, addition: 0x2F6B3A, deletion: 0xA22A2A,
        heading: 0x1F5F8B, tag: 0x9C2F3B,
        muted: 0x6B655B, hairline: 0xD1CDC4 /* 18 % */)

    /// Deep blue-black background with soft, evenly weighted accents.
    static let midnight = NativeSchemePalette(
        background: 0x11172B, foreground: 0xE6E9F5,
        key: 0x7FB5FF, string: 0x9BE0A9, number: 0xFFC48A, literal: 0xE0A8FF, keyword: 0xFF8FA3,
        comment: 0x9AA4C6, type: 0x7FE3E3, operator: 0xB5C0E0, addition: 0x9BE0A9, deletion: 0xFF9A9A,
        heading: 0xFFD27F, tag: 0xFF8FA3,
        muted: 0x9AA4C6, hairline: 0x2F3447 /* 14 % */)

    /// The palette of the live preview on the product's website (`.qv` in web/src/styles/preview-theme.css):
    /// near-black gray with pink keywords, cyan types and violet literals. The values are the website's own; only
    /// the comment ink was moved toward white to reach 4.5:1, and the muted ink is the website's chrome muted.
    static let aurora = NativeSchemePalette(
        background: 0x1B1C21, foreground: 0xE8E9EF,
        key: 0x8FB4FF, string: 0x9FE3B0, number: 0xF7C37B, literal: 0xC7A6FF, keyword: 0xFF8FC6,
        comment: 0x7F8393 /* 0x6C7083 */, type: 0x6FE0E8, operator: 0xA6A9B6, addition: 0x3FBF6F, deletion: 0xF05F5F,
        heading: 0xC7A6FF, tag: 0xFF8FC6,
        muted: 0x8E909C, hairline: 0x36373C /* 13 % */)
}

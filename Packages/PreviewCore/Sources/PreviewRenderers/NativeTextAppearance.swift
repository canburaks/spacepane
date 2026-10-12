import AppKit
import PreviewContracts

/// Fixed sRGB palettes keep text and every token legible without relying on color alone.
/// The palette is chosen from the user's light or dark color scheme (`NativeColorSchemes`); High Contrast
/// and the system Increase Contrast setting always override that choice.
@MainActor
struct NativeTextPalette {
    let background: NSColor
    let foreground: NSColor
    /// The quieter ink for secondary chrome text (counts, hints, notes): AA on `background` in every scheme and 7:1
    /// in High Contrast. It is a chrome tier, not a syntax role, so turning syntax colors off does not change it.
    let muted: NSColor
    /// The decorative 1 px rule between chrome regions: about 1.4:1 on `background`, 3.2:1 in High Contrast. Never
    /// the only cue for anything.
    let hairline: NSColor
    /// True where the scheme's body text has under 1.5x headroom over AA (Solarized Light, Solarized Dark and
    /// One Dark), so `muted` cannot look clearly lighter than the foreground. Chrome that sets muted text beside
    /// body-ink text then draws the muted text at 11 pt regular, below the body-ink size, so the size carries the
    /// hierarchy where the ink cannot.
    let mutedUsesSizeCue: Bool
    private let roleColors: [PreviewSyntaxRole: NSColor]
    /// Marks invisible characters in the Invisibles mode. It is a warning color, not a syntax role, so it
    /// keeps its paired values in every color scheme.
    private let invisibleMarker: NSColor

    /// `style` carries the user's color-scheme choices; its default is the Standard palettes.
    init(theme: PreviewTheme, isDark: Bool, increasedContrast: Bool, style: PreviewSyntaxStyle = PreviewSyntaxStyle()) {
        let dark: Bool
        switch theme {
        case .light: dark = false
        case .dark: dark = true
        case .system, .highContrast: dark = isDark
        }
        let contrast = theme == .highContrast || increasedContrast
        let scheme = NativeColorSchemes.palette(for: dark ? style.darkScheme : style.lightScheme,
                                                dark: dark, highContrast: contrast)
        background = Self.color(scheme.background)
        foreground = Self.color(scheme.foreground)
        muted = Self.color(scheme.muted)
        hairline = Self.color(scheme.hairline)
        mutedUsesSizeCue = scheme.mutedUsesSizeCue
        roleColors = Dictionary(uniqueKeysWithValues: PreviewSyntaxRole.allCases.map { ($0, Self.color(scheme.color(for: $0))) })
        invisibleMarker = dark ? Self.color(contrast ? 0xFFB3DA : 0xFF8FC8) : Self.color(contrast ? 0x7A0A47 : 0xA3125F)
    }

    func color(for role: PreviewSyntaxRole, style: PreviewSyntaxStyle = PreviewSyntaxStyle()) -> NSColor {
        guard style.usesColor else { return foreground }
        return roleColors[role] ?? foreground
    }

    /// Marks the visible stand-ins of the Invisibles mode. It is pink, apart from every token color,
    /// and meets the same contrast minimums. With color off it is the body color: the mode then
    /// relies on weight and underline.
    func invisibleMarkerColor(style: PreviewSyntaxStyle = PreviewSyntaxStyle()) -> NSColor {
        style.usesColor ? invisibleMarker : foreground
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

@MainActor
struct NativeTextTypography {
    let font: NSFont
    let paragraphStyle: NSParagraphStyle
    let characterSpacing: CGFloat
    let ligatures: Int
    let didUseFallback: Bool

    init(_ requested: PreviewTypography, syntaxStyle: PreviewSyntaxStyle = PreviewSyntaxStyle()) {
        // Snapshot validation is primary; this guard also protects direct renderer callers.
        let settings = requested.isValid ? requested : PreviewTypography()
        let resolution = Self.resolveFont(settings)
        font = resolution.font
        didUseFallback = !requested.isValid || resolution.fallback
            || syntaxStyle.boldRoles.union(syntaxStyle.italicRoles).contains(where: { role in
                !Self.styledFont(resolution.font, bold: syntaxStyle.boldRoles.contains(role),
                                 italic: syntaxStyle.italicRoles.contains(role)).supported
            })
        characterSpacing = CGFloat(settings.characterSpacing)
        ligatures = settings.ligatures ? 1 : 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(settings.lineSpacing)
        paragraph.alignment = .natural
        paragraph.baseWritingDirection = .natural
        paragraph.lineBreakMode = settings.wrapsLines ? .byWordWrapping : .byClipping
        // Empty stops remove the system's fixed stops; defaultTabInterval then repeats forever.
        paragraph.tabStops = []
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: resolution.font]).width
        paragraph.defaultTabInterval = max(1, spaceWidth + CGFloat(settings.characterSpacing)) * CGFloat(settings.tabWidth)
        paragraphStyle = paragraph.copy() as? NSParagraphStyle ?? paragraph
    }

    func attributes(foreground: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraphStyle,
         .kern: characterSpacing, .ligature: ligatures]
    }

    /// Font traits are applied to concealed tokens only; unavailable traits retain the readable base face.
    func attributes(foreground: NSColor, role: PreviewSyntaxRole,
                    style: PreviewSyntaxStyle) -> [NSAttributedString.Key: Any] {
        var attributes = attributes(foreground: foreground)
        attributes[.font] = Self.styledFont(font, bold: style.boldRoles.contains(role),
                                           italic: style.italicRoles.contains(role)).font
        return attributes
    }

    private static func styledFont(_ base: NSFont, bold: Bool, italic: Bool) -> (font: NSFont, supported: Bool) {
        let manager = NSFontManager.shared
        var styled = base
        var supported = true
        if bold {
            let candidate = manager.convert(styled, toHaveTrait: .boldFontMask)
            if manager.traits(of: candidate).contains(.boldFontMask) { styled = candidate }
            else { supported = false }
        }
        if italic {
            let candidate = manager.convert(styled, toHaveTrait: .italicFontMask)
            if manager.traits(of: candidate).contains(.italicFontMask) { styled = candidate }
            else { supported = false }
        }
        return (styled, supported)
    }

    private static func resolveFont(_ settings: PreviewTypography) -> (font: NSFont, fallback: Bool) {
        let manager = NSFontManager.shared
        let size = CGFloat(settings.fontSize)
        let weight: NSFont.Weight
        let familyWeight: Int
        switch settings.weight {
        case .regular: weight = .regular; familyWeight = 5
        case .medium: weight = .medium; familyWeight = 6
        case .semibold: weight = .semibold; familyWeight = 8
        case .bold: weight = .bold; familyWeight = 9
        }
        var fallback = false
        var font: NSFont
        if let family = settings.fontFamily {
            let traits: NSFontTraitMask = settings.italic ? [.italicFontMask] : []
            if let requested = manager.font(withFamily: family, traits: traits, weight: familyWeight, size: size) {
                font = requested
            } else if let regular = manager.font(withFamily: family, traits: [], weight: familyWeight, size: size) {
                font = regular
                fallback = true
            } else {
                font = .monospacedSystemFont(ofSize: size, weight: weight)
                fallback = true
            }
            // AppKit can choose a nearby available weight even when the requested face is absent.
            if manager.weight(of: font) != familyWeight { fallback = true }
        } else {
            font = .monospacedSystemFont(ofSize: size, weight: weight)
        }
        if settings.italic {
            let italic = manager.convert(font, toHaveTrait: .italicFontMask)
            if manager.traits(of: italic).contains(.italicFontMask) {
                font = italic
            } else {
                fallback = true
            }
        }
        return (font, fallback)
    }
}

import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native per-pass text style attributes", .serialized)
@MainActor
struct NativeTextStylePassTests {
    @Test func existingRoleAttributesPreserveFullTypographyAndSafeCharacters() {
        let requested = PreviewTypography(fontSize: 26, wrapsLines: false, weight: .semibold,
            italic: true, lineSpacing: 7, characterSpacing: 2, ligatures: false, tabWidth: 8)
        let syntaxStyle = PreviewSyntaxStyle(usesColor: false, boldRoles: [.key, .heading],
                                            italicRoles: [.comment, .key])
        let typography = NativeTextTypography(requested, syntaxStyle: syntaxStyle)
        let palette = NativeTextPalette(theme: .highContrast, isDark: true, increasedContrast: true)
        let expectedKeys: Set<NSAttributedString.Key> = [.font, .foregroundColor, .paragraphStyle, .kern, .ligature]
        let safe = "safe café • 日本語 • 😀 [REDACTED]\n\t42"
        for role in PreviewSyntaxRole.allCases {
            let attributes = typography.attributes(foreground: palette.color(for: role, style: syntaxStyle),
                                                   role: role, style: syntaxStyle)
            #expect(Set(attributes.keys) == expectedKeys)
            #expect((attributes[.font] as? NSFont)?.pointSize == 26)
            #expect(attributes[.foregroundColor] as? NSColor == palette.foreground)
            #expect(attributes[.kern] as? CGFloat == 2)
            #expect(attributes[.ligature] as? Int == 0)
            let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
            #expect(paragraph === typography.paragraphStyle)
            #expect(paragraph?.lineSpacing == 7)
            #expect(paragraph?.alignment == .natural)
            #expect(paragraph?.baseWritingDirection == .natural)
            #expect(paragraph?.lineBreakMode == .byClipping)
            #expect(paragraph?.tabStops.isEmpty == true)
            #expect(paragraph?.defaultTabInterval == typography.paragraphStyle.defaultTabInterval)
            let text = NSMutableAttributedString(string: safe)
            text.addAttributes(attributes, range: NSRange(location: 0, length: text.length))
            #expect(text.string == safe)
        }
    }

    @Test func existingRoleFontsRetainBaseTraitsAndUnsupportedFaceFallback() {
        let requested = PreviewTypography(fontSize: 19, weight: .bold, italic: true)
        let typography = NativeTextTypography(requested)
        let plain = typography.attributes(foreground: .textColor, role: .string, style: .init())
        #expect((plain[.font] as? NSFont)?.fontDescriptor == typography.font.fontDescriptor)
        let style = PreviewSyntaxStyle(boldRoles: [.key], italicRoles: [.comment])
        let unsupported = NativeTextTypography(PreviewTypography(fontFamily: "Apple Color Emoji"), syntaxStyle: style)
        #expect(unsupported.didUseFallback)
        for role in [.key, .comment] as [PreviewSyntaxRole] {
            let attributes = unsupported.attributes(foreground: .textColor, role: role, style: style)
            #expect((attributes[.font] as? NSFont)?.fontDescriptor == unsupported.font.fontDescriptor)
            #expect(attributes[.paragraphStyle] as? NSParagraphStyle === unsupported.paragraphStyle)
        }
        let missing = NativeTextTypography(PreviewTypography(fontSize: 19,
            fontFamily: "FixtureFontThatDoesNotExist-StylePass"))
        #expect(missing.didUseFallback)
        #expect(missing.font.pointSize == 19)
        let invalid = NativeTextTypography(PreviewTypography(fontSize: .nan, characterSpacing: .infinity))
        #expect(invalid.didUseFallback)
        #expect(invalid.font.pointSize == 13)
        #expect(invalid.characterSpacing == 0)
    }

    @Test func preparedPassMatchesEveryExistingAttributeAcrossAppearanceAndFallbackChoices() {
        let requests = [
            PreviewTypography(),
            PreviewTypography(fontSize: 26, wrapsLines: false, weight: .bold, italic: true,
                lineSpacing: 7, characterSpacing: 2, ligatures: false, tabWidth: 8),
            PreviewTypography(fontSize: 19, fontFamily: "FixtureFontThatDoesNotExist-StylePass"),
            PreviewTypography(fontFamily: "Apple Color Emoji"),
            PreviewTypography(fontSize: .nan, characterSpacing: .infinity)
        ]
        let styles = [
            PreviewSyntaxStyle(),
            PreviewSyntaxStyle(boldRoles: [.key, .heading], italicRoles: [.key, .comment]),
            PreviewSyntaxStyle(usesColor: false, boldRoles: [.number], italicRoles: [.string]),
            PreviewSyntaxStyle(boldRoles: Set(PreviewSyntaxRole.allCases),
                               italicRoles: Set(PreviewSyntaxRole.allCases))
        ]
        for requested in requests {
            for style in styles {
                let typography = NativeTextTypography(requested, syntaxStyle: style)
                for theme in PreviewTheme.allCases {
                    for dark in [false, true] {
                        let palette = NativeTextPalette(theme: theme, isDark: dark, increasedContrast: true)
                        let pass = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: style)
                        #expect((pass.baseAttributes as NSDictionary).isEqual(
                            typography.attributes(foreground: palette.foreground) as NSDictionary))
                        for role in PreviewSyntaxRole.allCases {
                            let expected = typography.attributes(foreground: palette.color(for: role, style: style),
                                                                 role: role, style: style)
                            #expect((pass.attributes(for: role) as NSDictionary).isEqual(expected as NSDictionary))
                        }
                    }
                }
            }
        }
    }

    @Test func repeatedLookupsReuseResolvedObjectsAndNewPassesRefreshStyleChoices() {
        let typography = NativeTextTypography(PreviewTypography(fontSize: 26, characterSpacing: 2))
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        let pass = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: .init())
        for role in PreviewSyntaxRole.allCases {
            let first = pass.attributes(for: role)
            let next = pass.attributes(for: role)
            let firstFont = first[.font] as? NSFont
            let nextFont = next[.font] as? NSFont
            #expect(firstFont === nextFont)
            #expect(first[.paragraphStyle] as? NSParagraphStyle === typography.paragraphStyle)
        }
        var altered = pass.attributes(for: .key)
        altered[.foregroundColor] = NSColor.red
        #expect(pass.attributes(for: .key)[.foregroundColor] as? NSColor == palette.color(for: .key))
        let changedStyle = PreviewSyntaxStyle(usesColor: false, boldRoles: [.key], italicRoles: [.key])
        let changed = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: changedStyle)
        #expect(changed.attributes(for: .key)[.foregroundColor] as? NSColor == palette.foreground)
        let changedFont = changed.attributes(for: .key)[.font] as? NSFont
        #expect(changedFont.map { NSFontManager.shared.traits(of: $0).contains([.boldFontMask, .italicFontMask]) } == true)
        #expect(pass.attributes(for: .key)[.foregroundColor] as? NSColor == palette.color(for: .key))
        let darkPalette = NativeTextPalette(theme: .dark, isDark: true, increasedContrast: false)
        let restyledTypography = NativeTextTypography(PreviewTypography(fontSize: 18, lineSpacing: 3,
            characterSpacing: -0.5, ligatures: false, tabWidth: 2), syntaxStyle: changedStyle)
        let restyled = NativeTextStylePass(typography: restyledTypography, palette: darkPalette, syntaxStyle: changedStyle)
        #expect((restyled.baseAttributes[.font] as? NSFont)?.pointSize == 18)
        #expect(restyled.baseAttributes[.foregroundColor] as? NSColor == darkPalette.foreground)
        #expect(restyled.baseAttributes[.kern] as? CGFloat == -0.5)
        #expect(restyled.baseAttributes[.ligature] as? Int == 0)
        #expect((restyled.baseAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing == 3)
        #expect((pass.baseAttributes[.font] as? NSFont)?.pointSize == 26)
    }
}

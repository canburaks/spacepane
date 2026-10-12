import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Native appearance and content preservation", .serialized)
@MainActor
struct NativeTextAppearanceTests {
    @Test func everyFixedPaletteHasReadableBodyAndTokenContrast() throws {
        for theme in PreviewTheme.allCases {
            for dark in [false, true] {
                for increased in [false, true] {
                    let palette = NativeTextPalette(theme: theme, isDark: dark, increasedContrast: increased)
                    let minimum = theme == .highContrast || increased ? 7.0 : 4.5
                    for color in [palette.foreground] + PreviewSyntaxRole.allCases.map({ palette.color(for: $0) }) {
                        #expect(try contrast(color, palette.background) >= minimum)
                    }
                }
            }
        }
    }

    @Test func semanticTraitsAndColorOptOutPreserveFontSizeAndConcealedCharacters() {
        let palette = NativeTextPalette(theme: .highContrast, isDark: false, increasedContrast: true)
        let style = PreviewSyntaxStyle(usesColor: false, boldRoles: [.key], italicRoles: [.comment])
        let typography = NativeTextTypography(PreviewTypography(fontSize: 26))
        let safe = #"{"password":"[REDACTED]","value":42}"#
        let attributed = NSMutableAttributedString(string: safe, attributes: typography.attributes(foreground: palette.foreground))
        let range = (safe as NSString).range(of: #""password""#)
        let attributes = typography.attributes(foreground: palette.color(for: .key, style: style), role: .key, style: style)
        attributed.addAttributes(attributes, range: range)
        #expect(attributed.string == safe)
        #expect(attributes[.foregroundColor] as? NSColor == palette.foreground)
        #expect((attributes[.font] as? NSFont)?.pointSize == 26)
        #expect((attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } == true)
        for role in PreviewSyntaxRole.allCases { #expect(palette.color(for: role, style: style) == palette.foreground) }
        let unsupported = NativeTextTypography(PreviewTypography(fontFamily: "Apple Color Emoji"),
            syntaxStyle: PreviewSyntaxStyle(italicRoles: [.comment]))
        #expect(unsupported.didUseFallback)
        let fallback = unsupported.attributes(foreground: palette.foreground, role: .comment,
            style: PreviewSyntaxStyle(italicRoles: [.comment]))
        #expect((fallback[.font] as? NSFont)?.pointSize == 13)
    }

    @Test func unavailableFamilyAndInvalidValuesResolveToSafeFonts() {
        let missing = NativeTextTypography(PreviewTypography(fontSize: 19, fontFamily: "FixtureFontThatDoesNotExist-80A7"))
        #expect(missing.didUseFallback)
        #expect(missing.font.pointSize == 19)
        #expect(missing.paragraphStyle.defaultTabInterval.isFinite)
        let invalid = NativeTextTypography(PreviewTypography(fontSize: .nan, lineSpacing: .infinity,
                                                            characterSpacing: .nan, tabWidth: Int.max))
        #expect(invalid.didUseFallback)
        #expect(invalid.font.pointSize == 13)
        #expect(invalid.paragraphStyle.lineSpacing == 0)
        #expect(invalid.characterSpacing == 0)
        #expect(invalid.paragraphStyle.defaultTabInterval > 0)
    }

    @Test func typographyAttributesPreserveRequestedSpacingAndTabPolicy() {
        let resolved = NativeTextTypography(PreviewTypography(fontSize: 16, weight: .bold, lineSpacing: 7,
                                                             characterSpacing: 2, ligatures: false, tabWidth: 8))
        #expect(!resolved.didUseFallback)
        #expect(resolved.font.pointSize == 16)
        #expect(resolved.paragraphStyle.lineSpacing == 7)
        #expect(resolved.characterSpacing == 2)
        #expect(resolved.ligatures == 0)
        #expect(resolved.paragraphStyle.tabStops.isEmpty)
        let space = (" " as NSString).size(withAttributes: [.font: resolved.font]).width
        #expect(abs(resolved.paragraphStyle.defaultTabInterval - (space + 2) * 8) < 0.01)
    }

    @Test func unsupportedItalicFaceKeepsReadableFontAndReportsFallback() {
        let resolved = NativeTextTypography(PreviewTypography(fontFamily: "Apple Color Emoji", italic: true))
        #expect(resolved.didUseFallback)
        #expect(resolved.font.pointSize == 13)
        #expect(resolved.paragraphStyle.defaultTabInterval > 0)
    }

    @Test func stylingKeepsExactConcealedTextSelectionAndViewport() throws {
        let text = #"{"password":"[REDACTED]","emoji":"😀"}"# + "\n" + String(repeating: "safe line\n", count: 200)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let outcome = ready(text, syntax: .json, redactions: 1)
        view.display(outcome, theme: .light)
        view.layoutSubtreeIfNeeded()
        let (scroll, content) = try components(of: view)
        let selection = (text as NSString).range(of: "[REDACTED]")
        content.setSelectedRange(selection)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 160))
        let origin = scroll.contentView.bounds.origin
        view.display(outcome, typography: PreviewTypography(fontSize: 17, lineSpacing: 3), theme: .dark)
        view.layoutSubtreeIfNeeded()
        #expect(content.string == text)
        #expect(content.textStorage?.string == text)
        #expect(content.selectedRange() == selection)
        #expect(scroll.contentView.bounds.origin == origin)
        #expect((content.string as NSString).substring(with: content.selectedRange()) == "[REDACTED]")
        view.viewDidChangeEffectiveAppearance()
        #expect(content.selectedRange() == selection)
        #expect(scroll.contentView.bounds.origin == origin)
        view.display(outcome, resetsContentState: true)
        #expect(content.selectedRange() == NSRange(location: 0, length: 0))
        #expect(scroll.contentView.bounds.origin == .zero)
    }

    @Test func syntaxIsASemanticHintAndDoesNotDependOnFormatID() throws {
        let text = #"{"key":12}"#
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.display(ready(text, syntax: .plain, format: .json), theme: .light)
        let (_, content) = try components(of: view)
        let keyOffset = (text as NSString).range(of: #""key""#).location
        let plain = try #require(content.textStorage?.attribute(.foregroundColor, at: keyOffset, effectiveRange: nil) as? NSColor)
        view.display(ready(text, syntax: .json, format: .plainText), theme: .light)
        let highlighted = try #require(content.textStorage?.attribute(.foregroundColor, at: keyOffset, effectiveRange: nil) as? NSColor)
        #expect(highlighted != plain)
        #expect(content.string == text)
    }

    @Test func zeroSizeHostDefersMeasurementAndWrappingUsesAvailableWidth() throws {
        let view = NativePreviewView(frame: .zero)
        view.display(ready(String(repeating: "line with safe words ", count: 40)))
        let (scroll, content) = try components(of: view)
        #expect(content.textContainer?.widthTracksTextView == false)
        view.setFrameSize(NSSize(width: 180, height: 200))
        view.layoutSubtreeIfNeeded()
        let container = try #require(content.textContainer)
        #expect(container.widthTracksTextView)
        #expect(abs(container.containerSize.width - (scroll.contentSize.width - content.textContainerInset.width * 2)) < 1)
        #expect(abs(content.frame.width - scroll.contentSize.width) < 1)
    }

    @Test func unwrappedLongLineExpandsAndReturnsToWrappingWithoutLosingSelection() throws {
        let text = String(repeating: "long source line ", count: 60)
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 240, height: 220))
        let outcome = ready(text)
        view.display(outcome, typography: PreviewTypography(wrapsLines: false))
        view.layoutSubtreeIfNeeded()
        let (scroll, content) = try components(of: view)
        #expect(scroll.hasHorizontalScroller)
        #expect(content.frame.width > scroll.contentSize.width * 2)
        let narrowWidth = content.frame.width
        let selection = NSRange(location: 10, length: 6)
        content.setSelectedRange(selection)
        view.display(outcome, typography: PreviewTypography(fontSize: 20, wrapsLines: false, characterSpacing: 2))
        #expect(content.frame.width > narrowWidth)
        #expect(content.selectedRange() == selection)
        view.display(outcome, typography: PreviewTypography(wrapsLines: true))
        view.layoutSubtreeIfNeeded()
        #expect(!scroll.hasHorizontalScroller)
        #expect(abs(content.frame.width - scroll.contentSize.width) < 1)
        #expect(content.selectedRange() == selection)
        #expect(content.string == text)
    }

    @Test func forcedThemeFillsStatusBackgroundAndFallbackHintIsVisible() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        for theme in [PreviewTheme.light, .dark] {
            view.display(ready("safe"), typography: PreviewTypography(fontFamily: "FixtureFontThatDoesNotExist-80A7"), theme: theme)
            let status = view.statusLabel
            #expect(status.stringValue.contains(PreviewStrings.text(.typographyFallbackHint)))
            let background = try #require(view.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
            #expect(try contrast(#require(status.textColor), background) >= 4.5)
        }
    }

    private func ready(_ text: String, syntax: TextSyntax = .plain, redactions: Int = 0,
                       format: FormatID = .plainText) -> PreviewOutcome {
        .ready(TextPresentation(formatID: format, text: text, lineCount: text.components(separatedBy: "\n").count,
                                byteCount: text.utf8.count, encoding: .utf8, redactionCount: redactions, syntax: syntax))
    }

    private func components(of view: NativePreviewView) throws -> (NSScrollView, NSTextView) {
        let scroll = view.scrollView
        return (scroll, try #require(scroll.documentView as? NSTextView))
    }

    private func contrast(_ first: NSColor, _ second: NSColor) throws -> Double {
        func luminance(_ input: NSColor) throws -> Double {
            let color = try #require(input.usingColorSpace(.sRGB))
            func channel(_ value: CGFloat) -> Double {
                let value = Double(value)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return channel(color.redComponent) * 0.2126 + channel(color.greenComponent) * 0.7152 + channel(color.blueComponent) * 0.0722
        }
        let first = try luminance(first)
        let second = try luminance(second)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

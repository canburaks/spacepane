import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Stored attributes are the contract for token colour, face and every shared typography attribute.
@Suite("Native source token styling", .serialized)
@MainActor
struct NativeSourceTokenStylingTests {
    private static let styles: [(PreviewTypography, PreviewSyntaxStyle, PreviewTheme)] = [
        (PreviewTypography(), PreviewSyntaxStyle(), .light),
        (PreviewTypography(fontSize: 26, weight: .semibold, italic: true, lineSpacing: 7, characterSpacing: 2, ligatures: false),
         PreviewSyntaxStyle(usesColor: false, boldRoles: [.key, .heading], italicRoles: [.comment, .key]), .highContrast),
        (PreviewTypography(fontFamily: "Menlo", weight: .bold),
         PreviewSyntaxStyle(boldRoles: Set(PreviewSyntaxRole.allCases), italicRoles: Set(PreviewSyntaxRole.allCases)), .dark),
        (PreviewTypography(wrapsLines: false, fontFamily: "FixtureFontThatDoesNotExist-TokenStyling"),
         PreviewSyntaxStyle(boldRoles: [.string], italicRoles: [.number]), .light)
    ]

    @Test func storageHasTheFullRoleAttributesOnTokensAndTheBaseAttributesBetween() throws {
        let source = "let value = 42 // note\nfunc run() { return \"text\" }\n# heading style\nif true { null }\n"
        for (requested, syntaxStyle, theme) in Self.styles {
            let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
            let outcome = PreviewOutcome.ready(TextPresentation(formatID: .sourceCode, text: source, lineCount: 4,
                byteCount: source.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .sourceCode))
            view.display(outcome, typography: requested, theme: theme, syntaxStyle: syntaxStyle, resetsContentState: true)
            view.layoutSubtreeIfNeeded()
            let scroll = view.scrollView
            let content = try #require(scroll.documentView as? NSTextView)
            let storage = try #require(content.textStorage)
            let tokens = SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode)
            #expect(!tokens.isEmpty)
            let resolved = NativeTextTypography(requested, syntaxStyle: syntaxStyle)
            let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let palette = NativeTextPalette(theme: theme, isDark: isDark,
                increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            let pass = NativeTextStylePass(typography: resolved, palette: palette, syntaxStyle: syntaxStyle)
            var covered = IndexSet()
            for token in tokens {
                covered.insert(integersIn: token.range.location..<NSMaxRange(token.range))
                var range = NSRange()
                let attributes = storage.attributes(at: token.range.location, effectiveRange: &range)
                #expect(NSDictionary(dictionary: attributes).isEqual(to: pass.attributes(for: token.role)),
                        "\(token.role) at \(token.range) for \(theme)")
                #expect(range.location <= token.range.location)
            }
            for offset in 0..<storage.length where !covered.contains(offset) {
                let attributes = storage.attributes(at: offset, effectiveRange: nil)
                #expect(NSDictionary(dictionary: attributes).isEqual(to: pass.baseAttributes), "base text at \(offset)")
            }
            #expect(storage.string == source)
        }
    }

    @Test func restylingReplacesEveryTokenRunWithoutRereadingTheSource() throws {
        let source = "let value = 42 // note\n\"key\": true\n"
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let outcome = PreviewOutcome.ready(TextPresentation(formatID: .sourceCode, text: source, lineCount: 2,
            byteCount: source.utf8.count, encoding: .utf8, redactionCount: 0, syntax: .sourceCode))
        view.display(outcome, typography: PreviewTypography(), theme: .light, resetsContentState: true)
        let scroll = view.scrollView
        let content = try #require(scroll.documentView as? NSTextView)
        let storage = try #require(content.textStorage)
        let before = try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        view.display(outcome, typography: PreviewTypography(fontSize: 21), theme: .dark)
        view.layoutSubtreeIfNeeded()
        let tokens = SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode)
        let keyword = try #require(tokens.first)
        let font = try #require(storage.attribute(.font, at: keyword.range.location, effectiveRange: nil) as? NSFont)
        let after = try #require(storage.attribute(.foregroundColor, at: keyword.range.location, effectiveRange: nil) as? NSColor)
        #expect(font.pointSize == 21)
        #expect(after != before)
        #expect(storage.string == source)
    }
}

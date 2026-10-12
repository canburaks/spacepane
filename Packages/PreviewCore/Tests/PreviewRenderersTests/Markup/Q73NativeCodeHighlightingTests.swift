import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 native safe code body highlighting", .serialized)
@MainActor
struct Q73NativeCodeHighlightingTests {
    private let english = Locale(identifier: "en_US")
    private let typography = PreviewTypography(fontSize: 18, wrapsLines: false, fontFamily: "Menlo")
    private let style = PreviewSyntaxStyle(usesColor: true, boldRoles: [.keyword], italicRoles: [.comment])

    @Test func renderedCodeUsesTheLanguageRolesAndConfiguredCodeFaceWhileProseKeepsItsReadingFont() throws {
        let host = InteractionHarness(width: 1200)
        defer { host.release() }
        let body = "let value = \"😀\" // comment\n\nreturn 12"
        let source = "# Heading\n\nprose let value\n\n```swift\n" + body + "\n```"
        show(source, in: host)
        let storage = try #require(host.textView.textStorage), text = storage.string as NSString
        let range = text.range(of: body), palette = host.view.currentPalette()
        try #require(range.location != NSNotFound)
        let resolved = NativeTextTypography(typography, syntaxStyle: style)
        let pass = NativeTextStylePass(typography: resolved, palette: palette, syntaxStyle: style)
        for (word, role) in [("let", PreviewSyntaxRole.keyword), ("\"😀\"", .string), ("// comment", .comment), ("12", .number)] {
            let token = text.range(of: word, options: [], range: range)
            try #require(token.location != NSNotFound)
            #expect(storage.attribute(.foregroundColor, at: token.location, effectiveRange: nil) as? NSColor == palette.color(for: role, style: style))
            #expect(storage.attribute(.font, at: token.location, effectiveRange: nil) as? NSFont == pass.attributes(for: role)[.font] as? NSFont)
            let paragraph = try #require(storage.attribute(.paragraphStyle, at: token.location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(paragraph.textBlocks.contains { $0 is NativeCodeTextBlock })
        }
        let prose = text.range(of: "prose let value").location
        #expect(storage.attribute(.font, at: prose, effectiveRange: nil) as? NSFont == NSFont.systemFont(ofSize: 18))
        #expect(storage.attribute(.foregroundColor, at: prose, effectiveRange: nil) as? NSColor == palette.foreground)
        #expect(text.substring(with: range).utf16.elementsEqual(body.utf16))
    }

    @Test func tokenStylingPreservesForeignParagraphsCardsDirectionIndentTabsAndNonTokenAttributes() throws {
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        let resolved = NativeTextTypography(typography, syntaxStyle: style)
        let pass = NativeTextStylePass(typography: resolved, palette: palette, syntaxStyle: style)
        let storage = NSTextStorage(string: "let\nمرحبا", attributes: pass.baseAttributes)
        let paragraph = NSMutableParagraphStyle(), foreign = NSTextBlock()
        let card = NativeCodeTextBlock.make(palette: palette)
        let quote = NativeQuoteTextBlock.make(fontSize: 18, palette: palette, direction: .rightToLeft)
        paragraph.textBlocks = [foreign, quote, card]; paragraph.baseWritingDirection = .rightToLeft
        paragraph.firstLineHeadIndent = 23; paragraph.headIndent = 17; paragraph.lineHeightMultiple = 1.7
        paragraph.defaultTabInterval = 35; paragraph.lineBreakMode = .byWordWrapping
        storage.addAttributes([.paragraphStyle: paragraph, .kern: 1.5, .ligature: 0,
                               .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                              range: NSRange(location: 0, length: storage.length))
        let before = storage.attributedSubstring(from: NSRange(location: 4, length: storage.length - 4))
        let tokens = [JSONSyntaxToken(range: NSRange(location: 0, length: 3), role: .keyword),
                      .init(range: NSRange(location: NSNotFound, length: Int.max), role: .string)]
        NativeCodeBlockStyling.apply(tokens, to: storage, stylePass: pass)
        let current = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(current == paragraph && current.textBlocks[0] === foreign && current.textBlocks[1] === quote && current.textBlocks[2] === card)
        #expect(storage.attribute(.kern, at: 0, effectiveRange: nil) as? Double == 1.5)
        #expect(storage.attribute(.ligature, at: 0, effectiveRange: nil) as? Int == 0)
        #expect(storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.color(for: .keyword, style: style))
        #expect(storage.attributedSubstring(from: NSRange(location: 4, length: storage.length - 4)).isEqual(to: before))
        #expect(storage.string == "let\nمرحبا")
    }

    @Test func appearanceOnlyChangesReuseTokensButExactCodeUnitsAndLanguageMetadataInvalidateThem() throws {
        let owner = PreviewTextContentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 400))
        var scans = 0
        owner.codeBlockTokenBuilder = { text, blocks in scans += 1; return CodeBlockSyntaxTokens.tokens(in: text, blocks: blocks) }
        let composed = "let value = \"café\"; return 1", decomposed = "let value = \"cafe\u{301}\"; return 1"
        #expect(composed == decomposed && !composed.utf16.elementsEqual(decomposed.utf16))
        replace(composed, language: .swift, in: owner)
        apply(.light, to: owner); try #require(scans == 1)
        let target = try #require(owner.codeBlockCopyTarget(at: 0))
        owner.textView.setSelectedRange(NSRange(location: 4, length: 5))
        let selection = owner.textView.selectedRanges
        for theme in [PreviewTheme.dark, .highContrast, .light] { apply(theme, to: owner) }
        #expect(scans == 1 && owner.codeBlockCopyTarget(at: 0) == target && owner.textView.selectedRanges == selection)
        replace(decomposed, language: .swift, in: owner); apply(.light, to: owner)
        #expect(scans == 2 && owner.textView.string.utf16.elementsEqual(decomposed.utf16))
        let number = (decomposed as NSString).range(of: "1").location
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        #expect(owner.textView.textStorage?.attribute(.foregroundColor, at: number, effectiveRange: nil) as? NSColor == palette.color(for: .number, style: style))
        replace(decomposed, language: .python, in: owner); apply(.light, to: owner)
        #expect(scans == 3)
        #expect(owner.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.color(for: .string, style: style))
    }

    @Test func emptyUnknownAndReplacementBodiesCannotReuseOldRoleRangesOrLeakCardsIntoSource() throws {
        let owner = PreviewTextContentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 400))
        replace("let value = 123 // comment", language: .swift, in: owner); apply(.light, to: owner)
        replace("let", language: nil, in: owner); apply(.light, to: owner)
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        #expect(owner.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.color(for: .string, style: style))
        _ = owner.replaceContent("let", syntax: .plain, language: nil, decorations: [], codeBlocks: [], markerRanges: [],
                                 hasDisplayableContent: true, keepsReadingPosition: false, resetsContentState: false)
        owner.apply(typography: typography, resolved: NativeTextTypography(typography, syntaxStyle: style), palette: palette,
                    syntaxStyle: style, showsLineNumbers: false, isRendered: false)
        let paragraph = try #require(owner.textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.textBlocks.isEmpty)
        #expect(owner.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.foreground)
        owner.clear(); apply(.light, to: owner)
        #expect(owner.textView.string.isEmpty && owner.codeBlockCopyTarget(at: 0) == nil)
    }

    private func replace(_ body: String, language: SourceLanguageID?, in owner: PreviewTextContentView) {
        let range = NSRange(location: 0, length: body.utf16.count)
        _ = owner.replaceContent(body, syntax: .plain, language: nil, decorations: [.init(range: range, style: .code)],
                                 codeBlocks: [.init(range: range, language: language)], markerRanges: [],
                                 hasDisplayableContent: true, keepsReadingPosition: false, resetsContentState: false)
    }
    private func apply(_ theme: PreviewTheme, to owner: PreviewTextContentView) {
        let palette = NativeTextPalette(theme: theme, isDark: false, increasedContrast: false)
        owner.apply(typography: typography, resolved: NativeTextTypography(typography, syntaxStyle: style), palette: palette,
                    syntaxStyle: style, showsLineNumbers: false, isRendered: true, locale: english)
    }
    private func show(_ source: String, in host: InteractionHarness) {
        host.view.display(.ready(plainPresentation(source, format: .markdown, syntax: .markdown)), typography: typography,
                          theme: .light, syntaxStyle: style, locale: english)
        host.view.layoutSubtreeIfNeeded()
    }
}

import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@MainActor
private func styled(_ document: SafeMarkdownDocument, theme: PreviewTheme = .light) -> (NSTextStorage, NativeTextTypography, NativeTextPalette) {
    let typography = NativeTextTypography(PreviewTypography())
    let palette = NativeTextPalette(theme: theme, isDark: false, increasedContrast: false)
    let pass = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: .init())
    let storage = NSTextStorage(string: document.text, attributes: pass.baseAttributes)
    for decoration in document.decorations {
        NativeMarkdownStyling.apply(decoration, to: storage, typography: typography, palette: palette, syntaxStyle: .init())
    }
    return (storage, typography, palette)
}

@MainActor
private func location(of text: String, in storage: NSTextStorage) -> Int {
    (storage.string as NSString).range(of: text).location
}

@MainActor
private func traits(_ storage: NSTextStorage, at location: Int) -> NSFontTraitMask {
    let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    return font.map { NSFontManager.shared.traits(of: $0) } ?? []
}

@MainActor
private func paragraph(_ storage: NSTextStorage, at location: Int) -> NSParagraphStyle? {
    storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
}

@Suite("Markup styling", .serialized)
@MainActor
struct MarkupStylingTests {
    @Test func boldAndItalicComposeOnTheSameText() throws {
        let (storage, _, _) = styled(try renderMarkdown("***both*** and *italic* and **bold**"))
        let both = traits(storage, at: location(of: "both", in: storage))
        #expect(both.contains(.boldFontMask) && both.contains(.italicFontMask))
        #expect(traits(storage, at: location(of: "italic", in: storage)).contains(.italicFontMask))
        #expect(!traits(storage, at: location(of: "italic", in: storage)).contains(.boldFontMask))
        #expect(traits(storage, at: location(of: "bold", in: storage)).contains(.boldFontMask))
    }

    @Test func headingsAreLargerAndInlineStylesComposeInsideThem() throws {
        let (storage, typography, _) = styled(try renderMarkdown("# Big *italic* title\n\nbody"))
        let heading = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize > typography.font.pointSize)
        let inner = location(of: "italic", in: storage)
        #expect(traits(storage, at: inner).contains(.italicFontMask))
        let italicFont = try #require(storage.attribute(.font, at: inner, effectiveRange: nil) as? NSFont)
        #expect(italicFont.pointSize == heading.pointSize)
    }

    @Test func strikethroughAndCodeUseTheirAttributes() throws {
        let (storage, typography, palette) = styled(try renderMarkdown("~~gone~~ and `code`\n\n```\nblock\n```"))
        let gone = location(of: "gone", in: storage)
        #expect((storage.attribute(.strikethroughStyle, at: gone, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.foregroundColor, at: gone, effectiveRange: nil) as? NSColor == palette.color(for: .comment))
        for word in ["code", "block"] {
            let font = try #require(storage.attribute(.font, at: location(of: word, in: storage), effectiveRange: nil) as? NSFont)
            #expect(font.isFixedPitch)
            #expect(font.pointSize == typography.font.pointSize)
        }
    }

    @Test func mathIsSerifItalicInADistinctColorAndDisplayMathIsCentered() throws {
        let (storage, _, palette) = styled(try renderMarkdown("Inline $x^2$ here\n\n$$\n\\alpha\n$$"))
        let inline = location(of: "x²", in: storage)
        #expect(traits(storage, at: inline).contains(.italicFontMask))
        #expect(storage.attribute(.foregroundColor, at: inline, effectiveRange: nil) as? NSColor == palette.color(for: .number))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor != palette.color(for: .number))
        #expect(paragraph(storage, at: location(of: "α", in: storage))?.alignment == .center)
        #expect(paragraph(storage, at: 0)?.alignment != .center)
    }

    @Test func alertsUseADifferentColorPerKindAndBoldTitles() throws {
        let (storage, _, _) = styled(try renderMarkdown("> [!NOTE]\n> a\n\n> [!CAUTION]\n> b"))
        let note = location(of: MarkdownRenderer.alertTitle(.note), in: storage)
        let caution = location(of: MarkdownRenderer.alertTitle(.caution), in: storage)
        #expect(traits(storage, at: note).contains(.boldFontMask))
        #expect(storage.attribute(.foregroundColor, at: note, effectiveRange: nil) as? NSColor
                != storage.attribute(.foregroundColor, at: caution, effectiveRange: nil) as? NSColor)
    }

    @Test func nestedListsIndentByDepthWithAHangingMarker() throws {
        let (storage, typography, _) = styled(try renderMarkdown("- top\n  - nested\n    continuation\n- again"))
        let top = try #require(paragraph(storage, at: location(of: "top", in: storage)))
        let nested = try #require(paragraph(storage, at: location(of: "nested", in: storage)))
        #expect(top.firstLineHeadIndent == 0)
        #expect(top.headIndent > 0)
        #expect(nested.firstLineHeadIndent >= typography.font.pointSize)
        #expect(nested.headIndent > nested.firstLineHeadIndent)
        let continuation = try #require(paragraph(storage, at: location(of: "continuation", in: storage)))
        #expect(continuation.firstLineHeadIndent == nested.headIndent)
    }

    @Test func rightToLeftParagraphsGetRightToLeftDirectionAndOthersKeepNatural() throws {
        let (storage, _, _) = styled(try renderMarkdown("English paragraph\n\nمرحبا بالعالم\n\nAnother English"))
        #expect(paragraph(storage, at: location(of: "مرحبا", in: storage))?.baseWritingDirection == .rightToLeft)
        #expect(paragraph(storage, at: location(of: "English paragraph", in: storage))?.baseWritingDirection == .natural)
        #expect(paragraph(storage, at: location(of: "Another", in: storage))?.baseWritingDirection == .natural)
    }

    @Test func aRightToLeftRunKeepsEachParagraphsOwnListIndentation() throws {
        let (storage, _, _) = styled(try renderMarkdown("- عنصر أول\n  - عنصر ثان\n"))
        let first = try #require(paragraph(storage, at: location(of: "عنصر أول", in: storage)))
        let second = try #require(paragraph(storage, at: location(of: "عنصر ثان", in: storage)))
        #expect(first.baseWritingDirection == .rightToLeft && second.baseWritingDirection == .rightToLeft)
        #expect(second.firstLineHeadIndent > first.firstLineHeadIndent)
    }

    @Test func frontMatterGetsABackgroundAndBoldKeys() throws {
        let (storage, _, _) = styled(try renderMarkdown("---\ntitle: Report\n---\nBody"))
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
        #expect(traits(storage, at: 0).contains(.boldFontMask))
        #expect(storage.attribute(.backgroundColor, at: location(of: "Body", in: storage), effectiveRange: nil) == nil)
    }

    @Test func screenplayLayoutUsesIndentAndAlignment() throws {
        let document = try #require(FountainRenderer.render("INT. A - DAY\n\nBOB\n(softly)\nHello.\n\nCUT TO:\n\n> THE END <", limits: .init()))
        let (storage, typography, _) = styled(document)
        let unit = typography.font.pointSize * 1.5
        #expect(paragraph(storage, at: location(of: "BOB", in: storage))?.firstLineHeadIndent == 4 * unit)
        #expect(paragraph(storage, at: location(of: "Hello.", in: storage))?.firstLineHeadIndent == 2 * unit)
        #expect(paragraph(storage, at: location(of: "CUT TO:", in: storage))?.alignment == .right)
        #expect(paragraph(storage, at: location(of: "THE END", in: storage))?.alignment == .center)
    }

    @Test func outOfRangeAndEmptyDecorationsAreIgnoredAndNeverCrash() {
        let storage = NSTextStorage(string: "short")
        let typography = NativeTextTypography(PreviewTypography())
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        for range in [NSRange(location: 0, length: 99), NSRange(location: -1, length: 2), NSRange(location: 2, length: 0), NSRange(location: 99, length: 1)] {
            for style in [MarkdownDecoration.Style.bold, .math, .rightToLeft, .listItem(depth: 3, markerLength: 2), .indent(2), .frontMatterBlock, .centered] {
                NativeMarkdownStyling.apply(.init(range: range, style: style), to: storage, typography: typography, palette: palette, syntaxStyle: .init())
            }
        }
        #expect(storage.string == "short")
    }

    @Test func colorlessSyntaxStylesFallBackToTheForegroundWithoutLosingFontTraits() throws {
        let document = try renderMarkdown("**bold** and $x$")
        let typography = NativeTextTypography(PreviewTypography())
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        let storage = NSTextStorage(string: document.text)
        let style = PreviewSyntaxStyle(usesColor: false)
        for decoration in document.decorations {
            NativeMarkdownStyling.apply(decoration, to: storage, typography: typography, palette: palette, syntaxStyle: style)
        }
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == palette.foreground)
        #expect(traits(storage, at: 0).contains(.boldFontMask))
    }

    @Test func nativeViewShowsDecoratedRenderedTextAndRestylingKeepsTheSelection() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let text = "# Title\n\nمرحبا بالعالم\n\n- item\n"
        let presentation = TextPresentation(formatID: .markdown, text: text, lineCount: 5, byteCount: text.utf8.count,
                                            encoding: .utf8, redactionCount: 0, syntax: .markdown)
        view.display(.ready(presentation))
        let textView = try #require(view.scrollView.documentView as? NSTextView)
        let range = (textView.string as NSString).range(of: "بالعالم")
        textView.setSelectedRange(range)
        view.display(.ready(presentation), typography: .init(fontSize: 18), theme: .dark)
        #expect(textView.selectedRange() == range)
        let storage = try #require(textView.textStorage)
        let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.baseWritingDirection == .rightToLeft)
    }
}

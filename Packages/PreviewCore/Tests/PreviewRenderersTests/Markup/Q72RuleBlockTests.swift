import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 rules as block edges", .serialized)
@MainActor
struct Q72RuleBlockTests {
    private let glyphs = String(repeating: "\u{2500}", count: 24)

    @Test func aRuleKeepsItsCharactersAsInvisibleAlmostHeightlessTextAndGainsABlockEdge() throws {
        let document = try renderMarkdown("above\n\n***\n\nbelow")
        for theme in [PreviewTheme.light, .dark, .highContrast] {
            for usesColor in [true, false] {
                let styled = Q72Support.styled(document, theme: theme, usesColor: usesColor)
                let at = try Q72Support.offset(of: glyphs, in: styled.storage)
                #expect(styled.storage.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor == NSColor.clear)
                let font = try #require(styled.storage.attribute(.font, at: at, effectiveRange: nil) as? NSFont)
                #expect(font.pointSize <= 2)
                let line = try #require(try Q72Support.paragraph(of: glyphs, in: styled.storage).textBlocks.first as? NativeRuleTextBlock)
                #expect(line.width(for: .border, edge: .maxY) == NativeRuleTextBlock.thickness)
                #expect(line.width(for: .border, edge: .minY) == 0 && line.width(for: .border, edge: .minX) == 0)
                #expect(line.borderColor(for: .maxY) == styled.palette.muted)
                #expect(try Q72Support.paragraph(of: "above", in: styled.storage).textBlocks.isEmpty)
                #expect(styled.storage.string.utf16.elementsEqual(document.text.utf16))
            }
        }
    }

    @Test func everyThematicBreakSpellingGetsItsOwnBlockAndRestyleKeepsExactlyOne() throws {
        let document = try renderMarkdown("a\n\n---\n\n***\n\n___\n\nb")
        let styled = Q72Support.styled(document)
        for decoration in document.decorations + document.decorations {
            NativeMarkdownStyling.apply(decoration, to: styled.storage, typography: styled.typography,
                                        palette: styled.palette, syntaxStyle: styled.syntax)
        }
        var blocks: [NativeRuleTextBlock] = []
        styled.storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: styled.storage.length),
                                          options: []) { value, _, _ in
            for block in (value as? NSParagraphStyle)?.textBlocks ?? [] {
                if let rule = block as? NativeRuleTextBlock { blocks.append(rule) }
            }
        }
        #expect(blocks.count == 3)
    }

    @Test func nativeTextKitDrawsOneLineAcrossTheColumnWhereTheGlyphsWereAndNothingAroundIt() throws {
        for words in ["above words", "مرحبا بالعالم"] {
            let host = InteractionHarness(width: 640, height: 420)
            defer { host.release() }
            Q72Support.show(words + "\n\n---\n\nbelow words", in: host)
            let paper = host.view.currentPalette().background
            let bounds = try Q72Support.blockBounds(of: glyphs, in: host.textView)
            let container = try #require(host.textView.textContainer)
            #expect(bounds.height > 1 && bounds.height < 40)
            #expect(bounds.minX >= host.textView.textContainerOrigin.x
                    && bounds.maxX <= host.textView.textContainerOrigin.x + container.containerSize.width)
            let run = try Q72Support.longestHorizontalRun(awayFrom: paper, in: bounds, of: host.textView)
            #expect(Double(run) >= Double(bounds.width) * 0.9)
            // The prose around the rule is not affected.
            let above = try Q72Support.paragraph(of: words, in: try #require(host.textView.textStorage))
            #expect(above.textBlocks.isEmpty)
        }
    }

    @Test func narrowWidthKeepsTheLineInsideTheColumnAndSelectionAndCopyKeepTheSourceCharacters() throws {
        let host = InteractionHarness(width: 360, height: 420)
        defer { host.release() }
        Q72Support.show("above\n\n***\n\nbelow", in: host, typography: .init(fontSize: 26, fontFamily: "Menlo"))
        #expect(!host.view.scrollView.hasHorizontalScroller)
        let bounds = try Q72Support.blockBounds(of: glyphs, in: host.textView)
        let container = try #require(host.textView.textContainer)
        #expect(bounds.maxX <= host.textView.textContainerOrigin.x + container.containerSize.width + 0.5)
        host.textView.setSelectedRange(try Q72Support.range(of: glyphs, in: host.textView))
        host.textView.copy(nil)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(glyphs.utf16))
    }
}

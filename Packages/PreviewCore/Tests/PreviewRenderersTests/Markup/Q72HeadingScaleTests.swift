import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 modular heading scale", .serialized)
@MainActor
struct Q72HeadingScaleTests {
    @Test func theScaleIsModularFromTheBodySizeAndLevelSixIsTheBody() {
        for base in [9.0, 13.0, 18.0, 26.0] {
            let size = CGFloat(base)
            #expect(MarkupHeadingScale.pointSize(level: 6, base: size) == size)
            for level in 1..<6 {
                let upper = MarkupHeadingScale.pointSize(level: level, base: size)
                let lower = MarkupHeadingScale.pointSize(level: level + 1, base: size)
                #expect(upper > lower)
                #expect(abs(upper / lower - MarkupHeadingScale.ratio) < 0.0001)
            }
            #expect(MarkupHeadingScale.pointSize(level: 1, base: size) <= size * 2.1)
        }
    }

    @Test func levelsOutsideOneToSixClampAndUnusableSizesNeverProduceNonsense() {
        #expect(MarkupHeadingScale.multiple(level: 0) == MarkupHeadingScale.multiple(level: 1))
        #expect(MarkupHeadingScale.multiple(level: 99) == 1)
        #expect(MarkupHeadingScale.pointSize(level: 1, base: 200) == 200)
        #expect(MarkupHeadingScale.pointSize(level: 1, base: 60) == MarkupHeadingScale.maximumPointSize)
        for base in [CGFloat.nan, .infinity, 0, -5] {
            #expect(MarkupHeadingScale.pointSize(level: 1, base: base) == 1)
            #expect(MarkupHeadingScale.spacingBefore(level: 1, base: base) == 0)
        }
    }

    @Test func spaceAboveGrowsWithTheRankOfTheHeading() {
        let spaces = (1...6).map { MarkupHeadingScale.spacingBefore(level: $0, base: 13) }
        #expect(spaces == spaces.sorted(by: >) && Set(spaces).count == 6 && spaces.last! > 0)
    }

    @Test func styledHeadingsUseTheSystemBoldFaceAtTheScaledSizeInTheHeadingInkWithSpaceAbove() throws {
        let source = (1...6).map { String(repeating: "#", count: $0) + " Level\($0)" }.joined(separator: "\n\n") + "\n\nbody"
        let document = try renderMarkdown(source)
        for size in [9.0, 13.0, 26.0] {
            for theme in [PreviewTheme.light, .dark, .highContrast] {
                let styled = Q72Support.styled(document, size: size, theme: theme)
                let base = styled.typography.font.pointSize
                for level in 1...6 {
                    let at = try Q72Support.offset(of: "Level\(level)", in: styled.storage)
                    let font = try #require(styled.storage.attribute(.font, at: at, effectiveRange: nil) as? NSFont)
                    #expect(font.pointSize == MarkupHeadingScale.pointSize(level: level, base: base))
                    #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
                    #expect(styled.storage.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor
                            == styled.palette.color(for: .heading))
                    let paragraph = try Q72Support.paragraph(of: "Level\(level)", in: styled.storage)
                    #expect(paragraph.paragraphSpacingBefore == MarkupHeadingScale.spacingBefore(level: level, base: base))
                }
                let body = try Q72Support.paragraph(of: "body", in: styled.storage)
                #expect(body.paragraphSpacingBefore == 0)
                #expect(styled.storage.string.utf16.elementsEqual(document.text.utf16))
            }
        }
    }

    @Test func inlineEmphasisInsideAHeadingKeepsTheHeadingSize() throws {
        let styled = Q72Support.styled(try renderMarkdown("## A *slanted* and `coded` title"), size: 18)
        let heading = MarkupHeadingScale.pointSize(level: 2, base: styled.typography.font.pointSize)
        let slanted = try Q72Support.offset(of: "slanted", in: styled.storage)
        let font = try #require(styled.storage.attribute(.font, at: slanted, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == heading && NSFontManager.shared.traits(of: font).contains(.italicFontMask))
    }

    @Test func narrowWrappingAndLargeTextKeepLongHeadingsInsideTheColumnAndTheCopyExact() throws {
        let host = InteractionHarness(width: 360, height: 420)
        defer { host.release() }
        let long = Array(repeating: "wrapping heading words", count: 12).joined(separator: " ")
        let source = "# " + long + "\n\nمرحبا بالعالم\n\n## " + long
        Q72Support.show(source, in: host, typography: .init(fontSize: 26, fontFamily: "Menlo"))
        #expect(!host.view.scrollView.hasHorizontalScroller)
        #expect(host.textView.frame.width <= host.view.scrollView.contentSize.width)
        let first = try Q72Support.glyphRect(of: Q72Support.range(of: "wrapping", in: host.textView), in: host.textView)
        let container = try #require(host.textView.textContainer)
        #expect(first.maxX <= host.textView.textContainerOrigin.x + container.containerSize.width + 0.5)
        host.textView.selectAll(nil)
        host.textView.copy(nil)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(host.textView.string.utf16))
    }
}

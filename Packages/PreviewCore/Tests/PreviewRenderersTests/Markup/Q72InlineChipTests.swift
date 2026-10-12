import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 inline code chips", .serialized)
@MainActor
struct Q72InlineChipTests {
    @Test func theTintKeepsTheCodeInkReadableOnEverySchemeOrDrawsNoChipAtAll() {
        for scheme in PreviewColorSchemeID.allCases {
            for dark in [false, true] where scheme.isAvailable(for: dark ? .dark : .light) {
                for highContrast in [false, true] {
                    let palette = NativeColorSchemes.palette(for: scheme, dark: dark, highContrast: highContrast)
                    let tint = MarkupSurface.chipTint(background: palette.background, foreground: palette.foreground,
                                                      ink: palette.string)
                    #expect(tint == 0 || MarkupSurface.chipLadder.contains(tint))
                    if tint > 0 {
                        let tinted = MarkupSurface.blend(palette.background, palette.foreground, fraction: tint)
                        let ratio = NativeSchemePalette.contrastRatio(palette.string, tinted)
                        #expect(ratio >= NativeSchemePalette.minimumTextContrast, "\(scheme.rawValue) \(dark) \(highContrast)")
                    }
                }
            }
        }
        for dark in [false, true] {
            let palette = NativeColorSchemes.standard(dark: dark)
            #expect(MarkupSurface.chipTint(background: palette.background, foreground: palette.foreground,
                                           ink: palette.string) > 0)
        }
    }

    @Test func blendingIsExactAtTheEndsAndClampsOutsideThem() {
        #expect(MarkupSurface.blend(0x102030, 0xF0E0D0, fraction: 0) == 0x102030)
        #expect(MarkupSurface.blend(0x102030, 0xF0E0D0, fraction: 1) == 0xF0E0D0)
        #expect(MarkupSurface.blend(0x102030, 0xF0E0D0, fraction: -3) == 0x102030)
        #expect(MarkupSurface.blend(0x102030, 0xF0E0D0, fraction: 9) == 0xF0E0D0)
        #expect(MarkupSurface.blend(0x000000, 0xFFFFFF, fraction: 0.5) == 0x808080)
    }

    @Test func inlineCodeGetsTheChipAndTheConfiguredCodeFaceWhileProseAndEmphasisDoNot() throws {
        let document = try renderMarkdown("Use `code` and **bold** here")
        for theme in [PreviewTheme.light, .dark] {
            for usesColor in [true, false] {
                let styled = Q72Support.styled(document, theme: theme, usesColor: usesColor)
                let palette = styled.palette
                let tint = MarkupSurface.chipTint(
                    background: MarkupSurface.rgb(of: palette.background), foreground: MarkupSurface.rgb(of: palette.foreground),
                    ink: MarkupSurface.rgb(of: palette.color(for: .string, style: styled.syntax)))
                let code = try Q72Support.offset(of: "code", in: styled.storage)
                let chip = styled.storage.attribute(.backgroundColor, at: code, effectiveRange: nil) as? NSColor
                if tint > 0 {
                    #expect(chip == palette.foreground.withAlphaComponent(CGFloat(tint)))
                } else {
                    #expect(chip == nil)
                }
                #expect(styled.storage.attribute(.font, at: code, effectiveRange: nil) as? NSFont == styled.typography.font)
                for word in ["Use", "bold", "here"] {
                    let at = try Q72Support.offset(of: word, in: styled.storage)
                    #expect(styled.storage.attribute(.backgroundColor, at: at, effectiveRange: nil) == nil)
                }
                #expect(styled.storage.string.utf16.elementsEqual(document.text.utf16))
            }
        }
    }

    @Test func aFencedBodyHasTheCardAndNoChipAndInlineCodeNextToItStillHasOne() throws {
        let document = try renderMarkdown("Use `inline` words\n\n```swift\nlet value = 1\n```\n\nafter")
        let styled = Q72Support.styled(document, cards: true)
        let body = try Q72Support.offset(of: "let value", in: styled.storage)
        #expect(styled.storage.attribute(.backgroundColor, at: body, effectiveRange: nil) == nil)
        let paragraph = try Q72Support.paragraph(of: "let value", in: styled.storage)
        #expect(paragraph.textBlocks.contains { $0 is NativeCodeTextBlock })
        let inline = try Q72Support.offset(of: "inline", in: styled.storage)
        #expect(styled.storage.attribute(.backgroundColor, at: inline, effectiveRange: nil) != nil)
    }

    @Test func nativeTextKitPaintsTheChipBehindTheSpanAndCopyStaysExactInBothDirections() throws {
        for (source, word) in [("Use `inline` here", "inline"), ("مرحبا `code` بالعالم", "code")] {
            let host = InteractionHarness()
            defer { host.release() }
            Q72Support.show(source, in: host)
            let palette = host.view.currentPalette()
            let tint = MarkupSurface.chipTint(
                background: MarkupSurface.rgb(of: palette.background), foreground: MarkupSurface.rgb(of: palette.foreground),
                ink: MarkupSurface.rgb(of: palette.color(for: .string)))
            try #require(tint > 0)
            let expected = Q72Support.color(MarkupSurface.blend(MarkupSurface.rgb(of: palette.background),
                                                                MarkupSurface.rgb(of: palette.foreground), fraction: tint))
            let range = try Q72Support.range(of: word, in: host.textView)
            let rect = try Q72Support.glyphRect(of: range, in: host.textView)
            #expect(try Q72Support.matchingFraction(expected, in: rect.insetBy(dx: 1, dy: 1), of: host.textView) > 0.35)
            host.textView.setSelectedRange(range)
            host.textView.copy(nil)
            #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(word.utf16))
        }
    }

    @Test func narrowWrappingAndALargeTextSizeKeepChipsInsideTheColumnWithoutHorizontalScrolling() throws {
        let host = InteractionHarness(width: 360, height: 420)
        defer { host.release() }
        let source = Array(repeating: "see `alpha beta` and `gamma`", count: 25).joined(separator: " ")
        Q72Support.show(source, in: host, typography: .init(fontSize: 26, fontFamily: "Menlo"))
        #expect(!host.view.scrollView.hasHorizontalScroller)
        #expect(host.textView.frame.width <= host.view.scrollView.contentSize.width)
        let storage = try #require(host.textView.textStorage)
        var chipRuns = 0
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            if value != nil { chipRuns += 1 }
        }
        #expect(chipRuns == 50)
    }
}

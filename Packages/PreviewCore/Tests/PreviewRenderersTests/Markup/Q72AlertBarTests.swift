import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 alert bars", .serialized)
@MainActor
struct Q72AlertBarTests {
    private func title(_ kind: MarkupAlertKind) -> String { MarkdownRenderer.alertTitle(kind) }

    @Test func everyKindHasItsOwnRoleAndEveryRoleMeetsContrastOnEveryBackground() {
        let roles = MarkupAlertKind.allCases.map(\.syntaxRole)
        #expect(Set(roles).count == MarkupAlertKind.allCases.count)
        for scheme in PreviewColorSchemeID.allCases {
            for dark in [false, true] where scheme.isAvailable(for: dark ? .dark : .light) {
                for highContrast in [false, true] {
                    let palette = NativeColorSchemes.palette(for: scheme, dark: dark, highContrast: highContrast)
                    for role in roles {
                        let ratio = NativeSchemePalette.contrastRatio(palette.color(for: role), palette.background)
                        #expect(ratio >= 3.0, "\(scheme.rawValue) dark \(dark) contrast \(highContrast) \(role.rawValue)")
                    }
                }
            }
        }
    }

    @Test func theMarkdownRendererMarksTheTitleAndEveryBodyLineOfAnAlertAndNothingElse() throws {
        let document = try renderMarkdown("> [!WARNING]\n> first\n> second\n\n> plain quote\n\nafter")
        let bars = document.decorations.compactMap { decoration -> (MarkupAlertKind, String)? in
            if case .alertBar(let kind) = decoration.style { return (kind, document.substring(decoration.range)) }
            return nil
        }
        let titleLine = MarkdownRenderer.alertGlyph(.warning) + " " + title(.warning)
        #expect(bars.map(\.0) == [.warning, .warning])
        #expect(bars.map(\.1) == [titleLine, "first second"])
        #expect(document.has(.quote, over: "plain quote"))
        #expect(!bars.contains { $0.1 == "plain quote" || $0.1 == "after" })
    }

    @Test func aQuoteAfterABlankLineIsNotPartOfThePrecedingAlert() throws {
        let document = try renderMarkdown("> [!TIP]\n> tip body\n\n> separate quote")
        let marked = document.decorations.filter { if case .alertBar = $0.style { true } else { false } }
        #expect(marked.map { document.substring($0.range) } == [MarkdownRenderer.alertGlyph(.tip) + " " + title(.tip), "tip body"])
    }

    @Test func theTitleOfARightToLeftAlertJoinsItsBodysDirectionRunAndAnEnglishAlertHasNone() throws {
        let document = try renderMarkdown("> [!NOTE]\n> مرحبا بالعالم\n\nplain English\n\n> [!TIP]\n> hello")
        let runs = document.decorations.filter { $0.style == .rightToLeft }.map { $0.range }
        try #require(runs.count == 1)
        let titleLine = MarkdownRenderer.alertGlyph(.note) + " " + title(.note)
        #expect(document.substring(runs[0]) == titleLine + "\nمرحبا بالعالم")
    }

    @Test func theLineOrientedRenderersMarkAdmonitionsTheSameWay() throws {
        let document = try #require(AsciiDocRenderer.render("NOTE: Remember this.", limits: .init()))
        let bars = document.decorations.compactMap { decoration -> (MarkupAlertKind, String)? in
            if case .alertBar(let kind) = decoration.style { return (kind, document.substring(decoration.range)) }
            return nil
        }
        #expect(bars.map(\.0) == [.note, .note])
        #expect(bars.map(\.1) == [MarkdownRenderer.alertGlyph(.note) + " " + title(.note), "Remember this."])
    }

    @Test func styledAlertsHaveOneBarInTheKindsRoleInkOnTitleAndBodyForEveryThemeAndColorChoice() throws {
        let source = MarkupAlertKind.allCases.map { "> [!\($0.rawValue.uppercased())]\n> body \($0.rawValue)" }
            .joined(separator: "\n\n")
        let document = try renderMarkdown(source)
        for theme in [PreviewTheme.light, .dark, .highContrast] {
            for usesColor in [true, false] {
                let styled = Q72Support.styled(document, theme: theme, usesColor: usesColor)
                for kind in MarkupAlertKind.allCases {
                    let expected = styled.palette.color(for: kind.syntaxRole, style: styled.syntax)
                    for word in [title(kind), "body \(kind.rawValue)"] {
                        let blocks = try Q72Support.paragraph(of: word, in: styled.storage).textBlocks
                        try #require(blocks.count == 1)
                        let bar = try #require(blocks[0] as? NativeAlertTextBlock)
                        #expect(bar.borderColor(for: .minX) == expected)
                        #expect(bar.width(for: .border, edge: .minX) == NativeAlertTextBlock.thickness)
                        #expect(bar.width(for: .border, edge: .maxX) == 0)
                    }
                }
                #expect(styled.storage.string.utf16.elementsEqual(document.text.utf16))
            }
        }
    }

    @Test func aRightToLeftBodyPutsTheBarOnTheTrailingEdgeOfTitleAndBodyAndAnEnglishOneOnTheLeft() throws {
        let document = try renderMarkdown("> [!NOTE]\n> مرحبا بالعالم\n\n> [!TIP]\n> hello world")
        let styled = Q72Support.styled(document)
        for (word, trailing) in [(title(.note), true), ("مرحبا", true), (title(.tip), false), ("hello", false)] {
            let paragraph = try Q72Support.paragraph(of: word, in: styled.storage)
            #expect(paragraph.baseWritingDirection == (trailing ? NSWritingDirection.rightToLeft : NSWritingDirection.natural))
            let bar = try #require(paragraph.textBlocks.first as? NativeAlertTextBlock)
            let leading = NSRectEdge.minX, trailingEdge = NSRectEdge.maxX
            #expect(bar.width(for: .border, edge: trailing ? trailingEdge : leading) == NativeAlertTextBlock.thickness)
            #expect(bar.width(for: .border, edge: trailing ? leading : trailingEdge) == 0)
        }
    }

    @Test func aPlainQuoteKeepsItsMutedBarWhileTheAlertBesideItHasTheKindBar() throws {
        let document = try renderMarkdown("> [!CAUTION]\n> careful\n\n> plain")
        let styled = Q72Support.styled(document)
        let plain = try Q72Support.paragraph(of: "plain", in: styled.storage)
        #expect(plain.textBlocks.count == 1 && plain.textBlocks.first is NativeQuoteTextBlock)
        #expect(try Q72Support.paragraph(of: "careful", in: styled.storage).textBlocks.first is NativeAlertTextBlock)
    }

    @Test func applyingTheDecorationsTwiceOrInAnyOrderStillLeavesExactlyOneBar() throws {
        let document = try renderMarkdown("> [!IMPORTANT]\n> body words")
        for reversed in [false, true] {
            let styled = Q72Support.styled(document)
            let decorations = reversed ? Array(document.decorations.reversed()) : document.decorations
            for decoration in decorations + decorations {
                NativeMarkdownStyling.apply(decoration, to: styled.storage, typography: styled.typography,
                                            palette: styled.palette, syntaxStyle: styled.syntax)
            }
            for word in [title(.important), "body words"] {
                let blocks = try Q72Support.paragraph(of: word, in: styled.storage).textBlocks
                #expect(blocks.count == 1 && blocks[0] is NativeAlertTextBlock)
            }
        }
    }

    @Test func nativeTextKitDrawsEachKindsBarBesideTheGlyphsInBothDirectionsAndWrapsNarrow() throws {
        for (words, rtl) in [("alert body words", false), ("مرحبا بالعالم", true)] {
            for kind in [MarkupAlertKind.note, .caution] {
                let host = InteractionHarness(width: 640, height: 420)
                defer { host.release() }
                let marker = "> [!\(kind.rawValue.uppercased())]\n> "
                Q72Support.show(marker + words, in: host)
                let ink = host.view.currentPalette().color(for: kind.syntaxRole)
                let bounds = try Q72Support.blockBounds(of: words, in: host.textView)
                let width = NativeAlertTextBlock.thickness
                let lane = NSRect(x: rtl ? bounds.maxX - width : bounds.minX, y: bounds.minY, width: width, height: bounds.height)
                #expect(try Q72Support.longestVerticalRun(of: ink, in: lane, of: host.textView) >= 12)

                host.window.setContentSize(NSSize(width: 360, height: 420))
                let long = Array(repeating: words, count: 30).joined(separator: " ")
                Q72Support.show(marker + long, in: host)
                let wrapped = try Q72Support.blockBounds(of: words, in: host.textView)
                let container = try #require(host.textView.textContainer)
                let origin = host.textView.textContainerOrigin.x
                #expect(wrapped.minX >= origin && wrapped.maxX <= origin + container.containerSize.width)
                #expect(wrapped.height > 40 && !host.view.scrollView.hasHorizontalScroller)
                let wrappedLane = NSRect(x: rtl ? wrapped.maxX - width : wrapped.minX, y: wrapped.minY, width: width,
                                         height: wrapped.height)
                #expect(try Q72Support.longestVerticalRun(of: ink, in: wrappedLane, of: host.textView) >= 12)
            }
        }
    }

    @Test func restylingChangesOnlyInkNotTheTextTheSelectionOrTheCopy() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let source = "> [!WARNING]\n> cafe\u{301} 😀 •••• safe\n\nafter"
        Q72Support.show(source, in: host)
        let safe = Array(host.textView.string.utf16)
        let selection = (host.textView.string as NSString).range(of: "cafe\u{301} 😀 ••••")
        host.textView.setSelectedRange(selection)
        for theme in [PreviewTheme.dark, .highContrast, .light] {
            Q72Support.show(source, in: host, theme: theme, usesColor: theme != .highContrast)
            #expect(Array(host.textView.string.utf16) == safe && host.textView.selectedRange() == selection)
        }
        host.textView.copy(nil)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual("cafe\u{301} 😀 ••••".utf16))
        host.textView.selectAll(nil)
        host.textView.copy(nil)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(safe))
    }
}

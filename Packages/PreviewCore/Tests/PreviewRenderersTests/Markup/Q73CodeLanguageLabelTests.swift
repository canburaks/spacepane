import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q73 code language label", .serialized)
@MainActor
struct Q73CodeLanguageLabelTests {
    private let english = Locale(identifier: "en_US")
    nonisolated static let copyCases = [
        ("en", "Copy Swift code"), ("tr", "Swift kodunu kopyala"), ("de", "Swift-Code kopieren"),
        ("fr", "Copier le code Swift"), ("zh-Hans", "复制 Swift 代码"), ("ja", "Swift コードをコピー"),
        ("hi", "Swift कोड कॉपी करें"), ("ku-Latn", "Koda Swift kopî bike"), ("ru", "Копировать код Swift"),
        ("id", "Salin kode Swift"), ("bn", "Swift কোড কপি করুন"), ("ha", "Kwafi lambar Swift"),
        ("pt", "Copiar código Swift"), ("es", "Copiar código Swift")
    ]

    // MARK: Names

    @Test func everyCanonicalLanguageHasADistinctNonEmptyPrintableName() {
        var seen = Set<String>()
        for language in SourceLanguageID.all {
            let name = CodeLanguageName.text(for: language)
            #expect(name != nil && !(name ?? "").isEmpty, "\(language.rawValue)")
            #expect(!(name ?? "").unicodeScalars.contains { $0.properties.generalCategory == .control || $0.value == 0x7F })
            seen.insert(name ?? "")
        }
        #expect(seen.count == SourceLanguageID.all.count)
    }

    @Test func properNamesAreWrittenTheWayTheirCommunitiesWriteThemAndAreNeverLocalized() {
        let expected: [(SourceLanguageID, String)] = [
            (.swift, "Swift"), (.cpp, "C++"), (.csharp, "C#"), (.objectiveC, "Objective-C"),
            (.javascript, "JavaScript"), (.powerShell, "PowerShell"), (.graphQL, "GraphQL"), (.sql, "SQL"),
            (.webAssemblyText, "WebAssembly"), (.fsharp, "F#"), (.html, "HTML")
        ]
        for (language, name) in expected { #expect(CodeLanguageName.text(for: language) == name) }
    }

    @Test func rawLabelsOutsideTheFiniteSetNeverBecomeANameOrALabel() {
        for language in [nil, SourceLanguageID(rawValue: "js"), .init(rawValue: "\u{212A}otlin"),
                         .init(rawValue: "swift\u{E0061}"), .init(rawValue: String(repeating: "x", count: 100))] {
            #expect(CodeLanguageName.text(for: language) == nil)
            #expect(CodeBlockCopyAccessibilityLabel.text(for: language, locale: english, languagePreferences: ["en"])
                    == "Copy Code Block")
        }
    }

    @Test(arguments: copyCases)
    func theCopyLabelNamesTheLanguageInEveryAppLanguageWithoutTranslatingIt(language: String, label: String) {
        let locale = Locale(identifier: language)
        #expect(CodeBlockCopyAccessibilityLabel.text(for: .swift, locale: locale, languagePreferences: [language]) == label)
        #expect(CodeBlockCopyAccessibilityLabel.text(for: .cpp, locale: locale, languagePreferences: [language]).contains("C++"))
    }

    // MARK: Metrics

    @Test func theLabelFollowsTheCodeSizeWithinBoundsAndTheBandFitsIt() {
        for code in [CGFloat(8), 9, 13, 18, 26, 48] {
            let font = CodeLanguageLabelMetrics.fontSize(forCodeSize: code)
            #expect(font >= 9 && font <= 14)
            // The label hangs from the card's top edge, so it must end inside the top padding and its band.
            let height = ("Swift" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: font)]).height
            #expect(CodeLanguageLabelMetrics.top + ceil(height)
                    <= NativeCodeTextBlock.padding + CodeLanguageLabelMetrics.bandHeight(forCodeSize: code))
        }
        for bad in [CGFloat.nan, .infinity, 0, -3] {
            #expect(CodeLanguageLabelMetrics.fontSize(forCodeSize: bad) == 9)
        }
    }

    // MARK: Cards

    @Test func aRecognizedLanguageKeepsABandAboveTheFirstLineAndOthersKeepTheOrdinaryCard() throws {
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        let plain = NativeCodeTextBlock.make(palette: palette)
        let banded = NativeCodeTextBlock.make(palette: palette, labelBand: 14)
        for edge in [NSRectEdge.minX, .maxX, .maxY] {
            #expect(plain.width(for: .padding, edge: edge) == NativeCodeTextBlock.padding)
            #expect(banded.width(for: .padding, edge: edge) == NativeCodeTextBlock.padding)
        }
        #expect(plain.width(for: .padding, edge: .minY) == NativeCodeTextBlock.padding)
        #expect(banded.width(for: .padding, edge: .minY) == NativeCodeTextBlock.padding + 14)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        for (language, hasBand) in [(SourceLanguageID?.some(.swift), true), (nil, false), (.init(rawValue: "js"), false)] {
            let storage = NSTextStorage(string: "let a = 1", attributes: [.font: font])
            NativeMarkdownStyling.applyCodeBlocks([.init(range: NSRange(location: 0, length: 9), language: language)],
                                                  to: storage, palette: palette)
            let style = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let card = try #require(style.textBlocks.first as? NativeCodeTextBlock)
            let expected = hasBand ? NativeCodeTextBlock.padding + CodeLanguageLabelMetrics.bandHeight(forCodeSize: 13)
                                   : NativeCodeTextBlock.padding
            #expect(card.width(for: .padding, edge: .minY) == expected)
        }
    }

    // MARK: Label ink

    @Test func theLabelInkIsAPaletteTierThatStaysReadableOnTheCardTintInEveryScheme() {
        for scheme in PreviewColorSchemeID.allCases {
            var cases: [(PreviewTheme, PreviewSyntaxStyle)] = []
            if scheme.isAvailable(for: .light) {
                cases.append((.light, PreviewSyntaxStyle(usesColor: true, lightScheme: scheme)))
            }
            if scheme.isAvailable(for: .dark) {
                cases.append((.dark, PreviewSyntaxStyle(usesColor: true, darkScheme: scheme)))
            }
            cases.append((.highContrast, PreviewSyntaxStyle(usesColor: true)))
            for (theme, style) in cases {
                let palette = NativeTextPalette(theme: theme, isDark: theme == .dark, increasedContrast: false, style: style)
                let ink = NativeCodeLanguageLabels.ink(for: palette)
                #expect(ink == palette.muted || ink == palette.foreground)
                let card = MarkupSurface.blend(MarkupSurface.rgb(of: palette.background), MarkupSurface.rgb(of: palette.foreground),
                                               fraction: NativeCodeTextBlock.tint)
                let ratio = NativeSchemePalette.contrastRatio(MarkupSurface.rgb(of: ink), card)
                #expect(ratio >= NativeSchemePalette.minimumTextContrast, "\(scheme.rawValue) \(theme)")
            }
        }
    }

    // MARK: Native view

    private func cardTint(_ host: InteractionHarness) -> NSColor {
        let palette = host.view.currentPalette()
        return Q72Support.color(MarkupSurface.blend(MarkupSurface.rgb(of: palette.background),
                                                    MarkupSurface.rgb(of: palette.foreground), fraction: NativeCodeTextBlock.tint))
    }

    /// Distance from the card's top edge to its first line of code.
    private func topOffset(of word: String, in host: InteractionHarness) throws -> CGFloat {
        let card = try Q72Support.blockBounds(of: word, in: host.textView)
        let manager = try #require(host.textView.layoutManager)
        let location = try Q72Support.offset(of: word, in: try #require(host.textView.textStorage))
        let line = manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: location), effectiveRange: nil)
        return line.minY + host.textView.textContainerOrigin.y - card.minY
    }

    @Test func aRecognizedLanguageIsDrawnAtTheLeadingCornerOfItsCardAboveTheFirstLineWideOrNarrow() throws {
        for width in [1200.0, 360.0] {
            let host = InteractionHarness(width: CGFloat(width), height: 620)
            defer { host.release() }
            host.view.scrollView.scrollerStyle = .overlay
            Q72Support.show("before\n\n```swift\nlet value = 1\n```\n\nafter", in: host)
            let card = try Q72Support.blockBounds(of: "let value", in: host.textView)
            let tint = cardTint(host)
            let band = CodeLanguageLabelMetrics.bandHeight(forCodeSize: 13)
            #expect(abs(try topOffset(of: "let value", in: host) - (NativeCodeTextBlock.padding + band)) < 1)
            let leading = NSRect(x: card.minX + CodeLanguageLabelMetrics.inset, y: card.minY + CodeLanguageLabelMetrics.top,
                                 width: 36, height: 10)
            let trailing = NSRect(x: card.maxX - CodeLanguageLabelMetrics.inset - 36, y: leading.minY, width: 36, height: 10)
            #expect(try Q72Support.matchingFraction(tint, in: leading, of: host.textView) < 0.97)
            #expect(try Q72Support.matchingFraction(tint, in: trailing, of: host.textView) > 0.999)
        }
    }

    @Test func aRightToLeftLayoutDrawsTheLabelAtTheTrailingCornerInstead() throws {
        let host = InteractionHarness(width: 900, height: 620)
        defer { host.release() }
        host.view.scrollView.scrollerStyle = .overlay
        Q72Support.show("```swift\nlet value = 1\n```", in: host)
        host.textView.userInterfaceLayoutDirection = .rightToLeft
        host.textView.needsDisplay = true
        host.view.layoutSubtreeIfNeeded()
        let card = try Q72Support.blockBounds(of: "let value", in: host.textView)
        let tint = cardTint(host)
        let leading = NSRect(x: card.minX + CodeLanguageLabelMetrics.inset, y: card.minY + CodeLanguageLabelMetrics.top,
                             width: 36, height: 10)
        let trailing = NSRect(x: card.maxX - CodeLanguageLabelMetrics.inset - 36, y: leading.minY, width: 36, height: 10)
        #expect(try Q72Support.matchingFraction(tint, in: trailing, of: host.textView) < 0.97)
        #expect(try Q72Support.matchingFraction(tint, in: leading, of: host.textView) > 0.999)
    }

    @Test func aBodyWithoutALanguageKeepsTheOrdinaryCardPaddingAndTheControlSaysCopyCodeBlock() throws {
        let host = InteractionHarness(width: 1200, height: 620)
        defer { host.release() }
        host.view.scrollView.scrollerStyle = .overlay
        Q72Support.show("```\nplain body\n```\n\n```js\nunknown body\n```", in: host)
        for word in ["plain body", "unknown body"] {
            #expect(abs(try topOffset(of: word, in: host) - NativeCodeTextBlock.padding) < 1)
        }
        for button in descendants(of: NativeCodeCopyButton.self, in: host.view).filter({ !$0.isHidden }) {
            #expect(button.accessibilityLabel() == CodeBlockCopyAccessibilityLabel.text(for: nil, locale: english))
        }
    }

    @Test func theMarginControlSpeaksTheLanguageAndTheLayerIsPassiveAndOne() throws {
        let host = InteractionHarness(width: 1200, height: 620)
        defer { host.release() }
        host.view.scrollView.scrollerStyle = .overlay
        Q72Support.show("```swift\nlet value = 1\n```\n\n```python\nvalue = 1\n```", in: host)
        let labels = descendants(of: NativeCodeCopyButton.self, in: host.view).filter { !$0.isHidden }
            .map { $0.accessibilityLabel() ?? "" }
        #expect(labels == [CodeBlockCopyAccessibilityLabel.text(for: .swift, locale: english),
                           CodeBlockCopyAccessibilityLabel.text(for: .python, locale: english)])
        #expect(labels.allSatisfy { $0.contains("Swift") || $0.contains("Python") })
        let layers = descendants(of: NativeCodeLanguageLabels.self, in: host.view)
        try #require(layers.count == 1)
        #expect(layers[0].hitTest(NSPoint(x: 5, y: 5)) == nil && !layers[0].isAccessibilityElement())
        // A second styling pass reuses the layer instead of stacking another one.
        Q72Support.show("```swift\nlet value = 1\n```", in: host, theme: .dark)
        #expect(descendants(of: NativeCodeLanguageLabels.self, in: host.view).count == 1)
    }

    @Test func theLabelNeverEntersTheTextTheSelectionOrTheCopyAndSourceShowsNoCard() throws {
        let host = InteractionHarness(width: 1200, height: 620)
        defer { host.release() }
        host.view.scrollView.scrollerStyle = .overlay
        Q72Support.show("```swift\nlet value = 1\n```", in: host)
        #expect(host.textView.string == "let value = 1")
        host.textView.selectAll(nil)
        host.textView.copy(nil)
        #expect(host.pasteboard.string(forType: .string) == "let value = 1")
        let index = try #require(host.view.displayedModes.firstIndex(of: .source))
        #expect(host.view.selectMode(number: index + 1)); host.view.layoutSubtreeIfNeeded()
        let storage = try #require(host.textView.textStorage)
        var cards = 0
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length), options: []) { value, _, _ in
            cards += ((value as? NSParagraphStyle)?.textBlocks.filter { $0 is NativeCodeTextBlock }.count) ?? 0
        }
        #expect(cards == 0)
    }
}

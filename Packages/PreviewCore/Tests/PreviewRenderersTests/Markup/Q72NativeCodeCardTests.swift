import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 native whole-code cards", .serialized)
@MainActor
struct Q72NativeCodeCardTests {
    private let english = Locale(identifier: "en_US")

    @Test func nativeTintIsContinuousThroughBlankParagraphsAndSourceHasNoCard() throws {
        for theme in [PreviewTheme.light, .dark, .highContrast] {
            for words in ["safe words", "مرحبا بالعالم"] {
                for body in ["\nlet first = \"" + words + "\"\n\nlet last = \"safe\"\n", "\n"] {
                    let host = InteractionHarness()
                    defer { host.release() }
                    let source = codeSource(body), document = try renderMarkdown(source)
                    let range = try #require(document.codeBlocks.first).range
                    show(source, in: host, theme: theme)
                    let tint = try referenceTint(host.view.currentPalette())
                    #expect(host.textView.string.utf16.elementsEqual(document.text.utf16))
                    let geometry = try cardGeometry(range, in: host.textView)
                    #expect(geometry.bounds.width > 100 && geometry.bounds.height > 16)
                    #expect(geometry.lines >= (body == "\n" ? 1 : 4))
                    #expect(try matchingFraction(tint, in: geometry.lane, of: host.textView) > 0.95)
                    #expect(try cards(in: range, of: #require(host.textView.textStorage)).count == 1)
                    try select(.source, in: host)
                    #expect(host.textView.string.utf16.elementsEqual(source.utf16))
                    let storage = try #require(host.textView.textStorage)
                    #expect(try cards(in: NSRange(location: 0, length: storage.length), of: storage).isEmpty)
                    // Text in the same local card lane in Source cannot masquerade as a filled card.
                    #expect(try matchingFraction(tint, in: geometry.lane, of: host.textView) < 0.1)
                }
            }
        }
    }

    @Test func narrowCardsWrapAndTheirVisibleInkStaysInsideTheReadingColumn() throws {
        for word in ["safeWords", "مرحبا بالعالم"] {
            let host = InteractionHarness(width: 360)
            defer { host.release() }
            let body = "let value = \"" + Array(repeating: word, count: 45).joined(separator: " ") + "\""
            let source = codeSource(body), document = try renderMarkdown(source)
            let range = try #require(document.codeBlocks.first).range
            show(source, in: host, typography: .init(fontSize: 18, wrapsLines: false, fontFamily: "Menlo"))
            let palette = host.view.currentPalette()
            let geometry = try cardGeometry(range, in: host.textView)
            let container = try #require(host.textView.textContainer), left = host.textView.textContainerOrigin.x
            #expect(geometry.lines > 2 && geometry.glyphs.width > 40)
            #expect(geometry.bounds.minX >= left && geometry.bounds.maxX <= left + container.containerSize.width)
            // Bidi glyph rectangles include shaping advances; actual raster ink supplies containment evidence.
            #expect(try inkOutsideReadingColumn(palette.background, of: host.textView) == 0)
            #expect(!host.view.scrollView.hasHorizontalScroller)
            #expect(try matchingFraction(referenceTint(palette), in: geometry.lane, of: host.textView) > 0.95)
            #expect(host.textView.string.utf16.elementsEqual(document.text.utf16))
        }
    }

    @Test func adjacentBodiesStaySeparateAndRestyleCannotMutateRetainedCards() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let source = "```swift\nfirst body\n```\n\n```python\nsecond body\n```\n\nOutside"
        let document = try renderMarkdown(source)
        try #require(document.codeBlocks.count == 2)
        show(source, in: host)
        let first = try cardGeometry(document.codeBlocks[0].range, in: host.textView)
        let second = try cardGeometry(document.codeBlocks[1].range, in: host.textView)
        #expect(first.block !== second.block && second.bounds.minY > first.bounds.maxY)
        let separator = NSRect(x: first.lane.minX, y: first.bounds.maxY,
                               width: first.lane.width, height: second.bounds.minY - first.bounds.maxY)
        let paper = host.view.currentPalette().background
        #expect(try matchingFraction(paper, in: separator, of: host.textView) > 0.9)
        let oldColor = first.block.backgroundColor
        for size in [18.0, 26.0, 18.0] {
            show(source, in: host, typography: .init(fontSize: size, fontFamily: "Menlo"), theme: .dark)
            let current = try cardGeometry(document.codeBlocks[0].range, in: host.textView)
            #expect(current.block !== first.block && first.block.backgroundColor == oldColor)
            let storage = try #require(host.textView.textStorage)
            for body in document.codeBlocks { #expect(try cards(in: body.range, of: storage).count == 1) }
            let outside = (storage.string as NSString).range(of: "Outside")
            #expect(try cards(in: outside, of: storage).isEmpty)
        }
    }

    @Test func repeatedCardPassPreservesForeignBlocksParagraphStateFontsAndExactText() throws {
        let body = "alpha\n\nbeta e\u{301} 😀", range = NSRange(location: 0, length: body.utf16.count)
        let light = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        let quote = NativeQuoteTextBlock.make(fontSize: 19, palette: light, direction: .rightToLeft)
        let foreign = NSTextBlock(), a = NSMutableParagraphStyle()
        a.textBlocks = [foreign, quote]; a.firstLineHeadIndent = 17; a.headIndent = 23; a.tailIndent = -5
        a.lineHeightMultiple = 1.7; a.lineBreakMode = .byWordWrapping; a.baseWritingDirection = .rightToLeft
        a.alignment = .right; a.tabStops = []; a.defaultTabInterval = 31
        let font = NSFont.systemFont(ofSize: 19, weight: .bold)
        let storage = NSTextStorage(string: body, attributes: [.font: font, .foregroundColor: NSColor.red,
                                                              .paragraphStyle: a])
        let beta = (body as NSString).range(of: "beta").location
        let b = try #require(a.mutableCopy() as? NSMutableParagraphStyle)
        b.alignment = .center; b.baseWritingDirection = .leftToRight; b.firstLineHeadIndent = 9
        storage.addAttribute(.paragraphStyle, value: b, range: NSRange(location: beta, length: storage.length - beta))
        let before = storage.copy() as! NSAttributedString
        let malformed = [MarkupCodeBlock(range: NSRange(location: NSNotFound, length: Int.max), language: nil),
                         .init(range: NSRange(location: 0, length: 0), language: nil)]
        NativeMarkdownStyling.applyCodeBlocks(malformed, to: storage, palette: light)
        #expect(storage.isEqual(to: before))
        var retained: NativeCodeTextBlock?
        var retainedColor: NSColor?
        for palette in [light, NativeTextPalette(theme: .dark, isDark: true, increasedContrast: false), light] {
            NativeMarkdownStyling.applyCodeBlocks([.init(range: range, language: .swift)], to: storage, palette: palette)
            let owned = try cards(in: range, of: storage)
            try #require(owned.count == 1)
            if let retained { #expect(owned[0] !== retained && retained.backgroundColor == retainedColor) }
            retained = owned[0]; retainedColor = owned[0].backgroundColor
            for location in [0, 6, beta] {
                let current = try #require(storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
                let original = try #require(before.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
                #expect(current.textBlocks.count == 3 && current.textBlocks.first === foreign)
                #expect(current.textBlocks[1] === quote && quote.width(for: .border, edge: .maxX) == 3)
                #expect(current.textBlocks.last === owned[0] && original.textBlocks == [foreign, quote])
                #expect(current.firstLineHeadIndent == original.firstLineHeadIndent && current.headIndent == original.headIndent)
                #expect(current.tailIndent == original.tailIndent && current.lineHeightMultiple == original.lineHeightMultiple)
                #expect(current.lineBreakMode == original.lineBreakMode && current.baseWritingDirection == original.baseWritingDirection)
                #expect(current.alignment == original.alignment && current.tabStops == original.tabStops)
                #expect(current.defaultTabInterval == original.defaultTabInterval)
                #expect(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == font)
                #expect(storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor == NSColor.red)
            }
            #expect(storage.string.utf16.elementsEqual(body.utf16))
        }
    }

    @Test func nativeFontRestyleKeepsSelectionCopyAndSafeCodeUnits() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let body = "cafe\u{301} 😀 ••••\n\nnext", source = codeSource(body)
        let document = try renderMarkdown(source), range = try #require(document.codeBlocks.first).range
        show(source, in: host)
        host.textView.setSelectedRange(range)
        for size in [18.0, 26.0] {
            let typography = PreviewTypography(fontSize: size, fontFamily: "Menlo")
            show(source, in: host, typography: typography, theme: .dark)
            #expect(host.textView.selectedRange() == range && host.textView.string.utf16.elementsEqual(document.text.utf16))
            let storage = try #require(host.textView.textStorage)
            let expected = NativeTextTypography(typography).font
            for word in ["cafe\u{301}", "next"] {
                let location = (storage.string as NSString).range(of: word).location
                try #require(location != NSNotFound && location < storage.length)
                #expect(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == expected)
            }
            #expect(try cards(in: range, of: storage).count == 1)
        }
        host.textView.copy(nil)
        #expect((host.pasteboard.string(forType: .string) ?? "").utf16.elementsEqual(body.utf16))
        try select(.source, in: host)
        #expect(host.textView.string.utf16.elementsEqual(source.utf16))
        let storage = try #require(host.textView.textStorage)
        #expect(try cards(in: NSRange(location: 0, length: storage.length), of: storage).isEmpty)
    }

    private func codeSource(_ body: String) -> String { "before\n\n```swift\n" + body + "\n```\n\nafter" }

    private func show(_ source: String, in host: InteractionHarness, typography: PreviewTypography = .init(),
                      theme: PreviewTheme = .light) {
        host.view.display(.ready(plainPresentation(source, format: .markdown, syntax: .markdown)), typography: typography,
                          theme: theme, syntaxStyle: .init(usesColor: false), locale: english)
        host.view.layoutSubtreeIfNeeded()
    }

    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws {
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1)); host.view.layoutSubtreeIfNeeded()
    }

    private func cards(in range: NSRange, of storage: NSTextStorage) throws -> [NativeCodeTextBlock] {
        var blocks: [NativeCodeTextBlock] = []
        storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, _, _ in
            for block in (value as? NSParagraphStyle)?.textBlocks ?? [] {
                if let card = block as? NativeCodeTextBlock, !blocks.contains(where: { $0 === card }) { blocks.append(card) }
            }
        }
        return blocks
    }

    private func cardGeometry(_ range: NSRange, in view: NSTextView) throws
        -> (block: NativeCodeTextBlock, bounds: NSRect, lane: NSRect, glyphs: NSRect, lines: Int) {
        let storage = try #require(view.textStorage), manager = try #require(view.layoutManager)
        let container = try #require(view.textContainer), blocks = try cards(in: range, of: storage)
        try #require(blocks.count == 1)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let bounds = manager.boundsRect(for: blocks[0], at: glyphs.location, effectiveRange: nil)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        let lane = NSRect(x: bounds.minX + 2, y: bounds.minY + 2, width: 2, height: bounds.height - 4)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
        return (blocks[0], bounds, lane, manager.boundingRect(forGlyphRange: glyphs, in: container), lines)
    }

    private func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: Int(ceil(view.bounds.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func referenceTint(_ palette: NativeTextPalette) throws -> NSColor {
        let reference = CodeCardTintReference(palette: palette)
        return try #require(try bitmap(of: reference).colorAt(x: 4, y: 4)?.usingColorSpace(.sRGB))
    }

    private func matches(_ color: NSColor, _ expected: NSColor) -> Bool {
        abs(color.redComponent - expected.redComponent) < 0.02
            && abs(color.greenComponent - expected.greenComponent) < 0.02
            && abs(color.blueComponent - expected.blueComponent) < 0.02
    }

    private func matchingFraction(_ ink: NSColor, in region: NSRect, of view: NSTextView) throws -> Double {
        let bitmap = try bitmap(of: view), expected = try #require(ink.usingColorSpace(.sRGB))
        let sx = CGFloat(bitmap.pixelsWide) / view.bounds.width, sy = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        let left = max(0, Int(ceil(region.minX * sx))), right = min(bitmap.pixelsWide, Int(floor(region.maxX * sx)))
        let top = max(0, Int(ceil(region.minY * sy))), bottom = min(bitmap.pixelsHigh, Int(floor(region.maxY * sy)))
        try #require(right > left && bottom > top)
        var matched = 0
        for x in left..<right { for y in top..<bottom {
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), matches(color, expected) { matched += 1 }
        } }
        return Double(matched) / Double((right - left) * (bottom - top))
    }

    private func inkOutsideReadingColumn(_ paper: NSColor, of view: NSTextView) throws -> Int {
        let bitmap = try bitmap(of: view), expected = try #require(paper.usingColorSpace(.sRGB))
        let container = try #require(view.textContainer), scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let left = Int(ceil(view.textContainerOrigin.x * scale))
        let right = Int(floor((view.textContainerOrigin.x + container.containerSize.width) * scale))
        var count = 0
        for x in 0..<bitmap.pixelsWide where x < left || x >= right { for y in 0..<bitmap.pixelsHigh {
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), !matches(color, expected) { count += 1 }
        } }
        return count
    }
}

@MainActor
private final class CodeCardTintReference: NSView {
    private let palette: NativeTextPalette
    init(palette: NativeTextPalette) {
        self.palette = palette
        super.init(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill(); bounds.fill()
        // An independent rendering of the brief's chosen tint in the same bitmap color space.
        palette.foreground.withAlphaComponent(0.07).setFill(); bounds.fill()
    }
}

import AppKit
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q72 rendered quote and emphasis", .serialized)
@MainActor
struct Q72RenderedQuoteStylingTests {
    private func style(_ document: SafeMarkdownDocument, size: Double = 13,
                       theme: PreviewTheme = .light, usesColor: Bool = true)
        -> (NSTextStorage, NativeTextTypography, NativeTextPalette) {
        let typography = NativeTextTypography(.init(fontSize: size, fontFamily: "Menlo"))
        let palette = NativeTextPalette(theme: theme, isDark: theme == .dark, increasedContrast: false)
        let syntax = PreviewSyntaxStyle(usesColor: usesColor)
        var base = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: syntax).baseAttributes
        let reading = ReadingLayout(typography: typography)
        base[.font] = reading.font
        base[.paragraphStyle] = reading.paragraphStyle
        let storage = NSTextStorage(string: document.text, attributes: base)
        apply(document.decorations, to: storage, typography: typography, palette: palette, syntax: syntax)
        return (storage, typography, palette)
    }

    private func apply(_ decorations: [MarkdownDecoration], to storage: NSTextStorage,
                       typography: NativeTextTypography, palette: NativeTextPalette,
                       syntax: PreviewSyntaxStyle = .init()) {
        for decoration in decorations {
            NativeMarkdownStyling.apply(decoration, to: storage, typography: typography,
                                        palette: palette, syntaxStyle: syntax)
        }
    }

    private func offset(_ word: String, in storage: NSTextStorage) throws -> Int {
        let location = (storage.string as NSString).range(of: word).location
        #expect(location != NSNotFound)
        return location
    }

    private func paragraph(_ word: String, in storage: NSTextStorage) throws -> NSParagraphStyle {
        try #require(storage.attribute(.paragraphStyle, at: offset(word, in: storage), effectiveRange: nil) as? NSParagraphStyle)
    }

    @Test func emphasisKeepsBodyInkAndComposedProseTraitsAcrossAppearanceChoices() throws {
        let document = try renderMarkdown("***both*** *italic* **bold** and `code`\n\n| header |\n|---|\n| row |")
        for theme in [PreviewTheme.light, .dark, .highContrast] {
            for usesColor in [true, false] {
                let (storage, typography, palette) = style(document, theme: theme, usesColor: usesColor)
                for word in ["both", "italic", "bold"] {
                    let at = try offset(word, in: storage)
                    #expect(storage.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor == palette.foreground)
                    let font = try #require(storage.attribute(.font, at: at, effectiveRange: nil) as? NSFont)
                    #expect(font.pointSize == typography.font.pointSize)
                    let traits = NSFontManager.shared.traits(of: font)
                    #expect(traits.contains(.boldFontMask) == (word != "italic"))
                    #expect(traits.contains(.italicFontMask) == (word != "bold"))
                }
                let at = try offset("code", in: storage)
                #expect(storage.attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor
                        == palette.color(for: .string, style: .init(usesColor: usesColor)))
                #expect(storage.attribute(.font, at: at, effectiveRange: nil) as? NSFont == typography.font)
                #expect(storage.attribute(.foregroundColor, at: try offset("header", in: storage), effectiveRange: nil) as? NSColor
                        == palette.color(for: .literal, style: .init(usesColor: usesColor)))
            }
        }
    }

    @Test func quotesPreserveHeadingCodeAndInertLinkComposition() throws {
        let document = try renderMarkdown("> # Heading\n\n> ordinary ***both*** `code` [label](https://example.invalid/path)")
        let (storage, typography, palette) = style(document)
        for word in ["ordinary", "both", "label", "https://example.invalid/path"] {
            #expect(storage.attribute(.foregroundColor, at: try offset(word, in: storage), effectiveRange: nil) as? NSColor == palette.foreground)
        }
        let heading = try offset("Heading", in: storage)
        #expect(storage.attribute(.foregroundColor, at: heading, effectiveRange: nil) as? NSColor == palette.color(for: .heading))
        #expect((try #require(storage.attribute(.font, at: heading, effectiveRange: nil) as? NSFont)).pointSize > typography.font.pointSize)
        let code = try offset("code", in: storage)
        #expect(storage.attribute(.foregroundColor, at: code, effectiveRange: nil) as? NSColor == palette.color(for: .string))
        #expect(storage.attribute(.font, at: code, effectiveRange: nil) as? NSFont == typography.font)
        for word in ["Heading", "code", "label"] {
            #expect(try paragraph(word, in: storage).textBlocks.count == 1)
            let at = try offset(word, in: storage)
            #expect(storage.attribute(.link, at: at, effectiveRange: nil) == nil)
            #expect(storage.attribute(.attachment, at: at, effectiveRange: nil) == nil)
        }
        // A quote is one native block across differently styled inline runs, even when applied again.
        for _ in 0..<2 {
            let body = try #require(try paragraph("ordinary", in: storage).textBlocks.first)
            #expect(try paragraph("code", in: storage).textBlocks.first === body)
            #expect(try paragraph("label", in: storage).textBlocks.first === body)
            apply(document.decorations, to: storage, typography: typography, palette: palette)
        }
        #expect(storage.string.utf16.elementsEqual(document.text.utf16))
    }

    @Test func nestedQuotesKeepReadingFontsIndentsAndUnadornedBlankParagraphs() throws {
        let document = try renderMarkdown("> outer\n>> nested\n\n> other\n\nOutside")
        for size in [11.0, 28.0] {
            let (storage, typography, _) = style(document, size: size, usesColor: false)
            let outer = try paragraph("outer", in: storage)
            let nested = try paragraph("nested", in: storage)
            #expect(nested.firstLineHeadIndent - outer.firstLineHeadIndent == typography.font.pointSize * 1.5)
            #expect(nested.headIndent - outer.headIndent == typography.font.pointSize * 1.5)
            for word in ["outer", "nested", "other"] {
                let paragraph = try paragraph(word, in: storage)
                #expect(paragraph.textBlocks.count == 1)
                #expect(paragraph.lineHeightMultiple == 1.4 && paragraph.lineBreakMode == .byWordWrapping)
                #expect(storage.attribute(.font, at: try offset(word, in: storage), effectiveRange: nil) as? NSFont == NSFont.systemFont(ofSize: size))
            }
            #expect(try paragraph("Outside", in: storage).textBlocks.isEmpty)
            let blank = (storage.string as NSString).range(of: "\n\n").location + 1
            let blankStyle = try #require(storage.attribute(.paragraphStyle, at: blank, effectiveRange: nil) as? NSParagraphStyle)
            #expect(blankStyle.textBlocks.isEmpty)
        }
    }

    @Test func directionChangesDoNotMutateSharedBlocksOrDuplicateBars() throws {
        let document = try renderMarkdown("> left\n\n> مرحبا\n>> أعمق\n\nOutside")
        let (storage, typography, palette) = style(document)
        for (word, edge) in [("left", NSRectEdge.minX), ("مرحبا", .maxX), ("أعمق", .maxX)] {
            let block = try #require(try paragraph(word, in: storage).textBlocks.first)
            #expect(block.width(for: .border, edge: edge) == 3)
            #expect(block.width(for: .border, edge: edge == .minX ? .maxX : .minX) == 0)
        }
        let retained = try paragraph("left", in: storage)
        let retainedBlock = try #require(retained.textBlocks.first)
        let range = (storage.string as NSString).range(of: "Outside")
        storage.addAttribute(.paragraphStyle, value: retained, range: range)
        let foreign = NSTextBlock()
        let shared = try #require(retained.mutableCopy() as? NSMutableParagraphStyle)
        shared.textBlocks = [foreign] + retained.textBlocks
        storage.addAttribute(.paragraphStyle, value: shared, range: range)
        apply([.init(range: range, style: .rightToLeft)], to: storage, typography: typography, palette: palette)
        let moved = try paragraph("Outside", in: storage)
        #expect(moved.textBlocks.first === foreign)
        let movedBlock = try #require(moved.textBlocks.last)
        #expect(movedBlock !== retainedBlock)
        #expect(movedBlock.width(for: .border, edge: .maxX) == 3)
        #expect(retainedBlock.width(for: .border, edge: .minX) == 3)
        #expect(retainedBlock.width(for: .border, edge: .maxX) == 0)
        apply(document.decorations, to: storage, typography: typography, palette: palette)
        apply(document.decorations, to: storage, typography: typography, palette: palette)
        for word in ["left", "مرحبا", "أعمق"] { #expect(try paragraph(word, in: storage).textBlocks.count == 1) }
        #expect(try paragraph("Outside", in: storage).textBlocks.first === foreign)
    }

    @Test func nativeRestyleAndSourceSwitchKeepExactSafeTextSelectionAndCopy() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let source = "> safe cafe\u{301} 😀 •••• and **bold**\n\nOutside"
        let presentation = plainPresentation(source, format: .markdown, syntax: .markdown)
        host.view.display(.ready(presentation), theme: .light, locale: Locale(identifier: "en_US"))
        host.view.layoutSubtreeIfNeeded()
        let safe = Array(host.textView.string.utf16)
        let selectedText = "cafe\u{301} 😀 ••••"
        let selection = (host.textView.string as NSString).range(of: selectedText)
        host.textView.setSelectedRange(selection)
        for size in [18.0, 26.0] {
            host.view.display(.ready(presentation), typography: .init(fontSize: size, fontFamily: "Menlo"),
                              theme: .dark, syntaxStyle: .init(usesColor: false), locale: Locale(identifier: "en_US"))
            host.view.layoutSubtreeIfNeeded()
            #expect(Array(host.textView.string.utf16) == safe)
            #expect(host.textView.selectedRange() == selection)
            let storage = try #require(host.textView.textStorage)
            #expect(try paragraph("safe", in: storage).textBlocks.count == 1)
        }
        host.textView.copy(nil)
        let copied = try #require(host.pasteboard.string(forType: .string))
        #expect(copied.utf16.elementsEqual(selectedText.utf16))
        host.view.modeControl.selectedSegment = try #require(host.view.displayedModes.firstIndex(of: .source))
        #expect(host.view.modeControl.sendAction(host.view.modeControl.action, to: host.view.modeControl.target))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.textView.string.utf16.elementsEqual(source.utf16))
        let sourceStorage = try #require(host.textView.textStorage)
        #expect(try paragraph("safe", in: sourceStorage).textBlocks.isEmpty)
    }

    @Test func nativeTextKitActuallyDrawsABarOutsideTheGlyphsAtEachParagraphsLeadingEdge() throws {
        let palette = NativeTextPalette(theme: .light, isDark: false, increasedContrast: false)
        for (words, rtl) in [("quoted words", false), ("مرحبا بالعالم", true)] {
            let host = InteractionHarness()
            defer { host.release() }
            func show(_ source: String) {
                host.view.display(.ready(plainPresentation(source, format: .markdown, syntax: .markdown)),
                                  theme: .light, syntaxStyle: .init(usesColor: false), locale: Locale(identifier: "en_US"))
                host.view.layoutSubtreeIfNeeded()
            }
            show("> " + words)
            let short = try quoteGeometry(words, rtl: rtl, in: host.textView)
            #expect(short.glyphs.width > 40 && short.lines == 1)
            #expect(try solidInkRows(palette.muted, in: short.bar, of: host.textView) >= 12)
            show(words)
            // Sample the same local lane in an undecorated control; text antialiasing cannot act as a bar.
            #expect(try solidInkRows(palette.muted, in: short.bar, of: host.textView) < 12)

            host.window.setContentSize(NSSize(width: 360, height: 420))
            let long = Array(repeating: words, count: 30).joined(separator: " ")
            show("> " + long)
            let wrapped = try quoteGeometry(long, rtl: rtl, in: host.textView)
            let container = try #require(host.textView.textContainer)
            let origin = host.textView.textContainerOrigin.x
            #expect(wrapped.lines > 2 && wrapped.glyphs.width > 40)
            // Glyph bounding rectangles can include bidi shaping advances outside the actual ink.
            #expect(wrapped.content.minX >= origin)
            #expect(wrapped.content.maxX <= origin + container.containerSize.width)
            #expect(try inkOutsideReadingColumn(palette.background, in: host.textView) == 0)
            #expect(!host.view.scrollView.hasHorizontalScroller)
            #expect(try solidInkRows(palette.muted, in: wrapped.bar, of: host.textView) >= 12)
        }
    }

    private func quoteGeometry(_ words: String, rtl: Bool, in view: NSTextView) throws
        -> (glyphs: NSRect, lines: Int, bar: NSRect, content: NSRect) {
        let manager = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let characters = (view.string as NSString).range(of: words)
        let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        let paragraph = try #require(view.textStorage?.attribute(.paragraphStyle, at: characters.location,
                                                                 effectiveRange: nil) as? NSParagraphStyle)
        let block = try #require(paragraph.textBlocks.first)
        let bounds = manager.boundsRect(for: block, at: glyphs.location, effectiveRange: nil)
        let content = manager.layoutRect(for: block, at: glyphs.location, effectiveRange: nil)
        // Arabic glyph bounding rectangles include advances beyond ink. The native block bounds identify
        // its border lane without assuming the glyph bounding rectangle ends at the rightmost ink.
        let edge: NSRectEdge = rtl ? .maxX : .minX
        let width = block.width(for: .border, edge: edge)
        let bar = NSRect(x: rtl ? bounds.maxX - width : bounds.minX, y: bounds.minY,
                         width: width, height: bounds.height)
        #expect(rtl ? bar.minX > content.maxX : bar.maxX < content.minX)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
        return (manager.boundingRect(forGlyphRange: glyphs, in: container)
                    .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y),
                lines, bar.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y),
                content.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y))
    }

    private func controlledBitmap(of view: NSTextView) throws -> NSBitmapImageRep {
        // Own the color space instead of accepting a cached bitmap tagged with the machine's display profile.
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: Int(ceil(view.bounds.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func inkOutsideReadingColumn(_ paper: NSColor, in view: NSTextView) throws -> Int {
        let bitmap = try controlledBitmap(of: view)
        let container = try #require(view.textContainer)
        let expected = try #require(paper.usingColorSpace(.sRGB))
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let left = Int(ceil(view.textContainerOrigin.x * scale))
        let right = Int(floor((view.textContainerOrigin.x + container.containerSize.width) * scale))
        var outside = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(color.redComponent - expected.redComponent) > 0.02
                    || abs(color.greenComponent - expected.greenComponent) > 0.02
                    || abs(color.blueComponent - expected.blueComponent) > 0.02 {
                    if x < left || x >= right { outside += 1 }
                }
            }
        }
        return outside
    }

    /// A continuous vertical run in the local glyph-free border lane proves AppKit draws the bar.
    private func solidInkRows(_ ink: NSColor, in lane: NSRect, of view: NSTextView) throws -> Int {
        let bitmap = try controlledBitmap(of: view)
        let expected = try #require(ink.usingColorSpace(.sRGB))
        let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        let start = max(0, min(bitmap.pixelsWide, Int(ceil(lane.minX * scaleX))))
        let end = max(start, min(bitmap.pixelsWide, Int(floor(lane.maxX * scaleX))))
        let top = max(0, min(bitmap.pixelsHigh, Int(ceil(lane.minY * scaleY))))
        let bottom = max(top, min(bitmap.pixelsHigh, Int(floor(lane.maxY * scaleY))))
        var longest = 0
        for x in start..<end {
            var run = 0
            for y in top..<bottom {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { run = 0; continue }
                if abs(color.redComponent - expected.redComponent) < 0.02,
                   abs(color.greenComponent - expected.greenComponent) < 0.02,
                   abs(color.blueComponent - expected.blueComponent) < 0.02 {
                    run += 1
                    longest = max(longest, run)
                } else { run = 0 }
            }
        }
        return longest
    }
}

import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Helpers shared by the Q72 block-styling and Q73 code-card tests: a styled text storage built exactly the way the
/// rendered view builds one, and pixel probes over a controlled bitmap of a text view.
@MainActor
enum Q72Support {
    struct Styled {
        let storage: NSTextStorage
        let typography: NativeTextTypography
        let palette: NativeTextPalette
        let syntax: PreviewSyntaxStyle
    }

    /// Applies every decoration of `document` in the order the renderer produced them, as the view does.
    static func styled(_ document: SafeMarkdownDocument, size: Double = 13, theme: PreviewTheme = .light,
                       usesColor: Bool = true, cards: Bool = false) -> Styled {
        let typography = NativeTextTypography(PreviewTypography(fontSize: size, fontFamily: "Menlo"))
        let palette = NativeTextPalette(theme: theme, isDark: theme == .dark, increasedContrast: false)
        let syntax = PreviewSyntaxStyle(usesColor: usesColor)
        var base = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: syntax).baseAttributes
        let reading = ReadingLayout(typography: typography)
        base[.font] = reading.font
        base[.paragraphStyle] = reading.paragraphStyle
        let storage = NSTextStorage(string: document.text, attributes: base)
        for decoration in document.decorations {
            NativeMarkdownStyling.apply(decoration, to: storage, typography: typography, palette: palette,
                                        syntaxStyle: syntax)
        }
        if cards { NativeMarkdownStyling.applyCodeBlocks(document.codeBlocks, to: storage, palette: palette) }
        return Styled(storage: storage, typography: typography, palette: palette, syntax: syntax)
    }

    /// The UTF-16 offset of the first occurrence of `word`.
    static func offset(of word: String, in storage: NSTextStorage) throws -> Int {
        let location = (storage.string as NSString).range(of: word).location
        try #require(location != NSNotFound)
        return location
    }

    static func paragraph(of word: String, in storage: NSTextStorage) throws -> NSParagraphStyle {
        let location = try offset(of: word, in: storage)
        return try #require(storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
    }

    static func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    // MARK: Pixels

    /// A bitmap in a color space this test owns, so a cached bitmap tagged with the display profile cannot skew colors.
    static func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: Int(ceil(view.bounds.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    static func matches(_ color: NSColor, _ expected: NSColor) -> Bool {
        abs(color.redComponent - expected.redComponent) < 0.02
            && abs(color.greenComponent - expected.greenComponent) < 0.02
            && abs(color.blueComponent - expected.blueComponent) < 0.02
    }

    /// The share of pixels in `region` (view coordinates) that have the color `ink`.
    static func matchingFraction(_ ink: NSColor, in region: NSRect, of view: NSView) throws -> Double {
        let image = try bitmap(of: view), expected = try #require(ink.usingColorSpace(.sRGB))
        let range = pixelRange(of: region, in: image, view: view)
        try #require(range.right > range.left && range.bottom > range.top)
        var matched = 0
        for x in range.left..<range.right {
            for y in range.top..<range.bottom {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), matches(color, expected) { matched += 1 }
            }
        }
        return Double(matched) / Double((range.right - range.left) * (range.bottom - range.top))
    }

    /// The longest unbroken vertical run of `ink` in any column of `lane`, in pixels.
    static func longestVerticalRun(of ink: NSColor, in lane: NSRect, of view: NSView) throws -> Int {
        let image = try bitmap(of: view), expected = try #require(ink.usingColorSpace(.sRGB))
        let range = pixelRange(of: lane, in: image, view: view)
        var longest = 0
        guard range.right > range.left, range.bottom > range.top else { return 0 }
        for x in range.left..<range.right {
            var run = 0
            for y in range.top..<range.bottom {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), matches(color, expected) {
                    run += 1
                    longest = max(longest, run)
                } else { run = 0 }
            }
        }
        return longest
    }

    /// The longest unbroken horizontal run of `ink` in any row of `band`, in pixels.
    static func longestHorizontalRun(of ink: NSColor, in band: NSRect, of view: NSView) throws -> Int {
        let image = try bitmap(of: view), expected = try #require(ink.usingColorSpace(.sRGB))
        let range = pixelRange(of: band, in: image, view: view)
        var longest = 0
        guard range.right > range.left, range.bottom > range.top else { return 0 }
        for y in range.top..<range.bottom {
            var run = 0
            for x in range.left..<range.right {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), matches(color, expected) {
                    run += 1
                    longest = max(longest, run)
                } else { run = 0 }
            }
        }
        return longest
    }

    /// The longest unbroken horizontal run of pixels that are not `paper`, in any row of `band`. A line that falls
    /// between two pixel rows is blended into both, so only its difference from the paper identifies it.
    static func longestHorizontalRun(awayFrom paper: NSColor, in band: NSRect, of view: NSView) throws -> Int {
        let image = try bitmap(of: view), expected = try #require(paper.usingColorSpace(.sRGB))
        let range = pixelRange(of: band, in: image, view: view)
        var longest = 0
        guard range.right > range.left, range.bottom > range.top else { return 0 }
        for y in range.top..<range.bottom {
            var run = 0
            for x in range.left..<range.right {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), !matches(color, expected) {
                    run += 1
                    longest = max(longest, run)
                } else { run = 0 }
            }
        }
        return longest
    }

    private static func pixelRange(of region: NSRect, in bitmap: NSBitmapImageRep, view: NSView)
        -> (left: Int, right: Int, top: Int, bottom: Int) {
        let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        return (max(0, Int(ceil(region.minX * scaleX))), min(bitmap.pixelsWide, Int(floor(region.maxX * scaleX))),
                max(0, Int(ceil(region.minY * scaleY))), min(bitmap.pixelsHigh, Int(floor(region.maxY * scaleY))))
    }

    // MARK: Hosts

    static func show(_ source: String, in host: InteractionHarness, typography: PreviewTypography = .init(),
                     theme: PreviewTheme = .light, usesColor: Bool = true) {
        host.view.display(.ready(plainPresentation(source, format: .markdown, syntax: .markdown)), typography: typography,
                          theme: theme, syntaxStyle: .init(usesColor: usesColor), locale: Locale(identifier: "en_US"))
        host.view.layoutSubtreeIfNeeded()
    }

    /// The bounds of the text block at `word`, in text view coordinates.
    static func blockBounds(of word: String, in view: NSTextView) throws -> NSRect {
        let storage = try #require(view.textStorage), manager = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let location = try offset(of: word, in: storage)
        let paragraph = try #require(storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
        let block = try #require(paragraph.textBlocks.first)
        let glyph = manager.glyphIndexForCharacter(at: location)
        return manager.boundsRect(for: block, at: glyph, effectiveRange: nil)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }

    /// The rectangle `range` occupies, in text view coordinates.
    static func glyphRect(of range: NSRange, in view: NSTextView) throws -> NSRect {
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
    }

    static func range(of word: String, in view: NSTextView) throws -> NSRange {
        let range = (view.string as NSString).range(of: word)
        try #require(range.location != NSNotFound)
        return range
    }
}

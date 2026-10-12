import AppKit
import PreviewContracts

/// Draws the language name of each code card in the band the card keeps above its first line. It is a passive layer
/// over the text view's own content: it takes no clicks, is not an accessibility element (the copy control beside
/// the card already says the language) and never touches the text, so selecting, finding and copying see only the
/// safe characters. Being a subview of the text view it scrolls and resizes with the text, and it draws wherever the
/// card is, whether or not the pane is wide enough for the margin copy control.
///
/// The styling pass hands it the code bodies of the displayed document (`configure`). A body is drawn only while its
/// paragraphs still carry a card, so a mode that shows no cards, or a replaced document, leaves nothing behind.
@MainActor
final class NativeCodeLanguageLabels: NSView {
    private var blocks: [MarkupCodeBlock] = []
    private var index = CodeBlockMarginIndex([], textLength: 0)
    private var ink = NSColor.textColor

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// How far below the dirty rectangle a card's first line can lie while the band above it is still dirty.
    private static let searchReach: CGFloat = 64

    /// The label layer of the text view that shows `storage`, made on first use; nil when no text view shows it.
    static func installed(for storage: NSTextStorage) -> NativeCodeLanguageLabels? {
        guard let textView = storage.layoutManagers.first?.firstTextView else { return nil }
        for subview in textView.subviews {
            if let existing = subview as? NativeCodeLanguageLabels { return existing }
        }
        let labels = NativeCodeLanguageLabels(frame: textView.bounds)
        labels.autoresizingMask = [.width, .height]
        labels.setAccessibilityElement(false)
        textView.addSubview(labels)
        return labels
    }

    /// The ink of the labels for a palette: the muted tier when it stays at the minimum text contrast on the card's
    /// tint, otherwise the body ink, so a label never reads worse than the code beside it.
    static func ink(for palette: NativeTextPalette) -> NSColor {
        let background = MarkupSurface.rgb(of: palette.background)
        let foreground = MarkupSurface.rgb(of: palette.foreground)
        let card = MarkupSurface.blend(background, foreground, fraction: NativeCodeTextBlock.tint)
        let ratio = NativeSchemePalette.contrastRatio(MarkupSurface.rgb(of: palette.muted), card)
        return ratio >= NativeSchemePalette.minimumTextContrast ? palette.muted : palette.foreground
    }

    func configure(blocks newBlocks: [MarkupCodeBlock], textLength: Int, palette: NativeTextPalette) {
        blocks = newBlocks
        index = CodeBlockMarginIndex(newBlocks, textLength: textLength)
        ink = Self.ink(for: palette)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !blocks.isEmpty, let textView = superview as? NSTextView, let manager = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage, storage.length > 0 else { return }
        let origin = textView.textContainerOrigin
        let searched = NSRect(x: dirtyRect.minX, y: dirtyRect.minY, width: dirtyRect.width,
                              height: dirtyRect.height + Self.searchReach)
        let glyphs = manager.glyphRange(forBoundingRect: searched.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let rightToLeft = LineNumberPlacement(textView.userInterfaceLayoutDirection).isRightToLeft
        for position in index.candidates(overlapping: characters) {
            guard blocks.indices.contains(position) else { continue }
            let body = blocks[position]
            let range = body.range
            guard let name = CodeLanguageName.text(for: body.language), range.location >= 0,
                  range.location != NSNotFound, range.length > 0, range.length <= storage.length - range.location,
                  let paragraph = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
                  let card = paragraph.textBlocks.first(where: { $0 is NativeCodeTextBlock }) else { continue }
            let glyph = manager.glyphIndexForCharacter(at: range.location)
            guard glyph < manager.numberOfGlyphs else { continue }
            let bounds = manager.boundsRect(for: card, at: glyph, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            let codeFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            let font = NSFont.systemFont(ofSize: CodeLanguageLabelMetrics.fontSize(forCodeSize: codeFont?.pointSize ?? 13))
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let size = (name as NSString).size(withAttributes: attributes)
            let width = ceil(size.width) + 2
            let x = rightToLeft ? bounds.maxX - CodeLanguageLabelMetrics.inset - width : bounds.minX + CodeLanguageLabelMetrics.inset
            let rect = NSRect(x: x, y: bounds.minY + CodeLanguageLabelMetrics.top, width: width, height: ceil(size.height))
            guard rect.intersects(dirtyRect) else { continue }
            (name as NSString).draw(in: rect, withAttributes: attributes)
        }
    }
}

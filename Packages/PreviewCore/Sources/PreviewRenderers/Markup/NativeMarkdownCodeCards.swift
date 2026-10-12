import AppKit

extension NativeMarkdownStyling {
    /// One card per explicit safe body, shared across all of its paragraph-style runs. A body with a recognized
    /// language keeps a band above its first line, and the text view's label layer draws the language name there.
    /// Inline-code chips end at the card: the card is the body's tint, and a chip over it would tint twice.
    @MainActor
    static func applyCodeBlocks(_ blocks: [MarkupCodeBlock], to storage: NSTextStorage,
                                palette: NativeTextPalette) {
        for body in blocks {
            let range = body.range
            guard range.location >= 0, range.location != NSNotFound, range.location <= storage.length,
                  range.length > 0, range.length <= storage.length - range.location else { continue }
            storage.removeAttribute(.backgroundColor, range: range)
            let card = NativeCodeTextBlock.make(palette: palette, labelBand: labelBand(for: body, in: storage))
            var updates: [(NSRange, NSParagraphStyle)] = []
            storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, subrange, _ in
                let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                // Copies share block references; preserve foreign/quote blocks without mutating them.
                paragraph.textBlocks = paragraph.textBlocks.filter { !($0 is NativeCodeTextBlock) } + [card]
                updates.append((subrange, paragraph))
            }
            for (subrange, paragraph) in updates {
                storage.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
            }
        }
        NativeCodeLanguageLabels.installed(for: storage)?.configure(blocks: blocks, textLength: storage.length, palette: palette)
    }

    /// The height of the label band: none unless the body's language has a name to show.
    @MainActor
    private static func labelBand(for body: MarkupCodeBlock, in storage: NSTextStorage) -> CGFloat {
        guard CodeLanguageName.text(for: body.language) != nil else { return 0 }
        let font = storage.attribute(.font, at: body.range.location, effectiveRange: nil) as? NSFont
        return CodeLanguageLabelMetrics.bandHeight(forCodeSize: font?.pointSize ?? 13)
    }
}

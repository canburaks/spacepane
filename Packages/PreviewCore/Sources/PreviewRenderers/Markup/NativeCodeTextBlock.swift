import AppKit

/// One inert native card for one explicit safe code body. Paragraph copies share this
/// object, so an appearance pass constructs a fresh block rather than mutating a retained one.
@MainActor
final class NativeCodeTextBlock: NSTextBlock {
    /// The padding on every side of a card.
    static let padding: CGFloat = 8
    /// How much of the foreground is laid over the background to make the card.
    static let tint: Double = 0.07

    /// `labelBand` is extra space above the first line, for the language label the margin control draws there.
    static func make(palette: NativeTextPalette, labelBand: CGFloat = 0) -> NativeCodeTextBlock {
        let block = NativeCodeTextBlock()
        // The default zero content width collapses native glyph layout.
        block.setContentWidth(100, type: .percentageValueType)
        for edge in [NSRectEdge.minX, .minY, .maxX, .maxY] {
            block.setWidth(Self.padding, type: .absoluteValueType, for: .padding, edge: edge)
        }
        if labelBand > 0 {
            // The text system is flipped, so the minimum Y edge is the top of the card.
            block.setWidth(Self.padding + labelBand, type: .absoluteValueType, for: .padding, edge: .minY)
        }
        // Apple documents this property on macOS10+; keep its first use in this wrapper.
        block.backgroundColor = palette.foreground.withAlphaComponent(CGFloat(tint))
        return block
    }
}

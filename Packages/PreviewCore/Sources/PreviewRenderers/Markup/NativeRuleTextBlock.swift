import AppKit

/// The app-owned thematic break: a one-point line along the bottom edge of an otherwise empty paragraph, across the
/// whole reading column. The characters the renderer wrote stay in the text, so copying and the reading order are
/// as before; styling gives them no ink and almost no height, and this block draws the rule beside them.
@MainActor
final class NativeRuleTextBlock: NSTextBlock {
    static let thickness: CGFloat = 1

    static func make(fontSize: CGFloat, ink: NSColor) -> NativeRuleTextBlock {
        let block = NativeRuleTextBlock()
        // NSTextBlock's default content width is zero; use the available reading column.
        block.setContentWidth(100, type: .percentageValueType)
        block.setWidth(thickness, type: .absoluteValueType, for: .border, edge: .maxY)
        // The same air above and below, so only the border's edge decides which side of the paragraph the line is on.
        let spacing = max(4, fontSize * 0.5)
        block.setWidth(spacing, type: .absoluteValueType, for: .padding, edge: .minY)
        block.setWidth(spacing, type: .absoluteValueType, for: .padding, edge: .maxY)
        block.setBorderColor(ink)
        return block
    }
}

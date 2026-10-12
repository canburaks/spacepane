import AppKit

/// The app-owned inert quote border. A paragraph-style copy shares its text blocks, so moving
/// a border always creates another block instead of mutating a retained paragraph's block.
/// The NSRectEdge APIs are available on macOS 15; their CGRectEdge replacements require macOS 27.
@MainActor
final class NativeQuoteTextBlock: NSTextBlock {
    static func make(fontSize: CGFloat, palette: NativeTextPalette,
                     direction: NSWritingDirection) -> NativeQuoteTextBlock {
        make(padding: max(6, fontSize * 0.5), ink: palette.muted, direction: direction)
    }

    func following(_ direction: NSWritingDirection) -> NativeQuoteTextBlock {
        let padding = max(width(for: .padding, edge: .minX), width(for: .padding, edge: .maxX))
        let ink = borderColor(for: .minX) ?? borderColor(for: .maxX) ?? .clear
        return Self.make(padding: padding, ink: ink, direction: direction)
    }

    private static func make(padding: CGFloat, ink: NSColor,
                             direction: NSWritingDirection) -> NativeQuoteTextBlock {
        let block = NativeQuoteTextBlock()
        // NSTextBlock's default content width is zero; use the available reading column.
        block.setContentWidth(100, type: .percentageValueType)
        let edge: NSRectEdge = direction == .rightToLeft ? .maxX : .minX
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: edge)
        block.setWidth(padding, type: .absoluteValueType, for: .padding, edge: edge)
        block.setBorderColor(ink)
        return block
    }
}

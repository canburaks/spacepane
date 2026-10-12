import AppKit
import PreviewContracts

extension MarkupAlertKind {
    /// The palette role that inks an alert's title and its bar. Roles, never literal colors, so every color scheme
    /// and High Contrast keep the contrast they were measured for, and turning syntax colors off turns these off too.
    /// The glyph and the localized title carry the kind where color cannot.
    var syntaxRole: PreviewSyntaxRole {
        switch self {
        case .note: .key
        case .tip: .addition
        case .important: .literal
        case .warning: .number
        case .caution: .deletion
        }
    }
}

/// The app-owned alert border: a bar along a paragraph's leading edge in the alert kind's ink. Like the quote's bar it
/// is a text block, so it is drawn beside the text and never in it: selecting, finding and copying see only the safe
/// characters. A paragraph-style copy shares its text blocks, so moving a bar always makes another block instead of
/// mutating a retained paragraph's block.
@MainActor
final class NativeAlertTextBlock: NSTextBlock {
    /// How thick the bar is: a little heavier than the quote's, so an alert reads as more than a quotation.
    static let thickness: CGFloat = 4

    static func make(fontSize: CGFloat, ink: NSColor, direction: NSWritingDirection) -> NativeAlertTextBlock {
        make(padding: max(8, fontSize * 0.6), ink: ink, direction: direction)
    }

    /// The same bar on the side that leads in `direction`.
    func following(_ direction: NSWritingDirection) -> NativeAlertTextBlock {
        let padding = max(width(for: .padding, edge: .minX), width(for: .padding, edge: .maxX))
        let ink = borderColor(for: .minX) ?? borderColor(for: .maxX) ?? .clear
        return Self.make(padding: padding, ink: ink, direction: direction)
    }

    private static func make(padding: CGFloat, ink: NSColor, direction: NSWritingDirection) -> NativeAlertTextBlock {
        let block = NativeAlertTextBlock()
        // NSTextBlock's default content width is zero; use the available reading column.
        block.setContentWidth(100, type: .percentageValueType)
        let edge: NSRectEdge = direction == .rightToLeft ? .maxX : .minX
        block.setWidth(thickness, type: .absoluteValueType, for: .border, edge: edge)
        block.setWidth(padding, type: .absoluteValueType, for: .padding, edge: edge)
        block.setBorderColor(ink)
        return block
    }
}

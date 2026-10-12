import AppKit

/// The only place the package makes `NSTextTab`s, the first use of them in the repository. The initializer and the
/// option key are the ones Apple documents for macOS 15 (AppKit, `NSTextTab`):
///
///     init(textAlignment alignment: NSTextAlignment, location loc: CGFloat, options: [NSTextTab.OptionKey : Any])
///     NSTextTab.OptionKey.columnTerminators   // a CharacterSet of the characters that end a column
///
/// A tab stop is a paragraph attribute (`NSMutableParagraphStyle.tabStops`): it moves where text lands after a tab
/// and leaves the text, and so what is copied, as it was. If the Mac session finds the option misbehaves, this file
/// is the only one to change: replace the `.decimal` case with the `.trailing` one.
@MainActor
enum MarkupTabStops {
    /// The character a decimal stop lines numbers up on. Only numbers written with a period reach a decimal stop.
    static let decimalTerminators = CharacterSet(charactersIn: ".")

    /// The stops of a layout, in column order. Right-to-left rows keep only leading stops until a host shows how
    /// mirrored numeric stops align; their columns still line up.
    static func stops(for layout: MarkupTableLayout, rightToLeft: Bool) -> [NSTextTab] {
        layout.stops.map { tab(for: $0, rightToLeft: rightToLeft) }
    }

    private static func tab(for stop: MarkupTableLayout.Stop, rightToLeft: Bool) -> NSTextTab {
        if rightToLeft {
            return NSTextTab(textAlignment: .natural, location: stop.location, options: [:])
        }
        switch stop.placement {
        case .leading:
            return NSTextTab(textAlignment: .left, location: stop.location, options: [:])
        case .center:
            return NSTextTab(textAlignment: .center, location: stop.location, options: [:])
        case .trailing:
            return NSTextTab(textAlignment: .right, location: stop.location, options: [:])
        case .decimal:
            let options: [NSTextTab.OptionKey: Any] = [.columnTerminators: decimalTerminators]
            return NSTextTab(textAlignment: .right, location: stop.location, options: options)
        }
    }
}

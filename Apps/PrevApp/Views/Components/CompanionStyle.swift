import AppKit
import SwiftUI

/// Shared measurements for every companion page, so screens stay aligned.
enum CompanionMetrics {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let headingSpacing: CGFloat = 8
    static let columnSpacing: CGFloat = 20
    /// Content narrower than this stacks its columns.
    static let columnBreakpoint: CGFloat = 620
    static let cardCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let rowVerticalPadding: CGFloat = 10
    static let sidebarWidth: CGFloat = 224
}

/// Text roles of every companion page. They are the system's semantic styles, so they follow the user's text
/// size setting. Nothing is smaller than the subheadline: no page uses a caption style.
enum CompanionTypography {
    /// A page's title, the largest text in the window.
    static var pageTitle: Font { .title2.weight(.semibold) }
    /// A section's heading above its cards.
    static var sectionHeading: Font { .headline }
    /// The label of a row and the text of a card.
    static var row: Font { .body }
    /// An explanation, a hint, a count or a unit that qualifies a row.
    static var note: Font { .subheadline }
}

/// Ink for companion text. The system's secondary label works out at about 3.9:1 on the light page and card fills
/// (calculated from its alpha, not yet measured), below the 4.5:1 that small text needs, so explanatory text uses
/// `hint`, and a link's title uses `link`.
/// The accent color is for controls and fills; it is never the color of text, because a yellow or orange
/// accent chosen in System Settings would leave that text unreadable.
enum CompanionInk {
    /// How much of its black or white the hint ink keeps.
    private static let hintAlpha: CGFloat = 0.62

    /// The hint ink for one appearance: white under the dark appearances (dark, and dark with increased contrast) and
    /// black under the others, as the label color is, at `hintAlpha`. The color is chosen from the appearance by name,
    /// not derived from `NSColor.labelColor`: `labelColor.withAlphaComponent(_:)` was used first, and a Mac measured it
    /// at 1.18:1 on the dark page when it was made under the light appearance, which fits a derived color keeping the
    /// value the label color had where it was made (inferred, not confirmed).
    static func hintInk(for appearance: NSAppearance) -> NSColor {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                                .accessibilityHighContrastDarkAqua])
        let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(hintAlpha)
    }

    /// The AppKit color behind `hint`, so a check can resolve it in each appearance. It is a dynamic color that asks
    /// `hintInk(for:)` when it is drawn and not where it is made, so it is right whichever appearance happens to be
    /// current while a view body runs.
    static var hintColor: NSColor {
        NSColor(name: nil) { appearance in CompanionInk.hintInk(for: appearance) }
    }
    /// Explanatory text, counts and units. At `hintAlpha` it works out at 5.5:1 or better on the page, card, group
    /// header, badge, search and window fills in the light, dark and both increased-contrast appearances. That is a
    /// calculation: `CompanionContrastChecks` measures it on a Mac and decides.
    static var hint: Color { Color(nsColor: hintColor) }
    /// The AppKit color behind `link`.
    static var linkColor: NSColor { .linkColor }
    /// The title of a link: the system link color, which is legible on the page fill in every appearance.
    static var link: Color { Color(nsColor: linkColor) }
}

/// Meaning of a status color. Text always carries the same information. Nothing here is green: the app cannot
/// verify that the extensions are on, so it never draws a state as confirmed.
enum CompanionTone {
    case informational, caution, neutral

    var color: Color {
        switch self {
        case .informational: .accentColor
        case .caution: .orange
        case .neutral: .secondary
        }
    }
}

extension ShapeStyle where Self == Color {
    /// Adaptive page surface behind cards.
    static var companionPage: Color { Color(nsColor: .textBackgroundColor) }
    /// Adaptive surface behind the navigation list.
    static var companionSidebar: Color { Color(nsColor: .windowBackgroundColor) }
}

import AppKit

/// When the Contents rail is offered, and its sizes. Pure rules over values, so the hosting preview and the tests
/// decide visibility the same way and no layout is needed to check them (decision 027, Q-74).
enum ContentsRailPolicy {
    /// PROVISIONAL, to be replaced by measured pane widths: the host width from which a wide pane offers the rail
    /// beside the rendered text. Like `PreviewChrome.compactWidth` (480 pt, whose density rule is the consumer this
    /// number belongs beside), it is a placeholder: what widths a Finder preview pane, column view, gallery view and
    /// Quick Look panel really get has not been measured (Wave 1, S2), and the measured widths replace it. What
    /// must survive the replacement is checked by `Q74ContentsRailPolicyTests`: at the lowest width inside the
    /// hysteresis band the text column keeps at least a regular-density width beside the rail.
    static let minimumHostWidth: CGFloat = 760
    /// Half the width of the band around `minimumHostWidth` in which the rail keeps the state it has, so a drag
    /// across the threshold, or a scroller appearing, never flickers it. The same shape as
    /// `PreviewChrome.compactHysteresis`.
    static let hysteresis: CGFloat = 24
    /// The rail's width with its list shown, and with only its toggle shown.
    static let expandedWidth: CGFloat = 220
    static let collapsedWidth: CGFloat = 32
    /// The largest size the rail's rows are set in. A reader's large text size scales the document, not this
    /// 220 pt strip, which would otherwise show a few letters per row.
    static let maximumRowPointSize: CGFloat = 15
    /// The indent per heading level in the rail; the Contents mode, which has the whole width, uses more.
    static let indentPerLevel: CGFloat = 10
    /// The fewest headings that make a rail worth showing. It matches the Contents mode, which
    /// `PreviewModePolicy` offers from two headings (checked by `Q74ContentsRailPolicyTests`).
    static let minimumHeadings = 2

    /// Whether a host `width` points wide is wide. It becomes wide from `minimumHostWidth + hysteresis` and narrow
    /// again below `minimumHostWidth - hysteresis`; in between it keeps `previous`. A host with no width yet says
    /// nothing and keeps `previous`.
    static func isWide(forWidth width: CGFloat, previous: Bool) -> Bool {
        guard width > 0 else { return previous }
        return previous ? width >= minimumHostWidth - hysteresis : width >= minimumHostWidth + hysteresis
    }

    /// Whether the rail is offered at all. Headings belong to the rendered text, so only the Rendered mode has
    /// one; the Contents mode keeps serving a compact pane.
    static func offers(mode: NativePreviewMode, headingCount: Int, isWide: Bool) -> Bool {
        mode == .rendered && isWide && headingCount >= minimumHeadings
    }

    /// The rail's width for its state: nothing while it is not offered.
    static func width(offered: Bool, collapsed: Bool) -> CGFloat {
        guard offered else { return 0 }
        return collapsed ? collapsedWidth : expandedWidth
    }
}

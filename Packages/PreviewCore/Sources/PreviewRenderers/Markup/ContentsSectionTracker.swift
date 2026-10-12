import AppKit

/// The part of the rendered text that is on screen: the characters in the viewport and the length of the whole
/// text. Both are UTF-16 offsets into the rendered text, the same unit as `MarkupHeading.range`.
struct ContentsViewport: Equatable, Sendable {
    let visible: NSRange
    let textLength: Int
}

/// Which heading is the current section of the Contents rail while the rendered text scrolls. It works on the
/// headings the renderer collected from already-concealed text and on character offsets only: it reads no text,
/// takes no focus and says nothing aloud, so following a scroll is silent by construction (decision 027, Q-74).
///
/// The rule, in order:
/// 1. The anchor is a quarter of the way down the visible characters, so a heading that has just come into the
///    top of the view counts before it reaches the very first line.
/// 2. The current section is the last heading that starts at or before the anchor, the nearest preceding heading;
///    nothing is current while no heading precedes the anchor.
/// 3. Once the end of the text is on screen (and the view is not also at the start), the last heading that starts
///    in or before the view is current, so the final short sections can be reached by scrolling.
/// 4. At the start of the text the first heading is current as soon as any heading precedes the anchor: the reader
///    is at the beginning, so the opening section is theirs even when a dense document fits its second heading into
///    the first quarter of the view.
/// 5. A heading the reader chose in the rail stays current while it is still visible and no later heading has
///    reached the anchor; scrolling it out of view, or past, releases it.
struct ContentsSectionTracker: Equatable, Sendable {
    /// The anchor divides the visible characters by this: one quarter.
    static let anchorDivisor = 4

    /// The index of the current heading, or nil while none precedes the anchor.
    private(set) var current: Int?
    /// The heading the reader chose, kept until the scroll position releases it.
    private(set) var pinned: Int?

    init() {}

    /// Whether `visible` can be measured against a text of `textLength` units. A zero-sized or not-yet-laid-out
    /// view reports an invalid range, and that says nothing about where the reader is.
    static func isUsable(_ visible: NSRange, textLength: Int) -> Bool {
        visible.location != NSNotFound && visible.location >= 0 && visible.length >= 0
            && textLength >= 0 && visible.location <= textLength
    }

    /// The nearest preceding heading for the visible range, or nil. `headings` is in document order, which the
    /// renderer's builder guarantees, so a binary search finds it; a heading start never needs the text.
    static func sectionIndex(visible: NSRange, textLength: Int, headings: [MarkupHeading]) -> Int? {
        guard !headings.isEmpty, isUsable(visible, textLength: textLength) else { return nil }
        // The end is clamped without adding the length first, so a huge length cannot overflow.
        let end = visible.length >= textLength - visible.location ? textLength : visible.location + visible.length
        let anchor = visible.location + (end - visible.location) / anchorDivisor
        let showsEnd = end >= textLength && visible.location > 0
        let found = lastHeading(startingAtOrBefore: showsEnd ? max(end - 1, 0) : anchor, in: headings)
        return visible.location == 0 ? found.map { _ in 0 } : found
    }

    /// The last index whose heading starts at or before `position`.
    private static func lastHeading(startingAtOrBefore position: Int, in headings: [MarkupHeading]) -> Int? {
        var low = 0
        var high = headings.count
        while low < high {
            let middle = low + (high - low) / 2
            if headings[middle].range.location <= position { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }

    /// Follows a scroll. Returns whether the current section changed. An unusable range changes nothing.
    @discardableResult
    mutating func update(visible: NSRange, textLength: Int, headings: [MarkupHeading]) -> Bool {
        guard Self.isUsable(visible, textLength: textLength) else { return false }
        let computed = Self.sectionIndex(visible: visible, textLength: textLength, headings: headings)
        var next = computed
        if let chosen = pinned {
            let isShown = headings.indices.contains(chosen)
                && Self.starts(headings[chosen].range, within: visible)
            if isShown, chosen >= (computed ?? 0) {
                next = chosen
            } else {
                pinned = nil
            }
        }
        let changed = next != current
        current = next
        return changed
    }

    /// The reader chose heading `index` in the rail: it is current at once and stays so while it remains in view.
    mutating func pin(_ index: Int) {
        pinned = index
        current = index
    }

    /// A different document replaced the headings: nothing is current until the next scroll reading.
    mutating func reset() {
        current = nil
        pinned = nil
    }

    private static func starts(_ range: NSRange, within visible: NSRange) -> Bool {
        range.location >= visible.location && range.location - visible.location < visible.length
    }
}

/// Reads the on-screen characters of a TextKit 1 text view with the same geometry the code-block copy controls use,
/// so scrolling never lays out text beyond the visible rectangle.
@MainActor
enum ContentsVisibleRange {
    /// The viewport of `textView`, or nil while it has no size, no text or no laid-out glyphs yet.
    static func viewport(of textView: NSTextView) -> ContentsViewport? {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage, storage.length > 0 else { return nil }
        let origin = textView.textContainerOrigin
        let rect = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let glyphs = manager.glyphRange(forBoundingRect: rect, in: container)
        guard glyphs.length > 0 else { return nil }
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return ContentsViewport(visible: characters, textLength: storage.length)
    }
}

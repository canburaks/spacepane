import AppKit

/// Finds descendants by type for surfaces without a named test seam. The breadth-first walk visits
/// siblings in `subviews` order, includes hidden views and subclasses, and excludes `view` itself.
/// Nesting changes which matching view comes first; do not use that order to identify a known control.
/// Prefer `NativePreviewView` members such as `modeControl`, `visibleModeControl`, `textView`,
/// `scrollView`, `outlineView`, `lineNumberGutter` and `contentView(for:)` when available.
@MainActor
func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    var matches: [T] = []
    var queue = view.subviews
    var next = 0
    while next < queue.count {
        let candidate = queue[next]
        next += 1
        if let match = candidate as? T { matches.append(match) }
        queue.append(contentsOf: candidate.subviews)
    }
    return matches
}

import Foundation

/// A typed filter string. Matching is a plain substring test on case-, diacritic- and width-insensitive
/// folded text; it never interprets the query as a pattern.
struct OutlineFilterQuery: Equatable {
    /// Longest searched prefix of one key or value, in UTF-16 units. Outline text is already bounded by the
    /// source cap, so this only keeps a single enormous value from dominating one keystroke.
    static let searchedUnitsPerField = 4_096
    /// Longest query used; extra characters are ignored.
    static let maximumQueryUnits = 256

    let folded: String

    /// Nil when nothing but whitespace was typed, which means no filtering.
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        folded = Self.fold(String(trimmed.prefix(Self.maximumQueryUnits)))
    }

    func isContained(in foldedText: String) -> Bool {
        foldedText.utf8.contains(folded.utf8)
    }

    static func fold(_ text: String) -> String {
        let bounded = text.utf16.count > searchedUnitsPerField ? String(text.prefix(searchedUnitsPerField)) : text
        return bounded.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// One outline row for the native outline view, with its filter state. Children are created once per
/// displayed node tree; filtering only changes which of them are `shown`.
final class OutlineItem: NSObject {
    /// JSON outlines give containers these placeholder values; searching them would match every container.
    private static let containerMarkers: Set<String> = ["{…}", "[…]"]

    let node: SafeOutlineNode
    let children: [OutlineItem]
    /// Children currently listed: all of them, or while filtering only those on the way to a match.
    private(set) var shown: [OutlineItem]
    private(set) var isMatch = false
    /// An ancestor of a match: listed expanded so the match is visible.
    private(set) var expandsForFilter = false
    private var foldedName: String?
    private var foldedValue: String?

    init(_ node: SafeOutlineNode) {
        self.node = node
        let children = node.children.map(OutlineItem.init)
        self.children = children
        shown = children
        super.init()
    }

    /// Restores the unfiltered state for this subtree.
    func resetFilter() {
        isMatch = false
        expandsForFilter = false
        shown = children
        for child in children { child.resetFilter() }
    }

    /// Marks matches below and including this row. Returns the number of matching rows and whether anything
    /// here is a match. A match without matching descendants keeps its whole subtree available, collapsed;
    /// any other row lists only the children that lead to a match.
    func applyFilter(_ query: OutlineFilterQuery) -> (matches: Int, containsMatch: Bool) {
        isMatch = matchesSelf(query)
        var count = isMatch ? 1 : 0
        var kept: [OutlineItem] = []
        for child in children {
            let result = child.applyFilter(query)
            count += result.matches
            if result.containsMatch { kept.append(child) }
        }
        expandsForFilter = !kept.isEmpty
        if isMatch && kept.isEmpty {
            shown = children
            for child in children { child.resetFilter() }
        } else {
            shown = kept
        }
        return (count, isMatch || !kept.isEmpty)
    }

    private func matchesSelf(_ query: OutlineFilterQuery) -> Bool {
        if foldedName == nil { foldedName = OutlineFilterQuery.fold(node.name) }
        if let foldedName, query.isContained(in: foldedName) { return true }
        if !children.isEmpty, Self.containerMarkers.contains(node.value) { return false }
        if foldedValue == nil { foldedValue = OutlineFilterQuery.fold(node.value) }
        return foldedValue.map(query.isContained(in:)) ?? false
    }
}

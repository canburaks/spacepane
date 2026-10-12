import Foundation
import PreviewContracts

struct TagSanitizedCopy: Equatable, Sendable {
    let text: String
    let removedTagScalarCount: Int
    /// UTF-16 ranges relative to the original selection, before deletion.
    let removedUTF16Ranges: [Range<Int>]
}

/// Copy-only policy over already-concealed, bounded text. Source storage never changes.
struct TagCopySanitizer: Sendable {
    private let text: String
    private let tagRanges: [Range<Int>]

    init(safeDisplayedText: String, safetyLensFoundTags: Bool) {
        text = safeDisplayedText
        // Classify the complete text before selecting: a selected suffix of a valid subdivision flag stays valid.
        tagRanges = safetyLensFoundTags ? HiddenCharacters.spans(in: safeDisplayedText)
            .filter { $0.kind == .tag }.map(\.utf16Range) : []
    }

    func wholeText() -> TagSanitizedCopy {
        selection(0..<text.utf16.count)!
    }

    func selection(_ range: Range<Int>) -> TagSanitizedCopy? {
        let source = text as NSString
        guard range.lowerBound >= 0, range.upperBound <= source.length,
              isScalarBoundary(range.lowerBound, in: source), isScalarBoundary(range.upperBound, in: source) else { return nil }
        let removed = tagRanges.compactMap { tag -> Range<Int>? in
            let lower = max(tag.lowerBound, range.lowerBound), upper = min(tag.upperBound, range.upperBound)
            return lower < upper ? (lower - range.lowerBound)..<(upper - range.lowerBound) : nil
        }
        let selected = source.substring(with: NSRange(range))
        guard !removed.isEmpty else { return .init(text: selected, removedTagScalarCount: 0, removedUTF16Ranges: []) }
        let result = NSMutableString(string: selected)
        for deletion in removed.reversed() { result.deleteCharacters(in: NSRange(deletion)) }
        // Every Unicode Tag scalar occupies two UTF-16 code units; selections are scalar aligned.
        return .init(text: result as String, removedTagScalarCount: removed.reduce(0) { $0 + $1.count / 2 },
                     removedUTF16Ranges: removed)
    }

    private func isScalarBoundary(_ offset: Int, in source: NSString) -> Bool {
        guard offset > 0, offset < source.length else { return true }
        return !(0xD800...0xDBFF).contains(source.character(at: offset - 1))
            || !(0xDC00...0xDFFF).contains(source.character(at: offset))
    }
}

import AppKit

extension NativePreviewView {
    /// Copies only the current explicit safe body. A stale target returns before touching the clipboard.
    @discardableResult
    func copyCodeBlock(_ target: CodeBlockCopyTarget) -> Bool {
        guard let range = currentCodeBlockRange(for: target),
              let copy = TagCopySanitizer(safeDisplayedText: textView.string,
                                         safetyLensFoundTags: safetyLensFoundTags)
                .selection(range.location..<(range.location + range.length)) else { return false }
        guard plainTextCopyWriter(copy.text, pasteboard) else { return false }
        reportCopy(.text.removingTags(copy.removedTagScalarCount))
        return true
    }
}

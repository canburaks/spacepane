import Foundation
import PreviewContracts

/// UTF-16 starts in the already-concealed displayed string, independent of text wrapping.
/// The separator rules live in `LogicalLines`, which findings use for the same numbering.
struct LogicalLineIndex: Equatable, Sendable {
    private let index: LogicalLines.Starts
    var starts: [Int] { index.starts }
    var utf16Length: Int { index.utf16Length }
    var count: Int { index.starts.count }

    init(_ text: String) { index = LogicalLines.starts(in: text) }

    /// Binary search avoids rescanning text while scrolling. Separators belong to the prior line.
    func lineIndex(containingUTF16 offset: Int) -> Int? {
        LogicalLines.lineIndex(containingUTF16: offset, in: index)
    }
}

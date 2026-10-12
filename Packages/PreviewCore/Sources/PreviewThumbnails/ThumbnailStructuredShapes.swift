import Foundation
import PreviewContracts

/// Presentations whose concealed text is JSON with a known shape. They are read from the safe text
/// only; the database and the notebook are never opened again. A shape that does not match the
/// expected one yields nil and the thumbnail stays generic: raw summary JSON is never drawn for them.
enum ThumbnailStructuredShapes {
    private static let maximumJSONBytes = 2_097_152

    /// The first notebook cells: markdown as a heading and prose, code as source.
    static func notebookPage(from text: String, metrics: ThumbnailMetrics) -> ThumbnailTextPage? {
        guard let root = object(text), let cells = root["cells"] as? [[String: Any]] else { return nil }
        var lines: [ThumbnailLine] = []
        var used = 0.0
        let capacity = Double(metrics.rows)
        for cell in cells {
            let remaining = Int(capacity - used)
            guard remaining >= 1 else { break }
            let text = sourceText(of: cell)
            guard !text.isEmpty else { continue }
            let isMarkdown = cell["cell_type"] as? String == "markdown"
            let rows = min(remaining, isMarkdown ? 3 : 5)
            let page = isMarkdown
                ? ThumbnailMarkdown.page(from: text, syntax: .markdown, metrics: metrics, rows: rows)
                : ThumbnailExcerpt.page(from: text, syntax: .sourceCode, metrics: metrics, rows: rows)
            guard let page else { continue }
            if !lines.isEmpty, used + 1 < capacity { lines.append(.blank); used += 1 }
            for line in page.lines where used + line.rowCost <= capacity {
                lines.append(line)
                used += line.rowCost
            }
        }
        while lines.last == .blank { lines.removeLast() }
        return lines.isEmpty ? nil : ThumbnailTextPage(lines: lines)
    }

    private static func sourceText(of cell: [String: Any]) -> String {
        if let text = cell["source"] as? String { return text }
        if let parts = cell["source"] as? [String] { return parts.joined() }
        return ""
    }

    private static func object(_ text: String) -> [String: Any]? {
        guard text.utf8.count <= maximumJSONBytes else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}

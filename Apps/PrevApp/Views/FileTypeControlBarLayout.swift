import SwiftUI

/// A search field followed by actions. When everything fits on one line the
/// actions sit at the trailing edge; otherwise children flow onto further lines.
/// Children keep one identity in both arrangements, so the field keeps its focus.
struct FileTypeControlBarLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let single = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(sizes.count - 1, 0))
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? single
        let rows = rows(width: width, sizes: sizes)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = rows(width: bounds.width, sizes: sizes)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (position, index) in row.indices.enumerated() {
                // On a single line everything after the first child moves to the trailing edge.
                if rows.count == 1, position == 1 { x = max(x, bounds.maxX - row.trailingWidth(sizes, spacing: spacing)) }
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - sizes[index].height) / 2), anchor: .topLeading,
                                      proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        func trailingWidth(_ sizes: [CGSize], spacing: CGFloat) -> CGFloat {
            let trailing = indices.dropFirst()
            return trailing.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(trailing.count - 1, 0))
        }
    }

    private func rows(width: CGFloat, sizes: [CGSize]) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > width {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

import CoreGraphics

/// Fixed-size tiles wrapped into rows, leading-aligned: the arithmetic behind the color scheme gallery. It is pure,
/// so a check can wrap any number of tiles at any width without a window. `TileFlowLayout` is the SwiftUI side.
enum AppearanceTileFlow {
    static let tileWidth: CGFloat = 84
    /// A swatch, a gap and a name of at most two lines.
    static let tileHeight: CGFloat = 76
    static let spacing: CGFloat = 8
    /// Narrower than this the gallery gives way to the two menus: room for three tiles in a row.
    static let minimumWidth: CGFloat = 3 * tileWidth + 2 * spacing

    /// How many tiles fit in a row of `width`, never fewer than one.
    static func columns(forWidth width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        // A width beyond any screen is held down so the conversion to Int cannot overflow.
        return max(Int(((min(width, 100_000) + spacing) / (tileWidth + spacing)).rounded(.down)), 1)
    }

    /// The tiles' frames, row by row, from the leading edge.
    static func frames(count: Int, width: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let perRow = columns(forWidth: width)
        return (0..<count).map { index in
            CGRect(x: CGFloat(index % perRow) * (tileWidth + spacing),
                   y: CGFloat(index / perRow) * (tileHeight + spacing),
                   width: tileWidth, height: tileHeight)
        }
    }

    /// The height of all rows.
    static func height(count: Int, width: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let perRow = columns(forWidth: width)
        let rows = (count + perRow - 1) / perRow
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * spacing
    }
}

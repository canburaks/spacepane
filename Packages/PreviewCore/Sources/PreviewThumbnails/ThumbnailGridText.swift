/// Bounded, one-line document headers for value-free grids.
enum ThumbnailGridText {
    private static let maximumCellScalars = 64

    /// One visible line: separators and line breaks inside a cell become spaces.
    static func cell(_ text: String) -> String {
        var scalars: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars.prefix(maximumCellScalars * 2) {
            if scalar.value < 32 || scalar.value == 127 || scalar.properties.isWhitespace {
                if scalars.last != " " { scalars.append(" ") }
            } else {
                scalars.append(scalar)
            }
            if scalars.count >= maximumCellScalars { break }
        }
        while scalars.last == " " { scalars.removeLast() }
        while scalars.first == " " { scalars.removeFirst() }
        return ThumbnailCells.string(scalars)
    }

    static func clip(_ text: String, to width: Int) -> String {
        let scalars = Array(text.unicodeScalars)
        guard ThumbnailCells.width(of: scalars) > width else { return text }
        return ThumbnailCells.string(ThumbnailCells.prefix(scalars, cells: max(0, width - 1))) + "…"
    }
}

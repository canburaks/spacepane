/// Cell-based text measures. One cell is the advance of a Latin glyph in the fixed-pitch face; a
/// wide East Asian or emoji scalar takes two cells and a combining mark none. Exact glyph metrics
/// are unnecessary because the renderer places each run at a cell column and clips to the page.
enum ThumbnailCells {
    static func width(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value < 0x300 { return 1 }
        switch value {
        case 0x0300...0x036F, 0x200B...0x200F, 0x2028...0x202E, 0x2060...0x2064, 0x20D0...0x20FF,
             0xFE00...0xFE0F, 0xE0100...0xE01EF:
            return 0
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    static func width<S: Sequence>(of scalars: S) -> Int where S.Element == Unicode.Scalar {
        scalars.reduce(0) { $0 + width(of: $1) }
    }

    static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// The leading scalars of `scalars` that fit in `cells`.
    static func prefix(_ scalars: [Unicode.Scalar], cells: Int) -> [Unicode.Scalar] {
        var used = 0
        var end = 0
        for scalar in scalars {
            let next = used + width(of: scalar)
            if next > cells { break }
            used = next
            end += 1
        }
        return Array(scalars[..<end])
    }
}

/// Bounded line splitting and wrapping over already concealed text.
enum ThumbnailLines {
    /// Splits at the separators the native text system recognizes (CRLF counts once) and returns at
    /// most `limit` lines. Each line keeps at most `maxScalars` scalars; the rest is consumed unread.
    static func raw(in text: String, limit: Int, maxScalars: Int) -> [[Unicode.Scalar]] {
        split(in: text, limit: limit, maxScalars: maxScalars, requiresCompleteLines: false,
              maximumInspectedScalars: nil) ?? []
    }

    /// Complete bounded lines for a stateful markup scanner. Unlike a display prefix, a discarded
    /// tail could open or close a comment. Refuse uncertain state instead of drawing a later body.
    static func complete(in text: String, limit: Int, maxScalars: Int,
                         maximumInspectedScalars: Int) -> [[Unicode.Scalar]]? {
        guard limit > 0, maxScalars > 0, maximumInspectedScalars > 0 else { return nil }
        return split(in: text, limit: limit, maxScalars: maxScalars, requiresCompleteLines: true,
                     maximumInspectedScalars: maximumInspectedScalars)
    }

    private static func split(in text: String, limit: Int, maxScalars: Int, requiresCompleteLines: Bool,
                              maximumInspectedScalars: Int?) -> [[Unicode.Scalar]]? {
        var lines: [[Unicode.Scalar]] = []
        var current: [Unicode.Scalar] = []
        var previousWasCR = false
        var inspectedScalars = 0
        func finish() -> Bool {
            lines.append(current)
            current = []
            return lines.count >= limit
        }
        for scalar in text.unicodeScalars {
            if let maximumInspectedScalars {
                guard inspectedScalars < maximumInspectedScalars else { return nil }
                inspectedScalars += 1
            }
            switch scalar.value {
            case 10:
                if previousWasCR { previousWasCR = false; continue }
                if finish() { return lines }
            case 13:
                previousWasCR = true
                if finish() { return lines }
            case 0x85, 0x2028, 0x2029:
                previousWasCR = false
                if finish() { return lines }
            default:
                previousWasCR = false
                if current.count < maxScalars { current.append(scalar) }
                else if requiresCompleteLines { return nil }
            }
        }
        if !current.isEmpty || lines.isEmpty { lines.append(current) }
        return lines
    }

    /// Tabs advance to the next stop; any other control scalar is dropped.
    static func expandTabs(_ line: [Unicode.Scalar], tabWidth: Int = 4) -> [Unicode.Scalar] {
        guard line.contains(where: { $0.value < 32 || $0.value == 127 }) else { return line }
        var result: [Unicode.Scalar] = []
        var column = 0
        for scalar in line {
            if scalar.value == 9 {
                let spaces = tabWidth - column % tabWidth
                result.append(contentsOf: repeatElement(Unicode.Scalar(32), count: spaces))
                column += spaces
            } else if scalar.value < 32 || scalar.value == 127 {
                continue
            } else {
                result.append(scalar)
                column += ThumbnailCells.width(of: scalar)
            }
        }
        return result
    }

    static func isBlank(_ line: [Unicode.Scalar]) -> Bool {
        line.allSatisfy { $0.properties.isWhitespace }
    }

    /// Spaces at the start of the line; the count is the indent in cells.
    static func leadingSpaces(_ line: [Unicode.Scalar]) -> Int {
        line.prefix(while: { $0.value == 32 }).count
    }

    static func trimmingTrailingWhitespace(_ line: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var end = line.count
        while end > 0, line[end - 1].properties.isWhitespace { end -= 1 }
        return Array(line[..<end])
    }

    /// Greedy wrapping at spaces; a word wider than a line is split at the cell limit.
    static func wrap(_ line: [Unicode.Scalar], cells: Int, maximumPieces: Int) -> [[Unicode.Scalar]] {
        guard cells > 0, maximumPieces > 0 else { return [] }
        var pieces: [[Unicode.Scalar]] = []
        var remaining = line[...]
        while !remaining.isEmpty, pieces.count < maximumPieces {
            let head = ThumbnailCells.prefix(Array(remaining), cells: cells)
            if head.count == remaining.count {
                pieces.append(head)
                break
            }
            var cut = head.count
            if remaining[remaining.startIndex + cut].value != 32,
               let space = head.lastIndex(where: { $0.value == 32 }), space > 0 {
                cut = space
            }
            if cut == 0 { cut = max(1, head.count) }
            pieces.append(Array(remaining.prefix(cut)))
            remaining = remaining.dropFirst(cut)
            while let first = remaining.first, first.value == 32 { remaining = remaining.dropFirst() }
        }
        return pieces
    }
}

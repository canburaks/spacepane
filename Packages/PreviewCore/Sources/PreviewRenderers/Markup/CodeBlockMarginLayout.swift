import AppKit

/// One bounded index per replacement; only candidate indices reach native layout on scroll.
struct CodeBlockMarginIndex: Sendable {
    private struct Entry: Sendable { let index: Int; let range: NSRange }
    private let entries: [Entry]
    private let textLength: Int

    init(_ blocks: [MarkupCodeBlock], textLength: Int) {
        self.textLength = max(0, textLength)
        var entries: [Entry] = [], lastEnd = 0
        for (index, block) in blocks.enumerated() {
            let range = block.range
            guard range.location >= lastEnd, range.location != NSNotFound, range.location <= self.textLength,
                  range.length > 0, range.length <= self.textLength - range.location else { continue }
            entries.append(.init(index: index, range: range))
            lastEnd = range.location + range.length
        }
        self.entries = entries
    }

    func candidates(overlapping characters: NSRange) -> [Int] {
        guard characters.location >= 0, characters.location != NSNotFound, characters.location <= textLength,
              characters.length > 0, characters.length <= textLength - characters.location else { return [] }
        var lower = 0, upper = entries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2, range = entries[middle].range
            if range.location + range.length <= characters.location { lower = middle + 1 } else { upper = middle }
        }
        var result: [Int] = [], index = lower
        let end = characters.location + characters.length
        while index < entries.count, entries[index].range.location < end {
            result.append(entries[index].index); index += 1
        }
        return result
    }
}

enum CodeBlockMarginPlacement {
    static func frame(card: NSRect, column: NSRect, viewport: NSRect, trailingOnLeft: Bool) -> NSRect? {
        guard [card, column, viewport].allSatisfy({ rect in
            [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
        }) else { return nil }
        guard card.width > 0, card.height > 0, column.width > 0, viewport.width > 0, viewport.height > 0 else { return nil }
        let margin = trailingOnLeft ? column.minX - viewport.minX : viewport.maxX - column.maxX
        guard margin >= 32 else { return nil }
        let x = trailingOnLeft ? column.minX - 27 : column.maxX + 5
        let frame = NSRect(x: x, y: card.minY + 4, width: 22, height: 22)
        guard viewport.contains(frame), !frame.intersects(column) else { return nil }
        return frame
    }
}

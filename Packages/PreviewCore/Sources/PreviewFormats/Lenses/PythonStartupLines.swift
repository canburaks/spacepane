import Foundation
import PreviewContracts

/// The lines of a Python path configuration file (`.pth`) that Python's `site` module runs at every
/// start (decision 030): a line that begins with `import` followed by a space or a tab. `site` skips
/// comment and blank lines and adds every other line to the module search path. Shared by the `.pth`
/// lens and the wheel adapter so both report the same lines.
enum PythonStartupLines {
    private static let importWord = Array("import".utf16)

    /// One-based logical line numbers (as `LogicalLines` counts them) of the lines that run code.
    static func lines(in text: String, context: RequestContext) throws -> [Int] {
        let index = LogicalLines.starts(in: text)
        guard !index.starts.isEmpty else { return [] }
        let units = Array(text.utf16)
        var found: [Int] = []
        for (number, start) in index.starts.enumerated() {
            if number.isMultiple(of: 1_024) { try context.checkpoint() }
            var position = start
            // A byte-order mark the decoder kept is not part of the first line.
            if number == 0, position < units.count, units[position] == 0xFEFF { position += 1 }
            guard position + importWord.count < units.count,
                  units[position..<(position + importWord.count)].elementsEqual(importWord) else { continue }
            let next = units[position + importWord.count]
            if next == 0x20 || next == 0x09 { found.append(number + 1) }
        }
        return found
    }
}

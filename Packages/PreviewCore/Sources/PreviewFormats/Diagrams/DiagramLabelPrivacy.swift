import Foundation
import PreviewContracts

/// Finds secret-like assignments inside diagram labels and attribute values, such as
/// `Password: hunter2` or `<b>API Key</b>=abc<br>next line`. The value after the delimiter is
/// concealed up to the end of its visible line, so the markup around it stays well formed.
/// Offsets count Unicode scalars of the value as given (already unescaped by the XML parser).
enum DiagramLabelPrivacy {
    /// Words before a delimiter that may name a secret together ("Access Key", "Client Secret").
    private static let maximumKeyWords = 2

    static func spans(in value: String, context: RequestContext) throws -> [Range<Int>] {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty else { return [] }
        // Mark scalars that belong to an HTML tag, and the tags that end a visible line.
        var isTag = [Bool](repeating: false, count: scalars.count)
        var isBreak = [Bool](repeating: false, count: scalars.count)
        var index = 0
        while index < scalars.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            guard scalars[index] == "<" else { index += 1; continue }
            var cursor = index + 1
            if cursor < scalars.count, scalars[cursor] == "/" { cursor += 1 }
            guard cursor < scalars.count, scalars[cursor].properties.isAlphabetic,
                  let close = (cursor..<min(scalars.count, index + 120)).first(where: { scalars[$0] == ">" }) else { index += 1; continue }
            let name = String(String.UnicodeScalarView(scalars[cursor..<close])).lowercased().prefix { $0.isLetter || $0.isNumber }
            for position in index...close { isTag[position] = true }
            if ["br", "div", "p", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6"].contains(String(name)) { isBreak[index] = true }
            index = close + 1
        }
        func endsLine(_ position: Int) -> Bool {
            isBreak[position] || (!isTag[position] && (scalars[position] == "\n" || scalars[position] == "\r"))
        }
        func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
            scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "_" || scalar == "." || scalar == "-"
        }

        var spans: [Range<Int>] = []
        var position = 0
        var lineStart = 0
        while position < scalars.count {
            if position.isMultiple(of: 512) { try context.checkpoint() }
            if endsLine(position) { lineStart = position + 1; position += 1; continue }
            guard !isTag[position], scalars[position] == ":" || scalars[position] == "=", position >= lineStart else { position += 1; continue }
            // Collect the visible words immediately before the delimiter, on this line.
            var words: [String] = []
            var cursor = position - 1
            while cursor >= lineStart, words.count < maximumKeyWords {
                while cursor >= lineStart, isTag[cursor] || scalars[cursor] == " " || scalars[cursor] == "\t" || scalars[cursor] == "\"" || scalars[cursor] == "'" { cursor -= 1 }
                var word = String.UnicodeScalarView()
                var end = cursor
                while end >= lineStart, !isTag[end], isWordScalar(scalars[end]) { word.insert(scalars[end], at: word.startIndex); end -= 1 }
                guard end < cursor else { break }
                words.insert(String(word), at: 0)
                cursor = end
            }
            let sensitive = (1...max(words.count, 1)).contains { count in
                words.count >= count && SecretFieldPolicy.isSensitive(words.suffix(count).joined())
            }
            guard sensitive else { position += 1; continue }
            var start = position + 1
            while start < scalars.count, !endsLine(start), scalars[start] == " " || scalars[start] == "\t" { start += 1 }
            var end = start
            while end < scalars.count, !endsLine(end) { end += 1 }
            if end > start { spans.append(start..<end) }
            position = max(end, position + 1)
        }
        return spans
    }
}

import PreviewContracts

/// Follows the comments of a markup that a thumbnail draws as a rendered page (Markdown, AsciiDoc, Org), one
/// line at a time. A reader of the rendered document never sees them, so the thumbnail does not draw them either
/// (decision 027, Q-127; thumbnails review TH-14): a comment can hold a note or an instruction that was never
/// meant to be read, and a thumbnail outlives the document's rendering in Finder's durable cache.
///
/// The caller hands over every line outside a fenced code block, in order, and keeps handing them over while
/// `isInsideComment` is true, because a comment can end in the middle of a line that then continues as text.
///
/// Markdown follows the rules of the shared scanner behind the hidden-comment finding: `<!-- ... -->` over any number
/// of lines and in the middle of a line, `<!-->` and `<!--->`, the link-reference forms `[//]: # (text)` and
/// `[comment]: <> (text)`, code spans and `\<!--` as literal text, and an opening that is never closed running to the
/// end of the document, as CommonMark has it. AsciiDoc has `//` lines and `////` blocks; Org has `# ` lines and
/// `#+BEGIN_COMMENT` blocks. A line that holds only comment text yields nil and draws nothing, not even the blank
/// line a paragraph break would be.
struct ThumbnailCommentSkipper {
    private enum Markup { case markdown, asciidoc, org }

    private let markup: Markup
    /// True from the line that opens a comment to the line that closes it.
    private(set) var isInsideComment = false

    private static let commentOpening = Array("<!--".unicodeScalars)
    private static let commentClosing = Array("-->".unicodeScalars)

    init(syntax: TextSyntax) {
        switch syntax {
        case .asciidoc: markup = .asciidoc
        case .orgMode: markup = .org
        default: markup = .markdown
        }
    }

    /// The part of `line` a reader sees, or nil when the whole line is comment.
    mutating func visible(in line: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        switch markup {
        case .markdown: return visibleMarkdown(line)
        case .asciidoc: return visibleAsciiDoc(line)
        case .org: return visibleOrg(line)
        }
    }

    // MARK: Markdown

    private mutating func visibleMarkdown(_ line: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        var index = 0
        var removedComment = false
        if isInsideComment {
            removedComment = true
            guard let close = Self.indexOfCommentEnd(in: line, from: 0) else { return nil }
            isInsideComment = false
            index = close + Self.commentClosing.count
        } else if Self.isLinkReferenceComment(line) {
            return nil
        }
        var visible: [Unicode.Scalar] = []
        let count = line.count
        while index < count {
            let scalar = line[index]
            if scalar == "`" {
                // A code span is text, so a comment opening inside it is literal.
                let end = Self.endOfCodeSpan(in: line, openingAt: index)
                visible.append(contentsOf: line[index..<end])
                index = end
                continue
            }
            if scalar == "\\", index + 1 < count {
                // A backslash escapes the next character: `\<!--` is literal text.
                visible.append(scalar)
                visible.append(line[index + 1])
                index += 2
                continue
            }
            if Self.matches(line, at: index, Self.commentOpening) {
                removedComment = true
                let body = index + Self.commentOpening.count
                if body < count, line[body] == ">" {
                    index = body + 1
                } else if body + 1 < count, line[body] == "-", line[body + 1] == ">" {
                    index = body + 2
                } else if let close = Self.indexOfCommentEnd(in: line, from: body) {
                    index = close + Self.commentClosing.count
                } else {
                    // Never closed on this line: the rest of it, and the lines after it, are comment.
                    isInsideComment = true
                    break
                }
                continue
            }
            visible.append(scalar)
            index += 1
        }
        if removedComment, visible.allSatisfy({ $0.properties.isWhitespace }) { return nil }
        return visible
    }

    /// Index of the `-->` at or after `start`, if the line holds one.
    private static func indexOfCommentEnd(in line: [Unicode.Scalar], from start: Int) -> Int? {
        var index = max(0, start)
        while index + commentClosing.count <= line.count {
            if matches(line, at: index, commentClosing) { return index }
            index += 1
        }
        return nil
    }

    /// Where a code span that opens at `start` ends: after the next run of backticks of the same length on the
    /// line, or after the opening run alone when none follows, which makes those backticks literal.
    private static func endOfCodeSpan(in line: [Unicode.Scalar], openingAt start: Int) -> Int {
        var runEnd = start
        while runEnd < line.count, line[runEnd] == "`" { runEnd += 1 }
        let length = runEnd - start
        var index = runEnd
        while index < line.count {
            guard line[index] == "`" else {
                index += 1
                continue
            }
            var closeEnd = index
            while closeEnd < line.count, line[closeEnd] == "`" { closeEnd += 1 }
            if closeEnd - index == length { return closeEnd }
            index = closeEnd
        }
        return runEnd
    }

    /// `[//]: # (text)`, `[//]: <> "text"` and `[comment]: <> (text)`: a link definition whose destination is empty
    /// or `#` and whose title holds the text. Up to three spaces of indentation, as for any definition.
    private static func isLinkReferenceComment(_ line: [Unicode.Scalar]) -> Bool {
        var index = 0
        while index < line.count, index < 3, line[index] == " " { index += 1 }
        guard index < line.count, line[index] == "[" else { return false }
        index += 1
        let labelStart = index
        while index < line.count, line[index] != "]", index - labelStart <= 8 { index += 1 }
        guard index + 1 < line.count, line[index] == "]", line[index + 1] == ":" else { return false }
        let label = ThumbnailCells.string(line[labelStart..<index]).lowercased()
        guard label == "//" || label == "comment" else { return false }
        index += 2
        let spaceStart = index
        while index < line.count, line[index] == " " { index += 1 }
        guard index > spaceStart, index < line.count else { return false }
        if line[index] == "#" {
            index += 1
        } else if index + 1 < line.count, line[index] == "<", line[index + 1] == ">" {
            index += 2
        } else {
            return false
        }
        let titleSpace = index
        while index < line.count, line[index] == " " { index += 1 }
        guard index > titleSpace, index < line.count else { return false }
        return line[index] == "(" || line[index] == "\"" || line[index] == "'"
    }

    // MARK: AsciiDoc

    private mutating func visibleAsciiDoc(_ line: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        let slashes = line.prefix(while: { $0 == "/" }).count
        if slashes >= 4, slashes == line.count {
            isInsideComment.toggle()
            return nil
        }
        if isInsideComment { return nil }
        // Exactly two slashes open a line comment; three or more followed by text are ordinary text.
        return slashes == 2 ? nil : line
    }

    // MARK: Org

    private mutating func visibleOrg(_ line: [Unicode.Scalar]) -> [Unicode.Scalar]? {
        let body = line.drop(while: { $0 == " " })
        let lowered = ThumbnailCells.string(body.prefix(16)).lowercased()
        if isInsideComment {
            if lowered.hasPrefix("#+end_comment") { isInsideComment = false }
            return nil
        }
        if lowered.hasPrefix("#+begin_comment") {
            isInsideComment = true
            return nil
        }
        // `# text` is a comment line; `#+` starts a keyword and is not one.
        if body.first == "#", body.count == 1 || body[body.startIndex + 1] == " " { return nil }
        return line
    }

    // MARK: Scanning

    private static func matches(_ line: [Unicode.Scalar], at index: Int, _ marker: [Unicode.Scalar]) -> Bool {
        guard index >= 0, index + marker.count <= line.count else { return false }
        for offset in marker.indices where line[index + offset] != marker[offset] { return false }
        return true
    }
}

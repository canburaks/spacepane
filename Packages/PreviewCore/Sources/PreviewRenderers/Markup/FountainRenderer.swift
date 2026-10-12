import Foundation

/// A reading of Fountain screenplay text for the Rendered and Contents views: a title page,
/// section markers, scene headings (listed in Contents), action, character cues,
/// parentheticals, dialogue, transitions, centered text, lyrics, synopses and notes.
/// The rules follow the public Fountain syntax description; forced elements (`!`, `@`, `.`, `>`,
/// `~`) are honored. Boneyard text (`/* ... */`) is shown dimmed. Nothing is converted or exported.
struct FountainRenderer {
    private let lines: [String]
    private var writer: MarkupBlockWriter

    private static let sceneStarts = ["INT.", "EXT.", "EST.", "INT/EXT", "INT./EXT", "I/E", "INT ", "EXT ", "EST ", "I/E."]
    private static let maximumTitlePageLines = 200

    static func render(_ source: String, limits: MarkupBuilder.Limits) -> SafeMarkdownDocument? {
        guard source.utf16.prefix(limits.maximumUTF16Units + 1).count <= limits.maximumUTF16Units else { return nil }
        let lines = MarkupLines.split(source)
        guard lines.count <= 20_000 else { return nil }
        var renderer = FountainRenderer(lines: lines, writer: MarkupBlockWriter(limits: limits))
        renderer.run()
        return renderer.writer.finish { text in
            var scratch = MarkupFootnotes()
            return MarkupDialectInline.render(text, dialect: .fountain, footnotes: &scratch)
        }
    }

    private init(lines: [String], writer: MarkupBlockWriter) {
        self.lines = lines
        self.writer = writer
    }

    private mutating func inline(_ text: String) -> MarkupInlineResult {
        MarkupDialectInline.render(text, dialect: .fountain, footnotes: &writer.footnotes)
    }

    // MARK: Driver

    private mutating func run() {
        let bodyStart = titlePage()
        body(from: bodyStart)
    }

    private func isBlank(_ index: Int) -> Bool {
        index < 0 || index >= lines.count || lines[index].trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Title page

    /// A title page is a block of `Key: value` lines at the top, ended by a blank line.
    /// Returns the index where the screenplay body starts.
    private mutating func titlePage() -> Int {
        var start = 0
        while start < lines.count, isBlank(start) { start += 1 }
        guard start < lines.count, Self.titleKey(lines[start]) != nil else { return 0 }
        var entries: [(key: String, value: [String])] = []
        var index = start
        while index < lines.count, !isBlank(index), index - start < Self.maximumTitlePageLines {
            let line = lines[index]
            if let (key, value) = Self.titleKey(line), !(line.first == " " || line.first == "\t") {
                entries.append((key, value.isEmpty ? [] : [value]))
            } else if !entries.isEmpty {
                entries[entries.count - 1].value.append(line.trimmingCharacters(in: .whitespaces))
            }
            index += 1
        }
        for entry in entries {
            let text = entry.value.joined(separator: " ")
            switch entry.key.lowercased() {
            case "title":
                if !text.isEmpty { writer.paragraph(inline(text), styles: [.bold, .centered]) }
            case "credit", "author", "authors", "source":
                if !text.isEmpty { writer.paragraph(inline(text), styles: [.centered]) }
            default:
                writer.dimmedLine(entry.key + ": " + text, grouped: true)
            }
        }
        writer.separate()
        return index
    }

    private static func titleKey(_ line: String) -> (String, String)? {
        guard let first = line.first, first.isLetter, let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colon])
        guard key.count <= 40, key.allSatisfy({ $0.isLetter || $0 == " " }) else { return nil }
        return (key, String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Body

    private enum Context { case none, dialogue }

    private mutating func body(from start: Int) {
        var index = start
        var context = Context.none
        var inBoneyard = false
        var actionOpen = false
        while index < lines.count {
            guard !writer.isOverflowed else { return }
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            defer { index += 1 }
            if inBoneyard {
                if trimmed.contains("*/") { inBoneyard = false }
                if !trimmed.isEmpty { writer.dimmedLine(trimmed) }
                continue
            }
            if trimmed.hasPrefix("/*") {
                inBoneyard = !trimmed.dropFirst(2).contains("*/")
                writer.dimmedLine(trimmed, grouped: false)
                context = .none
                actionOpen = false
                continue
            }
            if trimmed.isEmpty {
                // Exactly two spaces keep a dialogue block open; any other blank line ends it.
                if raw == "  ", context == .dialogue { writer.line(MarkupInlineResult(text: "", decorations: [])); continue }
                context = .none
                actionOpen = false
                continue
            }
            if context == .dialogue {
                dialogueLine(trimmed)
                continue
            }
            let previousBlank = isBlank(index - 1) || index == start
            let nextBlank = isBlank(index + 1)
            // Page break, synopsis, section, forced elements.
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "=" }) { writer.rule(); actionOpen = false; continue }
            if trimmed.hasPrefix("="), !trimmed.hasPrefix("=="), previousBlank {
                writer.line(inline(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)), styles: [.dimmed, .italic], groupedWithPrevious: false)
                continue
            }
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
                if level <= 6, !title.isEmpty {
                    writer.heading(level: min(level, 3), inline(title))
                    actionOpen = false
                    continue
                }
            }
            if trimmed.hasPrefix(">"), trimmed.hasSuffix("<"), trimmed.count > 2 {
                let text = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                writer.paragraph(inline(text), styles: [.centered])
                actionOpen = false
                continue
            }
            if trimmed.hasPrefix(">") {
                writer.paragraph(inline(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)), styles: [.trailing])
                actionOpen = false
                continue
            }
            if trimmed.hasPrefix("~") {
                writer.line(inline(String(trimmed.dropFirst())), styles: [.italic], groupedWithPrevious: actionOpen)
                actionOpen = true
                continue
            }
            if trimmed.hasPrefix("!") {
                writer.line(inline(String(trimmed.dropFirst())), groupedWithPrevious: actionOpen)
                actionOpen = true
                continue
            }
            if trimmed.hasPrefix("@") {
                character(String(trimmed.dropFirst()))
                context = .dialogue
                actionOpen = false
                continue
            }
            if let scene = Self.sceneHeading(trimmed, previousBlank: previousBlank) {
                writer.heading(level: 2, inline(scene), style: .bold)
                actionOpen = false
                continue
            }
            if previousBlank, Self.isTransition(trimmed) {
                writer.paragraph(inline(trimmed), styles: [.trailing])
                actionOpen = false
                continue
            }
            if previousBlank, !nextBlank, Self.isCharacter(trimmed) {
                character(trimmed)
                context = .dialogue
                actionOpen = false
                continue
            }
            // Action keeps its line breaks.
            writer.line(inline(trimmed), groupedWithPrevious: actionOpen)
            actionOpen = true
        }
    }

    // MARK: Elements

    private mutating func character(_ text: String) {
        var cue = text
        if cue.hasSuffix("^") { cue.removeLast() }
        writer.line(inline(cue.trimmingCharacters(in: .whitespaces)), styles: [.bold, .indent(4)], groupedWithPrevious: false)
    }

    private mutating func dialogueLine(_ trimmed: String) {
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") {
            writer.line(inline(trimmed), styles: [.italic, .indent(3)])
        } else {
            writer.line(inline(trimmed), styles: [.indent(2)])
        }
    }

    private static func sceneHeading(_ trimmed: String, previousBlank: Bool) -> String? {
        if trimmed.hasPrefix("."), !trimmed.hasPrefix(".."), trimmed.count > 1 { return stripSceneNumber(String(trimmed.dropFirst())) }
        guard previousBlank else { return nil }
        let upper = trimmed.uppercased()
        guard sceneStarts.contains(where: { upper.hasPrefix($0) }) else { return nil }
        return stripSceneNumber(trimmed)
    }

    /// A trailing `#12#` scene number is metadata, not part of the heading text.
    private static func stripSceneNumber(_ text: String) -> String {
        guard text.hasSuffix("#"), let open = text.dropLast().lastIndex(of: "#") else { return text }
        return String(text[..<open]).trimmingCharacters(in: .whitespaces)
    }

    private static func isUppercase(_ text: String) -> Bool {
        text.contains(where: { $0.isLetter }) && !text.contains(where: { $0.isLowercase })
    }

    private static func isTransition(_ trimmed: String) -> Bool {
        isUppercase(trimmed) && trimmed.hasSuffix("TO:")
    }

    /// An uppercase cue, optionally followed by an extension in parentheses such as `(V.O.)`.
    private static func isCharacter(_ trimmed: String) -> Bool {
        var name = trimmed
        if name.hasSuffix("^") { name.removeLast() }
        if let open = name.firstIndex(of: "(") { name = String(name[..<open]).trimmingCharacters(in: .whitespaces) }
        return !name.isEmpty && isUppercase(name)
    }
}

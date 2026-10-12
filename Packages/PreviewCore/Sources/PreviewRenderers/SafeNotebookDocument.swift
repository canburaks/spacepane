import Foundation

/// Inert, read-only view of a Jupyter notebook (nbformat 4). Cells come only from the concealed
/// notebook JSON, never from source bytes. Nothing is executed, imported, evaluated or fetched:
/// markdown cells use the native Markdown subset, code and raw cells are fenced text, `stream`
/// and `text/plain` outputs are fenced text, and every other output representation (images, HTML,
/// SVG, JavaScript, widgets) is replaced by a placeholder naming its MIME type without decoding it.
///
/// Limits: the safe JSON is parsed within 2 MiB of UTF-16 text, 20,000 values and 64 levels; any
/// larger or unparsable text returns nil, leaving Source (and Outline when available). The Markdown
/// handed to `SafeMarkdownDocument` stays inside its own 262,144-unit, 20,000-line, 20,000-decoration
/// ceilings by stopping at a cell boundary with a localized notice; a notebook whose first rendered
/// cell alone exceeds them returns nil. Individual output blocks are capped at 300 lines / 32,768
/// units with a localized count of the lines omitted.
enum SafeNotebookDocument {
    private enum Limits {
        static let jsonUTF16Units = 2_097_152
        static let jsonNodes = 20_000
        static let jsonDepth = 64
        static let markdownUTF16Units = 262_144
        static let markdownLines = 20_000
        // Room for the truncation notice, which is one short localized line.
        static let noticeUTF16Units = 1_024
        static let noticeLines = 8
        static let outputLines = 300
        static let outputUTF16Units = 32_768
        static let literalCharacters = 96
        static let languageCharacters = 32
    }

    struct RenderResult: Sendable {
        let document: SafeMarkdownDocument
        /// All decoded cells, including empty cells and cells omitted by the rendering bounds.
        let totalCells: Int
    }

    /// Compatibility entry point. Rendering and its count share one existing parse/plan.
    static func render(_ safeJSON: String, locale: Locale) -> SafeMarkdownDocument? {
        renderResult(safeJSON, locale: locale)?.document
    }

    /// `options` default to the original layout; `renderResult(for:locale:)` asks for the grouped one.
    static func renderResult(_ safeJSON: String, locale: Locale,
                             options: NotebookRenderOptions = .original) -> RenderResult? {
        guard let plan = Plan(safeJSON: safeJSON, locale: locale, options: options) else { return nil }
        let fitting = plan.fittingBlockCount
        guard fitting > 0 || plan.blocks.isEmpty else { return nil }
        if let document = SafeMarkdownDocument.render(plan.text(showingBlocks: fitting)) {
            return RenderResult(document: document, totalCells: plan.totalCells)
        }
        // The Markdown renderer also bounds decorations, which depend on inline emphasis. Larger
        // prefixes only add decorations, so the largest rendering prefix is found by bisection.
        var rendering = 0
        var failing = fitting
        while failing - rendering > 1 {
            let middle = (rendering + failing) / 2
            if SafeMarkdownDocument.render(plan.text(showingBlocks: middle)) != nil { rendering = middle } else { failing = middle }
        }
        guard rendering > 0,
              let document = SafeMarkdownDocument.render(plan.text(showingBlocks: rendering)) else { return nil }
        return RenderResult(document: document, totalCells: plan.totalCells)
    }

    /// The Markdown source for the largest prefix of cells that fits the Markdown ceilings, before
    /// native rendering. Exposed to tests; fence markers and language names are visible here even
    /// though the native renderer consumes fence lines.
    static func markdown(_ safeJSON: String, locale: Locale, options: NotebookRenderOptions = .original) -> String? {
        guard let plan = Plan(safeJSON: safeJSON, locale: locale, options: options) else { return nil }
        let fitting = plan.fittingBlockCount
        guard fitting > 0 || plan.blocks.isEmpty else { return nil }
        return plan.text(showingBlocks: fitting)
    }

    // MARK: Plan

    private struct Block {
        let text: String
        /// One-based position of the notebook cell, counting cells that render nothing.
        let cellNumber: Int
        let utf16Units: Int
        let lines: Int
        /// Whether a thematic break is written before this block (grouped layout only).
        let precededByRule: Bool
    }

    private struct Plan {
        /// The break between a cell group and its neighbours, written as its own paragraph.
        static let rule = "---"

        let header: String?
        let blocks: [Block]
        let totalCells: Int
        let locale: Locale

        init?(safeJSON: String, locale: Locale, options: NotebookRenderOptions = .original) {
            guard let root = SafeNotebookJSONParser.parse(safeJSON, maximumUTF16Units: Limits.jsonUTF16Units,
                                                          maximumNodes: Limits.jsonNodes, maximumDepth: Limits.jsonDepth),
                  let notebook = try? SafeNotebookDecoder.decode(root) else { return nil }
            self.locale = locale
            totalCells = notebook.cells.count
            header = notebook.language.map {
                "> " + Markup.escapedInline(PreviewStrings.format(.notebookLanguage, arguments: [$0], locale: locale))
            }
            var figures = FigureNumbering(notebook: notebook, figureCount: options.figureCount)
            var blocks: [Block] = []
            var previousWasGroup: Bool?
            for (index, cell) in notebook.cells.enumerated() {
                guard let text = Markup.block(for: cell, language: notebook.language, locale: locale,
                                              figures: &figures) else { continue }
                // A break goes between two blocks when either is a code or raw cell with its outputs; prose cells
                // beside each other need none.
                let isGroup = cell.isCellGroup
                let rule = options.separatesCellGroups && (previousWasGroup.map { $0 || isGroup } ?? false)
                previousWasGroup = isGroup
                blocks.append(Block(text: text, cellNumber: index + 1, utf16Units: text.utf16.count,
                                    lines: text.components(separatedBy: .newlines).count, precededByRule: rule))
            }
            // A notebook of only empty Markdown cells has nothing to show.
            guard !blocks.isEmpty || notebook.cells.isEmpty else { return nil }
            self.blocks = blocks
        }

        /// Largest block prefix whose joined text, and truncation notice, fit the Markdown ceilings.
        var fittingBlockCount: Int {
            var units = header?.utf16.count ?? 0
            var lines = header.map { $0.components(separatedBy: .newlines).count } ?? 0
            var count = 0
            for block in blocks {
                let separated = header != nil || count > 0
                // A break is its own paragraph: the rule, and one more blank line on each side of it.
                let nextUnits = units + block.utf16Units + (separated ? 2 : 0) + (block.precededByRule ? Self.rule.utf16.count + 2 : 0)
                let nextLines = lines + block.lines + (separated ? 1 : 0) + (block.precededByRule ? 2 : 0)
                guard nextUnits <= Limits.markdownUTF16Units - Limits.noticeUTF16Units,
                      nextLines <= Limits.markdownLines - Limits.noticeLines else { break }
                units = nextUnits
                lines = nextLines
                count += 1
            }
            return count
        }

        func text(showingBlocks count: Int) -> String {
            var parts: [String] = []
            if let header { parts.append(header) }
            for block in blocks.prefix(count) {
                if block.precededByRule { parts.append(Self.rule) }
                parts.append(block.text)
            }
            if totalCells == 0 {
                parts.append(Markup.escapedInline(PreviewStrings.text(.notebookEmpty)))
            } else if count < blocks.count {
                let shown = count == 0 ? 0 : blocks[count - 1].cellNumber
                parts.append(Markup.escapedInline(PreviewStrings.format(
                    .notebookTruncated, arguments: [Int64(shown), Int64(totalCells)], locale: locale)))
            }
            return parts.joined(separator: "\n\n")
        }
    }

    // MARK: Model

    private struct Notebook {
        let language: String?
        let cells: [Cell]
    }

    private enum Cell {
        case markdown(String)
        case code(source: String, executionCount: Int64?, outputs: [Output])
        case raw(String)

        /// Code and raw cells are groups (an input, then outputs) with a boundary of their own; Markdown is prose.
        var isCellGroup: Bool {
            switch self {
            case .markdown: false
            case .code, .raw: true
            }
        }
    }

    private enum Output {
        case stream(standardError: Bool, text: String)
        /// `omittedTypes` are the representations that are not shown, in file order. `figureTypes` are the PNG and
        /// JPEG ones among them whose payload was replaced by the inert `null` placeholder, in the order the
        /// adapter extracted figures from one output (PNG, then JPEG).
        case rich(executionCount: Int64?, text: String?, omittedTypes: [String], figureTypes: [String])
        case error(name: String, value: String, traceback: String)
        case unrecognized(String)
    }

    /// Gives each PNG or JPEG placeholder the number of the figure Pages shows for it. The adapter keeps the figures it
    /// could validate in notebook order and the Markdown cannot say which ones it skipped, so numbers are handed out
    /// only when the figures and the placeholders agree in number; otherwise every image output stays unnumbered.
    private struct FigureNumbering {
        private let isActive: Bool
        private var issued = 0

        init(notebook: Notebook, figureCount: Int) {
            var placeholders = 0
            for cell in notebook.cells {
                guard case .code(_, _, let outputs) = cell else { continue }
                for output in outputs {
                    if case .rich(_, _, _, let figureTypes) = output { placeholders += figureTypes.count }
                }
            }
            isActive = figureCount > 0 && placeholders == figureCount
        }

        mutating func next() -> Int? {
            guard isActive else { return nil }
            issued += 1
            return issued
        }
    }

    /// Reads exactly the fields the view displays; any wrong type, duplicate field or unsupported
    /// version declines the whole view rather than showing a partial notebook.
    private enum SafeNotebookDecoder {
        static func decode(_ root: SafeNotebookValue) throws -> Notebook {
            guard case .object = root, case .number(let version)? = try root.member("nbformat"), version == "4",
                  case .array(let cells)? = try root.member("cells") else { throw SafeNotebookInvalid() }
            return Notebook(language: language(root), cells: try cells.map(cell))
        }

        private static func language(_ root: SafeNotebookValue) -> String? {
            let paths = [["language_info", "name"], ["kernelspec", "language"], ["kernelspec", "name"]]
            for path in paths {
                var value = try? root.member("metadata")
                for name in path { value = value.flatMap { try? $0.member(name) } }
                if case .string(let name)? = value, let sanitized = Markup.sanitizedLanguage(name) { return sanitized }
            }
            return nil
        }

        private static func cell(_ value: SafeNotebookValue) throws -> Cell {
            guard case .object = value, case .string(let type)? = try value.member("cell_type"),
                  let source = try value.member("source") else { throw SafeNotebookInvalid() }
            let text = try multilineText(source)
            switch type {
            case "markdown": return .markdown(text)
            case "raw": return .raw(text)
            case "code":
                var outputs: [Output] = []
                if let raw = try value.member("outputs") {
                    guard case .array(let items) = raw else { throw SafeNotebookInvalid() }
                    outputs = try items.map(output)
                }
                return .code(source: text, executionCount: try executionCount(value), outputs: outputs)
            default: throw SafeNotebookInvalid()
            }
        }

        private static func output(_ value: SafeNotebookValue) throws -> Output {
            guard case .object = value, case .string(let type)? = try value.member("output_type") else { throw SafeNotebookInvalid() }
            switch type {
            case "stream":
                let text = try value.member("text").map(multilineText) ?? ""
                var standardError = false
                if case .string(let name)? = try value.member("name") { standardError = name == "stderr" }
                return .stream(standardError: standardError, text: text)
            case "execute_result", "display_data":
                var text: String?
                var omitted: [String] = []
                var figureTypes: [String] = []
                if case .object(let members)? = try value.member("data") {
                    for member in members {
                        if member.key == "text/plain", let plain = try? multilineText(member.value) {
                            guard text == nil else { throw SafeNotebookInvalid() }
                            text = plain
                        } else { omitted.append(member.key) }
                    }
                    figureTypes = figurePlaceholders(in: members)
                }
                var count: Int64?
                if type == "execute_result" { count = try executionCount(value) }
                return .rich(executionCount: count, text: text, omittedTypes: omitted, figureTypes: figureTypes)
            case "error":
                var lines: [String] = []
                if let traceback = try value.member("traceback") {
                    guard case .array(let items) = traceback else { throw SafeNotebookInvalid() }
                    lines = try items.map(plainText)
                }
                return .error(name: try value.member("ename").map(plainText) ?? "",
                              value: try value.member("evalue").map(plainText) ?? "",
                              traceback: lines.joined(separator: "\n"))
            default:
                return .unrecognized(type)
            }
        }

        /// The saved-figure representations of one output, in the order the adapter extracts them. A figure was
        /// extracted from a PNG or JPEG member that appears once and whose payload is now the inert `null` placeholder;
        /// a repeated member yields no figure, so it earns no number either.
        private static func figurePlaceholders(in members: [SafeNotebookMember]) -> [String] {
            ["image/png", "image/jpeg"].filter { type in
                let matches = members.filter { $0.key == type }
                guard matches.count == 1, case .literal(let lexeme) = matches[0].value else { return false }
                return lexeme == "null"
            }
        }

        private static func executionCount(_ value: SafeNotebookValue) throws -> Int64? {
            guard case .number(let lexeme)? = try value.member("execution_count"),
                  (1...18).contains(lexeme.utf8.count), lexeme.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return Int64(lexeme)
        }

        private static func plainText(_ value: SafeNotebookValue) throws -> String {
            switch value {
            case .string(let text): return text
            case .concealed: return SafeNotebookValue.concealmentToken
            default: throw SafeNotebookInvalid()
            }
        }

        /// nbformat multiline string: a string, or an array of strings joined without separator.
        /// A concealed array element stood for a whole line, so the line break its text carried is
        /// restored; without it the next line would merge into the concealment token.
        private static func multilineText(_ value: SafeNotebookValue) throws -> String {
            guard case .array(let items) = value else { return try plainText(value) }
            var text = ""
            for (index, item) in items.enumerated() {
                text += try plainText(item)
                if case .concealed = item, index < items.count - 1 { text += "\n" }
            }
            return text
        }
    }

    // MARK: Markdown text

    /// Builds Markdown only from already-safe model values. Every line interpreted by
    /// `SafeMarkdownDocument` outside a fence is escaped; fenced text is never reinterpreted.
    private enum Markup {
        static func block(for cell: Cell, language: String?, locale: Locale, figures: inout FigureNumbering) -> String? {
            switch cell {
            case .markdown(let source):
                var text = cleaned(source)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                while text.hasSuffix("\n") { text.removeLast() }
                return closingAnyOpenFence(text)
            case .raw(let source):
                let lines = codeLines(cleaned(source))
                return group(label: PreviewStrings.text(.notebookRawCell), body: lines.isEmpty ? nil : fenced(lines, language: nil))
            case .code(let source, let count, let outputs):
                let label = count.map { PreviewStrings.format(.notebookCodeCellNumbered, arguments: [$0], locale: locale) }
                    ?? PreviewStrings.text(.notebookCodeCell)
                let lines = codeLines(cleaned(source))
                var groups = [group(label: label, body: lines.isEmpty ? nil : fenced(lines, language: language))]
                for output in outputs {
                    if let rendered = outputGroup(output, locale: locale, figures: &figures) { groups.append(rendered) }
                }
                return groups.joined(separator: "\n\n")
            }
        }

        private static func outputGroup(_ output: Output, locale: Locale, figures: inout FigureNumbering) -> String? {
            switch output {
            case .stream(let standardError, let text):
                return textGroup(label: PreviewStrings.text(standardError ? .notebookOutputStderr : .notebookOutput),
                                 text: text, locale: locale)
            case .rich(let count, let text, let omitted, let figureTypes):
                let label = count.map { PreviewStrings.format(.notebookOutputNumbered, arguments: [$0], locale: locale) }
                    ?? PreviewStrings.text(.notebookOutput)
                var lines: [String] = []
                if let text, let body = textBlock(text, locale: locale) { lines.append(body) }
                // Numbers follow the adapter's extraction order, so the figure lines are written in that order too.
                var numbers: [String: Int] = [:]
                for type in figureTypes { numbers[type] = figures.next() }
                lines.append(contentsOf: omitted.filter { numbers[$0] == nil }.map { notShown($0, locale: locale) })
                for type in figureTypes {
                    if let number = numbers[type] { lines.append(figureInPages(number, locale: locale)) }
                }
                return lines.isEmpty ? nil : group(label: label, body: lines.joined(separator: "\n"))
            case .error(let name, let value, let traceback):
                let summary = [name, value].filter { !$0.isEmpty }.joined(separator: ": ")
                let text = [summary, traceback].filter { !$0.isEmpty }.joined(separator: "\n")
                return textGroup(label: PreviewStrings.text(.notebookOutputError), text: text, locale: locale)
            case .unrecognized(let type):
                return notShown(type, locale: locale)
            }
        }

        private static func textGroup(label: String, text: String, locale: Locale) -> String? {
            textBlock(text, locale: locale).map { group(label: label, body: $0) }
        }

        /// A capped, fenced output with a localized count of omitted lines.
        private static func textBlock(_ text: String, locale: Locale) -> String? {
            let lines = codeLines(cleaned(text))
            guard !lines.isEmpty else { return nil }
            var kept: [String] = []
            var units = 0
            for line in lines {
                let cost = line.utf16.count + 1
                if kept.count >= Limits.outputLines || (!kept.isEmpty && units + cost > Limits.outputUTF16Units) { break }
                kept.append(line)
                units += cost
            }
            var block = fenced(kept, language: nil)
            if kept.count < lines.count {
                block += "\n" + escapedInline(PreviewStrings.format(
                    .notebookOutputMoreLines, arguments: [Int64(lines.count - kept.count)], locale: locale))
            }
            return block
        }

        private static func notShown(_ type: String, locale: Locale) -> String {
            escapedInline(PreviewStrings.format(.notebookOutputNotShown, arguments: [literal(type)], locale: locale))
        }

        /// An inert line that points an image output at its saved figure in Pages. The number is the figure's place
        /// in the notebook, formatted for the locale; nothing from the output itself is shown.
        private static func figureInPages(_ number: Int, locale: Locale) -> String {
            escapedInline(PreviewStrings.format(.notebookOutputFigureInPages,
                                                arguments: [number.formatted(.number.locale(locale))], locale: locale))
        }

        private static func group(label: String, body: String?) -> String {
            ["**" + escapedInline(label) + "**", body].compactMap { $0 }.joined(separator: "\n")
        }

        /// Lines of a block of text; one trailing line break is a terminator, not an extra line.
        private static func codeLines(_ text: String) -> [String] {
            var lines = text.components(separatedBy: .newlines)
            if lines.last == "" { lines.removeLast() }
            return lines == [""] ? [] : lines
        }

        /// `SafeMarkdownDocument` opens a fence on any line starting with three backticks or tildes and
        /// closes it on the next line starting with the same marker, whatever its length or info text.
        /// Choose the marker that never starts a content line. If both do, neutralize only the colliding
        /// lines with an invisible WORD JOINER, which no whitespace trimming removes.
        private static func fenced(_ lines: [String], language: String?) -> String {
            func startsWith(_ marker: String, _ line: String) -> Bool {
                line.trimmingCharacters(in: .whitespaces).hasPrefix(marker)
            }
            var body = lines
            let marker: String
            if !lines.contains(where: { startsWith("```", $0) }) { marker = "```" }
            else if !lines.contains(where: { startsWith("~~~", $0) }) { marker = "~~~" }
            else {
                marker = "```"
                body = lines.map { startsWith("```", $0) ? "\u{2060}" + $0 : $0 }
            }
            return ([marker + (language ?? "")] + body + [marker]).joined(separator: "\n")
        }

        /// Notebook Markdown is shown as written, but an unterminated fence would otherwise absorb every
        /// following cell. The same line test and tracking rule as `SafeMarkdownDocument` are used.
        static func closingAnyOpenFence(_ text: String) -> String {
            var open: String?
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { continue }
                let marker = String(trimmed.prefix(3))
                if open == nil { open = marker } else if open == marker { open = nil }
            }
            return open.map { text + "\n" + $0 } ?? text
        }

        /// Escapes characters `SafeMarkdownDocument` interprets inside a line.
        static func escapedInline(_ text: String) -> String {
            var result = ""
            for character in singleLine(text) {
                // Math (`$`), strikethrough (`~`) and superscript-like (`^`) markers are escaped too, so
                // untrusted labels never acquire the extended Markdown subset's formatting.
                if "\\`*_[$~^".contains(character) { result.append("\\") }
                result.append(character)
            }
            return result
        }

        /// Every character `SafeMarkdownDocument` treats as a line break (including U+0085, U+2028 and
        /// U+2029) and every control character becomes a space, so untrusted text cannot start a new
        /// Markdown line, heading or fence.
        private static func singleLine(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.map {
                $0.value < 0x20 || $0.value == 0x7F || CharacterSet.newlines.contains($0) ? " " : $0
            }))
        }

        /// A MIME type or output type is untrusted text: single line, bounded, never decoded.
        private static func literal(_ text: String) -> String {
            let flattened = singleLine(text)
            guard flattened.count > Limits.literalCharacters else { return flattened }
            return String(flattened.prefix(Limits.literalCharacters)) + "…"
        }

        /// The language name only feeds the fence's info text; it keeps a conservative alphabet.
        static func sanitizedLanguage(_ name: String) -> String? {
            let allowed = name.unicodeScalars.filter {
                ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || "_+#.-".unicodeScalars.contains($0))
            }
            let value = String(String.UnicodeScalarView(allowed.prefix(Limits.languageCharacters)))
            return value.isEmpty ? nil : value
        }

        /// Removes terminal escape sequences (colors in IPython tracebacks) and control characters
        /// other than tab and line feed, and normalizes carriage returns to line feeds.
        static func cleaned(_ text: String) -> String {
            let scalars = Array(text.unicodeScalars)
            var output = String.UnicodeScalarView()
            var index = 0
            while index < scalars.count {
                let scalar = scalars[index]
                index += 1
                switch scalar.value {
                case 0x1B: index = endOfEscapeSequence(scalars, after: index)
                case 0x0D:
                    output.append("\n")
                    if index < scalars.count, scalars[index] == "\n" { index += 1 }
                case 0x09, 0x0A: output.append(scalar)
                case 0..<0x20, 0x7F: break
                default: output.append(scalar)
                }
            }
            return String(output)
        }

        /// Index after the escape sequence whose introducer is at `start`. Malformed sequences consume
        /// only well-formed prefixes and never a line break, so they cannot swallow following text.
        private static func endOfEscapeSequence(_ scalars: [Unicode.Scalar], after start: Int) -> Int {
            guard start < scalars.count else { return start }
            var index = start + 1
            switch scalars[start].value {
            case 0x5B:   // CSI: parameters, intermediates, final byte
                while index < scalars.count, (0x20...0x3F).contains(scalars[index].value) { index += 1 }
                if index < scalars.count, (0x40...0x7E).contains(scalars[index].value) { index += 1 }
                return index
            case 0x5D:   // OSC: ended by BEL or ESC \
                while index < scalars.count, scalars[index].value != 0x0A {
                    let next = scalars[index]
                    index += 1
                    if next.value == 0x07 { break }
                    if next.value == 0x1B, index < scalars.count, scalars[index].value == 0x5C { index += 1; break }
                }
                return index
            case 0x20...0x2F:   // Character-set style: intermediates then a final byte
                while index < scalars.count, (0x20...0x2F).contains(scalars[index].value) { index += 1 }
                if index < scalars.count, (0x30...0x7E).contains(scalars[index].value) { index += 1 }
                return index
            case 0x30...0x7E:   // Two-character sequence
                return index
            default:
                return start   // A bare ESC drops only itself.
            }
        }
    }
}

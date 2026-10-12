import Foundation
import PreviewContracts

/// Converts tolerant HTML or XHTML into the Markdown subset the native renderer shows. It is a streaming
/// state machine over `MarkupTokenizer` events: it never loads a resource, follows a link, applies a style or
/// runs a script. Headings, paragraphs, flat and nested lists, block quotes, preformatted text, emphasis,
/// code, tables (as pipe rows) and images (as `![alt]()`, a description without a source) are kept; scripts,
/// styles, frames, objects, forms, SVG, MathML and media are dropped with their content. Link destinations
/// and image sources are discarded, so only the readable text survives.
///
/// Nesting is bounded (lists, quotes, open emphasis), the element count is charged to a caller-owned
/// budget shared across documents, and output stops cleanly when the `MarkdownWriter` is full.
enum HTMLMarkdownConverter {
    struct Outcome: Equatable, Sendable {
        /// Text of the document's `<title>`, collapsed to one line.
        var title: String?
        /// Whether conversion stopped before the end of the input (output ceiling or element budget).
        var truncated: Bool
    }

    /// Elements removed together with everything inside them.
    static let droppedElements: Set<String> = ["script", "style", "iframe", "object", "embed", "form", "svg", "math", "head",
                                               "noscript", "template", "audio", "video", "canvas", "applet", "select",
                                               "button", "textarea", "rt", "rp", "frameset", "frame"]

    fileprivate static let blockElements: Set<String> = ["p", "div", "section", "article", "aside", "nav", "header", "footer",
                                                     "main", "figure", "figcaption", "address", "details", "summary",
                                                     "fieldset", "legend", "center", "caption", "dl", "dt", "dd", "body",
                                                     "html", "hgroup", "optgroup", "menu"]

    /// Elements the tokenizer treats as raw text; the conversion would discard their content anyway.
    static let rawTextElements: Set<String> = ["script", "style"]

    /// - Parameters:
    ///   - fallbackHeading: written before the first block when that block is not itself a heading, so a chapter
    ///     without its own heading is still navigable.
    ///   - nodeBudget: elements still allowed across the whole document; reduced by this call.
    @discardableResult
    static func convert(_ html: String, into writer: inout MarkdownWriter, fallbackHeading: String? = nil,
                        nodeBudget: inout Int, context: RequestContext) throws -> Outcome {
        var tokenizer = MarkupTokenizer(html, rawTextElements: rawTextElements, context: context)
        var converter = Converter(writer: writer, fallbackHeading: fallbackHeading, nodesRemaining: nodeBudget)
        var truncated = false
        while let event = try tokenizer.next() {
            converter.handle(event)
            if converter.writer.isFull || converter.nodesRemaining < 0 {
                truncated = true
                break
            }
        }
        converter.finish()
        writer = converter.writer
        nodeBudget = max(0, converter.nodesRemaining)
        return Outcome(title: converter.title, truncated: truncated || converter.writer.isFull)
    }

    // MARK: State machine

    private struct ListFrame { var ordered: Bool; var counter: Int }

    private struct TableState {
        var rows: [[String]] = []
        var row: [String] = []
        var cellIsOpen = false
        var cellCount = 0
    }

    private struct Converter {
        static let maximumListDepth = 8
        static let maximumQuoteDepth = 8
        static let maximumOpenMarkers = 16
        static let maximumTableCells = 5_000
        static let maximumCellCharacters = 200

        var writer: MarkdownWriter
        var fallbackHeading: String?
        var nodesRemaining: Int
        var title: String?

        /// An emphasis or code marker already written to `current`, and where the text after it begins.
        /// A marker closed with nothing written since it opened is removed instead of left empty.
        private struct OpenMarker { let text: String; var offset: Int }

        // Inline accumulation: finished hard-broken lines plus the one being built.
        private var lines: [String] = []
        private var current = ""
        private var pendingSpace = false
        private var markers: [OpenMarker] = []
        private var codeDepth = 0
        private var codeOffset = 0

        // Block context.
        private var headingLevel: Int?
        private var quoteDepth = 0
        private var lists: [ListFrame] = []
        private var pendingMarker: String?
        private var forceBlankBeforeNext = false
        private var preDepth = 0
        private var preText = ""
        private var skip: (name: String, depth: Int)?
        private var titleCapture: String?
        private var table: TableState?
        private var tableDepth = 0
        private var emittedBlock = false

        init(writer: MarkdownWriter, fallbackHeading: String?, nodesRemaining: Int) {
            self.writer = writer
            self.fallbackHeading = fallbackHeading.map { MarkdownEscaping.singleLine($0) }.flatMap { $0.isEmpty ? nil : $0 }
            self.nodesRemaining = nodesRemaining
        }

        mutating func finish() {
            flushBlock()
            if table != nil { emitTable() }
            if preDepth > 0 { preDepth = 0; emitPreformatted() }
        }

        mutating func handle(_ event: MarkupEvent) {
            switch event {
            case .text(let text): handleText(text)
            case .start(let name, let attributes, let selfClosing):
                nodesRemaining -= 1
                handleStart(name, attributes: attributes, selfClosing: selfClosing)
                if selfClosing, !HTMLVoidElements.names.contains(name) { handleEnd(name) }
            case .end(let name): handleEnd(name)
            }
        }

        // MARK: Text

        private mutating func handleText(_ text: String) {
            if titleCapture != nil { titleCapture?.append(text); return }
            if skip != nil { return }
            if preDepth > 0 { preText.append(text); return }
            appendProse(text)
        }

        private mutating func appendProse(_ text: String) {
            let isCode = codeDepth > 0
            for scalar in text.unicodeScalars {
                if MarkdownEscaping.isBreakingSpace(scalar) { pendingSpace = true; continue }
                if MarkdownEscaping.isRemovable(scalar) { continue }
                if pendingSpace, !current.isEmpty { current.append(" ") }
                pendingSpace = false
                if isCode {
                    if scalar == "`" { current.append("'"); continue }
                    if scalar == "\\" { current.append("\\") }
                } else if MarkdownEscaping.needsEscape(scalar, after: current.unicodeScalars.last) {
                    current.append("\\")
                }
                current.unicodeScalars.append(scalar)
            }
        }

        private mutating func appendLiteral(_ text: String) {
            if pendingSpace, !current.isEmpty { current.append(" ") }
            pendingSpace = false
            current.append(text)
        }

        // MARK: Start tags

        private mutating func handleStart(_ name: String, attributes: [MarkupAttribute], selfClosing: Bool) {
            if name == "title", skip == nil || skip?.name == "head" {
                if !selfClosing { titleCapture = "" }
                return
            }
            if let active = skip {
                if name == "body", active.name == "head" { skip = nil }
                else if name == active.name, !selfClosing { skip?.depth += 1 }
                if skip != nil { return }
            }
            if Self.dropped(name) {
                if !selfClosing { skip = (name, 1) }
                return
            }
            if let level = Self.headingLevel(of: name) {
                flushBlock()
                headingLevel = level
                return
            }
            switch name {
            case "br":
                lineBreak()
            case "hr":
                flushBlock()
                beforeBlock(isHeading: false)
                writer.thematicBreak(prefix: blockPrefix(marker: nil))
            case "ul", "ol":
                flushBlock()
                if lists.isEmpty { forceBlankBeforeNext = true }
                if lists.count < Self.maximumListDepth {
                    let start = attributes.first { $0.name == "start" }.flatMap { Int($0.value) } ?? 1
                    lists.append(ListFrame(ordered: name == "ol", counter: max(0, min(start, 1_000_000))))
                }
            case "li":
                flushBlock()
                if var frame = lists.popLast() {
                    pendingMarker = frame.ordered ? "\(frame.counter). " : "- "
                    frame.counter += 1
                    lists.append(frame)
                } else {
                    pendingMarker = "- "
                }
            case "blockquote":
                flushBlock()
                forceBlankBeforeNext = true
                quoteDepth = min(quoteDepth + 1, Self.maximumQuoteDepth)
            case "pre":
                flushBlock()
                preDepth += 1
                if preDepth == 1 { preText = "" }
            case "code", "kbd", "samp", "tt":
                guard preDepth == 0 else { return }
                codeDepth += 1
                if codeDepth == 1 {
                    appendLiteral("`")
                    codeOffset = current.utf8.count
                }
            case "em", "i", "cite", "dfn", "var": openMarker("*")
            case "strong", "b": openMarker("**")
            case "img":
                if let image = MarkdownEscaping.image(description: attributes.first { $0.name == "alt" }?.value ?? "") {
                    appendLiteral(image)
                }
            case "table":
                flushBlock()
                tableDepth += 1
                if tableDepth == 1 { table = TableState() }
            case "tr":
                if tableDepth == 1 { commitRow() } else if tableDepth > 1 { pendingSpace = true }
            case "td", "th":
                if tableDepth == 1 { startCell() } else if tableDepth > 1 { pendingSpace = true }
            default:
                if HTMLMarkdownConverter.blockElements.contains(name) { flushBlock() }
            }
        }

        // MARK: End tags

        private mutating func handleEnd(_ name: String) {
            if name == "title", let captured = titleCapture {
                let collapsed = MarkdownEscaping.singleLine(captured)
                if title == nil, !collapsed.isEmpty { title = collapsed }
                titleCapture = nil
                return
            }
            if let active = skip {
                if name == active.name {
                    skip?.depth -= 1
                    if skip?.depth == 0 { skip = nil }
                }
                return
            }
            if Self.headingLevel(of: name) != nil {
                finishHeading()
                return
            }
            switch name {
            case "ul", "ol":
                flushBlock()
                if !lists.isEmpty { lists.removeLast() }
                if lists.isEmpty { forceBlankBeforeNext = true }
            case "li":
                flushBlock()
                pendingMarker = nil
            case "blockquote":
                flushBlock()
                quoteDepth = max(0, quoteDepth - 1)
                forceBlankBeforeNext = true
            case "pre":
                if preDepth > 0 {
                    preDepth -= 1
                    if preDepth == 0 { emitPreformatted() }
                }
            case "code", "kbd", "samp", "tt":
                guard codeDepth > 0 else { return }
                codeDepth -= 1
                if codeDepth == 0 { closeCode() }
            case "em", "i", "cite", "dfn", "var": closeMarker("*")
            case "strong", "b": closeMarker("**")
            case "table":
                if tableDepth > 0 {
                    tableDepth -= 1
                    if tableDepth == 0 { emitTable() }
                }
            case "tr":
                if tableDepth == 1 { commitRow() }
            case "td", "th":
                if tableDepth == 1 { commitCell() } else if tableDepth > 1 { pendingSpace = true }
            default:
                if HTMLMarkdownConverter.blockElements.contains(name) { flushBlock() }
            }
        }

        // MARK: Inline markers

        private mutating func openMarker(_ marker: String) {
            guard markers.count < Self.maximumOpenMarkers, codeDepth == 0, preDepth == 0 else { return }
            appendLiteral(marker)
            markers.append(OpenMarker(text: marker, offset: current.utf8.count))
        }

        private mutating func closeMarker(_ marker: String) {
            guard let index = markers.lastIndex(where: { $0.text == marker }) else { return }
            // Markers opened after this one close first so the line stays balanced.
            while markers.count > index { close(markers.removeLast()) }
        }

        private mutating func close(_ open: OpenMarker) {
            if current.utf8.count == open.offset {
                current.removeLast(open.text.count)
            } else {
                // A closing marker attaches to the preceding word, never to a pending space.
                pendingSpace = false
                current.append(open.text)
            }
        }

        private mutating func closeCode() {
            if current.utf8.count == codeOffset {
                current.removeLast()
            } else {
                pendingSpace = false
                current.append("`")
            }
        }

        private mutating func closeAllMarkers() {
            if codeDepth > 0 { codeDepth = 0; closeCode() }
            while let open = markers.popLast() { close(open) }
        }

        private mutating func lineBreak() {
            if tableDepth > 0 { pendingSpace = true; return }
            let open = markers
            for marker in open.reversed() { close(marker) }
            lines.append(current)
            current = ""
            markers = []
            // Emphasis that spans the break reopens at the start of the next line.
            for marker in open {
                current.append(marker.text)
                markers.append(OpenMarker(text: marker.text, offset: current.utf8.count))
            }
            pendingSpace = false
        }

        // MARK: Blocks

        private func blockPrefix(marker: String?) -> LinePrefix {
            let depth = max(0, lists.count - 1)
            let continuation = marker == nil && !lists.isEmpty
            return LinePrefix(quoteDepth: quoteDepth, indent: depth * 2 + (continuation ? 2 : 0), marker: marker)
        }

        /// Writes the fallback heading ahead of the chapter's first block when that block is not a heading.
        private mutating func beforeBlock(isHeading: Bool) {
            guard !emittedBlock else { return }
            emittedBlock = true
            if !isHeading, let heading = fallbackHeading {
                writer.heading(level: 1, content: MarkdownEscaping.prose(heading))
            }
        }

        private mutating func flushBlock() {
            if headingLevel != nil { finishHeading(); return }
            if tableDepth > 0 { pendingSpace = true; return }
            closeAllMarkers()
            lines.append(current)
            let content = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            lines = []
            current = ""
            pendingSpace = false
            guard !content.isEmpty else { return }
            beforeBlock(isHeading: false)
            let marker = pendingMarker
            pendingMarker = nil
            let tight = marker != nil && !forceBlankBeforeNext
            writer.paragraph(lines: content, prefix: blockPrefix(marker: marker), tight: tight)
            forceBlankBeforeNext = false
        }

        private mutating func finishHeading() {
            guard let level = headingLevel else { return }
            headingLevel = nil
            closeAllMarkers()
            lines.append(current)
            let content = lines.joined(separator: " ")
            lines = []
            current = ""
            pendingSpace = false
            guard !MarkdownEscaping.singleLine(content).isEmpty else { return }
            beforeBlock(isHeading: true)
            pendingMarker = nil
            writer.heading(level: level, content: content, prefix: blockPrefix(marker: nil))
            forceBlankBeforeNext = false
        }

        private mutating func emitPreformatted() {
            let normalized = preText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            preText = ""
            var rows = normalized.components(separatedBy: "\n").map { line -> String in
                var cleaned = ""
                for scalar in line.unicodeScalars where !MarkdownEscaping.isRemovable(scalar) && scalar.value != 0x85
                    && scalar.value != 0x2028 && scalar.value != 0x2029 { cleaned.unicodeScalars.append(scalar) }
                return cleaned
            }
            while rows.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { rows.removeFirst() }
            while rows.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { rows.removeLast() }
            guard !rows.isEmpty else { return }
            beforeBlock(isHeading: false)
            writer.codeBlock(lines: rows, prefix: blockPrefix(marker: nil))
            forceBlankBeforeNext = true
        }

        // MARK: Tables

        private mutating func startCell() {
            commitCell()
            resetInline()
            table?.cellIsOpen = true
        }

        private mutating func resetInline() {
            lines = []
            current = ""
            pendingSpace = false
            markers = []
            codeDepth = 0
        }

        private mutating func commitCell() {
            guard var state = table, state.cellIsOpen else { return }
            closeAllMarkers()
            lines.append(current)
            var text = MarkdownEscaping.singleLine(lines.joined(separator: " "))
            if text.count > Self.maximumCellCharacters { text = String(text.prefix(Self.maximumCellCharacters)) + "…" }
            text = text.replacingOccurrences(of: "|", with: "¦")
            resetInline()
            state.cellIsOpen = false
            if state.cellCount < Self.maximumTableCells {
                state.row.append(text)
                state.cellCount += 1
            }
            table = state
        }

        private mutating func commitRow() {
            commitCell()
            guard var state = table, !state.row.isEmpty else { return }
            state.rows.append(state.row)
            state.row = []
            table = state
        }

        private mutating func emitTable() {
            commitRow()
            let rows = table?.rows ?? []
            table = nil
            tableDepth = 0
            resetInline()
            guard !rows.isEmpty else { return }
            beforeBlock(isHeading: false)
            writer.table(rows: rows, prefix: blockPrefix(marker: nil))
            forceBlankBeforeNext = true
        }

        // MARK: Classification

        private static func headingLevel(of name: String) -> Int? {
            guard name.count == 2, name.first == "h", let digit = name.last?.wholeNumberValue, (1...6).contains(digit) else { return nil }
            return digit
        }

        private static func dropped(_ name: String) -> Bool { HTMLMarkdownConverter.droppedElements.contains(name) }
    }
}

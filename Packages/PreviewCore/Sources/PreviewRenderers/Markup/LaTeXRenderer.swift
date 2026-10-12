import Foundation

/// A structural reading of LaTeX source for the Rendered and Contents views.
///
/// Nothing is compiled, expanded or evaluated: macros are not defined, packages are not
/// loaded and `\input`, `\include` and `\includegraphics` are shown as dimmed source text,
/// never followed. Sectioning commands become headings, `itemize`/`enumerate`/`description`
/// become lists, quote environments and verbatim-like blocks are styled, math is approximated
/// in Unicode, text commands such as `\emph`, `\textbf` and `\texttt` style their argument and
/// comments are dimmed. Paragraphs are reflowed as LaTeX would. Unknown commands lose their
/// name and keep their braced argument, so no text is hidden by an unrecognized macro.
struct LaTeXRenderer {
    private struct ListContext {
        enum Kind { case bullet, numbered, description }
        let kind: Kind
        var counter = 0
    }
    private struct OpenItem {
        let start: Int
        let depth: Int
        let markerLength: Int
    }

    private let characters: [Character]
    private var index = 0
    private var builder: MarkupBuilder
    private var footnotes = MarkupFootnotes()
    private var pendingSpace = false
    private var lists: [ListContext] = []
    private var openItem: OpenItem?
    private var groupStyles: [[(style: MarkdownDecoration.Style, start: Int)]] = [[]]
    private var depth = 0
    private var levels: [String: Int] = [:]
    private var title: String?
    private var author: String?
    private var date: String?

    private static let maximumDepth = 32
    private static let maximumMathScan = 4_096
    private static let maximumRawEnvironmentUnits = 262_144
    private static let sectioning = ["part", "chapter", "section", "subsection", "subsubsection", "paragraph", "subparagraph"]
    private static let mathEnvironments: Set<String> = [
        "equation", "equation*", "align", "align*", "gather", "gather*", "multline", "multline*", "eqnarray", "eqnarray*",
        "displaymath", "math", "flalign", "flalign*", "alignat", "alignat*", "split"
    ]
    private static let verbatimEnvironments: Set<String> = ["verbatim", "verbatim*", "lstlisting", "minted", "Verbatim", "alltt", "BVerbatim", "LVerbatim"]
    private static let quoteEnvironments: Set<String> = ["quote", "quotation", "verse"]
    /// Commands shown as dimmed source when they appear in the body: they load files or define macros.
    private static let directives: Set<String> = [
        "input", "include", "includeonly", "bibliography", "bibliographystyle", "addbibresource", "usepackage",
        "RequirePackage", "documentclass", "newcommand", "renewcommand", "providecommand", "def", "let",
        "newenvironment", "renewenvironment", "setlength", "geometry", "hypersetup", "graphicspath", "newtheorem",
        "DeclareMathOperator", "includegraphics", "lstinputlisting", "inputminted", "import", "subfile", "subimport"
    ]
    /// Layout-only commands that vanish; the number is how many braced arguments they take.
    private static let layoutCommands: [String: Int] = [
        "noindent": 0, "centering": 0, "raggedright": 0, "raggedleft": 0, "clearpage": 0, "newpage": 0, "cleardoublepage": 0,
        "pagebreak": 0, "linebreak": 0, "tableofcontents": 0, "listoffigures": 0, "listoftables": 0, "appendix": 0,
        "protect": 0, "relax": 0, "small": 0, "footnotesize": 0, "scriptsize": 0, "tiny": 0, "large": 0, "Large": 0,
        "LARGE": 0, "huge": 0, "Huge": 0, "normalsize": 0, "hline": 0, "toprule": 0, "midrule": 0, "bottomrule": 0,
        "cline": 1, "vspace": 1, "hspace": 1, "vskip": 0, "hskip": 0, "bigskip": 0, "medskip": 0, "smallskip": 0,
        "label": 1, "pagestyle": 1, "thispagestyle": 1, "pagenumbering": 1, "setcounter": 2, "addtocounter": 2,
        "fontsize": 2, "selectfont": 0, "indent": 0, "newline": 0, "maketitle": 0, "frontmatter": 0, "mainmatter": 0,
        "backmatter": 0, "nocite": 1, "index": 1, "glossary": 1, "phantom": 1, "linewidth": 0, "textwidth": 0
    ]
    private static let italicCommands: Set<String> = ["emph", "textit", "textsl", "em", "itshape", "slshape"]
    private static let boldCommands: Set<String> = ["textbf", "bfseries", "bf"]
    private static let codeCommands: Set<String> = ["texttt", "ttfamily", "code", "tt", "lstinline", "mintinline"]
    private static let declarations: Set<String> = ["em", "itshape", "slshape", "bfseries", "bf", "ttfamily", "tt"]
    private static let citations: Set<String> = [
        "cite", "citep", "citet", "citeauthor", "citeyear", "parencite", "textcite", "autocite", "footcite", "smartcite", "citealp", "citealt"
    ]
    private static let references: Set<String> = ["ref", "eqref", "pageref", "autoref", "cref", "Cref", "nameref", "vref"]

    static func render(_ source: String, limits: MarkupBuilder.Limits) -> SafeMarkdownDocument? {
        guard source.utf16.prefix(limits.maximumUTF16Units + 1).count <= limits.maximumUTF16Units else { return nil }
        var renderer = LaTeXRenderer(characters: Array(source), builder: MarkupBuilder(limits: limits))
        return renderer.run()
    }

    private init(characters: [Character], builder: MarkupBuilder) {
        self.characters = characters
        self.builder = builder
    }

    private var isAtEnd: Bool { index >= characters.count }

    // MARK: Driver

    private mutating func run() -> SafeMarkdownDocument? {
        levels = sectioningLevels()
        if let start = documentBodyStart() {
            readPreamble(before: start)
            index = start
        }
        sequence(endEnvironment: nil, closeBrace: false)
        endParagraph()
        builder.appendFootnotes(footnotes) { text in
            MarkupInlineResult(text: text, decorations: [])
        }
        return builder.finish()
    }

    /// Levels compress to the sectioning commands the document uses: with chapters, `\chapter` is 1.
    private func sectioningLevels() -> [String: Int] {
        var present = Set<String>()
        var position = 0
        while position < characters.count {
            guard characters[position] == "\\" else { position += 1; continue }
            var end = position + 1
            while end < characters.count, characters[end].isASCII, characters[end].isLetter { end += 1 }
            let name = String(characters[(position + 1)..<end])
            if Self.sectioning.contains(name) { present.insert(name) }
            position = max(end, position + 1)
        }
        var result: [String: Int] = [:]
        for (offset, name) in Self.sectioning.filter(present.contains).enumerated() { result[name] = min(offset + 1, 6) }
        return result
    }

    /// The index just after `\begin{document}`, when the source has a preamble.
    private func documentBodyStart() -> Int? {
        let marker = Array("\\begin{document}")
        guard characters.count >= marker.count else { return nil }
        for start in 0...(characters.count - marker.count) where characters[start] == "\\" {
            if Array(characters[start..<(start + marker.count)]) == marker { return start + marker.count }
        }
        return nil
    }

    /// Captures `\title`, `\author` and `\date` from the preamble; the rest of it is never displayed.
    private mutating func readPreamble(before end: Int) {
        var position = 0
        while position < end {
            guard characters[position] == "\\" else { position += 1; continue }
            var nameEnd = position + 1
            while nameEnd < end, characters[nameEnd].isASCII, characters[nameEnd].isLetter { nameEnd += 1 }
            let name = String(characters[(position + 1)..<nameEnd])
            position = max(nameEnd, position + 1)
            guard ["title", "author", "date"].contains(name) else { continue }
            index = position
            let raw = rawGroup()
            let text = MarkupLaTeXText.plain(raw)
            switch name {
            case "title": title = text
            case "author": author = text
            default: date = text
            }
            position = max(index, position)
        }
        index = 0
    }

    // MARK: Output helpers

    private mutating func flushSpace() {
        if pendingSpace, !builder.isAtLineStart { builder.append(" ") }
        pendingSpace = false
    }

    private mutating func word(_ text: String, style: MarkdownDecoration.Style? = nil) {
        guard !text.isEmpty else { return }
        flushSpace()
        if let style { builder.append(text, style: style) } else { builder.append(text) }
    }

    /// Ends the first line of the open list item with its hanging-indent decoration.
    private mutating func closeItemLine() {
        guard let item = openItem else { return }
        builder.decorate(.listItem(depth: item.depth, markerLength: item.markerLength), from: item.start)
        openItem = nil
    }

    private mutating func endParagraph() {
        closeItemLine()
        pendingSpace = false
        builder.ensureBlockSeparation()
    }

    private mutating func startLine() {
        closeItemLine()
        pendingSpace = false
        builder.ensureLineStart()
    }

    private mutating func lineBreak() {
        closeItemLine()
        pendingSpace = false
        builder.newline()
    }

    // MARK: Scanning helpers

    private mutating func skipSpaces(includingNewlines: Bool = true) {
        while !isAtEnd {
            let character = characters[index]
            if character == " " || character == "\t" || (includingNewlines && (character == "\n" || character == "\r")) { index += 1 } else { break }
        }
    }

    /// The raw text of one braced group (balanced, escapes skipped), or empty when none follows.
    private mutating func rawGroup() -> String {
        skipSpaces()
        guard !isAtEnd, characters[index] == "{" else { return "" }
        index += 1
        var nesting = 1
        var raw = ""
        while !isAtEnd {
            let character = characters[index]
            index += 1
            if character == "\\", !isAtEnd { raw.append(character); raw.append(characters[index]); index += 1; continue }
            if character == "{" { nesting += 1 }
            else if character == "}" { nesting -= 1; if nesting == 0 { return raw } }
            raw.append(character)
        }
        return raw
    }

    /// An optional `[...]` argument, or nil.
    private mutating func optionalArgument() -> String? {
        let saved = index
        skipSpaces(includingNewlines: false)
        guard !isAtEnd, characters[index] == "[" else { index = saved; return nil }
        index += 1
        var raw = ""
        var nesting = 0
        while !isAtEnd {
            let character = characters[index]
            index += 1
            if character == "{" { nesting += 1 } else if character == "}" { nesting = max(nesting - 1, 0) }
            else if character == "]", nesting == 0 { return raw }
            raw.append(character)
        }
        return raw
    }

    private func commandName(at start: Int) -> (name: String, end: Int)? {
        var end = start
        while end < characters.count, characters[end].isASCII, characters[end].isLetter { end += 1 }
        return end > start ? (String(characters[start..<end]), end) : nil
    }

    // MARK: Sequences

    /// Reads content until the end of input, the closing brace of the current group, or
    /// `\end{endEnvironment}`. The closing brace is left for the caller to consume.
    private mutating func sequence(endEnvironment: String?, closeBrace: Bool) {
        var text = ""
        func flushText(_ renderer: inout LaTeXRenderer) {
            if !text.isEmpty { renderer.word(text); text = "" }
        }
        while !isAtEnd {
            guard !builder.isOverflowed else { return }
            let character = characters[index]
            switch character {
            case "}":
                if closeBrace { flushText(&self); return }
                index += 1
            case "{":
                flushText(&self)
                index += 1
                group()
            case "\\":
                flushText(&self)
                if command(endEnvironment: endEnvironment) { return }
            case "%":
                flushText(&self)
                comment()
            case "$":
                flushText(&self)
                mathShift()
            case "~":
                index += 1
                text.append("\u{00A0}")
            case "&":
                index += 1
                pendingSpace = true
            case " ", "\t":
                index += 1
                flushText(&self)
                pendingSpace = true
            case "\n", "\r":
                var newlines = 0
                while !isAtEnd, [" ", "\t", "\n", "\r"].contains(characters[index]) {
                    if characters[index] == "\n" || characters[index] == "\r" { newlines += 1 }
                    index += 1
                }
                flushText(&self)
                if newlines >= 2 { endParagraph() } else { pendingSpace = true }
            case "-":
                var run = 0
                while !isAtEnd, characters[index] == "-" { run += 1; index += 1 }
                text += run >= 3 ? "—" : run == 2 ? "–" : String(repeating: "-", count: run)
            case "`":
                index += 1
                if !isAtEnd, characters[index] == "`" { index += 1; text.append("“") } else { text.append("‘") }
            case "'":
                index += 1
                if !isAtEnd, characters[index] == "'" { index += 1; text.append("”") } else { text.append("’") }
            default:
                index += 1
                text.append(character)
            }
        }
        flushText(&self)
    }

    private mutating func group() {
        guard depth < Self.maximumDepth else { return }
        depth += 1
        groupStyles.append([])
        sequence(endEnvironment: nil, closeBrace: true)
        if !isAtEnd, characters[index] == "}" { index += 1 }
        for declared in groupStyles.removeLast() { builder.decorate(declared.style, from: declared.start) }
        depth -= 1
    }

    /// A braced argument whose content takes `style`.
    private mutating func styledArgument(_ style: MarkdownDecoration.Style?) {
        skipSpaces()
        guard !isAtEnd else { return }
        flushSpace()
        let start = builder.length
        if characters[index] == "{" {
            index += 1
            group()
        } else {
            // A single token: one character or command.
            let character = characters[index]
            if character == "\\" { _ = command(endEnvironment: nil) } else { index += 1; word(String(character)) }
        }
        if let style { builder.decorate(style, from: start) }
    }

    private mutating func comment() {
        var text = ""
        while !isAtEnd, characters[index] != "\n", characters[index] != "\r" { text.append(characters[index]); index += 1 }
        // A comment runs to the end of its source line, so it takes a line of its own inside the paragraph.
        if !builder.isAtLineStart { lineBreak() }
        pendingSpace = false
        builder.append(text, style: .dimmed)
        lineBreak()
    }

    // MARK: Math

    private mutating func mathShift() {
        if index + 1 < characters.count, characters[index + 1] == "$" {
            index += 2
            let tex = scanUntil("$$")
            displayMath(tex)
            return
        }
        index += 1
        let start = index
        var tex = ""
        var closed = false
        while !isAtEnd, index - start < Self.maximumMathScan {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count { tex.append(character); tex.append(characters[index + 1]); index += 2; continue }
            if character == "$" { closed = true; index += 1; break }
            tex.append(character)
            index += 1
        }
        if closed { word(MarkupMath.approximate(tex), style: .math) } else { index = start; word("$") }
    }

    /// Raw text up to (and consuming) `terminator`, or to the bound.
    private mutating func scanUntil(_ terminator: String) -> String {
        let end = Array(terminator)
        var raw = ""
        let start = index
        while !isAtEnd, index - start < Self.maximumMathScan {
            if index + end.count <= characters.count, Array(characters[index..<(index + end.count)]) == end { index += end.count; return raw }
            if characters[index] == "\\", index + 1 < characters.count { raw.append(characters[index]); raw.append(characters[index + 1]); index += 2; continue }
            raw.append(characters[index])
            index += 1
        }
        return raw
    }

    private mutating func displayMath(_ tex: String) {
        endParagraph()
        for line in MarkupMath.approximate(tex, multiline: true).components(separatedBy: "\n") {
            builder.ensureLineStart()
            let start = builder.length
            builder.append(line)
            builder.decorate(.mathBlock, from: start)
        }
        endParagraph()
    }

    // MARK: Commands

    /// Handles a command at the cursor. Returns true when it ended the enclosing environment.
    private mutating func command(endEnvironment: String?) -> Bool {
        index += 1 // the backslash
        guard !isAtEnd else { word("\\"); return false }
        let first = characters[index]
        guard first.isASCII, first.isLetter, let (name, nameEnd) = commandName(at: index) else {
            index += 1
            symbolCommand(first)
            return false
        }
        index = nameEnd
        switch name {
        case "begin":
            let environment = rawGroup().trimmingCharacters(in: .whitespaces)
            beginEnvironment(environment)
            return false
        case "end":
            let environment = rawGroup().trimmingCharacters(in: .whitespaces)
            // Nothing after the end of the document is shown.
            if environment == "document" { index = characters.count }
            return environment == endEnvironment
        case "par": endParagraph()
        case "item": item()
        case "maketitle": makeTitle()
        case "footnote": footnote()
        case "url", "path": styledArgument(.code)
        case "href":
            let target = rawGroup()
            styledArgument(nil)
            if !target.isEmpty { word(" (" + target + ")") }
        case "verb", "lstinline": verb()
        case "caption", "captionof":
            _ = optionalArgument()
            endParagraph()
            styledArgument(.italic)
            endParagraph()
        case "section", "chapter", "subsection", "subsubsection", "paragraph", "subparagraph", "part": heading(name)
        case "title": title = MarkupLaTeXText.plain(rawGroup())
        case "author": author = MarkupLaTeXText.plain(rawGroup())
        case "date": date = MarkupLaTeXText.plain(rawGroup())
        case "multicolumn": _ = rawGroup(); _ = rawGroup(); styledArgument(nil)
        case "textsuperscript", "textsubscript", "textsc", "textrm", "textsf", "textnormal", "mbox", "hbox", "underline", "text":
            styledArgument(nil)
        case "frac":
            let numerator = MarkupLaTeXText.plain(rawGroup()), denominator = MarkupLaTeXText.plain(rawGroup())
            word(numerator + "⁄" + denominator)
        default: otherCommand(name)
        }
        return false
    }

    private mutating func otherCommand(_ name: String) {
        if Self.italicCommands.contains(name) || Self.boldCommands.contains(name) || Self.codeCommands.contains(name) {
            let style: MarkdownDecoration.Style = Self.italicCommands.contains(name) ? .italic : Self.boldCommands.contains(name) ? .bold : .code
            if Self.declarations.contains(name) {
                // A declaration styles the rest of the enclosing group.
                flushSpace()
                groupStyles[groupStyles.count - 1].append((style, builder.length))
                skipSpaces()
            } else {
                styledArgument(style)
            }
            return
        }
        if Self.citations.contains(name) {
            _ = optionalArgument(); _ = optionalArgument()
            let keys = MarkupLaTeXText.plain(rawGroup())
            word("[" + keys.replacingOccurrences(of: ",", with: ", ").replacingOccurrences(of: ",  ", with: ", ") + "]")
            return
        }
        if Self.references.contains(name) {
            let key = MarkupLaTeXText.plain(rawGroup())
            word("[" + key + "]")
            return
        }
        if Self.directives.contains(name) { shownDirective(name); return }
        if let count = Self.layoutCommands[name] {
            for _ in 0..<count { _ = optionalArgument(); _ = rawGroup() }
            skipSpaces(includingNewlines: false)
            return
        }
        if let symbol = MarkupLaTeXText.symbol(named: name) {
            word(symbol)
            // A control word swallows the spaces after it; keep a word break for readability.
            if !isAtEnd, characters[index] == " " || characters[index] == "\n" { pendingSpace = true; skipSpaces() }
            return
        }
        if name.count == 1, let mark = MarkupLaTeXText.accent(named: name[name.startIndex]) {
            accent(mark)
            return
        }
        // Unknown command: the name disappears, its braced argument remains as ordinary text.
        skipSpaces(includingNewlines: false)
    }

    private mutating func symbolCommand(_ character: Character) {
        switch character {
        case "&", "%", "$", "#", "_", "{", "}": word(String(character))
        case "\\":
            _ = optionalArgumentStar()
            lineBreak()
        case " ", ",", ";", ":": pendingSpace = true
        case "-", "/", "!": break
        case "(":
            let tex = scanUntil("\\)")
            word(MarkupMath.approximate(tex), style: .math)
        case "[":
            displayMath(scanUntil("\\]"))
        default:
            if let mark = MarkupLaTeXText.accent(named: character) { accent(mark) } else { word(String(character)) }
        }
    }

    /// `\\*` and `\\[2pt]` carry layout options that are not shown.
    private mutating func optionalArgumentStar() -> String? {
        if !isAtEnd, characters[index] == "*" { index += 1 }
        return optionalArgument()
    }

    private mutating func accent(_ mark: Character) {
        skipSpaces(includingNewlines: false)
        guard !isAtEnd else { return }
        var base = ""
        if characters[index] == "{" { base = MarkupLaTeXText.plain(rawGroup()) }
        else if characters[index] == "\\" {
            // `\'\i`: the dotless letters are commands; read one command name.
            let saved = index
            index += 1
            if let (name, end) = commandName(at: index) { index = end; base = MarkupLaTeXText.symbol(named: name) ?? "" } else { index = saved + 1 }
        } else { base = String(characters[index]); index += 1 }
        word(MarkupLaTeXText.compose(mark, onto: base))
    }

    private mutating func verb() {
        guard !isAtEnd else { return }
        let delimiter = characters[index]
        index += 1
        var text = ""
        while !isAtEnd, characters[index] != delimiter, characters[index] != "\n" { text.append(characters[index]); index += 1 }
        if !isAtEnd, characters[index] == delimiter { index += 1 }
        word(text, style: .code)
    }

    /// Directives are shown as dimmed source; their arguments are consumed, never followed.
    private mutating func shownDirective(_ name: String) {
        var shown = "\\" + name
        var groups = 0
        var target: String?
        while groups < 3 {
            let saved = index
            if let option = optionalArgument() { shown += "[" + option + "]"; continue }
            skipSpaces()
            if !isAtEnd, characters[index] == "{" {
                let group = rawGroup()
                shown += "{" + group + "}"
                if target == nil { target = group }
                groups += 1
            } else if name == "def" || name == "let", !isAtEnd, characters[index] == "\\", groups == 0 {
                // `\def\name{...}`: the macro name, then its body.
                index += 1
                if let (macro, end) = commandName(at: index) { index = end; shown += "\\" + macro }
                groups += 1
            } else { index = saved; break }
        }
        // Pictures and other files the directive points at are shown and counted, never loaded.
        switch name {
        case "includegraphics":
            if let kind = OmittedResourceKind.image(destination: target ?? "") { builder.noteOmitted(kind) }
        case "input", "include":
            builder.noteOmitted(.linkedFile)
        default: break
        }
        // At the top level a directive is a line of its own; inside text it keeps its place.
        if depth == 0, lists.isEmpty { startLine() }
        flushSpace()
        builder.append(shown, style: .dimmed)
        if depth == 0, lists.isEmpty { startLine() } else { pendingSpace = true }
    }

    // MARK: Headings, title

    private mutating func heading(_ name: String) {
        if !isAtEnd, characters[index] == "*" { index += 1 }
        _ = optionalArgument()
        endParagraph()
        let start = builder.length
        skipSpaces()
        if !isAtEnd, characters[index] == "{" {
            index += 1
            group()
        }
        let level = levels[name] ?? 1
        let titleText = builder.text(from: start)
        builder.decorate(.heading(level), from: start)
        builder.addHeading(level: level, title: titleText, range: NSRange(location: start, length: builder.length - start))
        endParagraph()
    }

    private mutating func makeTitle() {
        endParagraph()
        if let title, !title.isEmpty {
            let start = builder.length
            builder.append(title)
            builder.decorate(.heading(1), from: start)
            builder.decorate(.centered, from: start)
            builder.ensureBlockSeparation()
        }
        for text in [author, date] {
            guard let text, !text.isEmpty else { continue }
            let start = builder.length
            builder.append(text)
            builder.decorate(.centered, from: start)
            builder.ensureBlockSeparation()
        }
    }

    private mutating func footnote() {
        _ = optionalArgument()
        let text = MarkupLaTeXText.plain(rawGroup())
        if let number = footnotes.add(text: text) {
            word(MarkupFootnotes.superscript(number), style: .footnoteMark)
        } else {
            word(" (" + text + ")")
        }
    }

    // MARK: Lists

    private mutating func item() {
        startLine()
        let level = lists.count - 1
        let current = level >= 0 ? lists[level].kind : .bullet
        let itemDepth = max(level, 0)
        var label = ""
        if let option = optionalArgument() { label = MarkupLaTeXText.plain(option) }
        let start = builder.length
        var marker: String
        switch current {
        case .bullet: marker = ["\u{2022}", "\u{25E6}", "\u{25AA}"][min(itemDepth, 2)]
        case .numbered:
            lists[level].counter += 1
            marker = "\(lists[level].counter)."
        case .description: marker = ""
        }
        if current == .description {
            if !label.isEmpty { builder.append(label, style: .definitionTerm); builder.append(" ") }
            openItem = OpenItem(start: start, depth: itemDepth, markerLength: 2)
        } else {
            if !label.isEmpty { marker = label }
            builder.append(marker + " ")
            openItem = OpenItem(start: start, depth: itemDepth, markerLength: marker.count + 1)
        }
        pendingSpace = false
        skipSpaces()
    }

    // MARK: Environments

    private mutating func beginEnvironment(_ name: String) {
        guard depth < Self.maximumDepth else { return }
        switch name {
        case "itemize", "enumerate", "description":
            endParagraphKeepingItem()
            let kind: ListContext.Kind = name == "itemize" ? .bullet : name == "enumerate" ? .numbered : .description
            lists.append(ListContext(kind: kind))
            nested(name)
            lists.removeLast()
            closeItemLine()
            if lists.isEmpty { endParagraph() }
        case _ where Self.verbatimEnvironments.contains(name): verbatimBlock(name)
        case _ where Self.mathEnvironments.contains(name):
            let tex = rawEnvironment(name)
            displayMath(tex)
        case _ where Self.quoteEnvironments.contains(name):
            endParagraph()
            let start = builder.length
            nested(name)
            endParagraph()
            builder.decorate(.quote, from: start)
            builder.decorate(.indent(1), from: start)
        case "center":
            endParagraph()
            let start = builder.length
            nested(name)
            endParagraph()
            builder.decorate(.centered, from: start)
        case "tabular", "tabular*", "tabularx", "longtable", "array": tabular(name)
        case "comment": dimmedBlock(name)
        case "document":
            // The body starts here; text before it was handled as the preamble.
            break
        default:
            // Unknown environments (theorem, proof, figure, table, abstract, minipage ...) are transparent.
            if name == "minipage" || name.hasPrefix("tabular") { _ = rawGroup() }
            _ = optionalArgument()
            if ["figure", "table", "figure*", "table*", "abstract"].contains(name) { endParagraph() }
            nested(name)
            if ["figure", "table", "figure*", "table*", "abstract"].contains(name) { endParagraph() }
        }
    }

    /// Reads an environment's body as ordinary content, up to its `\end`.
    private mutating func nested(_ name: String) {
        depth += 1
        groupStyles.append([])
        sequence(endEnvironment: name, closeBrace: false)
        for declared in groupStyles.removeLast() { builder.decorate(declared.style, from: declared.start) }
        depth -= 1
    }

    /// A list nested in an item starts on its own line without a blank line.
    private mutating func endParagraphKeepingItem() {
        if lists.isEmpty { endParagraph() } else { startLine() }
    }

    /// The raw text up to `\end{name}`, which is consumed. Unterminated environments run to the end of input.
    private mutating func rawEnvironment(_ name: String) -> String {
        let terminator = Array("\\end{" + name + "}")
        var raw = ""
        while !isAtEnd {
            if characters[index] == "\\", index + terminator.count <= characters.count,
               Array(characters[index..<(index + terminator.count)]) == terminator {
                index += terminator.count
                return raw
            }
            if raw.utf16.count > Self.maximumRawEnvironmentUnits { break }
            raw.append(characters[index])
            index += 1
        }
        return raw
    }

    private mutating func verbatimBlock(_ name: String) {
        // Optional `[options]` and (for minted) a `{language}` argument precede the body.
        _ = optionalArgument()
        if name == "minted" { _ = rawGroup() }
        var body = rawEnvironment(name)
        if body.hasPrefix("\n") { body.removeFirst() }
        if body.hasPrefix("\r\n") { body.removeFirst(2) }
        endParagraph()
        var lines = MarkupLines.split(body)
        if lines.last == "" { lines.removeLast() }
        for line in lines {
            builder.ensureLineStart()
            let start = builder.length
            builder.append(line)
            if !line.isEmpty { builder.decorate(.codeBlock, from: start) }
            builder.newline()
        }
        endParagraph()
    }

    private mutating func dimmedBlock(_ name: String) {
        let body = rawEnvironment(name)
        endParagraph()
        for line in MarkupLines.split(body) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            builder.ensureLineStart()
            builder.append(line, style: .dimmed)
            builder.newline()
        }
        endParagraph()
    }

    /// Rows of cells, shown as tab-separated text; formatting inside cells is reduced to plain text.
    private mutating func tabular(_ name: String) {
        _ = optionalArgument()
        if name == "tabular*" || name == "tabularx" { _ = rawGroup() }
        _ = rawGroup() // the column specification
        let body = rawEnvironment(name)
        endParagraph()
        var rows: [String] = []
        var current = ""
        var nesting = 0
        var previous: Character = " "
        for character in body {
            if character == "{" { nesting += 1 } else if character == "}" { nesting = max(nesting - 1, 0) }
            if character == "\\", previous == "\\", nesting == 0 {
                current.removeLast()
                rows.append(current)
                current = ""
                previous = " "
                continue
            }
            current.append(character)
            previous = character
        }
        rows.append(current)
        for row in rows.prefix(2_000) {
            let cells = row.split(separator: "&", omittingEmptySubsequences: false).map { cell -> String in
                var text = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                for rule in ["\\hline", "\\toprule", "\\midrule", "\\bottomrule"] { text = text.replacingOccurrences(of: rule, with: "") }
                if text.hasPrefix("\\multicolumn") {
                    var parts = Self.groups(in: String(text.dropFirst("\\multicolumn".count)), count: 3)
                    text = parts.count == 3 ? parts.removeLast() : text
                }
                return MarkupLaTeXText.plain(text)
            }
            if cells.allSatisfy(\.isEmpty) { continue }
            builder.ensureLineStart()
            builder.append(cells.joined(separator: "\t"))
            builder.newline()
        }
        endParagraph()
    }

    /// The first `count` braced groups of `text`, raw.
    private static func groups(in text: String, count: Int) -> [String] {
        var result: [String] = []
        var nesting = 0
        var current = ""
        for character in text {
            if character == "{" {
                nesting += 1
                if nesting == 1 { current = ""; continue }
            } else if character == "}" {
                nesting -= 1
                if nesting == 0 { result.append(current); if result.count == count { break }; continue }
            }
            if nesting >= 1 { current.append(character) }
        }
        return result
    }
}

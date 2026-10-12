import Foundation

/// Parses `classDiagram`: classes with annotations, attributes and methods, the UML relations
/// (inheritance, realization, composition, aggregation, association, dependency, links) with
/// multiplicities and labels, namespaces (flattened) and notes. Styling statements are ignored.
enum MermaidClassParser {
    private static let ignored: Set<String> = ["classDef", "cssClass", "style", "click", "callback", "link", "linkStyle", "accTitle", "title"]

    static func parse(statements: [String], direction: DiagramGraph.Direction) throws -> DiagramGraph {
        var builder = DiagramGraphBuilder(direction: direction)
        var openClass: Int?
        var namespaceDepth = 0
        var skippingBlock = false
        for raw in statements {
            let statement = raw.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty || MermaidLexing.isComment(statement) { continue }
            if skippingBlock {
                if statement.contains("}") { skippingBlock = false }
                continue
            }
            if let current = openClass {
                if statement == "}" { openClass = nil } else { try addMember(statement, to: current, builder: &builder) }
                continue
            }
            let word = MermaidLexing.firstWord(of: statement)
            let rest = String(statement.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            switch word {
            case "direction":
                guard let value = MermaidFlowchartParser.parseDirection(rest) else { throw DiagramFailure.malformed }
                builder.setClusterDirection(value)
            case "namespace":
                guard statement.hasSuffix("{") else { throw DiagramFailure.malformed }
                namespaceDepth += 1
            case "}":
                guard namespaceDepth > 0 else { throw DiagramFailure.malformed }
                namespaceDepth -= 1
            case "accDescr":
                if statement.contains("{"), !statement.contains("}") { skippingBlock = true }
            case _ where ignored.contains(word):
                continue
            case "class":
                openClass = try declareClass(rest, builder: &builder)
            case "note":
                try parseNote(rest, builder: &builder)
            default:
                if statement.hasPrefix("<<") {
                    // `<<interface>> Name` annotates an existing or new class.
                    guard let close = statement.range(of: ">>") else { throw DiagramFailure.malformed }
                    let name = String(statement[close.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let node = try classNode(name, builder: &builder)
                    builder.appendDetail("«" + DiagramText.singleLine(from: String(statement[statement.index(statement.startIndex, offsetBy: 2)..<close.lowerBound])) + "»", to: node)
                } else if try parseRelation(statement, builder: &builder) {
                    continue
                } else if let colon = firstUnquoted(":", in: statement) {
                    // `Name : member`
                    let name = String(statement[..<colon]).trimmingCharacters(in: .whitespaces)
                    let node = try classNode(name, builder: &builder)
                    try addMember(String(statement[statement.index(after: colon)...]), to: node, builder: &builder)
                } else {
                    throw DiagramFailure.malformed
                }
            }
        }
        guard openClass == nil, namespaceDepth == 0 else { throw DiagramFailure.malformed }
        return try builder.finished()
    }

    // MARK: Classes

    /// `Name`, `Name~T~`, `Name["Label"]`, each optionally followed by `{` and `:::css`.
    private static func declareClass(_ text: String, builder: inout DiagramGraphBuilder) throws -> Int? {
        var rest = text
        let opensBlock = rest.hasSuffix("{")
        if opensBlock { rest = String(rest.dropLast()).trimmingCharacters(in: .whitespaces) }
        if let css = rest.range(of: ":::") { rest = String(rest[..<css.lowerBound]).trimmingCharacters(in: .whitespaces) }
        var label: String?
        if rest.hasSuffix("]"), let open = rest.firstIndex(of: "[") {
            label = DiagramText.singleLine(from: MermaidLexing.unquoted(String(rest[rest.index(after: open)..<rest.index(before: rest.endIndex)])))
            rest = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
        }
        guard !rest.isEmpty, !rest.contains(" ") else { throw DiagramFailure.malformed }
        let node = try classNode(rest, label: label, builder: &builder)
        return opensBlock ? node : nil
    }

    /// Finds or creates the record node for a class name; generics in `Name~T~` appear as `Name<T>`.
    private static func classNode(_ rawName: String, label: String? = nil, builder: inout DiagramGraphBuilder) throws -> Int {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("`"), name.hasSuffix("`"), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
        guard !name.isEmpty else { throw DiagramFailure.malformed }
        let identifier = name.firstIndex(of: "~").map { String(name[..<$0]) } ?? name
        guard !identifier.isEmpty else { throw DiagramFailure.malformed }
        let display = label ?? (name.contains("~") ? generics(name) : nil)
        return try builder.node(id: identifier, label: display, shape: .record)
    }

    private static func addMember(_ text: String, to node: Int, builder: inout DiagramGraphBuilder) throws {
        let member = text.trimmingCharacters(in: .whitespaces)
        guard !member.isEmpty else { return }
        if member.hasPrefix("<<"), member.hasSuffix(">>"), member.count > 4 {
            builder.appendDetail("«" + DiagramText.singleLine(from: String(member.dropFirst(2).dropLast(2))) + "»", to: node)
            return
        }
        let display = DiagramText.lines(from: generics(member), stripsTags: false).joined(separator: " ")
        // Methods (anything with a parameter list) go in their own compartment below the attributes.
        builder.appendMember(display, group: member.contains("(") ? 1 : 0, to: node)
    }

    /// Converts Mermaid's `~T~` generic notation to angle brackets, nested pairs included.
    static func generics(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        var depth = 0
        for (index, character) in characters.enumerated() {
            guard character == "~" else { result.append(character); continue }
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let opens = depth == 0 || (next.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false)
            if opens { depth += 1; result.append("<") } else { depth -= 1; result.append(">") }
        }
        return result + String(repeating: ">", count: max(depth, 0))
    }

    // MARK: Relations

    private static func parseRelation(_ statement: String, builder: inout DiagramGraphBuilder) throws -> Bool {
        let colon = firstUnquoted(":", in: statement)
        let left = colon.map { String(statement[..<$0]) } ?? statement
        let tokens = tokenize(left)
        guard let operatorIndex = tokens.firstIndex(where: { parseOperator($0) != nil }), let relation = parseOperator(tokens[operatorIndex]) else {
            return false
        }
        let before = Array(tokens[..<operatorIndex]), after = Array(tokens[(operatorIndex + 1)...])
        guard (1...2).contains(before.count), (1...2).contains(after.count),
              !before[0].hasPrefix("\""), !after[after.count - 1].hasPrefix("\"") else { throw DiagramFailure.malformed }
        let sourceCardinality = before.count == 2 ? MermaidLexing.unquoted(before[1]) : nil
        let targetCardinality = after.count == 2 ? MermaidLexing.unquoted(after[0]) : nil
        guard sourceCardinality == nil || before[1].hasPrefix("\""), targetCardinality == nil || after[0].hasPrefix("\"") else {
            throw DiagramFailure.malformed
        }
        let source = try classNode(before[0], builder: &builder)
        let target = try classNode(after[after.count - 1], builder: &builder)
        let text = colon.map { DiagramText.lines(from: String(statement[statement.index(after: $0)...])).joined(separator: "\n") }
        try builder.addEdge(.init(source: .node(source), target: .node(target), label: text?.isEmpty == false ? text : nil,
                                  line: relation.line, sourceHead: relation.left, targetHead: relation.right,
                                  sourceLabel: sourceCardinality, targetLabel: targetCardinality))
        return true
    }

    private static func parseOperator(_ token: String) -> (left: DiagramArrowhead, line: DiagramLineStyle, right: DiagramArrowhead)? {
        var rest = Substring(token)
        var left = DiagramArrowhead.none
        if rest.hasPrefix("<|") { left = .hollowTriangle; rest = rest.dropFirst(2) }
        else if rest.hasPrefix("*") { left = .filledDiamond; rest = rest.dropFirst() }
        else if rest.hasPrefix("o") { left = .diamond; rest = rest.dropFirst() }
        else if rest.hasPrefix("<") { left = .open; rest = rest.dropFirst() }
        let line: DiagramLineStyle
        if rest.hasPrefix("--") { line = .solid } else if rest.hasPrefix("..") { line = .dashed } else { return nil }
        rest = rest.dropFirst(2)
        var right = DiagramArrowhead.none
        if rest.hasPrefix("|>") { right = .hollowTriangle; rest = rest.dropFirst(2) }
        else if rest.hasPrefix("*") { right = .filledDiamond; rest = rest.dropFirst() }
        else if rest.hasPrefix("o") { right = .diamond; rest = rest.dropFirst() }
        else if rest.hasPrefix(">") { right = .open; rest = rest.dropFirst() }
        guard rest.isEmpty else { return nil }
        return (left, line, right)
    }

    private static func parseNote(_ text: String, builder: inout DiagramGraphBuilder) throws {
        var rest = text
        var target: String?
        if rest.hasPrefix("for ") {
            let afterFor = rest.dropFirst(4).trimmingCharacters(in: .whitespaces)
            guard let quote = afterFor.firstIndex(of: "\"") else { throw DiagramFailure.malformed }
            target = String(afterFor[..<quote]).trimmingCharacters(in: .whitespaces)
            rest = String(afterFor[quote...])
        }
        let body = DiagramText.lines(from: MermaidLexing.unquoted(rest).replacingOccurrences(of: "\\n", with: "\n")).joined(separator: "\n")
        let note = try builder.node(id: "[note]\(builder.graph.nodes.count)", label: body, shape: .note)
        if let target {
            let node = try classNode(target, builder: &builder)
            try builder.addEdge(.init(source: .node(node), target: .node(note), label: nil, line: .dotted, sourceHead: .none, targetHead: .none))
        }
    }

    // MARK: Lexing

    /// Whitespace-separated tokens; a quoted string is one token, quotes included.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle(); current.append(character); continue }
            if character.isWhitespace, !inQuotes {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func firstUnquoted(_ target: Character, in text: String) -> String.Index? {
        var inQuotes = false
        for index in text.indices {
            if text[index] == "\"" { inQuotes.toggle() }
            else if text[index] == target, !inQuotes { return index }
        }
        return nil
    }
}

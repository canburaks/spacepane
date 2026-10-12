import Foundation

/// Parses `erDiagram`: entities with typed attributes (keys and comments) and relationships in
/// crow's foot notation (`||--o{`, `}o..o|` and so on) with labels. Styling statements are ignored.
enum MermaidERParser {
    private static let ignored: Set<String> = ["title", "accTitle", "classDef", "class", "style", "linkStyle"]
    private static let cardinalities: [String: DiagramArrowhead] = [
        "||": .exactlyOne, "|o": .zeroOrOne, "o|": .zeroOrOne, "}|": .oneOrMore, "|{": .oneOrMore, "}o": .zeroOrMore, "o{": .zeroOrMore
    ]

    static func parse(statements: [String], direction: DiagramGraph.Direction) throws -> DiagramGraph {
        var builder = DiagramGraphBuilder(direction: direction)
        var openEntity: Int?
        var skippingBlock = false
        for raw in statements {
            let statement = raw.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty || MermaidLexing.isComment(statement) { continue }
            if skippingBlock {
                if statement.contains("}") { skippingBlock = false }
                continue
            }
            if let entity = openEntity {
                if statement == "}" { openEntity = nil } else { try addAttribute(statement, to: entity, builder: &builder) }
                continue
            }
            let word = MermaidLexing.firstWord(of: statement)
            if word == "direction" {
                guard let value = MermaidFlowchartParser.parseDirection(String(statement.dropFirst(word.count))) else { throw DiagramFailure.malformed }
                builder.setClusterDirection(value)
            } else if word == "accDescr" {
                if statement.contains("{"), !statement.contains("}") { skippingBlock = true }
            } else if ignored.contains(word) {
                continue
            } else if try parseRelationship(statement, builder: &builder) {
                continue
            } else if statement.hasSuffix("{") {
                openEntity = try entityNode(String(statement.dropLast()), builder: &builder)
            } else {
                // A lone name declares an entity without attributes.
                _ = try entityNode(statement, builder: &builder)
            }
        }
        guard openEntity == nil else { throw DiagramFailure.malformed }
        return try builder.finished()
    }

    /// `NAME`, `"Quoted name"` or `NAME["alias"]`.
    private static func entityNode(_ text: String, builder: inout DiagramGraphBuilder) throws -> Int {
        var name = text.trimmingCharacters(in: .whitespaces)
        // An unquoted name is one word; anything else is a statement this subset does not know.
        guard name.hasPrefix("\"") || !name.contains(where: \.isWhitespace) || name.hasSuffix("]") else { throw DiagramFailure.malformed }
        var alias: String?
        if name.hasSuffix("]"), let open = name.firstIndex(of: "[") {
            alias = DiagramText.singleLine(from: MermaidLexing.unquoted(String(name[name.index(after: open)..<name.index(before: name.endIndex)])))
            name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
        }
        name = MermaidLexing.unquoted(name)
        guard !name.isEmpty, !name.contains("{"), !name.contains("}") else { throw DiagramFailure.malformed }
        if alias == nil, !builder.hasNode(name) { alias = DiagramText.singleLine(from: name) }
        return try builder.node(id: name, label: alias, shape: .record)
    }

    /// `type name`, optionally followed by `PK`/`FK`/`UK` keys and a quoted comment.
    private static func addAttribute(_ statement: String, to entity: Int, builder: inout DiagramGraphBuilder) throws {
        var rest = statement
        var comment: String?
        if let quote = rest.firstIndex(of: "\""), rest.hasSuffix("\"") {
            comment = String(rest[rest.index(after: quote)..<rest.index(before: rest.endIndex)])
            rest = String(rest[..<quote]).trimmingCharacters(in: .whitespaces)
        }
        let words = rest.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard words.count >= 2 else { throw DiagramFailure.malformed }
        var row = words[0] + " " + words[1]
        if words.count > 2 { row += "  " + words[2...].joined(separator: " ") }
        if let comment, !comment.isEmpty { row += "  \"" + comment + "\"" }
        builder.appendMember(DiagramText.lines(from: row, stripsTags: false).joined(separator: " "), group: 0, to: entity)
    }

    /// `A ||--o{ B : label`. Returns false when the statement has no relationship operator.
    private static func parseRelationship(_ statement: String, builder: inout DiagramGraphBuilder) throws -> Bool {
        var left = statement
        var label: String?
        if let colon = firstUnquoted(":", in: statement) {
            left = String(statement[..<colon])
            let text = DiagramText.lines(from: MermaidLexing.unquoted(String(statement[statement.index(after: colon)...]))).joined(separator: "\n")
            label = text.isEmpty ? nil : text
        }
        let tokens = tokenize(left)
        guard let index = tokens.firstIndex(where: { parseOperator($0) != nil }), let relation = parseOperator(tokens[index]) else { return false }
        guard index == 1, tokens.count == 3 else { throw DiagramFailure.malformed }
        let source = try entityNode(tokens[0], builder: &builder)
        let target = try entityNode(tokens[2], builder: &builder)
        try builder.addEdge(.init(source: .node(source), target: .node(target), label: label, line: relation.line,
                                  sourceHead: relation.left, targetHead: relation.right))
        return true
    }

    private static func parseOperator(_ token: String) -> (left: DiagramArrowhead, line: DiagramLineStyle, right: DiagramArrowhead)? {
        guard token.count == 6 else { return nil }
        let characters = Array(token)
        let leftToken = String(characters[0..<2]), line = String(characters[2..<4]), rightToken = String(characters[4..<6])
        guard let left = cardinalities[leftToken], let right = cardinalities[rightToken], line == "--" || line == ".." else { return nil }
        return (left, line == "--" ? .solid : .dashed, right)
    }

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

import Foundation

/// Parses the flowchart subset of Mermaid: `flowchart`/`graph` with directions, the documented
/// node shapes, the common link types with labels, chains, `&` groups and subgraphs. Styling
/// statements (`classDef`, `style`, `class`, `click`, `linkStyle`) are recognized and ignored;
/// nothing is executed and no link is followed.
enum MermaidFlowchartParser {
    static func parseDirection(_ text: String) -> DiagramGraph.Direction? {
        switch text.trimmingCharacters(in: .whitespaces) {
        case "", "TD", "TB", "v": .topDown
        case "BT", "^": .bottomUp
        case "LR", ">": .leftRight
        case "RL", "<": .rightLeft
        default: nil
        }
    }

    static func parse(statements: [String], direction: DiagramGraph.Direction) throws -> DiagramGraph {
        var builder = DiagramGraphBuilder(direction: direction)
        var skippingBlock = false
        for raw in statements {
            let statement = raw.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty || MermaidLexing.isComment(statement) { continue }
            if skippingBlock {
                if statement.contains("}") { skippingBlock = false }
                continue
            }
            switch MermaidLexing.firstWord(of: statement) {
            case "subgraph":
                let (id, title) = try subgraphHeading(String(statement.dropFirst("subgraph".count)))
                try builder.openCluster(id: id, title: title)
            case "end" where statement == "end":
                try builder.closeCluster()
            case "direction":
                guard let value = parseDirection(String(statement.dropFirst("direction".count))) else { throw DiagramFailure.malformed }
                builder.setClusterDirection(value)
            case "classDef", "class", "style", "linkStyle", "click", "callback", "call", "accTitle", "title":
                continue
            case "accDescr":
                if statement.contains("{"), !statement.contains("}") { skippingBlock = true }
            default:
                var scanner = FlowchartStatementScanner(statement)
                try scanner.parse(into: &builder)
            }
        }
        return try builder.finished()
    }

    /// `subgraph id [Title]`, `subgraph "Title"` or `subgraph Title`.
    private static func subgraphHeading(_ rest: String) throws -> (id: String, title: String) {
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw DiagramFailure.malformed }
        if let open = text.firstIndex(of: "["), text.hasSuffix("]"), open != text.startIndex || text.count > 2 {
            let id = text[..<open].trimmingCharacters(in: .whitespaces)
            let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            let title = DiagramText.singleLine(from: MermaidLexing.unquoted(inside))
            return (id.isEmpty ? title : id, title)
        }
        let title = DiagramText.singleLine(from: MermaidLexing.unquoted(text))
        return (title, title)
    }
}

/// One node/edge statement: `A --> B & C -->|label| D`.
private struct FlowchartStatementScanner {
    private let characters: [Character]
    private var index = 0

    init(_ statement: String) { characters = Array(statement) }

    private var current: Character? { index < characters.count ? characters[index] : nil }
    private func peek(_ offset: Int) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }
    private mutating func skipSpaces() { while let c = current, c == " " || c == "\t" { index += 1 } }

    mutating func parse(into builder: inout DiagramGraphBuilder) throws {
        var previous = try parseGroup(into: &builder)
        skipSpaces()
        while current != nil {
            let link = try parseLink()
            let next = try parseGroup(into: &builder)
            for source in previous {
                for target in next {
                    try builder.addEdge(.init(source: source, target: target, label: link.label, line: link.line,
                                              sourceHead: link.sourceHead, targetHead: link.targetHead,
                                              isInvisible: link.isInvisible))
                }
            }
            previous = next
            skipSpaces()
        }
    }

    // MARK: Nodes

    private mutating func parseGroup(into builder: inout DiagramGraphBuilder) throws -> [DiagramGraph.Endpoint] {
        var endpoints = [try parseNode(into: &builder)]
        skipSpaces()
        while current == "&" {
            index += 1
            endpoints.append(try parseNode(into: &builder))
            skipSpaces()
        }
        return endpoints
    }

    private mutating func parseNode(into builder: inout DiagramGraphBuilder) throws -> DiagramGraph.Endpoint {
        skipSpaces()
        let id = readIdentifier()
        guard !id.isEmpty else { throw DiagramFailure.malformed }
        var label: String?
        var shape: DiagramNodeShape?
        let afterIdentifier = index
        skipSpaces()
        if let parsed = try parseShape() {
            label = parsed.label
            shape = parsed.shape
        } else {
            index = afterIdentifier
        }
        skipClassSuffix()
        skipAttributeBlock()
        // An identifier naming an existing subgraph (and no node) is an edge to that cluster.
        if label == nil, shape == nil, !builder.hasNode(id), let cluster = builder.clusterIndex(for: id) {
            return .cluster(cluster)
        }
        return .node(try builder.node(id: id, label: label, shape: shape))
    }

    private mutating func readIdentifier() -> String {
        var result = ""
        while let c = current {
            if c.isLetter || c.isNumber || c == "_" { result.append(c); index += 1; continue }
            // A dash continues an identifier unless it starts a link; a dot only between identifier characters.
            if c == "-", let next = peek(1), next != ">", next != "-", next != "." , !result.isEmpty {
                result.append(c); index += 1; continue
            }
            if c == ".", !result.isEmpty, let next = peek(1), next.isLetter || next.isNumber || next == "_" {
                result.append(c); index += 1; continue
            }
            if c == "=", let next = peek(1), next != "=", next != ">", !result.isEmpty {
                result.append(c); index += 1; continue
            }
            break
        }
        return result
    }

    private mutating func skipClassSuffix() {
        guard current == ":", peek(1) == ":", peek(2) == ":" else { return }
        index += 3
        while let c = current, c.isLetter || c.isNumber || c == "_" || c == "-" { index += 1 }
    }

    /// `A@{ shape: rect, label: "x" }`: the attribute block is inert data and is skipped.
    private mutating func skipAttributeBlock() {
        guard current == "@", peek(1) == "{" else { return }
        var depth = 0
        while let c = current {
            index += 1
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1; if depth == 0 { return } }
        }
    }

    private struct Opener {
        let opening: String
        let closings: [String]
        let shape: DiagramNodeShape
    }

    // Longest openers first so `(((` wins over `((` and `(`.
    private static let openers: [Opener] = [
        .init(opening: "(((", closings: [")))"], shape: .doubleCircle),
        .init(opening: "((", closings: ["))"], shape: .circle),
        .init(opening: "([", closings: ["])"], shape: .stadium),
        .init(opening: "(", closings: [")"], shape: .rounded),
        .init(opening: "[[", closings: ["]]"], shape: .subroutine),
        .init(opening: "[(", closings: [")]"], shape: .cylinder),
        .init(opening: "[/", closings: ["/]", "\\]"], shape: .parallelogram),
        .init(opening: "[\\", closings: ["\\]", "/]"], shape: .parallelogram),
        .init(opening: "[", closings: ["]"], shape: .rectangle),
        .init(opening: "{{", closings: ["}}"], shape: .hexagon),
        .init(opening: "{", closings: ["}"], shape: .diamond),
        .init(opening: ">", closings: ["]"], shape: .asymmetric)
    ]

    private mutating func parseShape() throws -> (label: String, shape: DiagramNodeShape)? {
        guard let first = current, "([{>".contains(first) else { return nil }
        for opener in Self.openers where hasPrefix(opener.opening) {
            index += opener.opening.count
            let label = try readLabel(closings: opener.closings)
            return (DiagramText.lines(from: label).joined(separator: "\n"), opener.shape)
        }
        return nil
    }

    /// Reads a node label up to its closing delimiter. An unterminated label (for example one cut
    /// short by concealment) extends to the end of the statement rather than failing the diagram.
    private mutating func readLabel(closings: [String]) throws -> String {
        skipSpaces()
        if current == "\"" {
            index += 1
            var text = ""
            while let c = current, c != "\"" { text.append(c); index += 1 }
            if current == "\"" { index += 1 }
            skipSpaces()
            for closing in closings where hasPrefix(closing) { index += closing.count; return text }
            return text
        }
        var text = ""
        while index < characters.count {
            if closings.contains(where: { hasPrefix($0) }) {
                index += closings.first(where: { hasPrefix($0) })?.count ?? 0
                return text.trimmingCharacters(in: .whitespaces)
            }
            text.append(characters[index])
            index += 1
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private func hasPrefix(_ text: String) -> Bool {
        var cursor = index
        for character in text {
            guard cursor < characters.count, characters[cursor] == character else { return false }
            cursor += 1
        }
        return true
    }

    // MARK: Links

    private struct Link {
        var line: DiagramLineStyle = .solid
        var sourceHead: DiagramArrowhead = .none
        var targetHead: DiagramArrowhead = .none
        var label: String?
        var isInvisible = false
    }

    private mutating func parseLink() throws -> Link {
        skipSpaces()
        var link = Link()
        // Invisible link `~~~`.
        if current == "~" {
            var count = 0
            while current == "~" { index += 1; count += 1 }
            guard count >= 3 else { throw DiagramFailure.malformed }
            link.isInvisible = true
            return link
        }
        // An optional head at the start of a bidirectional link.
        if let first = current, let second = peek(1), second == "-" || second == "=" {
            switch first {
            case "<": link.sourceHead = .arrow; index += 1
            case "o" where hasLinkRun(after: 1): link.sourceHead = .circle; index += 1
            case "x" where hasLinkRun(after: 1): link.sourceHead = .cross; index += 1
            default: break
            }
        }
        guard let lead = current, lead == "-" || lead == "=" else { throw DiagramFailure.malformed }
        if lead == "-", peek(1) == "." {
            try parseDotted(&link)
        } else {
            try parseRun(lead, &link)
        }
        if link.label == nil { link.label = try parsePipeLabel() }
        return link
    }

    /// True when a run of at least two `-` or `=` follows `offset` characters ahead.
    private func hasLinkRun(after offset: Int) -> Bool {
        guard let c = index + offset < characters.count ? characters[index + offset] : nil, c == "-" || c == "=" else { return false }
        return index + offset + 1 < characters.count && characters[index + offset + 1] == c
    }

    private mutating func parseRun(_ symbol: Character, _ link: inout Link) throws {
        var count = 0
        while current == symbol { index += 1; count += 1 }
        guard count >= 2 else { throw DiagramFailure.malformed }
        link.line = symbol == "=" ? .thick : .solid
        // `-- text -->` : the text sits between the opening run and the closing one.
        if count == 2, let next = current, next == " " || next == "\t" {
            let rest = index
            var cursor = rest
            while cursor < characters.count {
                if characters[cursor] == symbol {
                    var run = 0
                    while cursor + run < characters.count, characters[cursor + run] == symbol { run += 1 }
                    let after = cursor + run < characters.count ? characters[cursor + run] : nil
                    let isHead = after == ">" || after == "o" || after == "x"
                    if run >= 3 || (run == 2 && isHead) {
                        let text = String(characters[rest..<cursor]).trimmingCharacters(in: .whitespaces)
                        link.label = DiagramText.lines(from: MermaidLexing.unquoted(text)).joined(separator: "\n")
                        index = cursor + run
                        applyEndHead(&link)
                        return
                    }
                    cursor += run
                } else { cursor += 1 }
            }
            throw DiagramFailure.malformed
        }
        applyEndHead(&link)
        if link.targetHead == .none, count == 2 { throw DiagramFailure.malformed }
    }

    private mutating func applyEndHead(_ link: inout Link) {
        switch current {
        case ">": link.targetHead = .arrow; index += 1
        case "o": link.targetHead = .circle; index += 1
        case "x": link.targetHead = .cross; index += 1
        default: break
        }
    }

    /// Dotted links: `-.->`, `-..->`, `-.-` and `-. text .->`.
    private mutating func parseDotted(_ link: inout Link) throws {
        index += 1 // the leading dash
        var dots = 0
        while current == "." { index += 1; dots += 1 }
        link.line = .dotted
        if let next = current, next == " " || next == "\t" {
            let rest = index
            var cursor = rest
            while cursor + 1 < characters.count {
                if characters[cursor] == ".", characters[cursor + 1] == "-" {
                    let text = String(characters[rest..<cursor]).trimmingCharacters(in: .whitespaces)
                    link.label = DiagramText.lines(from: MermaidLexing.unquoted(text)).joined(separator: "\n")
                    index = cursor + 2
                    applyEndHead(&link)
                    return
                }
                cursor += 1
            }
            throw DiagramFailure.malformed
        }
        guard current == "-" else { throw DiagramFailure.malformed }
        index += 1
        applyEndHead(&link)
    }

    private mutating func parsePipeLabel() throws -> String? {
        let saved = index
        skipSpaces()
        guard current == "|" else { index = saved; return nil }
        index += 1
        var text = ""
        while let c = current, c != "|" { text.append(c); index += 1 }
        if current == "|" { index += 1 }
        return DiagramText.lines(from: MermaidLexing.unquoted(text)).joined(separator: "\n")
    }
}

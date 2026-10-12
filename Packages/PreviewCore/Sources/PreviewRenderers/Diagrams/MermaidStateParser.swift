import Foundation

/// Parses `stateDiagram` and `stateDiagram-v2`: states with descriptions, `[*]` start and end
/// markers, labelled transitions, choice/fork/join pseudo-states, notes and composite states
/// (drawn as frames). Styling and `classDef` statements are ignored.
enum MermaidStateParser {
    private enum PendingEndpoint {
        case node(Int)
        case cluster(String)
    }
    private struct PendingEdge {
        var source: PendingEndpoint
        var target: PendingEndpoint
        var label: String?
        var isNoteLink: Bool
    }

    static func parse(statements: [String], direction: DiagramGraph.Direction) throws -> DiagramGraph {
        var builder = DiagramGraphBuilder(direction: direction, defaultShape: .rounded)
        var pending: [PendingEdge] = []
        // Composite states can be referenced before their block, so their identifiers are known up front.
        let composites = compositeIdentifiers(in: statements)
        var skippingBlock = false
        var noteLines: (target: String, side: String, lines: [String])?

        func endpoint(_ token: String, isSource: Bool) throws -> PendingEndpoint {
            let id = stripClassSuffix(token)
            if id == "[*]" {
                let scope = builder.currentCluster.map(String.init) ?? "root"
                let markerID = (isSource ? "[*]start:" : "[*]end:") + scope
                return .node(try builder.node(id: markerID, label: "", shape: isSource ? .startMarker : .endMarker))
            }
            if composites.contains(id), !builder.hasNode(id) { return .cluster(id) }
            return .node(try builder.node(id: id))
        }
        func addNote(target: String, side: String, text: String) throws {
            let anchor = try endpoint(target, isSource: true)
            let noteNode = try builder.node(id: "[note]\(builder.graph.nodes.count)", label: text, shape: .note)
            pending.append(.init(source: anchor, target: .node(noteNode), label: nil, isNoteLink: true))
        }

        for raw in statements {
            let statement = raw.trimmingCharacters(in: .whitespaces)
            if var collected = noteLines {
                if statement == "end note" {
                    let text = DiagramText.lines(from: collected.lines.joined(separator: "\n")).joined(separator: "\n")
                    try addNote(target: collected.target, side: collected.side, text: text)
                    noteLines = nil
                } else {
                    collected.lines.append(statement)
                    noteLines = collected
                }
                continue
            }
            if statement.isEmpty || MermaidLexing.isComment(statement) { continue }
            if skippingBlock {
                if statement.contains("}") { skippingBlock = false }
                continue
            }
            let word = MermaidLexing.firstWord(of: statement)
            switch word {
            case "classDef", "class", "style", "click", "hide", "scale", "accTitle", "title", "linkStyle":
                continue
            case "accDescr":
                if statement.contains("{"), !statement.contains("}") { skippingBlock = true }
            case "direction":
                guard let value = MermaidFlowchartParser.parseDirection(String(statement.dropFirst("direction".count))) else {
                    throw DiagramFailure.malformed
                }
                builder.setClusterDirection(value)
            case "--", "---", "-----":
                continue // concurrency separators are not drawn
            case "}":
                try builder.closeCluster()
            case "state":
                try parseStateDeclaration(String(statement.dropFirst("state".count)).trimmingCharacters(in: .whitespaces),
                                          builder: &builder)
            case "note", "Note":
                let rest = String(statement.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
                guard let (side, target, text) = noteHeader(rest) else { throw DiagramFailure.malformed }
                if let text { try addNote(target: target, side: side, text: text) }
                else { noteLines = (target, side, []) }
            default:
                if let arrow = statement.range(of: "-->") {
                    try parseTransition(statement, arrow: arrow, endpoint: endpoint, pending: &pending)
                } else if let colon = statement.firstIndex(of: ":"), !statement[colon...].hasPrefix(":::") {
                    // `id : description` adds a description row to the state.
                    let id = stripClassSuffix(String(statement[..<colon]).trimmingCharacters(in: .whitespaces))
                    let text = DiagramText.singleLine(from: String(statement[statement.index(after: colon)...]))
                    guard !id.isEmpty else { throw DiagramFailure.malformed }
                    let node = try builder.node(id: id)
                    if !text.isEmpty { builder.appendDetail(text, to: node) }
                } else if statement.contains("{") || statement.contains("}") {
                    throw DiagramFailure.malformed
                } else {
                    _ = try builder.node(id: stripClassSuffix(statement))
                }
            }
        }
        guard noteLines == nil else { throw DiagramFailure.malformed }
        for edge in pending {
            func resolve(_ endpoint: PendingEndpoint) throws -> DiagramGraph.Endpoint {
                switch endpoint {
                case .node(let index): return .node(index)
                case .cluster(let id):
                    guard let cluster = builder.clusterIndex(for: id) else { throw DiagramFailure.malformed }
                    return .cluster(cluster)
                }
            }
            try builder.addEdge(.init(source: try resolve(edge.source), target: try resolve(edge.target),
                                      label: edge.label, line: edge.isNoteLink ? .dotted : .solid,
                                      sourceHead: .none, targetHead: edge.isNoteLink ? .none : .arrow))
        }
        return try builder.finished()
    }

    private static func compositeIdentifiers(in statements: [String]) -> Set<String> {
        var identifiers: Set<String> = []
        for raw in statements {
            let statement = raw.trimmingCharacters(in: .whitespaces)
            guard statement.hasPrefix("state "), statement.hasSuffix("{") else { continue }
            let (id, _) = declaredIdentifier(String(statement.dropFirst("state ".count).dropLast()).trimmingCharacters(in: .whitespaces))
            identifiers.insert(id)
        }
        return identifiers
    }

    /// `"Long description" as id`, `id`, or `id <<choice>>`: returns the identifier and any description.
    private static func declaredIdentifier(_ text: String) -> (id: String, description: String?) {
        if text.hasPrefix("\""), let close = text.dropFirst().firstIndex(of: "\"") {
            let description = String(text[text.index(after: text.startIndex)..<close])
            let after = text[text.index(after: close)...].trimmingCharacters(in: .whitespaces)
            if after.hasPrefix("as ") {
                return (stripClassSuffix(String(after.dropFirst(3)).trimmingCharacters(in: .whitespaces)), description)
            }
            return (description, description)
        }
        let id = text.split(separator: " ", maxSplits: 1).first.map(String.init) ?? text
        return (stripClassSuffix(id), nil)
    }

    private static func parseStateDeclaration(_ text: String, builder: inout DiagramGraphBuilder) throws {
        var rest = text
        let opensBlock = rest.hasSuffix("{")
        if opensBlock { rest = String(rest.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard !rest.isEmpty else { throw DiagramFailure.malformed }
        var shape: DiagramNodeShape?
        for (marker, value) in [("<<choice>>", DiagramNodeShape.diamond), ("<<fork>>", .bar), ("<<join>>", .bar),
                                ("[[choice]]", .diamond), ("[[fork]]", .bar), ("[[join]]", .bar)] where rest.hasSuffix(marker) {
            shape = value
            rest = String(rest.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        let (id, description) = declaredIdentifier(rest)
        guard !id.isEmpty else { throw DiagramFailure.malformed }
        let title = description.map { DiagramText.singleLine(from: $0) }
        if opensBlock {
            try builder.openCluster(id: id, title: title ?? id)
        } else {
            _ = try builder.node(id: id, label: title.map { $0.isEmpty ? id : $0 }, shape: shape ?? .rounded)
        }
    }

    private static func parseTransition(_ statement: String, arrow: Range<String.Index>,
                                        endpoint: (String, Bool) throws -> PendingEndpoint,
                                        pending: inout [PendingEdge]) throws {
        let left = String(statement[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
        var right = String(statement[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
        var label: String?
        if let colon = firstLabelColon(in: right) {
            let text = DiagramText.lines(from: String(right[right.index(after: colon)...])).joined(separator: "\n")
            label = text.isEmpty ? nil : text
            right = String(right[..<colon]).trimmingCharacters(in: .whitespaces)
        }
        guard !left.isEmpty, !right.isEmpty else { throw DiagramFailure.malformed }
        pending.append(.init(source: try endpoint(left, true), target: try endpoint(right, false),
                             label: label, isNoteLink: false))
    }

    /// The first `:` that is not part of a `:::class` suffix.
    private static func firstLabelColon(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == ":" {
                if text[index...].hasPrefix(":::") { index = text.index(index, offsetBy: 3); continue }
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func stripClassSuffix(_ token: String) -> String {
        guard let range = token.range(of: ":::") else { return token.trimmingCharacters(in: .whitespaces) }
        return String(token[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// `left of X : text` / `right of X` (the text then follows on later lines until `end note`).
    private static func noteHeader(_ rest: String) -> (side: String, target: String, text: String?)? {
        for side in ["left of ", "right of "] where rest.hasPrefix(side) {
            let after = String(rest.dropFirst(side.count))
            if let colon = after.firstIndex(of: ":") {
                let target = after[..<colon].trimmingCharacters(in: .whitespaces)
                let text = DiagramText.lines(from: String(after[after.index(after: colon)...])).joined(separator: "\n")
                return (side.trimmingCharacters(in: .whitespaces), target, text)
            }
            return (side.trimmingCharacters(in: .whitespaces), after.trimmingCharacters(in: .whitespaces), nil)
        }
        return nil
    }
}

import Foundation

/// The semantic content of a parsed diagram, before any layout.
enum DiagramModel: Equatable, Sendable {
    case flowchart(DiagramGraph)
    case state(DiagramGraph)
    case classDiagram(DiagramGraph)
    case entityRelationship(DiagramGraph)
    case sequence(SequenceDiagramModel)
    case pie(PieDiagramModel)
    case drawio(DrawioModel)
}

/// Entry point for Mermaid source: finds the diagram type, strips front matter, directives and
/// comments, and hands the statements to the parser for that type. Unsupported diagram types and
/// syntax errors throw, which leaves the Source view as the only presentation.
enum MermaidParser {
    static func parse(_ source: String) throws -> DiagramModel {
        let lines = try MermaidLexing.lines(source)
        var index = try MermaidLexing.skipFrontMatter(lines)
        var header: String?
        var statements: [String] = []
        while index < lines.count, header == nil {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            index += 1
            if trimmed.isEmpty || MermaidLexing.isComment(trimmed) { continue }
            let pieces = MermaidLexing.statements(in: trimmed)
            header = pieces[0].trimmingCharacters(in: .whitespaces)
            statements.append(contentsOf: pieces.dropFirst())
        }
        guard let header else { throw DiagramFailure.malformed }
        for line in lines[index...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || MermaidLexing.isComment(trimmed) { continue }
            statements.append(contentsOf: MermaidLexing.statements(in: trimmed))
        }
        let keyword = MermaidLexing.firstWord(of: header)
        let remainder = String(header.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
        switch keyword {
        case "graph", "flowchart":
            guard let direction = MermaidFlowchartParser.parseDirection(remainder) else { throw DiagramFailure.malformed }
            return .flowchart(try MermaidFlowchartParser.parse(statements: statements, direction: direction))
        case "stateDiagram", "stateDiagram-v2":
            guard remainder.isEmpty else { throw DiagramFailure.malformed }
            return .state(try MermaidStateParser.parse(statements: statements, direction: .topDown))
        case "classDiagram", "classDiagram-v2":
            guard remainder.isEmpty else { throw DiagramFailure.malformed }
            return .classDiagram(try MermaidClassParser.parse(statements: statements, direction: .topDown))
        case "erDiagram":
            guard remainder.isEmpty else { throw DiagramFailure.malformed }
            return .entityRelationship(try MermaidERParser.parse(statements: statements, direction: .topDown))
        case "sequenceDiagram":
            guard remainder.isEmpty else { throw DiagramFailure.malformed }
            return .sequence(try MermaidSequenceParser.parse(statements: statements))
        case "pie":
            return .pie(try MermaidPieParser.parse(remainder: remainder, statements: statements))
        default:
            throw DiagramFailure.unsupported
        }
    }
}

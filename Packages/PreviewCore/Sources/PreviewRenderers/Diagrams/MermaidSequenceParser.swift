import Foundation

/// A sequence diagram: participants in columns, then messages, notes and frames in time order.
struct SequenceDiagramModel: Equatable, Sendable {
    struct Participant: Equatable, Sendable {
        var id: String
        var label: String
        var isActor: Bool
    }

    struct Message: Equatable, Sendable {
        var source: Int
        var target: Int
        var text: String
        var line: DiagramLineStyle
        var head: DiagramArrowhead
        var startHead: DiagramArrowhead
    }

    enum Placement: Equatable, Sendable {
        case leftOf(Int), rightOf(Int), over(Int, Int)
    }

    struct Note: Equatable, Sendable {
        var placement: Placement
        var text: String
    }

    enum Item: Equatable, Sendable {
        case message(Message)
        case note(Note)
    }

    /// A labelled group of items, `loop`, `alt`, `opt`, `par`, `critical` or `break`. `dividers` are
    /// `else`/`and`/`option` lines with the index of the item that follows each one.
    struct Frame: Equatable, Sendable {
        var keyword: String
        var label: String
        var firstItem: Int
        var endItem: Int
        var dividers: [Divider]
    }

    struct Divider: Equatable, Sendable {
        var label: String
        var beforeItem: Int
    }

    var participants: [Participant] = []
    var items: [Item] = []
    var frames: [Frame] = []
}

/// Parses the sequence-diagram subset: participants and actors with aliases, the documented
/// message arrows, notes, and `loop`/`alt`/`opt`/`par`/`critical`/`break` frames. Activations,
/// numbering, links and menus are recognized and ignored.
enum MermaidSequenceParser {
    private struct OpenFrame {
        var keyword: String
        var label: String
        var firstItem: Int
        var dividers: [SequenceDiagramModel.Divider]
        var isDrawn: Bool
    }

    private struct Arrow {
        let token: String
        let line: DiagramLineStyle
        let head: DiagramArrowhead
        let startHead: DiagramArrowhead
    }

    // Longest tokens first so `-->>` is read before `-->` and `->`.
    private static let arrows: [Arrow] = [
        .init(token: "<<-->>", line: .dashed, head: .arrow, startHead: .arrow),
        .init(token: "<<->>", line: .solid, head: .arrow, startHead: .arrow),
        .init(token: "-->>", line: .dashed, head: .arrow, startHead: .none),
        .init(token: "->>", line: .solid, head: .arrow, startHead: .none),
        .init(token: "--x", line: .dashed, head: .cross, startHead: .none),
        .init(token: "--)", line: .dashed, head: .open, startHead: .none),
        .init(token: "-->", line: .dashed, head: .none, startHead: .none),
        .init(token: "->", line: .solid, head: .none, startHead: .none),
        .init(token: "-x", line: .solid, head: .cross, startHead: .none),
        .init(token: "-)", line: .solid, head: .open, startHead: .none)
    ]

    private static let ignoredKeywords: Set<String> = [
        "autonumber", "activate", "deactivate", "title", "accTitle", "accDescr", "link", "links",
        "properties", "details", "destroy"
    ]
    private static let frameKeywords: Set<String> = ["loop", "alt", "opt", "par", "critical", "break", "rect", "box"]
    private static let dividerKeywords: Set<String> = ["else", "and", "option"]

    static func parse(statements: [String]) throws -> SequenceDiagramModel {
        var model = SequenceDiagramModel()
        var indexes: [String: Int] = [:]
        var stack: [OpenFrame] = []
        var skippingBlock = false

        func participant(_ id: String, label: String? = nil, isActor: Bool? = nil) throws -> Int {
            if let existing = indexes[id] {
                if let label { model.participants[existing].label = label }
                if let isActor { model.participants[existing].isActor = isActor }
                return existing
            }
            guard model.participants.count < DiagramLimits.maximumParticipants else { throw DiagramFailure.tooLarge }
            indexes[id] = model.participants.count
            model.participants.append(.init(id: id, label: label ?? id, isActor: isActor ?? false))
            return model.participants.count - 1
        }
        func addItem(_ item: SequenceDiagramModel.Item) throws {
            guard model.items.count < DiagramLimits.maximumSequenceItems else { throw DiagramFailure.tooLarge }
            model.items.append(item)
        }

        for raw in statements {
            var statement = raw.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty || MermaidLexing.isComment(statement) { continue }
            if skippingBlock {
                if statement.contains("}") { skippingBlock = false }
                continue
            }
            if statement.hasPrefix("create ") {
                statement = String(statement.dropFirst("create ".count)).trimmingCharacters(in: .whitespaces)
            }
            let word = MermaidLexing.firstWord(of: statement)
            let remainder = String(statement.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
            switch word {
            case "participant", "actor":
                let (id, label) = try definition(remainder)
                _ = try participant(id, label: label, isActor: word == "actor")
            case "Note", "note":
                try addItem(.note(try note(remainder, participant: participant)))
            case "end" where remainder.isEmpty:
                guard let closed = stack.popLast() else { throw DiagramFailure.malformed }
                if closed.isDrawn {
                    model.frames.append(.init(keyword: closed.keyword, label: closed.label, firstItem: closed.firstItem,
                                              endItem: model.items.count, dividers: closed.dividers))
                }
            case let keyword where frameKeywords.contains(keyword) && (remainder.isEmpty || statement.dropFirst(keyword.count).first?.isWhitespace == true):
                guard stack.count < DiagramLimits.maximumClusterDepth else { throw DiagramFailure.tooLarge }
                stack.append(.init(keyword: keyword, label: keyword == "rect" || keyword == "box" ? "" : DiagramText.singleLine(from: remainder),
                                   firstItem: model.items.count, dividers: [], isDrawn: keyword != "rect" && keyword != "box"))
            case let keyword where dividerKeywords.contains(keyword) && !stack.isEmpty:
                stack[stack.count - 1].dividers.append(.init(label: DiagramText.singleLine(from: remainder), beforeItem: model.items.count))
            case let keyword where ignoredKeywords.contains(keyword):
                if keyword == "accDescr", statement.contains("{"), !statement.contains("}") { skippingBlock = true }
            default:
                guard let message = try message(statement, participant: participant) else { throw DiagramFailure.malformed }
                try addItem(.message(message))
            }
        }
        guard stack.isEmpty, !model.participants.isEmpty else { throw DiagramFailure.malformed }
        return model
    }

    /// `A`, or `A as Alice`.
    private static func definition(_ text: String) throws -> (id: String, label: String?) {
        guard !text.isEmpty else { throw DiagramFailure.malformed }
        // The `@{ ... }` participant configuration is inert data and is dropped.
        let withoutConfig = text.range(of: "@{").map { String(text[..<$0.lowerBound]) } ?? text
        if let range = withoutConfig.range(of: " as ") {
            let id = withoutConfig[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let label = DiagramText.singleLine(from: String(withoutConfig[range.upperBound...]))
            guard !id.isEmpty else { throw DiagramFailure.malformed }
            return (id, label.isEmpty ? id : label)
        }
        let id = withoutConfig.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { throw DiagramFailure.malformed }
        return (id, nil)
    }

    private static func message(_ statement: String, participant: (String, String?, Bool?) throws -> Int) throws -> SequenceDiagramModel.Message? {
        let colon = statement.firstIndex(of: ":")
        let head = colon.map { String(statement[..<$0]) } ?? statement
        let text = colon.map { DiagramText.lines(from: String(statement[statement.index(after: $0)...])).joined(separator: "\n") } ?? ""
        let characters = Array(head)
        for position in characters.indices {
            // Participant names never contain `-` or `<`, so an arrow can only start at one of them.
            guard characters[position] == "-" || characters[position] == "<",
                  let arrow = arrows.first(where: { matches($0.token, in: characters, at: position) }) else { continue }
            let sourceName = String(characters[..<position]).trimmingCharacters(in: .whitespaces)
            var targetName = String(characters[(position + arrow.token.count)...]).trimmingCharacters(in: .whitespaces)
            // `+` and `-` activate or deactivate the target; they never name it.
            if targetName.hasPrefix("+") || targetName.hasPrefix("-") {
                targetName = String(targetName.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !sourceName.isEmpty, !targetName.isEmpty else { return nil }
            let source = try participant(sourceName, nil, nil)
            let target = try participant(targetName, nil, nil)
            return .init(source: source, target: target, text: text, line: arrow.line, head: arrow.head,
                         startHead: arrow.startHead)
        }
        return nil
    }

    private static func matches(_ token: String, in characters: [Character], at position: Int) -> Bool {
        var cursor = position
        for character in token {
            guard cursor < characters.count, characters[cursor] == character else { return false }
            cursor += 1
        }
        return true
    }

    private static func note(_ remainder: String, participant: (String, String?, Bool?) throws -> Int) throws -> SequenceDiagramModel.Note {
        let colon = remainder.firstIndex(of: ":")
        let head = (colon.map { String(remainder[..<$0]) } ?? remainder).trimmingCharacters(in: .whitespaces)
        let text = colon.map { DiagramText.lines(from: String(remainder[remainder.index(after: $0)...])).joined(separator: "\n") } ?? ""
        for (prefix, build) in [("left of ", 0), ("right of ", 1), ("over ", 2)] where head.hasPrefix(prefix) {
            let names = head.dropFirst(prefix.count).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = names.first, !first.isEmpty, names.count <= 2 else { throw DiagramFailure.malformed }
            let a = try participant(first, nil, nil)
            switch build {
            case 0: return .init(placement: .leftOf(a), text: text)
            case 1: return .init(placement: .rightOf(a), text: text)
            default:
                let b = names.count == 2 ? try participant(names[1], nil, nil) : a
                return .init(placement: .over(a, b), text: text)
            }
        }
        throw DiagramFailure.malformed
    }
}

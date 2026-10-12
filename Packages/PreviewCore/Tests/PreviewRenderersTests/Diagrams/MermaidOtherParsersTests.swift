import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Mermaid sequence, pie and state parsers")
struct MermaidOtherParsersTests {
    private func sequence(_ source: String) throws -> SequenceDiagramModel {
        guard case .sequence(let model) = try MermaidParser.parse(source) else { throw DiagramFailure.malformed }
        return model
    }
    private func pie(_ source: String) throws -> PieDiagramModel {
        guard case .pie(let model) = try MermaidParser.parse(source) else { throw DiagramFailure.malformed }
        return model
    }
    private func state(_ source: String) throws -> DiagramGraph {
        guard case .state(let graph) = try MermaidParser.parse(source) else { throw DiagramFailure.malformed }
        return graph
    }

    // MARK: Sequence

    @Test func participantsActorsAndAliasesKeepDeclarationOrder() throws {
        let model = try sequence("""
        sequenceDiagram
          participant A as Alice
          actor B as Bob the Builder
          participant C
          A->>B: hi
        """)
        #expect(model.participants.map(\.id) == ["A", "B", "C"])
        #expect(model.participants.map(\.label) == ["Alice", "Bob the Builder", "C"])
        #expect(model.participants.map(\.isActor) == [false, true, false])
    }

    @Test(arguments: [
        ("->>", DiagramLineStyle.solid, DiagramArrowhead.arrow), ("-->>", .dashed, .arrow), ("->", .solid, .none),
        ("-->", .dashed, .none), ("-x", .solid, .cross), ("--x", .dashed, .cross), ("-)", .solid, .open), ("--)", .dashed, .open)
    ])
    func messageArrows(token: String, line: DiagramLineStyle, head: DiagramArrowhead) throws {
        let model = try sequence("sequenceDiagram\nAlice\(token)Bob: hello")
        guard case .message(let message) = model.items[0] else { Issue.record("Expected a message"); return }
        #expect(message.line == line)
        #expect(message.head == head)
        #expect(message.text == "hello")
        #expect(model.participants.map(\.id) == ["Alice", "Bob"])
    }

    @Test func bidirectionalArrowsAndActivationMarkersAreRead() throws {
        let model = try sequence("sequenceDiagram\nA<<->>B: both\nA->>+B: start\nB-->>-A: stop\nactivate A\ndeactivate A\nautonumber")
        #expect(model.items.count == 3)
        guard case .message(let first) = model.items[0], case .message(let second) = model.items[1] else { return }
        #expect(first.startHead == .arrow && first.head == .arrow)
        #expect(model.participants.map(\.id) == ["A", "B"])
        #expect(second.text == "start")
    }

    @Test func selfMessagesAndMessagesWithoutTextParse() throws {
        let model = try sequence("sequenceDiagram\nA->>A: think\nA->>B")
        guard case .message(let loop) = model.items[0], case .message(let bare) = model.items[1] else { return }
        #expect(loop.source == loop.target)
        #expect(bare.text.isEmpty)
    }

    @Test func notesCoverLeftRightAndOver() throws {
        let model = try sequence("""
        sequenceDiagram
          participant A
          participant B
          Note left of A: left
          Note right of B: right
          Note over A,B: both
          note over A: one
        """)
        let placements = model.items.compactMap { item -> SequenceDiagramModel.Placement? in
            if case .note(let note) = item { return note.placement } else { return nil }
        }
        #expect(placements == [.leftOf(0), .rightOf(1), .over(0, 1), .over(0, 0)])
    }

    @Test func framesRecordRangesDividersAndNesting() throws {
        let model = try sequence("""
        sequenceDiagram
          A->>B: before
          loop Every minute
            B->>A: ping
            alt ok
              A->>B: yes
            else failed
              A->>B: no
            end
          end
          opt maybe
            A->>B: extra
          end
          rect rgb(200, 200, 255)
            A->>B: highlighted
          end
        """)
        #expect(model.frames.map(\.keyword) == ["alt", "loop", "opt"])
        let alt = model.frames[0]
        #expect(alt.label == "ok" && alt.firstItem == 2 && alt.endItem == 4)
        #expect(alt.dividers == [.init(label: "failed", beforeItem: 3)])
        #expect(model.frames[1].firstItem == 1 && model.frames[1].endItem == 4)
        #expect(model.items.count == 6)
    }

    @Test(arguments: ["sequenceDiagram\nloop x\nA->>B: y", "sequenceDiagram\nend", "sequenceDiagram\nA ->> : x", "sequenceDiagram\nnonsense line",
                      "sequenceDiagram\nNote over : x", "sequenceDiagram\n"])
    func malformedSequencesThrow(source: String) {
        #expect(throws: DiagramFailure.self) { try MermaidParser.parse(source) }
    }

    @Test func participantAndItemLimits() {
        let participants = (0...DiagramLimits.maximumParticipants).map { "participant P\($0)" }.joined(separator: "\n")
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse("sequenceDiagram\n" + participants) }
        let messages = (0...DiagramLimits.maximumSequenceItems).map { _ in "A->>B: m" }.joined(separator: "\n")
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse("sequenceDiagram\n" + messages) }
    }

    // MARK: Pie

    @Test func pieReadsTitleShowDataAndSlices() throws {
        let model = try pie("""
        pie showData title Pets adopted
          "Dogs" : 386
          "Cats" : 85.5
          "Rats" : 15
        """)
        #expect(model.title == "Pets adopted")
        #expect(model.showsData)
        #expect(model.slices.map(\.label) == ["Dogs", "Cats", "Rats"])
        #expect(model.slices.map(\.value) == [386, 85.5, 15])
        #expect(model.slices[1].valueText == "85.5")
    }

    @Test func pieTitleMayBeOnItsOwnLine() throws {
        let model = try pie("pie\n  title Key elements\n  \"A\" : 1\n  \"B\" : 2")
        #expect(model.title == "Key elements")
        #expect(!model.showsData)
    }

    @Test(arguments: ["pie\n\"A\" : -1", "pie\n\"A\" : many", "pie\nA : 1", "pie\n\"A\" 1", "pie\n\"A\" : 0", "pie", "pie extra\n\"A\" : 1", "pie\n\"A\" : ••••\n\"B\" : 0"])
    func malformedPiesThrow(source: String) {
        #expect(throws: DiagramFailure.self) { try MermaidParser.parse(source) }
    }

    @Test func pieSliceLimit() {
        let slices = (0...DiagramLimits.maximumSlices).map { "\"S\($0)\" : 1" }.joined(separator: "\n")
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse("pie\n" + slices) }
    }

    // MARK: State

    @Test func statesStartEndMarkersAndTransitions() throws {
        let graph = try state("""
        stateDiagram-v2
          [*] --> Still
          Still --> Moving : push
          Moving --> Still
          Moving --> [*]
        """)
        let shapes = graph.nodes.map(\.shape)
        #expect(shapes.filter { $0 == .startMarker }.count == 1)
        #expect(shapes.filter { $0 == .endMarker }.count == 1)
        #expect(graph.edges.count == 4)
        #expect(graph.edges[1].label == "push")
        #expect(graph.edges.allSatisfy { $0.targetHead == .arrow })
        #expect(graph.nodes.filter { $0.id == "Still" || $0.id == "Moving" }.allSatisfy { $0.shape == .rounded })
    }

    @Test func descriptionsAliasesAndPseudoStates() throws {
        let graph = try state("""
        stateDiagram
          state "A long description" as long
          long : first line
          state choose <<choice>>
          state fork_state <<fork>>
          long --> choose
          choose --> fork_state
        """)
        let byID = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        #expect(byID["long"]?.label == "A long description")
        #expect(byID["long"]?.details == ["first line"])
        #expect(byID["choose"]?.shape == .diamond)
        #expect(byID["fork_state"]?.shape == .bar)
    }

    @Test func compositeStatesBecomeFramesWithTheirOwnMarkers() throws {
        let graph = try state("""
        stateDiagram-v2
          [*] --> Active
          Active --> Done
          state Active {
            [*] --> Inner
            Inner --> [*]
            direction LR
          }
        """)
        #expect(graph.clusters.map(\.id) == ["Active"])
        #expect(graph.clusters[0].direction == .leftRight)
        // Root and composite each get a start and an end marker.
        #expect(graph.nodes.filter { $0.shape == .startMarker }.count == 2)
        let inner = graph.nodes.first { $0.id == "Inner" }
        #expect(inner?.cluster == 0)
        // The edge to the composite attaches to the frame even though the block comes later.
        #expect(graph.edges.contains { $0.target == .cluster(0) })
        #expect(graph.edges.contains { $0.source == .cluster(0) })
    }

    @Test func notesBecomeDottedLinkedNodes() throws {
        let graph = try state("""
        stateDiagram-v2
          S1 --> S2
          note right of S1 : one line
          note left of S2
            first
            second
          end note
        """)
        let notes = graph.nodes.filter { $0.shape == .note }
        #expect(notes.map(\.label) == ["one line", "first\nsecond"])
        #expect(graph.edges.filter { $0.line == .dotted && $0.targetHead == .none }.count == 2)
    }

    @Test(arguments: ["stateDiagram-v2\nstate A {\nB --> C", "stateDiagram-v2\n}", "stateDiagram-v2\nA -->", "stateDiagram-v2 extra\nA --> B", "stateDiagram-v2\n"])
    func malformedStateDiagramsThrow(source: String) {
        #expect(throws: DiagramFailure.self) { try MermaidParser.parse(source) }
    }
}

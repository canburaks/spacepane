import CoreGraphics
import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Diagram layout")
struct SafeDiagramLayoutTests {
    private let english = DiagramEnvironment(font: .standard, locale: Locale(identifier: "en_US"))

    private func diagram(_ source: String) throws -> SafeDiagram {
        try #require(SafeDiagram.parse(mermaid: source, environment: english))
    }

    private func shapes(_ diagram: SafeDiagram) -> [DiagramShapeItem] {
        diagram.scene.primitives.compactMap { if case .shape(let item) = $0 { item } else { nil } }
    }
    private func paths(_ diagram: SafeDiagram) -> [DiagramPathItem] {
        diagram.scene.primitives.compactMap { if case .path(let item) = $0 { item } else { nil } }
    }
    private func frames(_ diagram: SafeDiagram) -> [DiagramFrameItem] {
        diagram.scene.primitives.compactMap { if case .frame(let item) = $0 { item } else { nil } }
    }
    private func texts(_ diagram: SafeDiagram) -> [DiagramTextItem] {
        diagram.scene.primitives.compactMap { if case .text(let item) = $0 { item } else { nil } }
    }
    private func rect(_ diagram: SafeDiagram, label: String) throws -> CGRect {
        try #require(shapes(diagram).first { $0.lines.joined(separator: " ") == label }).rect
    }

    // MARK: Flowcharts

    @Test(arguments: [
        ("TD", 0), ("TB", 0), ("BT", 1), ("LR", 2), ("RL", 3)
    ])
    func directionsOrderNodesAlongTheirAxis(direction: String, axis: Int) throws {
        let flow = try diagram("flowchart \(direction)\nA --> B --> C")
        let a = try rect(flow, label: "A"), b = try rect(flow, label: "B"), c = try rect(flow, label: "C")
        switch axis {
        case 0: #expect(a.maxY < b.minY && b.maxY < c.minY)
        case 1: #expect(a.minY > b.maxY && b.minY > c.maxY)
        case 2: #expect(a.maxX < b.minX && b.maxX < c.minX)
        default: #expect(a.minX > b.maxX && b.minX > c.maxX)
        }
    }

    @Test func nodesNeverOverlapAndTheSceneContainsEverythingWithItsMargin() throws {
        var lines = ["flowchart TD"]
        for index in 0..<40 { lines.append("N\(index) --> N\((index * 7 + 3) % 40)") }
        for index in 0..<40 { lines.append("N\(index)[Node number \(index) with text] --> N\((index + 1) % 40)") }
        let flow = try diagram(lines.joined(separator: "\n"))
        let items = shapes(flow)
        #expect(items.count == 40)
        for (index, first) in items.enumerated() {
            for second in items[(index + 1)...] { #expect(!first.rect.intersects(second.rect), "\(first.lines) overlaps \(second.lines)") }
        }
        for primitive in flow.scene.primitives {
            let bounds = primitive.bounds.insetBy(dx: 12, dy: 12)
            #expect(bounds.minX >= 24 - 0.001 - 4 && bounds.minY >= 24 - 0.001 - 4)
            #expect(bounds.maxX <= flow.scene.size.width + 0.001 && bounds.maxY <= flow.scene.size.height + 0.001)
        }
    }

    @Test func layoutIsDeterministicAcrossParses() throws {
        let source = "flowchart LR\nA[Start] --> B{Choice}\nB -->|yes| C\nB -->|no| D\nC --> E\nD --> E\nE --> A\nsubgraph g [Group]\nC\nD\nend"
        let first = try diagram(source), second = try diagram(source)
        #expect(first.scene == second.scene)
        #expect(first == second)
        #expect(first.generation != second.generation)
    }

    @Test func edgesCarryHeadsStylesAndLabelChips() throws {
        let flow = try diagram("flowchart TD\nA -->|go| B\nB -.-> C\nC ==> D\nD --- E\nE --x F")
        let items = paths(flow)
        #expect(items.count == 5)
        #expect(items[0].endHead == .arrow && items[0].line == .solid)
        #expect(items[1].line == .dotted && items[2].line == .thick)
        #expect(items[3].endHead == .none)
        #expect(items[4].endHead == .cross)
        #expect(texts(flow).filter(\.hasBackground).map(\.lines) == [["go"]])
        // Every edge starts and ends on the border of its nodes, not at their centers.
        let a = try rect(flow, label: "A"), b = try rect(flow, label: "B")
        let start = try #require(items[0].points.first), end = try #require(items[0].points.last)
        #expect(abs(start.y - a.maxY) < 1 && abs(end.y - b.minY) < 1)
    }

    @Test func invisibleLinksDrawNothingButStillRank() throws {
        let flow = try diagram("flowchart TD\nA ~~~ B")
        #expect(paths(flow).isEmpty)
        #expect(try rect(flow, label: "A").maxY < rect(flow, label: "B").minY)
    }

    @Test func selfLoopsAndParallelEdgesAreDrawnSeparately() throws {
        let flow = try diagram("flowchart TD\nA --> A\nA --> B\nA --> B\nB --> A")
        let items = paths(flow)
        #expect(items.count == 4)
        #expect(items[0].points.count == 4)
        let routes = items.dropFirst().map(\.points)
        #expect(Set(routes.map { $0.map { "\($0.x.rounded()),\($0.y.rounded())" }.joined(separator: ";") }).count == 3)
    }

    @Test func subgraphFramesEncloseTheirNodesAndNestCleanly() throws {
        let flow = try diagram("""
        flowchart TD
          Start --> A
          subgraph outer [Outer group]
            A --> B
            subgraph inner [Inner]
              C --> D
            end
            B --> C
          end
          D --> End
        """)
        let groupFrames = frames(flow)
        #expect(groupFrames.map(\.title) == ["Outer group", "Inner"])
        let outer = groupFrames[0].rect, inner = groupFrames[1].rect
        #expect(outer.contains(inner))
        for label in ["A", "B", "C", "D"] { #expect(outer.contains(try rect(flow, label: label)), "\(label) is inside the outer frame") }
        for label in ["C", "D"] { #expect(inner.contains(try rect(flow, label: label))) }
        for label in ["Start", "End", "A", "B"] { #expect(!inner.intersects(try rect(flow, label: label))) }
        for label in ["Start", "End"] { #expect(!outer.intersects(try rect(flow, label: label))) }
    }

    @Test func edgesCrossingAClusterBoundaryStillReachTheInnerNode() throws {
        let flow = try diagram("flowchart TD\nsubgraph g\nInner\nend\nOutside --> Inner")
        let inner = try rect(flow, label: "Inner")
        let edge = try #require(paths(flow).first)
        let end = try #require(edge.points.last)
        #expect(inner.insetBy(dx: -1, dy: -1).contains(end))
        #expect(abs(end.y - inner.minY) < 1.5)
    }

    @Test func edgesToAClusterEndOnItsFrame() throws {
        let flow = try diagram("flowchart TD\nsubgraph g [Group]\nA\nB\nend\nOutside --> g")
        let frame = try #require(frames(flow).first).rect
        let edge = try #require(paths(flow).first)
        let end = try #require(edge.points.last)
        #expect(abs(end.y - frame.minY) < 1.5)
    }

    @Test func labelsWrapAtTheMaximumWidthAndGrowTheirNodes() throws {
        let long = String(repeating: "word ", count: 40)
        let flow = try diagram("flowchart TD\nA[\"\(long)\"] --> B[Short]")
        let big = try #require(shapes(flow).first)
        #expect(big.lines.count > 1)
        #expect(big.rect.width < 320)
        #expect(big.rect.height > (try rect(flow, label: "Short")).height)
    }

    @Test func accessibilityFactsListNodesAndConnections() throws {
        let flow = try diagram("flowchart TD\nA[Start] -->|ok| B[Finish]\nsubgraph g [Group]\nC\nend")
        #expect(flow.accessibilityNodes.map(\.label) == ["Start", "Finish", "C", "Group"])
        #expect(flow.accessibilityNodes.allSatisfy { $0.role == .node })
        #expect(flow.connections == [DiagramConnection(source: "Start", target: "Finish", label: "ok")])
        #expect(flow.kind == .flowchart)
        #expect(flow.nodeCount == 4 && flow.connectionCount == 1)
    }

    @Test func aTwoThousandNodeChainStaysWithinTheLayoutBudget() throws {
        let source = "flowchart TD\n" + (0..<(DiagramLimits.maximumNodes - 1)).map { "N\($0) --> N\($0 + 1)" }.joined(separator: "\n")
        let started = ContinuousClock.now
        let flow = try #require(SafeDiagram.parse(mermaid: source, environment: english))
        #expect(flow.nodeCount == DiagramLimits.maximumNodes)
        #expect(started.duration(to: .now) < .seconds(20))
        #expect(SafeDiagram.parse(mermaid: source + "\nN1999 --> Extra", environment: english) == nil)
    }

    @Test func aDenseGraphAtTheEdgeLimitIsDeclinedOrLaidOutQuickly() {
        var lines = ["flowchart LR"]
        for index in 0..<DiagramLimits.maximumEdges { lines.append("N\(index % 200) --> N\((index * 31 + 17) % 200)") }
        let started = ContinuousClock.now
        let flow = SafeDiagram.parse(mermaid: lines.joined(separator: "\n"), environment: english)
        #expect(started.duration(to: .now) < .seconds(30))
        if let flow { #expect(flow.nodeCount <= 200) }
    }

    @Test func unsupportedAndMalformedSourceProduceNoDiagram() {
        #expect(SafeDiagram.parse(mermaid: "gantt\n  title x", environment: english) == nil)
        #expect(SafeDiagram.parse(mermaid: "flowchart TD\nA -->", environment: english) == nil)
        #expect(SafeDiagram.parse(mermaid: "", environment: english) == nil)
    }

    @Test func aDifferentFontReMeasuresTheSameDiagram() throws {
        let flow = try diagram("flowchart TD\nA[A reasonably long label] --> B")
        let large = try #require(flow.laidOut(with: DiagramEnvironment(font: DiagramFont(size: 30), locale: Locale(identifier: "en_US"))))
        #expect(large.contentSize.width > flow.contentSize.width)
        #expect(large.model == flow.model)
        #expect(flow.laidOut(with: english) == flow)
    }

    // MARK: Sequence

    @Test func sequenceDiagramsPlaceParticipantsAtBothEndsAndMessagesBetweenLifelines() throws {
        let sequence = try diagram("""
        sequenceDiagram
          participant A as Alice
          participant B as Bob
          A->>B: A reasonably long message label
          B-->>A: reply
          A->>A: think
        """)
        #expect(sequence.kind == .sequence)
        let boxes = shapes(sequence).filter { $0.shape == .rectangle }
        #expect(boxes.count == 4)
        let alice = try #require(boxes.first { $0.lines == ["Alice"] }).rect
        let bob = try #require(boxes.first { $0.lines == ["Bob"] }).rect
        let messages = paths(sequence).filter { $0.line != .dashed || $0.points.count == 2 }.filter { $0.endHead != .none }
        #expect(messages.count == 3)
        let first = messages[0]
        #expect(first.points[0].x == alice.midX && first.points[1].x == bob.midX)
        // The label fits between the two lifelines.
        let label = try #require(texts(sequence).first { $0.lines == ["A reasonably long message label"] })
        #expect(label.rect.minX >= alice.midX - 1 && label.rect.maxX <= bob.midX + 1)
        // Messages run downward in document order, dashed replies stay dashed.
        #expect(messages[0].points[0].y < messages[1].points[0].y && messages[1].points[0].y < messages[2].points[0].y)
        #expect(messages[1].line == .dashed && messages[0].line == .solid)
        #expect(messages[2].points.count == 4)
    }

    @Test func sequenceFramesWrapTheirMessagesAndShowDividers() throws {
        let sequence = try diagram("""
        sequenceDiagram
          A->>B: first
          alt works
            A->>B: yes
          else broken
            A->>B: no
          end
          B->>A: last
        """)
        let frame = try #require(frames(sequence).first)
        #expect(frame.title == "alt [works]")
        let ys = paths(sequence).filter { $0.endHead == .arrow }.map { $0.points[0].y }
        #expect(ys.count == 4)
        #expect(frame.rect.minY < ys[1] && frame.rect.maxY > ys[2])
        #expect(frame.rect.minY > ys[0] && frame.rect.maxY < ys[3])
        #expect(texts(sequence).contains { $0.lines == ["[broken]"] })
    }

    @Test func sequenceNotesAreDrawnBesideAndOverLifelines() throws {
        let sequence = try diagram("sequenceDiagram\nparticipant A\nparticipant B\nNote left of A: left side\nNote right of B: right side\nNote over A,B: spanning both")
        let notes = shapes(sequence).filter { $0.shape == .note }
        #expect(notes.count == 3)
        let boxes = shapes(sequence).filter { $0.shape == .rectangle }
        let a = try #require(boxes.first { $0.lines == ["A"] }).rect, b = try #require(boxes.first { $0.lines == ["B"] }).rect
        #expect(notes[0].rect.maxX < a.midX && notes[1].rect.minX > b.midX)
        #expect(notes[2].rect.minX <= a.midX && notes[2].rect.maxX >= b.midX)
        #expect(notes.allSatisfy { $0.rect.minX >= 0 && $0.rect.maxX <= sequence.scene.size.width })
        #expect(sequence.accessibilityNodes.map(\.role) == [.participant, .participant])
    }

    // MARK: Pie

    @Test func pieSlicesAreOrderedDescendingAndCoverTheCircle() throws {
        let pie = try diagram("pie showData title Pets\n\"Rats\" : 15\n\"Dogs\" : 386\n\"Cats\" : 85")
        let slices = pie.scene.primitives.compactMap { primitive -> DiagramSliceItem? in if case .slice(let item) = primitive { item } else { nil } }
        #expect(slices.count == 3)
        #expect(abs(slices[0].startAngle + Double.pi / 2) < 1e-9)
        for (a, b) in zip(slices, slices.dropFirst()) { #expect(abs(a.endAngle - b.startAngle) < 1e-9) }
        #expect(abs(slices[2].endAngle - 3 * Double.pi / 2) < 1e-9)
        let spans = slices.map { $0.endAngle - $0.startAngle }
        #expect(spans == spans.sorted(by: >))
        #expect(abs(spans[0] / (2 * Double.pi) - 386.0 / 486.0) < 1e-9)
        #expect(pie.scene.primitives.filter { if case .swatch = $0 { true } else { false } }.count == 3)
        let legend = texts(pie).map(\.lines.first).compactMap { $0 }
        #expect(legend.contains("Dogs [386]") && legend.contains("Rats [15]"))
        #expect(texts(pie).contains { $0.isBold && $0.lines == ["Pets"] })
        #expect(legend.contains("79 %") || legend.contains("79%"))
    }

    @Test func piePercentagesFollowTheLocale() throws {
        let source = "pie\n\"A\" : 1\n\"B\" : 3"
        let german = try #require(SafeDiagram.parse(mermaid: source, environment: DiagramEnvironment(locale: Locale(identifier: "de_DE"))))
        let american = try #require(SafeDiagram.parse(mermaid: source, environment: english))
        let germanLabels = texts(german).filter(\.isSmall).compactMap(\.lines.first)
        let americanLabels = texts(american).filter(\.isSmall).compactMap(\.lines.first)
        #expect(americanLabels == ["75%", "25%"])
        #expect(germanLabels != americanLabels)
        #expect(germanLabels.allSatisfy { $0.contains("%") })
        #expect(german.accessibilityNodes.map(\.role) == [.slice, .slice])
    }

    // MARK: State

    @Test func stateDiagramsUseMarkersAndFrames() throws {
        let state = try diagram("""
        stateDiagram-v2
          [*] --> Idle
          Idle --> Busy : start
          state Busy {
            [*] --> Working
            Working --> [*]
          }
          Busy --> [*]
        """)
        #expect(state.kind == .state)
        let markers = shapes(state).filter { $0.shape == .startMarker || $0.shape == .endMarker }
        #expect(markers.count == 4)
        #expect(frames(state).map(\.title) == ["Busy"])
        let frame = try #require(frames(state).first).rect
        let working = try rect(state, label: "Working")
        #expect(frame.contains(working))
        #expect(!frame.intersects(try rect(state, label: "Idle")))
        #expect(state.accessibilityNodes.allSatisfy { $0.role == .state })
        #expect(state.connections.contains(DiagramConnection(source: "Idle", target: "Busy", label: "start")))
        #expect(state.connections.contains { $0.source == "[*]" })
    }
}

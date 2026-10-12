import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Mermaid flowchart parser")
struct MermaidFlowchartParserTests {
    private func flowchart(_ source: String) throws -> DiagramGraph {
        guard case .flowchart(let graph) = try MermaidParser.parse(source) else {
            Issue.record("Expected a flowchart")
            throw DiagramFailure.malformed
        }
        return graph
    }

    private func labels(_ graph: DiagramGraph) -> [String: String] {
        Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.label) })
    }

    @Test(arguments: [
        ("flowchart TD", DiagramGraph.Direction.topDown), ("graph TB", .topDown), ("graph BT", .bottomUp),
        ("flowchart LR", .leftRight), ("flowchart RL", .rightLeft), ("graph", .topDown)
    ])
    func directions(header: String, expected: DiagramGraph.Direction) throws {
        #expect(try flowchart(header + "\nA --> B").direction == expected)
    }

    @Test func chainsCreateOneEdgePerLink() throws {
        let graph = try flowchart("flowchart TD\nA --> B --> C")
        #expect(graph.nodes.map(\.id) == ["A", "B", "C"])
        #expect(graph.edges.count == 2)
        #expect(graph.edges[0].source == .node(0) && graph.edges[0].target == .node(1))
        #expect(graph.edges[1].source == .node(1) && graph.edges[1].target == .node(2))
    }

    @Test(arguments: [
        ("A[Text]", DiagramNodeShape.rectangle), ("A(Text)", .rounded), ("A((Text))", .circle), ("A{Text}", .diamond),
        ("A[[Text]]", .subroutine), ("A[(Text)]", .cylinder), ("A>Text]", .asymmetric), ("A{{Text}}", .hexagon),
        ("A([Text])", .stadium), ("A(((Text)))", .doubleCircle), ("A[/Text/]", .parallelogram), ("A[\\Text\\]", .parallelogram)
    ])
    func nodeShapes(statement: String, shape: DiagramNodeShape) throws {
        let graph = try flowchart("flowchart TD\n" + statement + " --> Z")
        #expect(graph.nodes[0].shape == shape)
        #expect(graph.nodes[0].label == "Text")
    }

    @Test(arguments: [
        ("A --> B", DiagramLineStyle.solid, DiagramArrowhead.none, DiagramArrowhead.arrow),
        ("A --- B", .solid, .none, .none),
        ("A -.-> B", .dotted, .none, .arrow),
        ("A ==> B", .thick, .none, .arrow),
        ("A --o B", .solid, .none, .circle),
        ("A --x B", .solid, .none, .cross),
        ("A <--> B", .solid, .arrow, .arrow),
        ("A o--o B", .solid, .circle, .circle),
        ("A ---> B", .solid, .none, .arrow),
        ("A -..-> B", .dotted, .none, .arrow),
        ("A === B", .thick, .none, .none),
        ("A-->B", .solid, .none, .arrow)
    ])
    func linkTypes(statement: String, line: DiagramLineStyle, start: DiagramArrowhead, end: DiagramArrowhead) throws {
        let edge = try flowchart("flowchart TD\n" + statement).edges[0]
        #expect(edge.line == line)
        #expect(edge.sourceHead == start)
        #expect(edge.targetHead == end)
    }

    @Test(arguments: [
        "A -->|go| B", "A -- go --> B", "A --> |go| B", "A == go ==> B", "A -. go .-> B", "A -->|\"go\"| B"
    ])
    func linkLabels(statement: String) throws {
        let graph = try flowchart("flowchart LR\n" + statement)
        #expect(graph.edges.count == 1)
        #expect(graph.edges[0].label == "go")
        #expect(graph.nodes.map(\.id) == ["A", "B"])
    }

    @Test func groupsExpandToEveryPair() throws {
        let graph = try flowchart("flowchart TD\nA & B --> C & D")
        #expect(graph.edges.count == 4)
        #expect(Set(graph.nodes.map(\.id)) == ["A", "B", "C", "D"])
    }

    @Test func laterLabelsReplaceEarlierOnesAndBareReferencesKeepThem() throws {
        let graph = try flowchart("flowchart TD\nA[First] --> B\nA --> B\nB[Second]")
        #expect(labels(graph) == ["A": "First", "B": "Second"])
    }

    @Test func quotedLabelsKeepSpecialCharactersAndBreaks() throws {
        let graph = try flowchart("flowchart TD\nA[\"Hello (world) [x]<br/>second #35; line\"] --> B")
        #expect(graph.nodes[0].label == "Hello (world) [x]\nsecond # line")
    }

    @Test func subgraphsBecomeClustersWithMembershipAndTitles() throws {
        let graph = try flowchart("""
        flowchart TB
          subgraph one [First group]
            A --> B
            direction LR
          end
          subgraph two
            C
          end
          B --> C
          one --> D
        """)
        #expect(graph.clusters.map(\.id) == ["one", "two"])
        #expect(graph.clusters[0].title == "First group")
        #expect(graph.clusters[0].direction == .leftRight)
        #expect(graph.clusters[1].title == "two")
        func cluster(of id: String) -> Int? { graph.nodes.first { $0.id == id }?.cluster }
        #expect(cluster(of: "A") == 0 && cluster(of: "B") == 0 && cluster(of: "C") == 1 && cluster(of: "D") == nil)
        // An edge naming a subgraph attaches to the whole cluster.
        #expect(graph.edges.last?.source == .cluster(0))
    }

    @Test func nestedSubgraphsRecordTheirParent() throws {
        let graph = try flowchart("flowchart TD\nsubgraph outer\nsubgraph inner\nA\nend\nend")
        #expect(graph.clusters[1].parent == 0)
        #expect(graph.nodes[0].cluster == 1)
    }

    @Test func styleAndInteractionStatementsAreIgnoredAndNeverRun() throws {
        let graph = try flowchart("""
        %%{init: {"theme": "dark"}}%%
        flowchart TD
          %% a comment
          A:::highlight --> B
          classDef highlight fill:#f9f,stroke:#333
          class A highlight
          style B fill:#bbf
          linkStyle 0 stroke:#ff3
          click A href "https://example.invalid/never-opened" "tip"
          click B callback
          accTitle: A title
        """)
        #expect(graph.nodes.map(\.id) == ["A", "B"])
        #expect(graph.edges.count == 1)
    }

    @Test func semicolonsSeparateStatementsButNotEntityCodesOrQuotedText() throws {
        let graph = try flowchart("graph TD; A-->B; B-->C[\"x; y #59; z\"]")
        #expect(graph.edges.count == 2)
        #expect(graph.nodes[2].label == "x; y ; z")
    }

    @Test func frontMatterIsSkipped() throws {
        let graph = try flowchart("---\ntitle: Example\nconfig:\n  theme: dark\n---\nflowchart TD\nA --> B")
        #expect(graph.nodes.count == 2)
    }

    @Test func invisibleLinksShapeLayoutOnly() throws {
        let graph = try flowchart("flowchart TD\nA ~~~ B")
        #expect(graph.edges[0].isInvisible)
    }

    @Test func aConcealedLabelStillParsesAsAnUnterminatedLabel() throws {
        // Concealment replaces the rest of a secret assignment's line, including the closing bracket.
        let graph = try flowchart("flowchart TD\nA[token: ••••\nA --> B")
        #expect(graph.nodes.first?.label == "token: ••••")
        #expect(graph.edges.count == 1)
    }

    @Test(arguments: ["flowchart TD\nA -->", "flowchart TD\nA -- B", "flowchart TD\nA --> B -->", "flowchart TD\nend", "flowchart TD\nsubgraph x\nA",
                      "flowchart TD\n-->B", "flowchart XX\nA --> B", "flowchart TD\nA @ B", "flowchart TD\n"])
    func malformedSourceThrows(source: String) {
        #expect(throws: DiagramFailure.self) { try MermaidParser.parse(source) }
    }

    @Test(arguments: ["gantt\n title x", "journey\n title x", "mindmap\n root", "C4Context", "timeline\n title t", "gitGraph\n commit", "quadrantChart\n title x"])
    func unsupportedDiagramTypesAreDeclined(source: String) {
        #expect(throws: DiagramFailure.unsupported) { try MermaidParser.parse(source) }
    }

    @Test func nodeAndEdgeLimitsAreEnforced() {
        let nodes = (0...DiagramLimits.maximumNodes).map { "N\($0)" }.joined(separator: "\n")
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse("flowchart TD\n" + nodes) }
        let edges = (0...DiagramLimits.maximumEdges).map { _ in "A --> B" }.joined(separator: "\n")
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse("flowchart TD\n" + edges) }
        let deep = (0...DiagramLimits.maximumClusterDepth).map { "subgraph s\($0)" }.joined(separator: "\n")
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse("flowchart TD\n" + deep) }
        let oversized = "flowchart TD\n" + String(repeating: "A --> B\n", count: 100_000)
        #expect(throws: DiagramFailure.tooLarge) { try MermaidParser.parse(oversized) }
    }

    @Test func labelsAreBoundedInCharactersAndLines() throws {
        let long = String(repeating: "x", count: 5_000)
        let graph = try flowchart("flowchart TD\nA[\"\(long)\"] --> B[\"" + (0..<40).map { "l\($0)" }.joined(separator: "<br/>") + "\"]")
        #expect(graph.nodes[0].label.count <= DiagramLimits.maximumLabelCharacters + 1)
        #expect(graph.nodes[0].label.hasSuffix("…"))
        #expect(graph.nodes[1].label.components(separatedBy: "\n").count <= DiagramLimits.maximumLabelLines + 1)
    }

    @Test func parsingIsLinearForLongSingleLines() throws {
        // A single 200 KB line of dashes must not trigger quadratic scanning.
        let line = "A " + String(repeating: "-", count: 200_000) + "> B"
        let started = ContinuousClock.now
        _ = try? MermaidParser.parse("flowchart TD\n" + line)
        #expect(started.duration(to: .now) < .seconds(5))
    }
}

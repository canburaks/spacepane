import CoreGraphics
import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Mermaid class and entity-relationship diagrams")
struct MermaidClassAndERTests {
    private let english = DiagramEnvironment(font: .standard, locale: Locale(identifier: "en_US"))

    private func classGraph(_ source: String) throws -> DiagramGraph {
        guard case .classDiagram(let graph) = try MermaidParser.parse(source) else { throw DiagramFailure.malformed }
        return graph
    }
    private func erGraph(_ source: String) throws -> DiagramGraph {
        guard case .entityRelationship(let graph) = try MermaidParser.parse(source) else { throw DiagramFailure.malformed }
        return graph
    }
    private func node(_ graph: DiagramGraph, _ id: String) throws -> DiagramGraph.Node {
        try #require(graph.nodes.first { $0.id == id })
    }

    // MARK: Class diagrams

    @Test func classesCollectAnnotationsAttributesAndMethods() throws {
        let graph = try classGraph("""
        classDiagram
          class Animal {
            <<abstract>>
            +String name
            -int age
            +eat(food) bool
            +sleep()$
          }
          class Duck
          Duck : +swim()
          Duck : +int wingspan
        """)
        let animal = try node(graph, "Animal")
        #expect(animal.shape == .record && animal.details == ["«abstract»"])
        #expect(animal.memberGroups == [["+String name", "-int age"], ["+eat(food) bool", "+sleep()$"]])
        let duck = try node(graph, "Duck")
        // Attributes come first, methods in their own compartment, whatever order they were written in.
        #expect(duck.memberGroups == [["+int wingspan"], ["+swim()"]])
    }

    @Test func genericsLabelsAndAnnotationStatementsAreRead() throws {
        let graph = try classGraph("""
        classDiagram
          class Square~Shape~
          class List~List~int~~ {
            +add(T item)
          }
          class Shape["Shape (base)"]
          <<interface>> Shape
          Square : +List~int~ items
        """)
        #expect(try node(graph, "Square").label == "Square<Shape>")
        #expect(try node(graph, "Square").memberGroups == [["+List<int> items"]])
        #expect(try node(graph, "List").label == "List<List<int>>")
        #expect(try node(graph, "List").memberGroups == [[], ["+add(T item)"]])
        #expect(try node(graph, "Shape").label == "Shape (base)")
        #expect(try node(graph, "Shape").details == ["«interface»"])
        #expect(MermaidClassParser.generics("Map~string, List~int~~") == "Map<string, List<int>>")
    }

    @Test(arguments: [
        ("A <|-- B", DiagramArrowhead.hollowTriangle, DiagramLineStyle.solid, DiagramArrowhead.none),
        ("A --|> B", .none, .solid, .hollowTriangle),
        ("A *-- B", .filledDiamond, .solid, .none),
        ("A --* B", .none, .solid, .filledDiamond),
        ("A o-- B", .diamond, .solid, .none),
        ("A --o B", .none, .solid, .diamond),
        ("A --> B", .none, .solid, .open),
        ("A <-- B", .open, .solid, .none),
        ("A -- B", .none, .solid, .none),
        ("A ..> B", .none, .dashed, .open),
        ("A <.. B", .open, .dashed, .none),
        ("A ..|> B", .none, .dashed, .hollowTriangle),
        ("A <|.. B", .hollowTriangle, .dashed, .none),
        ("A .. B", .none, .dashed, .none)
    ])
    func relationOperatorsMapToUMLHeads(statement: String, left: DiagramArrowhead, line: DiagramLineStyle, right: DiagramArrowhead) throws {
        let graph = try classGraph("classDiagram\n" + statement)
        let edge = try #require(graph.edges.first)
        #expect(edge.sourceHead == left && edge.line == line && edge.targetHead == right)
        #expect(graph.nodes.map(\.id) == ["A", "B"])
    }

    @Test func multiplicitiesAndLabelsAttachToTheEdge() throws {
        let graph = try classGraph("classDiagram\nCustomer \"1\" --> \"*\" Ticket : buys\nA \"0..1\" o-- B")
        let first = graph.edges[0]
        #expect(first.sourceLabel == "1" && first.targetLabel == "*" && first.label == "buys")
        #expect(graph.edges[1].sourceLabel == "0..1" && graph.edges[1].targetLabel == nil)
    }

    @Test func namespacesAreFlattenedNotesAreLinkedAndDirectionApplies() throws {
        let graph = try classGraph("""
        classDiagram
          direction LR
          namespace Shapes {
            class Circle
            class Square
          }
          Circle <|-- Square
          note "A floating note"
          note for Circle "About circles\\nsecond line"
        """)
        #expect(graph.direction == .leftRight)
        #expect(graph.nodes.filter { $0.shape == .record }.map(\.id) == ["Circle", "Square"])
        let notes = graph.nodes.filter { $0.shape == .note }
        #expect(notes.map(\.label) == ["A floating note", "About circles\nsecond line"])
        #expect(graph.edges.filter { $0.line == .dotted }.count == 1)
    }

    @Test func ignoredStatementsAndCommentsAreSkipped() throws {
        let graph = try classGraph("classDiagram\n%% comment\nclassDef big fill:#f9f\ncssClass \"A\" big\nstyle A fill:#ccc\nclick A href \"https://example.invalid\"\nclass A:::big")
        #expect(graph.nodes.map(\.id) == ["A"])
    }

    @Test(arguments: ["classDiagram\nclass A {\n+x", "classDiagram\n}", "classDiagram\nA <|--", "classDiagram\nA \"1\" \"2\" --> B", "classDiagram\nnonsense",
                      "classDiagram\nnamespace X {\nclass A", "classDiagram\nclass A B", "classDiagram extra\nclass A", "classDiagram\n"])
    func malformedClassDiagramsThrow(source: String) {
        #expect(throws: DiagramFailure.self) { try MermaidParser.parse(source) }
    }

    @Test func memberRowsAreCapped() throws {
        let members = (0..<(DiagramLimits.maximumRecordMembers + 30)).map { "A : +field\($0)" }.joined(separator: "\n")
        let graph = try classGraph("classDiagram\n" + members)
        let rows = try node(graph, "A").memberGroups.flatMap { $0 }
        #expect(rows.count == DiagramLimits.maximumRecordMembers + 1 && rows.last == "…")
    }

    @Test func classBoxesHaveCompartmentsAndParentsSitAboveChildren() throws {
        let diagram = try #require(SafeDiagram.parse(mermaid: """
        classDiagram
          class Animal {
            +String name
            +eat() bool
          }
          Animal <|-- Duck
          Animal "1" o-- "*" Leg : has
        """, environment: english))
        #expect(diagram.kind == .classDiagram)
        let shapes = diagram.scene.primitives.compactMap { primitive -> DiagramShapeItem? in if case .shape(let item) = primitive { item } else { nil } }
        let animal = try #require(shapes.first { $0.lines.first == "Animal" })
        #expect(animal.shape == .record && animal.compartments == [1, 1, 1])
        #expect(animal.lines == ["Animal", "+String name", "+eat() bool"])
        let duck = try #require(shapes.first { $0.lines == ["Duck"] })
        #expect(duck.compartments == [1] && animal.rect.maxY < duck.rect.minY)
        // A record is as tall as its compartments (lines plus padding), so members never spill out.
        let lineHeight = DiagramTextMeasurer(font: .standard).lineHeight
        #expect(abs(animal.rect.height - (3 * lineHeight + 3 * 8 + 2)) < 0.5)
        let paths = diagram.scene.primitives.compactMap { primitive -> DiagramPathItem? in if case .path(let item) = primitive { item } else { nil } }
        #expect(paths[0].startHead == .hollowTriangle && paths[1].startHead == .diamond)
        let texts = diagram.scene.primitives.compactMap { primitive -> DiagramTextItem? in if case .text(let item) = primitive { item } else { nil } }
        #expect(texts.contains { $0.lines == ["1"] && $0.isSmall } && texts.contains { $0.lines == ["*"] && $0.isSmall })
        #expect(texts.contains { $0.lines == ["has"] && $0.hasBackground })
        #expect(diagram.accessibilityNodes.allSatisfy { $0.role == .classType })
        #expect(diagram.connections.count == 2)
    }

    // MARK: Entity-relationship diagrams

    @Test func entitiesListTheirAttributes() throws {
        let graph = try erGraph("""
        erDiagram
          CUSTOMER {
            string name PK
            string email UK "login address"
            int age
          }
          "Order Line" {
            int quantity
          }
          PRODUCT["Product catalogue"]
        """)
        #expect(try node(graph, "CUSTOMER").memberGroups == [["string name  PK", "string email  UK  \"login address\"", "int age"]])
        #expect(try node(graph, "Order Line").label == "Order Line")
        let product = try node(graph, "PRODUCT")
        #expect(product.label == "Product catalogue" && product.memberGroups.isEmpty)
    }

    @Test(arguments: [
        ("||--||", DiagramArrowhead.exactlyOne, DiagramLineStyle.solid, DiagramArrowhead.exactlyOne),
        ("|o--o|", .zeroOrOne, .solid, .zeroOrOne),
        ("}|--|{", .oneOrMore, .solid, .oneOrMore),
        ("}o--o{", .zeroOrMore, .solid, .zeroOrMore),
        ("||..o{", .exactlyOne, .dashed, .zeroOrMore),
        ("|o..|{", .zeroOrOne, .dashed, .oneOrMore),
        ("}|..||", .oneOrMore, .dashed, .exactlyOne)
    ])
    func cardinalitiesMapToCrowsFootEnds(operatorToken: String, left: DiagramArrowhead, line: DiagramLineStyle, right: DiagramArrowhead) throws {
        let graph = try erGraph("erDiagram\nA \(operatorToken) B : \"has many\"")
        let edge = try #require(graph.edges.first)
        #expect(edge.sourceHead == left && edge.line == line && edge.targetHead == right && edge.label == "has many")
        #expect(graph.nodes.map(\.id) == ["A", "B"])
    }

    @Test(arguments: ["erDiagram\nA ||--o{", "erDiagram\nA ||--o{ B C : x", "erDiagram\nA {\nstring", "erDiagram\nA {\nstring name\n", "erDiagram\nA -- B", "erDiagram\n", "erDiagram extra\nA"])
    func malformedEntityRelationshipDiagramsThrow(source: String) {
        #expect(throws: DiagramFailure.self) { try MermaidParser.parse(source) }
    }

    @Test func entityBoxesAndRelationshipsLayOutWithCrowsFeet() throws {
        let diagram = try #require(SafeDiagram.parse(mermaid: """
        erDiagram
          CUSTOMER ||--o{ ORDER : places
          ORDER ||..|{ LINE_ITEM : contains
          CUSTOMER {
            string name PK
          }
        """, environment: english))
        #expect(diagram.kind == .entityRelationship)
        let shapes = diagram.scene.primitives.compactMap { primitive -> DiagramShapeItem? in if case .shape(let item) = primitive { item } else { nil } }
        #expect(shapes.count == 3 && shapes.allSatisfy { $0.shape == .record })
        let customer = try #require(shapes.first { $0.lines.first == "CUSTOMER" })
        #expect(customer.compartments == [1, 1] && customer.lines == ["CUSTOMER", "string name  PK"])
        for (index, first) in shapes.enumerated() { for second in shapes[(index + 1)...] { #expect(!first.rect.intersects(second.rect)) } }
        let paths = diagram.scene.primitives.compactMap { primitive -> DiagramPathItem? in if case .path(let item) = primitive { item } else { nil } }
        #expect(paths[0].startHead == .exactlyOne && paths[0].endHead == .zeroOrMore && paths[0].line == .solid)
        #expect(paths[1].endHead == .oneOrMore && paths[1].line == .dashed)
        #expect(diagram.accessibilityNodes.allSatisfy { $0.role == .entity })
        #expect(diagram.connections.map(\.label) == ["places", "contains"])
    }

    // MARK: Drawing

    @Test func classAndEntityDiagramsDrawTheirMarkings() throws {
        let sources = [
            "classDiagram\nclass A {\n+int x\n+f()\n}\nA <|-- B\nA *-- C\nA o-- D\nA ..> E\nB ..|> F\nA \"1\" --> \"many\" G",
            "erDiagram\nA ||--o{ B : x\nB }|..|{ C : y\nC |o--o| D : z\nA {\nint id PK\n}"
        ]
        for source in sources {
            let diagram = try #require(SafeDiagram.parse(mermaid: source, environment: english))
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 2_400, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            diagram.draw(in: context, size: CGSize(width: 600, height: 400), palette: .standard(isDark: false))
            let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            let pixels = UnsafeBufferPointer(start: data, count: 600 * 400 * 4)
            let inked = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 200 }.count
            #expect(inked > 1_500, "\(source.prefix(12)) drew \(inked) dark pixels")
        }
    }
}

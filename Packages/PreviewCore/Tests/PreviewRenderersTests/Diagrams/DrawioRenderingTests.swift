import CoreGraphics
import Foundation
import Testing
@testable import PreviewRenderers

@Suite("draw.io rendering")
struct DrawioRenderingTests {
    private let english = DiagramEnvironment(font: .standard, locale: Locale(identifier: "en_US"))

    /// A model with the two standard layer cells followed by `cells`.
    private func page(_ cells: String) -> String {
        "<mxGraphModel><root><mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>\(cells)</root></mxGraphModel>"
    }

    private func vertex(_ id: String, _ value: String, style: String = "", x: Int, y: Int, width: Int = 100, height: Int = 60,
                        parent: String = "1") -> String {
        "<mxCell id=\"\(id)\" value=\"\(value)\" style=\"\(style)\" vertex=\"1\" parent=\"\(parent)\"><mxGeometry x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" as=\"geometry\"/></mxCell>"
    }

    private func edge(_ id: String, source: String, target: String, style: String = "", value: String = "", points: String = "") -> String {
        let inner = points.isEmpty ? "" : "<Array as=\"points\">\(points)</Array>"
        return "<mxCell id=\"\(id)\" value=\"\(value)\" style=\"\(style)\" edge=\"1\" parent=\"1\" source=\"\(source)\" target=\"\(target)\"><mxGeometry relative=\"1\" as=\"geometry\">\(inner)</mxGeometry></mxCell>"
    }

    private func diagram(_ cells: String) throws -> SafeDiagram {
        try #require(SafeDiagram.parse(drawio: page(cells), environment: english))
    }
    private func shapes(_ diagram: SafeDiagram) -> [DiagramShapeItem] {
        diagram.scene.primitives.compactMap { if case .shape(let item) = $0 { item } else { nil } }
    }
    private func paths(_ diagram: SafeDiagram) -> [DiagramPathItem] {
        diagram.scene.primitives.compactMap { if case .path(let item) = $0 { item } else { nil } }
    }
    private func texts(_ diagram: SafeDiagram) -> [DiagramTextItem] {
        diagram.scene.primitives.compactMap { if case .text(let item) = $0 { item } else { nil } }
    }
    private func shape(_ diagram: SafeDiagram, _ label: String) throws -> DiagramShapeItem {
        try #require(shapes(diagram).first { $0.lines.joined(separator: " ") == label })
    }

    @Test func styleWordsSelectTheDrawnShapes() throws {
        let result = try diagram([
            vertex("2", "plain", x: 0, y: 0), vertex("3", "round", style: "rounded=1;whiteSpace=wrap;html=1;", x: 120, y: 0),
            vertex("4", "oval", style: "ellipse;whiteSpace=wrap;", x: 240, y: 0), vertex("5", "diamond", style: "rhombus;", x: 360, y: 0),
            vertex("6", "tri", style: "triangle;", x: 480, y: 0), vertex("7", "db", style: "shape=cylinder3;", x: 600, y: 0),
            vertex("8", "hex", style: "shape=hexagon;", x: 720, y: 0), vertex("9", "para", style: "shape=parallelogram;", x: 840, y: 0),
            vertex("10", "words", style: "text;html=1;strokeColor=none;fillColor=none;", x: 960, y: 0),
            vertex("11", "lane", style: "swimlane;startSize=30;", x: 0, y: 200, width: 200, height: 120),
            vertex("12", "side", style: "swimlane;horizontal=0;startSize=20;", x: 300, y: 200, width: 200, height: 120)
        ].joined())
        func kind(_ label: String) throws -> DiagramNodeShape { try shape(result, label).shape }
        #expect(try kind("plain") == .rectangle && kind("round") == .rounded && kind("oval") == .ellipse)
        #expect(try kind("diamond") == .diamond && kind("tri") == .triangle && kind("db") == .cylinder)
        #expect(try kind("hex") == .hexagon && kind("para") == .parallelogram && kind("words") == .textOnly)
        #expect(try kind("lane") == .swimlane(header: 30, leftHeader: false))
        #expect(try kind("side") == .swimlane(header: 20, leftHeader: true))
        #expect(try shape(result, "words").hasOutline == false)
        #expect(result.kind == .drawio)
    }

    @Test func childGeometryIsOffsetByEveryAncestorContainer() throws {
        let result = try diagram([
            vertex("2", "outer", style: "swimlane;", x: 100, y: 100, width: 400, height: 300),
            vertex("3", "inner", style: "swimlane;", x: 20, y: 50, width: 200, height: 150, parent: "2"),
            vertex("4", "leaf", x: 10, y: 40, width: 60, height: 30, parent: "3"),
            vertex("5", "loose", x: 700, y: 20)
        ].joined())
        let outer = try shape(result, "outer").rect, inner = try shape(result, "inner").rect, leaf = try shape(result, "leaf").rect
        #expect(inner.minX - outer.minX == 20 && inner.minY - outer.minY == 50)
        #expect(leaf.minX - inner.minX == 10 && leaf.minY - inner.minY == 40)
        #expect(leaf.minX - outer.minX == 30 && leaf.minY - outer.minY == 90)
        #expect(leaf.size == CGSize(width: 60, height: 30) && outer.size == CGSize(width: 400, height: 300))
        #expect(try shape(result, "loose").rect.minX - outer.minX == 600)
        // Containers draw before their children (document order).
        let order = shapes(result).map { $0.lines.joined() }
        #expect(order.firstIndex(of: "outer")! < order.firstIndex(of: "inner")! && order.firstIndex(of: "inner")! < order.firstIndex(of: "leaf")!)
    }

    @Test func edgesRunBetweenShapeBordersWithArrowsAndStyles() throws {
        let result = try diagram([
            vertex("2", "A", x: 0, y: 0), vertex("3", "B", x: 300, y: 0),
            edge("4", source: "2", target: "3"),
            edge("5", source: "2", target: "3", style: "endArrow=none;dashed=1;"),
            edge("6", source: "3", target: "2", style: "startArrow=oval;endArrow=open;")
        ].joined())
        let items = paths(result)
        #expect(items.count == 3)
        let a = try shape(result, "A").rect, b = try shape(result, "B").rect
        #expect(items[0].endHead == .arrow && items[0].startHead == .none && items[0].line == .solid)
        #expect(abs(items[0].points[0].x - a.maxX) < 1 && abs(items[0].points.last!.x - b.minX) < 1)
        #expect(items[1].endHead == .none && items[1].line == .dashed)
        #expect(items[2].startHead == .circle && items[2].endHead == .open)
    }

    @Test func waypointsAndFloatingEndsAreUsed() throws {
        let points = "<mxPoint x=\"150\" y=\"200\"/><mxPoint x=\"250\" y=\"200\"/>"
        let floating = "<mxCell id=\"9\" style=\"endArrow=classic;\" edge=\"1\" parent=\"1\"><mxGeometry relative=\"1\" as=\"geometry\"><mxPoint x=\"0\" y=\"400\" as=\"sourcePoint\"/><mxPoint x=\"90\" y=\"460\" as=\"targetPoint\"/></mxGeometry></mxCell>"
        let result = try diagram([vertex("2", "A", x: 0, y: 0), vertex("3", "B", x: 300, y: 0),
                                  edge("4", source: "2", target: "3", points: points), floating].joined())
        let items = paths(result)
        #expect(items[0].points.count == 4)
        #expect(items[0].points[1].y == items[0].points[2].y && items[0].points[2].x - items[0].points[1].x == 100)
        #expect(items[1].points.count == 2)
        #expect(items[1].points[1].x - items[1].points[0].x == 90 && items[1].points[1].y - items[1].points[0].y == 60)
    }

    @Test func orthogonalEdgesWithoutWaypointsBendTwice() throws {
        let result = try diagram([vertex("2", "A", x: 0, y: 0), vertex("3", "B", x: 300, y: 200),
                                  edge("4", source: "2", target: "3", style: "edgeStyle=orthogonalEdgeStyle;")].joined())
        let route = try #require(paths(result).first).points
        #expect(route.count == 4)
        #expect(route[0].y == route[1].y && route[1].x == route[2].x && route[2].y == route[3].y)
    }

    @Test func htmlLabelsBecomePlainTextLines() throws {
        let label = "&lt;b&gt;Hello&lt;/b&gt;&lt;br&gt;World &amp;amp; more&lt;div&gt;third&lt;/div&gt;"
        let result = try diagram(vertex("2", label, style: "html=1;whiteSpace=wrap;", x: 0, y: 0, width: 300))
        let item = try #require(shapes(result).first)
        #expect(item.lines == ["Hello", "World & more", "third"])
        #expect(result.accessibilityNodes.first?.label == "Hello World & more third")
    }

    @Test func wrappedLabelsFitTheirShapeWidth() throws {
        let words = String(repeating: "word ", count: 30)
        let result = try diagram(vertex("2", words, style: "whiteSpace=wrap;", x: 0, y: 0, width: 120, height: 400))
        #expect(try #require(shapes(result).first).lines.count > 3)
    }

    @Test func edgeLabelsAndLabelCellsSitOnTheEdge() throws {
        let labelCell = "<mxCell id=\"7\" value=\"on edge\" style=\"edgeLabel;html=1;\" vertex=\"1\" connectable=\"0\" parent=\"4\"><mxGeometry x=\"0\" y=\"-10\" relative=\"1\" as=\"geometry\"/></mxCell>"
        let result = try diagram([vertex("2", "A", x: 0, y: 0), vertex("3", "B", x: 300, y: 0),
                                  edge("4", source: "2", target: "3", value: "direct"), labelCell].joined())
        let chips = texts(result).filter(\.hasBackground)
        #expect(chips.map(\.lines) == [["direct"], ["on edge"]])
        let route = try #require(paths(result).first).points
        let middle = (route[0].x + route[1].x) / 2
        #expect(abs(chips[0].rect.midX - middle) < 1 && abs(chips[1].rect.midX - middle) < 1)
        #expect(chips[1].rect.midY < chips[0].rect.midY)
        #expect(result.connections == [DiagramConnection(source: "A", target: "B", label: "direct")])
    }

    @Test func hiddenCellsAndLayersAreNotDrawn() throws {
        let hidden = "<mxCell id=\"20\" parent=\"0\" visible=\"0\" value=\"Hidden layer\"/>"
        let result = try diagram([vertex("2", "shown", x: 0, y: 0),
                                  "<mxCell id=\"3\" value=\"gone\" vertex=\"1\" parent=\"1\" visible=\"0\"><mxGeometry x=\"200\" y=\"0\" width=\"50\" height=\"50\" as=\"geometry\"/></mxCell>",
                                  hidden, vertex("21", "on hidden layer", x: 0, y: 100, parent: "20")].joined())
        #expect(shapes(result).map { $0.lines.joined() } == ["shown"])
    }

    @Test func objectWrappersSupplyIdAndLabel() throws {
        let wrapped = "<object label=\"Wrapped label\" id=\"9\" owner=\"synthetic\"><mxCell style=\"rounded=1;\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"0\" y=\"0\" width=\"100\" height=\"40\" as=\"geometry\"/></mxCell></object>"
        let result = try diagram([wrapped, vertex("10", "B", x: 200, y: 0), edge("11", source: "9", target: "10")].joined())
        #expect(try shape(result, "Wrapped label").shape == .rounded)
        #expect(paths(result).count == 1)
    }

    @Test func documentColorsAndImagesAreNeverApplied() throws {
        let style = "fillColor=#FF0000;strokeColor=#00FF00;fontColor=#0000FF;image=https://example.invalid/never-fetched.png;shape=image;"
        let result = try diagram(vertex("2", "styled", style: style, x: 0, y: 0))
        let item = try #require(shapes(result).first)
        #expect(item.fill == .node && item.shape == .rectangle && item.hasOutline)
        #expect(item.lines == ["styled"])
    }

    @Test func noneFillAndStrokeAreHonoured() throws {
        let result = try diagram([vertex("2", "ghost", style: "fillColor=none;", x: 0, y: 0),
                                  vertex("3", "plain text", style: "fillColor=none;strokeColor=none;", x: 200, y: 0)].joined())
        #expect(try shape(result, "ghost").fill == .none)
        #expect(try shape(result, "plain text").shape == .textOnly)
    }

    @Test func hostileCoordinatesAreClampedAndOversizedScenesAreDeclined() throws {
        // A lone shape far away is clamped, so its scene stays bounded.
        let alone = try diagram(vertex("2", "far", x: 900_000_000, y: -900_000_000, width: 500_000_000))
        #expect(alone.contentSize.width.isFinite && alone.contentSize.height.isFinite)
        #expect(alone.contentSize.width <= DiagramLimits.maximumSceneDimension + 48)
        // Two shapes a million points apart exceed the scene limit and are declined.
        let apart = vertex("2", "far", x: 900_000_000, y: 0) + vertex("3", "near", x: 0, y: 0)
        #expect(SafeDiagram.parse(drawio: page(apart), environment: english) == nil)
    }

    @Test(arguments: [
        "", "not xml", "<mxfile></mxfile>", "<mxGraphModel/>", "<mxGraphModel><root/></mxGraphModel>",
        "<mxGraphModel><root><mxCell id=\"0\"/></root></mxGraphModel>",
        "<?xml version=\"1.0\"?><!DOCTYPE mxGraphModel [<!ENTITY xxe SYSTEM \"file:///etc/hosts\">]><mxGraphModel><root><mxCell id=\"0\"/><mxCell id=\"1\" value=\"&xxe;\" vertex=\"1\" parent=\"0\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell></root></mxGraphModel>",
        "<!DOCTYPE lolz [<!ENTITY lol \"lol\"><!ENTITY lol2 \"&lol;&lol;\">]><mxGraphModel><root><mxCell id=\"0\"/></root></mxGraphModel>",
        "<mxGraphModel><root><mxCell id=\"0\"/><mxCell id=\"1\" value=\"&undefined;\" vertex=\"1\" parent=\"0\"/></root></mxGraphModel>"
    ])
    func malformedOrHostileModelsProduceNoDiagram(source: String) {
        #expect(SafeDiagram.parse(drawio: source, environment: english) == nil)
    }

    @Test func tooManyCellsDeclinesTheDiagram() throws {
        let cells = (0..<(DiagramLimits.maximumDrawioCells + 1)).map { vertex("v\($0)", "n", x: $0 % 50 * 120, y: $0 / 50 * 80) }.joined()
        #expect(SafeDiagram.parse(drawio: page(cells), environment: english) == nil)
        let vertices = (0..<(DiagramLimits.maximumNodes + 1)).map { vertex("v\($0)", "n", x: $0 % 50 * 120, y: $0 / 50 * 80) }.joined()
        #expect(SafeDiagram.parse(drawio: page(vertices), environment: english) == nil)
    }

    @Test func parentCyclesAndDeepNestingAreDeclined() throws {
        let cycle = vertex("2", "a", x: 0, y: 0, parent: "3") + vertex("3", "b", x: 0, y: 0, parent: "2")
        #expect(SafeDiagram.parse(drawio: page(cycle), environment: english) == nil)
        func chain(_ length: Int, reversed: Bool) -> String {
            let cells = (2..<(2 + length)).map { vertex("\($0)", "n", x: 1, y: 1, parent: "\($0 - 1)") }
            return (reversed ? cells.reversed() : cells).joined()
        }
        // Parents written before their children (as draw.io does) nest as deep as the file asks.
        let deep = try #require(SafeDiagram.parse(drawio: page(chain(DiagramLimits.maximumDrawioDepth + 20, reversed: false)), environment: english))
        #expect(deep.nodeCount == DiagramLimits.maximumDrawioDepth + 20)
        // A chain listed child-first needs unbounded look-ahead, so the lookup depth limit declines it.
        #expect(SafeDiagram.parse(drawio: page(chain(DiagramLimits.maximumDrawioDepth + 20, reversed: true)), environment: english) == nil)
        #expect(SafeDiagram.parse(drawio: page(chain(10, reversed: true)), environment: english) != nil)
    }

    @Test func accessibilityFactsDescribeLabelledShapes() throws {
        let result = try diagram([vertex("2", "Start", x: 0, y: 0), vertex("3", "", x: 200, y: 0), vertex("4", "End", x: 400, y: 0),
                                  edge("5", source: "2", target: "4")].joined())
        #expect(result.accessibilityNodes.map(\.label) == ["Start", "End"])
        #expect(result.accessibilityNodes.allSatisfy { $0.role == .shape })
        #expect(result.connections == [DiagramConnection(source: "Start", target: "End", label: nil)])
    }
}

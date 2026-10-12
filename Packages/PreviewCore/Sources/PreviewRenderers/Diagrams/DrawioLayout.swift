import CoreGraphics
import Foundation

/// Turns a draw.io page into a scene. Geometry comes from the file (nested parents offset their
/// children); colors never do, so the preview theme controls every color. Shapes the drawing code
/// does not know are drawn as rectangles, and image, link and style-script values are ignored.
enum DrawioLayout {
    private static let margin: CGFloat = 24

    private struct VertexInfo {
        var rect: CGRect
        var shape: DiagramNodeShape
        var style: DrawioStyle
    }

    static func layout(_ model: DrawioModel, environment: DiagramEnvironment) throws -> DiagramLayoutResult {
        let measurer = DiagramTextMeasurer(font: environment.font)
        var indexes: [String: Int] = [:]
        for (index, cell) in model.cells.enumerated() where indexes[cell.id] == nil { indexes[cell.id] = index }
        guard model.cells.count <= DiagramLimits.maximumDrawioCells else { throw DiagramFailure.tooLarge }

        // Visibility and absolute origins follow the parent chain, which is bounded and checked for cycles.
        var visibility: [Int: Bool] = [:]
        func isVisible(_ index: Int, trail: Int = 0) throws -> Bool {
            if let known = visibility[index] { return known }
            guard trail <= DiagramLimits.maximumDrawioDepth else { throw DiagramFailure.malformed }
            var result = model.cells[index].isVisible
            if result, let parent = model.cells[index].parent, let parentIndex = indexes[parent], parentIndex != index {
                result = try isVisible(parentIndex, trail: trail + 1)
            }
            visibility[index] = result
            return result
        }
        var origins: [Int: CGPoint] = [:]
        func origin(ofParent parentID: String?, trail: Int = 0) throws -> CGPoint {
            guard let parentID, let index = indexes[parentID] else { return .zero }
            if let known = origins[index] { return known }
            guard trail <= DiagramLimits.maximumDrawioDepth else { throw DiagramFailure.malformed }
            let cell = model.cells[index]
            var point = try origin(ofParent: cell.parent == cell.id ? nil : cell.parent, trail: trail + 1)
            // Only a vertex container offsets its children; layers and edges carry no offset here.
            if cell.isVertex, let geometry = cell.geometry, !geometry.isRelative {
                point.x += geometry.x
                point.y += geometry.y
            }
            origins[index] = point
            return point
        }

        // Vertices.
        var vertices: [Int: VertexInfo] = [:]
        var vertexCount = 0, edgeCount = 0
        for (index, cell) in model.cells.enumerated() {
            if cell.isEdge { edgeCount += 1 }
            guard cell.isVertex, let geometry = cell.geometry, !geometry.isRelative, try isVisible(index) else { continue }
            vertexCount += 1
            guard vertexCount <= DiagramLimits.maximumNodes else { throw DiagramFailure.tooLarge }
            let base = try origin(ofParent: cell.parent)
            let rect = CGRect(x: base.x + geometry.x, y: base.y + geometry.y,
                              width: min(max(geometry.width, 1), 100_000), height: min(max(geometry.height, 1), 100_000))
            let style = DrawioStyle(cell.style)
            vertices[index] = VertexInfo(rect: rect, shape: shape(for: style, rect: rect), style: style)
        }
        guard edgeCount <= DiagramLimits.maximumEdges else { throw DiagramFailure.tooLarge }

        var primitives: [DiagramPrimitive] = []
        var accessibility: [DiagramAccessibilityNode] = []
        var connections: [DiagramConnection] = []
        var routes: [Int: [CGPoint]] = [:]

        func labelLines(_ cell: DrawioModel.Cell, wrapWidth: CGFloat?) -> [String] {
            let lines = DiagramText.lines(from: cell.value, hashEntities: false)
            guard let wrapWidth, wrapWidth > 20 else { return lines }
            return measurer.wrap(lines, maximumWidth: wrapWidth)
        }
        func labelOf(_ id: String?) -> String? {
            guard let id, let index = indexes[id] else { return nil }
            let text = DiagramText.singleLine(from: model.cells[index].value)
            return text.isEmpty ? nil : text
        }

        // Document order is draw order: containers come before their children, edges where written.
        for (index, cell) in model.cells.enumerated() {
            if cell.isVertex, let info = vertices[index] {
                let style = info.style
                let wraps = style.value("whiteSpace") == "wrap" || style.isOn("html")
                let lines = labelLines(cell, wrapWidth: wraps ? info.rect.width - 14 : nil)
                var fill: DiagramFill = .node
                if style.value("fillColor")?.lowercased() == "none" { fill = .none }
                let alignment: DiagramTextAlignment = style.value("align") == "left" ? .leading : style.value("align") == "right" ? .trailing : .center
                let vertical: DiagramVerticalAlignment = style.value("verticalAlign") == "top" ? .top : style.value("verticalAlign") == "bottom" ? .bottom : .middle
                var shape = info.shape
                var outline = style.value("strokeColor")?.lowercased() != "none"
                if shape != .textOnly, fill == .none, !outline { shape = .textOnly }
                if case .textOnly = shape { outline = false }
                primitives.append(.shape(.init(rect: info.rect, shape: shape, fill: fill, lines: lines, alignment: alignment,
                                               verticalAlignment: vertical, isBold: (Int(style.value("fontStyle") ?? "") ?? 0) & 1 == 1,
                                               isDashed: style.isOn("dashed"), hasOutline: outline)))
                if !lines.isEmpty {
                    accessibility.append(.init(label: lines.joined(separator: " "), role: .shape, rect: info.rect))
                }
            } else if cell.isEdge, try isVisible(index) {
                let style = DrawioStyle(cell.style)
                let geometry = cell.geometry
                let base = try origin(ofParent: cell.parent)
                func absolute(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + base.x, y: point.y + base.y) }
                let sourceInfo = cell.source.flatMap { indexes[$0] }.flatMap { vertices[$0] }
                let targetInfo = cell.target.flatMap { indexes[$0] }.flatMap { vertices[$0] }
                let waypoints = (geometry?.points ?? []).map(absolute)
                var points: [CGPoint]
                let sourceFloat = geometry?.sourcePoint.map(absolute)
                let targetFloat = geometry?.targetPoint.map(absolute)
                if waypoints.isEmpty, let sourceInfo, let targetInfo,
                   style.value("edgeStyle")?.lowercased().contains("elbow") == true || style.value("edgeStyle")?.lowercased().contains("orthogonal") == true {
                    points = elbowRoute(from: sourceInfo, to: targetInfo)
                } else {
                    let sourceCenter = sourceInfo.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
                    let targetCenter = targetInfo.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
                    let towardSource = waypoints.first ?? targetFloat ?? targetCenter ?? .zero
                    let towardTarget = waypoints.last ?? sourceFloat ?? sourceCenter ?? .zero
                    let start = sourceInfo.map { GraphLayout.boundary(of: $0.rect, shape: $0.shape, toward: towardSource) } ?? sourceFloat ?? waypoints.first
                    let end = targetInfo.map { GraphLayout.boundary(of: $0.rect, shape: $0.shape, toward: towardTarget) } ?? targetFloat ?? waypoints.last
                    guard let start, let end else { continue }
                    points = [start] + waypoints + [end]
                }
                routes[index] = points
                primitives.append(.path(.init(points: points, line: style.isOn("dashed") ? .dashed : .solid,
                                              startHead: arrowhead(style.value("startArrow"), defaultHead: .none),
                                              endHead: arrowhead(style.value("endArrow"), defaultHead: .arrow))))
                let lines = labelLines(cell, wrapWidth: 200)
                if !lines.isEmpty { primitives.append(labelChip(lines, at: GraphLayout.midpoint(of: points), measurer: measurer)) }
                if let source = labelOf(cell.source) ?? cell.source, let target = labelOf(cell.target) ?? cell.target {
                    connections.append(.init(source: source, target: target, label: lines.isEmpty ? nil : lines.joined(separator: " ")))
                }
            }
        }

        // Labels that are cells of their own, positioned along their edge by relative geometry.
        for (index, cell) in model.cells.enumerated() where cell.isVertex {
            guard let geometry = cell.geometry, geometry.isRelative, let parent = cell.parent.flatMap({ indexes[$0] }),
                  let route = routes[parent], try isVisible(index) else { continue }
            let lines = labelLines(cell, wrapWidth: 200)
            guard !lines.isEmpty else { continue }
            let fraction = min(max((geometry.x + 1) / 2, 0), 1)
            var anchor = pointAlong(route, fraction: fraction)
            anchor.y += geometry.y
            primitives.append(labelChip(lines, at: anchor, measurer: measurer))
        }

        var bounds = CGRect.null
        for primitive in primitives { bounds = bounds.union(primitive.bounds) }
        guard !bounds.isNull, bounds.width.isFinite, bounds.height.isFinite else { throw DiagramFailure.malformed }
        let shift = CGPoint(x: margin - bounds.minX, y: margin - bounds.minY)
        let size = CGSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        guard size.width <= DiagramLimits.maximumSceneDimension, size.height <= DiagramLimits.maximumSceneDimension else {
            throw DiagramFailure.tooLarge
        }
        let moved = primitives.map { GraphLayout.translated($0, by: shift) }
        let movedAccessibility = accessibility.map { DiagramAccessibilityNode(label: $0.label, role: $0.role, rect: $0.rect.offsetBy(dx: shift.x, dy: shift.y)) }
        return DiagramLayoutResult(scene: DiagramScene(size: size, primitives: moved), nodes: movedAccessibility, connections: connections)
    }

    private static func shape(for style: DrawioStyle, rect: CGRect) -> DiagramNodeShape {
        let declared = style.value("shape")?.lowercased() ?? ""
        func names(_ words: String...) -> Bool { words.contains { declared.contains($0) || style.has($0) } }
        if names("swimlane") {
            let header = min(max(style.double("startSize") ?? 23, 10), (style.isOn("horizontal") || style.value("horizontal") == nil ? rect.height : rect.width) - 2)
            return .swimlane(header: max(header, 10), leftHeader: style.value("horizontal") == "0")
        }
        if names("ellipse", "circle") { return .ellipse }
        if names("rhombus", "diamond") { return .diamond }
        if names("triangle") { return .triangle }
        if names("cylinder") { return .cylinder }
        if names("hexagon") { return .hexagon }
        if names("parallelogram") { return .parallelogram }
        if style.has("text") || declared == "text" { return .textOnly }
        if names("note") { return .note }
        if names("group") { return .textOnly }
        if style.isOn("rounded") { return .rounded }
        return .rectangle
    }

    private static func arrowhead(_ value: String?, defaultHead: DiagramArrowhead) -> DiagramArrowhead {
        guard let value = value?.lowercased() else { return defaultHead }
        if value == "none" { return .none }
        if value.hasPrefix("open") || value.hasPrefix("async") { return .open }
        if value.hasPrefix("oval") { return .circle }
        if value.hasPrefix("diamond") { return .diamond }
        if value == "cross" { return .cross }
        return .arrow
    }

    private static func labelChip(_ lines: [String], at anchor: CGPoint, measurer: DiagramTextMeasurer) -> DiagramPrimitive {
        let size = measurer.size(of: lines)
        return .text(.init(lines: lines, rect: CGRect(x: anchor.x - size.width / 2 - 4, y: anchor.y - size.height / 2 - 2,
                                                       width: size.width + 8, height: size.height + 4), hasBackground: true))
    }

    /// Horizontal-vertical-horizontal (or vertical-horizontal-vertical) elbow between two shapes.
    private static func elbowRoute(from source: VertexInfo, to target: VertexInfo) -> [CGPoint] {
        let a = source.rect, b = target.rect
        let dx = b.midX - a.midX, dy = b.midY - a.midY
        if abs(dx) >= abs(dy) {
            let start = CGPoint(x: dx >= 0 ? a.maxX : a.minX, y: a.midY)
            let end = CGPoint(x: dx >= 0 ? b.minX : b.maxX, y: b.midY)
            let middle = (start.x + end.x) / 2
            return [start, CGPoint(x: middle, y: start.y), CGPoint(x: middle, y: end.y), end]
        }
        let start = CGPoint(x: a.midX, y: dy >= 0 ? a.maxY : a.minY)
        let end = CGPoint(x: b.midX, y: dy >= 0 ? b.minY : b.maxY)
        let middle = (start.y + end.y) / 2
        return [start, CGPoint(x: start.x, y: middle), CGPoint(x: end.x, y: middle), end]
    }

    /// The point at `fraction` of a polyline's length.
    static func pointAlong(_ points: [CGPoint], fraction: CGFloat) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        var lengths: [CGFloat] = []
        for index in 1..<points.count { lengths.append(hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)) }
        var remaining = lengths.reduce(0, +) * fraction
        for (index, length) in lengths.enumerated() {
            if remaining <= length, length > 0 {
                let t = remaining / length
                return CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * t,
                               y: points[index].y + (points[index + 1].y - points[index].y) * t)
            }
            remaining -= length
        }
        return points[points.count - 1]
    }
}

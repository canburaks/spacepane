import CoreGraphics
import Foundation

/// Lays out a `DiagramGraph` as a scene. Subgraphs and composite states are laid out recursively:
/// each cluster is arranged on its own, becomes one box in its parent, and its frame is drawn
/// around the result. Edges are routed at the outermost scope that contains both endpoints and
/// finish at the real endpoint, so a link into a cluster still reaches its inner node.
struct DiagramLayoutResult {
    var scene: DiagramScene
    var nodes: [DiagramAccessibilityNode]
    var connections: [DiagramConnection]
}

final class GraphLayout {
    private enum Child: Hashable {
        case node(Int)
        case cluster(Int)
    }

    private struct ScopeLayout {
        var childRects: [Child: CGRect] = [:]
        var size: CGSize = .zero
        /// Interior route points per owned edge index, in scope coordinates.
        var waypoints: [Int: [CGPoint]] = [:]
    }

    private struct EdgePlan {
        var scope: Int
        var source: Child
        var target: Child
    }

    private static let rootScope = -1
    private static let margin: CGFloat = 24
    private static let clusterPadding: CGFloat = 16
    private static let maximumLabelWidth: CGFloat = 220
    private static let maximumEdgeLabelWidth: CGFloat = 180

    private let graph: DiagramGraph
    private let measurer: DiagramTextMeasurer
    private let nodeRole: DiagramNodeRole
    private var childrenOfScope: [Int: [Child]] = [:]
    private var plans: [Int: EdgePlan] = [:]
    private var scopeLayouts: [Int: ScopeLayout] = [:]
    private var nodeLines: [[String]] = []
    /// Line counts per compartment for record nodes; empty for every other shape.
    private var nodeCompartments: [[Int]] = []
    private var nodeRects: [CGRect] = []
    private var clusterRects: [CGRect] = []
    private var clusterOrigins: [Int: CGPoint] = [:]
    private var scopeOrigins: [Int: CGPoint] = [:]

    init(graph: DiagramGraph, environment: DiagramEnvironment, nodeRole: DiagramNodeRole) {
        self.graph = graph
        self.measurer = DiagramTextMeasurer(font: environment.font)
        self.nodeRole = nodeRole
    }

    static func layout(_ graph: DiagramGraph, environment: DiagramEnvironment, nodeRole: DiagramNodeRole) throws -> DiagramLayoutResult {
        try GraphLayout(graph: graph, environment: environment, nodeRole: nodeRole).run()
    }

    // MARK: Driver

    private func run() throws -> DiagramLayoutResult {
        nodeLines = []
        nodeCompartments = []
        for node in graph.nodes {
            let header = node.label.isEmpty ? [] : node.label.components(separatedBy: "\n")
            if node.shape == .record {
                // A record's compartments wrap independently so each keeps its own line count.
                // Annotations such as «interface» sit above the name in the header compartment.
                var lines = measurer.wrap(node.details + header, maximumWidth: Self.maximumLabelWidth, bold: true)
                var counts = [lines.count]
                for group in node.memberGroups {
                    let wrapped = measurer.wrap(group, maximumWidth: Self.maximumLabelWidth)
                    lines += wrapped
                    counts.append(wrapped.count)
                }
                nodeLines.append(lines)
                nodeCompartments.append(counts)
            } else {
                nodeLines.append(measurer.wrap(header + node.details, maximumWidth: Self.maximumLabelWidth))
                nodeCompartments.append([])
            }
        }
        nodeRects = Array(repeating: .zero, count: graph.nodes.count)
        clusterRects = Array(repeating: .zero, count: graph.clusters.count)
        try buildScopes()
        // Deeper clusters first, so a cluster's size is known when its parent is arranged.
        let order = graph.clusters.indices.sorted { a, b in
            let (depthA, depthB) = (depth(of: a), depth(of: b))
            return depthA != depthB ? depthA > depthB : a < b
        }
        for cluster in order { scopeLayouts[cluster] = try layoutScope(cluster) }
        scopeLayouts[Self.rootScope] = try layoutScope(Self.rootScope)
        place(scope: Self.rootScope, origin: CGPoint(x: Self.margin, y: Self.margin))
        return try compose()
    }

    private func depth(of cluster: Int) -> Int {
        var depth = 0
        var current = graph.clusters[cluster].parent
        while let parent = current { depth += 1; current = graph.clusters[parent].parent }
        return depth
    }

    private func effectiveDirection(of scope: Int) -> DiagramGraph.Direction {
        var current: Int? = scope == Self.rootScope ? nil : scope
        while let cluster = current {
            if let direction = graph.clusters[cluster].direction { return direction }
            current = graph.clusters[cluster].parent
        }
        return graph.direction
    }

    // MARK: Scopes

    private func path(of endpoint: DiagramGraph.Endpoint) -> [Child] {
        var chain: [Child] = []
        var current: Int?
        switch endpoint {
        case .node(let index): current = graph.nodes[index].cluster
        case .cluster(let index): current = graph.clusters[index].parent
        }
        while let cluster = current {
            chain.append(.cluster(cluster))
            current = graph.clusters[cluster].parent
        }
        chain.reverse()
        switch endpoint {
        case .node(let index): chain.append(.node(index))
        case .cluster(let index): chain.append(.cluster(index))
        }
        return chain
    }

    private func buildScopes() throws {
        for index in graph.nodes.indices {
            childrenOfScope[graph.nodes[index].cluster ?? Self.rootScope, default: []].append(.node(index))
        }
        for index in graph.clusters.indices {
            childrenOfScope[graph.clusters[index].parent ?? Self.rootScope, default: []].append(.cluster(index))
        }
        for (index, edge) in graph.edges.enumerated() {
            if edge.source == edge.target {
                // A self loop is drawn beside its node; clusters cannot loop onto themselves.
                if case .node(let node) = edge.source {
                    plans[index] = EdgePlan(scope: graph.nodes[node].cluster ?? Self.rootScope, source: .node(node), target: .node(node))
                }
                continue
            }
            let source = path(of: edge.source), target = path(of: edge.target)
            var shared = 0
            while shared < source.count, shared < target.count, source[shared] == target[shared] { shared += 1 }
            // An edge between a cluster and something inside it has no route.
            guard shared < source.count, shared < target.count else { continue }
            var scope = Self.rootScope
            if shared > 0, case .cluster(let cluster) = source[shared - 1] { scope = cluster }
            plans[index] = EdgePlan(scope: scope, source: source[shared], target: target[shared])
        }
    }

    private func size(of child: Child, direction: DiagramGraph.Direction) -> CGSize {
        switch child {
        case .node(let index): return nodeSize(index, direction: direction)
        case .cluster(let index): return scopeLayouts[index].map { clusterFrameSize(index, content: $0.size) } ?? .zero
        }
    }

    private func clusterTitleHeight(_ cluster: Int) -> CGFloat {
        graph.clusters[cluster].title.isEmpty ? 0 : measurer.lineHeight + 10
    }

    private func clusterFrameSize(_ cluster: Int, content: CGSize) -> CGSize {
        let titleWidth = graph.clusters[cluster].title.isEmpty ? 0 : measurer.width(of: graph.clusters[cluster].title, bold: true) + 24
        return CGSize(width: max(content.width + Self.clusterPadding * 2, titleWidth, 80),
                      height: max(content.height + Self.clusterPadding * 2 + clusterTitleHeight(cluster), 48))
    }

    private func nodeSize(_ index: Int, direction: DiagramGraph.Direction) -> CGSize {
        let node = graph.nodes[index]
        let lines = nodeLines[index]
        let text = measurer.size(of: lines)
        if node.shape == .record {
            let counts = nodeCompartments[index]
            let headerWidth = measurer.size(of: Array(lines.prefix(counts.first ?? 0)), bold: true).width
            // Each compartment has four points of padding above and below its lines.
            return CGSize(width: max(max(text.width, headerWidth) + 24, 72),
                          height: CGFloat(lines.count) * measurer.lineHeight + CGFloat(counts.count) * 8 + 2)
        }
        let line = measurer.lineHeight
        var width = max(text.width + 28, 48)
        var height = max(text.height + 18, line + 16)
        switch node.shape {
        case .circle, .ellipse:
            let diameter = max((text.width * text.width + text.height * text.height).squareRoot() + 16, 44)
            return CGSize(width: diameter, height: diameter)
        case .doubleCircle:
            let diameter = max((text.width * text.width + text.height * text.height).squareRoot() + 28, 52)
            return CGSize(width: diameter, height: diameter)
        case .diamond, .triangle:
            return CGSize(width: max(text.width * 1.8 + 24, 60), height: max(text.height * 1.8 + 16, 48))
        case .startMarker: return CGSize(width: 16, height: 16)
        case .endMarker: return CGSize(width: 22, height: 22)
        case .bar:
            return direction == .leftRight || direction == .rightLeft ? CGSize(width: 8, height: 64) : CGSize(width: 64, height: 8)
        case .subroutine: width += 16
        case .parallelogram: width += 28
        case .hexagon: width += 28
        case .asymmetric: width += 14
        case .cylinder: height += 16
        case .note: width += 8
        case .stadium, .rectangle, .rounded, .swimlane, .textOnly, .record: break
        }
        return CGSize(width: width, height: height)
    }

    private func layoutScope(_ scope: Int) throws -> ScopeLayout {
        let children = childrenOfScope[scope] ?? []
        guard !children.isEmpty else { return ScopeLayout() }
        let direction = effectiveDirection(of: scope)
        let horizontal = direction == .leftRight || direction == .rightLeft
        let sizes = children.map { size(of: $0, direction: direction) }
        var childIndexes: [Child: Int] = [:]
        for (index, child) in children.enumerated() { childIndexes[child] = index }
        var ownedEdges: [Int] = []
        var layeredEdges: [LayeredLayoutInput.Edge] = []
        for index in graph.edges.indices {
            guard let plan = plans[index], plan.scope == scope,
                  let from = childIndexes[plan.source], let to = childIndexes[plan.target] else { continue }
            ownedEdges.append(index)
            layeredEdges.append(.init(from: from, to: to, hasLabel: graph.edges[index].label != nil && !graph.edges[index].isInvisible))
        }
        let input = LayeredLayoutInput(orderSizes: sizes.map { horizontal ? $0.height : $0.width },
                                       rankSizes: sizes.map { horizontal ? $0.width : $0.height },
                                       edges: layeredEdges)
        let output = try LayeredLayout.run(input)
        func point(order: CGFloat, rank: CGFloat) -> CGPoint {
            switch direction {
            case .topDown: CGPoint(x: order, y: rank)
            case .bottomUp: CGPoint(x: order, y: output.rankExtent - rank)
            case .leftRight: CGPoint(x: rank, y: order)
            case .rightLeft: CGPoint(x: output.rankExtent - rank, y: order)
            }
        }
        var layout = ScopeLayout()
        for (index, child) in children.enumerated() {
            let center = point(order: output.orderCenters[index], rank: output.rankCenters[index])
            layout.childRects[child] = CGRect(x: center.x - sizes[index].width / 2, y: center.y - sizes[index].height / 2,
                                              width: sizes[index].width, height: sizes[index].height)
        }
        for (position, edge) in ownedEdges.enumerated() {
            layout.waypoints[edge] = output.waypoints[position].map { point(order: $0.x, rank: $0.y) }
        }
        layout.size = horizontal ? CGSize(width: output.rankExtent, height: output.orderExtent)
                                 : CGSize(width: output.orderExtent, height: output.rankExtent)
        guard layout.size.width <= DiagramLimits.maximumSceneDimension,
              layout.size.height <= DiagramLimits.maximumSceneDimension else { throw DiagramFailure.tooLarge }
        return layout
    }

    /// Assigns absolute rectangles to every node and cluster below `scope`.
    private func place(scope: Int, origin: CGPoint) {
        scopeOrigins[scope] = origin
        guard let layout = scopeLayouts[scope] else { return }
        for (child, rect) in layout.childRects {
            let absolute = rect.offsetBy(dx: origin.x, dy: origin.y)
            switch child {
            case .node(let index): nodeRects[index] = absolute
            case .cluster(let index):
                clusterRects[index] = absolute
                let inner = scopeLayouts[index]?.size ?? .zero
                let contentOrigin = CGPoint(x: absolute.minX + (absolute.width - inner.width) / 2,
                                            y: absolute.minY + Self.clusterPadding + clusterTitleHeight(index))
                place(scope: index, origin: contentOrigin)
            }
        }
    }

    // MARK: Composition

    private func rect(of endpoint: DiagramGraph.Endpoint) -> CGRect {
        switch endpoint {
        case .node(let index): nodeRects[index]
        case .cluster(let index): clusterRects[index]
        }
    }

    private func shape(of endpoint: DiagramGraph.Endpoint) -> DiagramNodeShape? {
        if case .node(let index) = endpoint { return graph.nodes[index].shape }
        return nil
    }

    private func label(of endpoint: DiagramGraph.Endpoint) -> String {
        switch endpoint {
        case .node(let index):
            let node = graph.nodes[index]
            return node.shape == .startMarker || node.shape == .endMarker ? "[*]" : DiagramText.singleLine(from: node.label)
        case .cluster(let index): return graph.clusters[index].title
        }
    }

    private func compose() throws -> DiagramLayoutResult {
        var primitives: [DiagramPrimitive] = []
        // Frames, outermost first, so nested frames draw over their parents.
        for index in graph.clusters.indices.sorted(by: { (depth(of: $0), $0) < (depth(of: $1), $1) }) {
            primitives.append(.frame(.init(rect: clusterRects[index], title: graph.clusters[index].title.isEmpty ? nil : graph.clusters[index].title,
                                           isDashed: false, fill: .frame)))
        }
        var paths: [DiagramPrimitive] = []
        var labels: [DiagramPrimitive] = []
        var connections: [DiagramConnection] = []
        // Parallel edges between the same two endpoints fan out sideways.
        var groups: [Set<DiagramGraph.Endpoint>: [Int]] = [:]
        for (index, edge) in graph.edges.enumerated() where plans[index] != nil && edge.source != edge.target {
            groups[[edge.source, edge.target], default: []].append(index)
        }
        for (index, edge) in graph.edges.enumerated() {
            guard let plan = plans[index] else { continue }
            if !edge.isInvisible {
                connections.append(.init(source: label(of: edge.source), target: label(of: edge.target),
                                         label: edge.label.map { DiagramText.singleLine(from: $0) }))
            }
            guard !edge.isInvisible else { continue }
            let origin = scopeOrigins[plan.scope] ?? .zero
            let waypoints = (scopeLayouts[plan.scope]?.waypoints[index] ?? []).map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
            var points: [CGPoint]
            if edge.source == edge.target {
                points = selfLoop(for: nodeRects[nodeIndex(plan.source)])
            } else {
                var offset = CGPoint.zero
                if let group = groups[[edge.source, edge.target]], group.count > 1, let position = group.firstIndex(of: index) {
                    // A canonical orientation keeps opposite-direction edges from sharing an offset.
                    var a = rect(of: edge.source), b = rect(of: edge.target)
                    if (a.midY, a.midX) > (b.midY, b.midX) { swap(&a, &b) }
                    let dx = b.midX - a.midX, dy = b.midY - a.midY
                    let length = max((dx * dx + dy * dy).squareRoot(), 1)
                    let spread = (CGFloat(position) - CGFloat(group.count - 1) / 2) * 18
                    offset = CGPoint(x: -dy / length * spread, y: dx / length * spread)
                }
                let sourceRect = rect(of: edge.source), targetRect = rect(of: edge.target)
                let shifted = waypoints.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
                let towardSource = shifted.first ?? CGPoint(x: targetRect.midX + offset.x, y: targetRect.midY + offset.y)
                let towardTarget = shifted.last ?? CGPoint(x: sourceRect.midX + offset.x, y: sourceRect.midY + offset.y)
                points = [Self.boundary(of: sourceRect, shape: shape(of: edge.source), toward: towardSource)]
                    + shifted + [Self.boundary(of: targetRect, shape: shape(of: edge.target), toward: towardTarget)]
            }
            paths.append(.path(.init(points: points, line: edge.line, startHead: edge.sourceHead, endHead: edge.targetHead)))
            if points.count >= 2 {
                if let text = edge.sourceLabel, !text.isEmpty { labels.append(endLabel(text, at: points[0], toward: points[1])) }
                if let text = edge.targetLabel, !text.isEmpty { labels.append(endLabel(text, at: points[points.count - 1], toward: points[points.count - 2])) }
            }
            if let text = edge.label, !text.isEmpty {
                let lines = measurer.wrap(text.components(separatedBy: "\n"), maximumWidth: Self.maximumEdgeLabelWidth)
                let size = measurer.size(of: lines)
                let anchor = Self.midpoint(of: points)
                labels.append(.text(.init(lines: lines,
                                          rect: CGRect(x: anchor.x - size.width / 2 - 6, y: anchor.y - size.height / 2 - 2,
                                                       width: size.width + 12, height: size.height + 4),
                                          hasBackground: true)))
            }
        }
        primitives += paths
        for index in graph.nodes.indices {
            let node = graph.nodes[index]
            var item = DiagramShapeItem(rect: nodeRects[index], shape: node.shape, fill: node.shape == .note ? .note : .node,
                                        lines: nodeLines[index])
            item.compartments = nodeCompartments[index]
            primitives.append(.shape(item))
        }
        primitives += labels
        var bounds = CGRect.null
        for primitive in primitives { bounds = bounds.union(primitive.bounds) }
        guard !bounds.isNull else { throw DiagramFailure.malformed }
        // Translate so the content starts at the margin, then size the scene around it.
        let shift = CGPoint(x: Self.margin - bounds.minX, y: Self.margin - bounds.minY)
        let size = CGSize(width: bounds.width + Self.margin * 2, height: bounds.height + Self.margin * 2)
        guard size.width <= DiagramLimits.maximumSceneDimension, size.height <= DiagramLimits.maximumSceneDimension else {
            throw DiagramFailure.tooLarge
        }
        let moved = primitives.map { Self.translated($0, by: shift) }
        var accessibility: [DiagramAccessibilityNode] = []
        for index in graph.nodes.indices where graph.nodes[index].shape != .startMarker && graph.nodes[index].shape != .endMarker && graph.nodes[index].shape != .bar {
            let text = nodeLines[index].joined(separator: " ")
            accessibility.append(.init(label: text.isEmpty ? graph.nodes[index].id : text, role: nodeRole,
                                       rect: nodeRects[index].offsetBy(dx: shift.x, dy: shift.y)))
        }
        for index in graph.clusters.indices where !graph.clusters[index].title.isEmpty {
            accessibility.append(.init(label: graph.clusters[index].title, role: nodeRole,
                                       rect: clusterRects[index].offsetBy(dx: shift.x, dy: shift.y)))
        }
        return DiagramLayoutResult(scene: DiagramScene(size: size, primitives: moved), nodes: accessibility, connections: connections)
    }

    /// Small text (a multiplicity) beside one end of an edge, on the side away from the line.
    private func endLabel(_ text: String, at end: CGPoint, toward next: CGPoint) -> DiagramPrimitive {
        let size = measurer.size(of: [text])
        let length = max(hypot(next.x - end.x, next.y - end.y), 1)
        let ux = (next.x - end.x) / length, uy = (next.y - end.y) / length
        let center = CGPoint(x: end.x + ux * 22 - uy * (size.width / 2 + 8), y: end.y + uy * 22 + ux * (size.height / 2 + 4))
        return .text(.init(lines: [text], rect: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                                       width: size.width, height: size.height), isSmall: true))
    }

    private func nodeIndex(_ child: Child) -> Int {
        if case .node(let index) = child { return index }
        return 0
    }

    // MARK: Geometry

    private func selfLoop(for rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.maxX, y: rect.midY - 8), CGPoint(x: rect.maxX + 30, y: rect.midY - 8),
         CGPoint(x: rect.maxX + 30, y: rect.midY + 8), CGPoint(x: rect.maxX, y: rect.midY + 8)]
    }

    /// Where the ray from a shape's center toward `target` leaves the shape.
    static func boundary(of rect: CGRect, shape: DiagramNodeShape?, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x, dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return CGPoint(x: center.x, y: rect.maxY) }
        let halfWidth = max(rect.width / 2, 0.5), halfHeight = max(rect.height / 2, 0.5)
        let scale: CGFloat
        switch shape {
        case .circle, .doubleCircle, .ellipse, .startMarker, .endMarker:
            scale = 1 / ((dx / halfWidth) * (dx / halfWidth) + (dy / halfHeight) * (dy / halfHeight)).squareRoot()
        case .diamond:
            scale = 1 / (abs(dx) / halfWidth + abs(dy) / halfHeight)
        default:
            let sx = dx == 0 ? CGFloat.greatestFiniteMagnitude : halfWidth / abs(dx)
            let sy = dy == 0 ? CGFloat.greatestFiniteMagnitude : halfHeight / abs(dy)
            scale = min(sx, sy)
        }
        let clamped = min(scale, 1)
        return CGPoint(x: center.x + dx * clamped, y: center.y + dy * clamped)
    }

    /// The point halfway along a polyline's length.
    static func midpoint(of points: [CGPoint]) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for index in 1..<points.count {
            let length = hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            lengths.append(length)
            total += length
        }
        var remaining = total / 2
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

    static func translated(_ primitive: DiagramPrimitive, by shift: CGPoint) -> DiagramPrimitive {
        switch primitive {
        case .frame(var item): item.rect = item.rect.offsetBy(dx: shift.x, dy: shift.y); return .frame(item)
        case .shape(var item): item.rect = item.rect.offsetBy(dx: shift.x, dy: shift.y); return .shape(item)
        case .text(var item): item.rect = item.rect.offsetBy(dx: shift.x, dy: shift.y); return .text(item)
        case .swatch(var item): item.rect = item.rect.offsetBy(dx: shift.x, dy: shift.y); return .swatch(item)
        case .slice(var item): item.center = CGPoint(x: item.center.x + shift.x, y: item.center.y + shift.y); return .slice(item)
        case .path(var item):
            item.points = item.points.map { CGPoint(x: $0.x + shift.x, y: $0.y + shift.y) }
            return .path(item)
        }
    }
}

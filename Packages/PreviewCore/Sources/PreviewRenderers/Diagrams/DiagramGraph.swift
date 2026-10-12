import CoreGraphics
import Foundation

/// A node-and-edge diagram: flowcharts and state diagrams share this model and one layout.
struct DiagramGraph: Equatable, Sendable {
    enum Direction: Equatable, Sendable { case topDown, bottomUp, leftRight, rightLeft }
    enum Endpoint: Equatable, Hashable, Sendable { case node(Int), cluster(Int) }

    struct Node: Equatable, Sendable {
        var id: String
        var label: String
        var shape: DiagramNodeShape
        /// Extra rows under the label (state descriptions).
        var details: [String] = []
        /// Member compartments of a record node (class attributes and methods, entity attributes).
        var memberGroups: [[String]] = []
        var cluster: Int?
        var hasExplicitLabel = false
    }

    struct Edge: Equatable, Sendable {
        var source: Endpoint
        var target: Endpoint
        var label: String?
        var line: DiagramLineStyle
        var sourceHead: DiagramArrowhead
        var targetHead: DiagramArrowhead
        /// Invisible links shape the layout but draw nothing.
        var isInvisible = false
        /// Cardinality text near each end (UML multiplicities).
        var sourceLabel: String?
        var targetLabel: String?
    }

    struct Cluster: Equatable, Sendable {
        var id: String
        var title: String
        var parent: Int?
        var direction: Direction?
    }

    var direction: Direction = .topDown
    var nodes: [Node] = []
    var edges: [Edge] = []
    var clusters: [Cluster] = []
}

/// Mutable construction of a `DiagramGraph` with the caps enforced as items are added.
struct DiagramGraphBuilder {
    private(set) var graph: DiagramGraph
    private var nodeIndexes: [String: Int] = [:]
    private var clusterIndexes: [String: Int] = [:]
    private(set) var clusterStack: [Int] = []

    private let defaultShape: DiagramNodeShape

    init(direction: DiagramGraph.Direction, defaultShape: DiagramNodeShape = .rectangle) {
        self.defaultShape = defaultShape
        graph = DiagramGraph(direction: direction)
    }

    var currentCluster: Int? { clusterStack.last }

    /// Finds or creates a node. Only a node still at the root moves into the open cluster.
    mutating func node(id: String, label: String? = nil, shape: DiagramNodeShape? = nil) throws -> Int {
        let index: Int
        if let existing = nodeIndexes[id] {
            index = existing
            if graph.nodes[index].cluster == nil, let current = currentCluster { graph.nodes[index].cluster = current }
        } else {
            guard graph.nodes.count < DiagramLimits.maximumNodes else { throw DiagramFailure.tooLarge }
            index = graph.nodes.count
            graph.nodes.append(.init(id: id, label: id, shape: defaultShape, cluster: currentCluster))
            nodeIndexes[id] = index
        }
        if let label { graph.nodes[index].label = label; graph.nodes[index].hasExplicitLabel = true }
        if let shape { graph.nodes[index].shape = shape }
        return index
    }

    func hasNode(_ id: String) -> Bool { nodeIndexes[id] != nil }
    func clusterIndex(for id: String) -> Int? { clusterIndexes[id] }

    /// Resolves an identifier to a cluster when one already exists and no node uses the name.
    func endpoint(for id: String, nodeIndex: Int?) -> DiagramGraph.Endpoint? {
        if let nodeIndex { return .node(nodeIndex) }
        if let cluster = clusterIndexes[id] { return .cluster(cluster) }
        return nil
    }

    mutating func openCluster(id: String, title: String) throws {
        guard graph.clusters.count < DiagramLimits.maximumClusters,
              clusterStack.count < DiagramLimits.maximumClusterDepth else { throw DiagramFailure.tooLarge }
        let index = graph.clusters.count
        graph.clusters.append(.init(id: id, title: title, parent: currentCluster, direction: nil))
        // The first definition owns the identifier for edge endpoints.
        if clusterIndexes[id] == nil { clusterIndexes[id] = index }
        clusterStack.append(index)
    }

    mutating func setClusterDirection(_ direction: DiagramGraph.Direction) {
        guard let current = currentCluster else { graph.direction = direction; return }
        graph.clusters[current].direction = direction
    }

    mutating func closeCluster() throws {
        guard !clusterStack.isEmpty else { throw DiagramFailure.malformed }
        clusterStack.removeLast()
    }

    mutating func addEdge(_ edge: DiagramGraph.Edge) throws {
        guard graph.edges.count < DiagramLimits.maximumEdges else { throw DiagramFailure.tooLarge }
        graph.edges.append(edge)
    }

    /// Adds one member row to a record node's compartment `group`; rows beyond the cap end in one ellipsis.
    mutating func appendMember(_ text: String, group: Int, to node: Int) {
        while graph.nodes[node].memberGroups.count <= group { graph.nodes[node].memberGroups.append([]) }
        let count = graph.nodes[node].memberGroups.reduce(0) { $0 + $1.count }
        if count < DiagramLimits.maximumRecordMembers {
            graph.nodes[node].memberGroups[group].append(text)
        } else if count == DiagramLimits.maximumRecordMembers {
            graph.nodes[node].memberGroups[group].append("…")
        }
    }

    mutating func appendDetail(_ text: String, to node: Int) {
        guard graph.nodes[node].details.count < DiagramLimits.maximumLabelLines else { return }
        graph.nodes[node].details.append(text)
    }

    /// A graph is complete only when every opened cluster was closed.
    func finished() throws -> DiagramGraph {
        guard clusterStack.isEmpty, !graph.nodes.isEmpty || !graph.clusters.isEmpty else { throw DiagramFailure.malformed }
        return graph
    }
}

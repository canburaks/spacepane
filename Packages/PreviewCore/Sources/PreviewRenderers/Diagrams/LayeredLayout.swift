import CoreGraphics
import Foundation

/// Input to the layered layout in abstract axes: nodes are ranked along the *rank* axis and
/// ordered along the *order* axis. The caller maps the axes to x/y for the diagram direction.
struct LayeredLayoutInput {
    struct Edge {
        var from: Int
        var to: Int
        var hasLabel: Bool
    }

    var orderSizes: [CGFloat]
    var rankSizes: [CGFloat]
    var edges: [Edge]
    var nodeSeparation: CGFloat = 36
    var rankSeparation: CGFloat = 56
}

struct LayeredLayoutOutput {
    /// Center of each input node on the order axis and rank axis.
    var orderCenters: [CGFloat] = []
    var rankCenters: [CGFloat] = []
    var orderExtent: CGFloat = 0
    var rankExtent: CGFloat = 0
    /// Interior route points (x: order, y: rank) per input edge, listed from its source to its
    /// target. Edges between adjacent ranks have none.
    var waypoints: [[CGPoint]] = []
}

/// A deterministic Sugiyama-style layout written for this app: cycle breaking by depth-first
/// search, longest-path ranking, dummy nodes for long edges, a fixed number of barycenter
/// sweeps, and coordinates from a fixed number of order-preserving relaxation passes. Every
/// loop is bounded by `DiagramLimits`, so the work is proportional to nodes plus edges.
enum LayeredLayout {
    private struct Pair: Hashable { let from: Int; let to: Int }

    static func run(_ input: LayeredLayoutInput) throws -> LayeredLayoutOutput {
        let count = input.orderSizes.count
        guard count > 0 else { return LayeredLayoutOutput(waypoints: input.edges.map { _ in [] }) }
        guard input.rankSizes.count == count,
              input.edges.allSatisfy({ $0.from >= 0 && $0.from < count && $0.to >= 0 && $0.to < count }) else {
            throw DiagramFailure.malformed
        }

        // 1. Unique ordered pairs (self loops carry no ranking information).
        var pairIndexes: [Pair: Int] = [:]
        var pairs: [Pair] = []
        var successors = [[Int]](repeating: [], count: count)
        for edge in input.edges where edge.from != edge.to {
            let pair = Pair(from: edge.from, to: edge.to)
            if pairIndexes[pair] == nil {
                pairIndexes[pair] = pairs.count
                pairs.append(pair)
                successors[edge.from].append(edge.to)
            }
        }

        // 2. Break cycles: a depth-first search marks edges that return to the active path.
        let backEdges = findBackEdges(count: count, successors: successors)
        var oriented: [Pair] = []
        var orientedIndexes: [Pair: Int] = [:]
        var pairToOriented: [Int] = []
        var pairIsReversed: [Bool] = []
        for pair in pairs {
            let reversed = backEdges.contains(pair)
            let layered = reversed ? Pair(from: pair.to, to: pair.from) : pair
            if orientedIndexes[layered] == nil {
                orientedIndexes[layered] = oriented.count
                oriented.append(layered)
            }
            pairToOriented.append(orientedIndexes[layered] ?? 0)
            pairIsReversed.append(reversed)
        }

        // 3. Longest-path ranks over the acyclic edge set.
        var layeredSuccessors = [[Int]](repeating: [], count: count)
        var layeredPredecessors = [[Int]](repeating: [], count: count)
        for pair in oriented {
            layeredSuccessors[pair.from].append(pair.to)
            layeredPredecessors[pair.to].append(pair.from)
        }
        var rank = [Int](repeating: 0, count: count)
        var remaining = layeredPredecessors.map(\.count)
        var queue = (0..<count).filter { remaining[$0] == 0 }
        var cursor = 0
        var topological: [Int] = []
        while cursor < queue.count {
            let node = queue[cursor]
            cursor += 1
            topological.append(node)
            for next in layeredSuccessors[node] {
                rank[next] = max(rank[next], rank[node] + 1)
                remaining[next] -= 1
                if remaining[next] == 0 { queue.append(next) }
            }
        }
        guard topological.count == count else { throw DiagramFailure.malformed }
        // Sources sit just above their nearest successor instead of at the top.
        for node in topological where layeredPredecessors[node].isEmpty && !layeredSuccessors[node].isEmpty {
            rank[node] = (layeredSuccessors[node].map { rank[$0] }.min() ?? 1) - 1
        }
        let rankCount = (rank.max() ?? 0) + 1
        guard rankCount <= DiagramLimits.maximumRanks else { throw DiagramFailure.tooLarge }

        // 4. Dummy nodes: every edge becomes a chain of unit-rank segments.
        var layerOf = rank
        var orderSize = input.orderSizes
        var segmentSuccessors = [[Int]](repeating: [], count: count)
        var segmentPredecessors = [[Int]](repeating: [], count: count)
        var chains: [[Int]] = []
        var virtualCount = 0
        for pair in oriented {
            let span = rank[pair.to] - rank[pair.from]
            var chain: [Int] = []
            var previous = pair.from
            if span > 1 {
                virtualCount += span - 1
                guard virtualCount <= DiagramLimits.maximumVirtualNodes else { throw DiagramFailure.tooLarge }
                for step in 1..<span {
                    let id = layerOf.count
                    layerOf.append(rank[pair.from] + step)
                    orderSize.append(0)
                    segmentSuccessors.append([])
                    segmentPredecessors.append([])
                    segmentSuccessors[previous].append(id)
                    segmentPredecessors[id].append(previous)
                    chain.append(id)
                    previous = id
                }
            }
            segmentSuccessors[previous].append(pair.to)
            segmentPredecessors[pair.to].append(previous)
            chains.append(chain)
        }
        let total = layerOf.count

        // 5. Initial order: breadth-first from the sources in input order.
        var layers = [[Int]](repeating: [], count: rankCount)
        var seen = [Bool](repeating: false, count: total)
        var frontier: [Int] = []
        for node in 0..<count where layeredPredecessors[node].isEmpty { frontier.append(node); seen[node] = true }
        var head = 0
        while head < frontier.count {
            let node = frontier[head]
            head += 1
            layers[layerOf[node]].append(node)
            for next in segmentSuccessors[node] where !seen[next] { seen[next] = true; frontier.append(next) }
        }
        for node in 0..<total where !seen[node] { layers[layerOf[node]].append(node) }
        var position = [Int](repeating: 0, count: total)
        func refreshPositions(_ layer: Int) { for (index, node) in layers[layer].enumerated() { position[node] = index } }
        for layer in 0..<rankCount { refreshPositions(layer) }

        // 6. Barycenter sweeps with a fixed count, alternating direction.
        if rankCount > 1 {
            for sweep in 0..<DiagramLimits.orderingSweeps {
                if sweep.isMultiple(of: 2) {
                    for layer in 1..<rankCount { reorder(&layers[layer], neighbors: segmentPredecessors, position: &position) }
                } else {
                    for layer in stride(from: rankCount - 2, through: 0, by: -1) {
                        reorder(&layers[layer], neighbors: segmentSuccessors, position: &position)
                    }
                }
            }
        }

        // 7. Coordinates along the order axis.
        func separation(_ a: Int, _ b: Int) -> CGFloat {
            let isVirtualA = a >= count, isVirtualB = b >= count
            let gap: CGFloat = (isVirtualA && isVirtualB) ? 14 : (isVirtualA || isVirtualB) ? 22 : input.nodeSeparation
            return (orderSize[a] + orderSize[b]) / 2 + gap
        }
        var x = [CGFloat](repeating: 0, count: total)
        var widest: CGFloat = 0
        for layer in layers {
            var cursorX: CGFloat = 0
            for (index, node) in layer.enumerated() {
                if index > 0 { cursorX += separation(layer[index - 1], node) }
                x[node] = cursorX
            }
            widest = max(widest, cursorX)
        }
        for layer in layers {
            guard let last = layer.last else { continue }
            let shift = (widest - x[last]) / 2
            for node in layer { x[node] += shift }
        }
        func relax(layer: Int, using neighbors: [[Int]], alsoUsing other: [[Int]]? = nil) {
            let nodes = layers[layer]
            guard !nodes.isEmpty else { return }
            var targets = [CGFloat](repeating: 0, count: nodes.count)
            var gaps = [CGFloat](repeating: 0, count: nodes.count)
            for (index, node) in nodes.enumerated() {
                var sum: CGFloat = 0
                var number: CGFloat = 0
                for neighbor in neighbors[node] { sum += x[neighbor]; number += 1 }
                if let other { for neighbor in other[node] { sum += x[neighbor]; number += 1 } }
                targets[index] = number > 0 ? sum / number : x[node]
                if index > 0 { gaps[index] = separation(nodes[index - 1], node) }
            }
            let placed = orderPreservingPositions(targets: targets, gaps: gaps)
            for (index, node) in nodes.enumerated() { x[node] = placed[index] }
        }
        if rankCount > 1 {
            for pass in 0..<DiagramLimits.coordinatePasses {
                if pass.isMultiple(of: 2) {
                    for layer in 1..<rankCount { relax(layer: layer, using: segmentPredecessors) }
                } else {
                    for layer in stride(from: rankCount - 2, through: 0, by: -1) { relax(layer: layer, using: segmentSuccessors) }
                }
            }
            for layer in 0..<rankCount { relax(layer: layer, using: segmentPredecessors, alsoUsing: segmentSuccessors) }
        }
        let minimum = (0..<total).map { x[$0] - orderSize[$0] / 2 }.min() ?? 0
        for node in 0..<total { x[node] -= minimum }
        let orderExtent = (0..<total).map { x[$0] + orderSize[$0] / 2 }.max() ?? 0

        // 8. Coordinates along the rank axis.
        var thickness = [CGFloat](repeating: 0, count: rankCount)
        for node in 0..<count { thickness[layerOf[node]] = max(thickness[layerOf[node]], input.rankSizes[node]) }
        var labelledGap = [Bool](repeating: false, count: rankCount)
        for edge in input.edges where edge.hasLabel && edge.from != edge.to {
            labelledGap[min(rank[edge.from], rank[edge.to])] = true
        }
        var rankCenters = [CGFloat](repeating: 0, count: rankCount)
        var offset: CGFloat = 0
        for layer in 0..<rankCount {
            if layer > 0 {
                offset += thickness[layer - 1] / 2 + input.rankSeparation + (labelledGap[layer - 1] ? 26 : 0) + thickness[layer] / 2
            } else {
                offset = thickness[0] / 2
            }
            rankCenters[layer] = offset
        }
        let rankExtent = rankCenters.last.map { $0 + thickness[rankCount - 1] / 2 } ?? 0

        // 9. Routes per input edge.
        var waypoints: [[CGPoint]] = []
        for edge in input.edges {
            guard edge.from != edge.to, let pairIndex = pairIndexes[Pair(from: edge.from, to: edge.to)] else {
                waypoints.append([])
                continue
            }
            var chain = chains[pairToOriented[pairIndex]]
            // A reversed edge was laid out target-to-source; the chain is read in layout order.
            if pairIsReversed[pairIndex] { chain.reverse() }
            waypoints.append(chain.map { CGPoint(x: x[$0], y: rankCenters[layerOf[$0]]) })
        }
        return LayeredLayoutOutput(orderCenters: Array(x[0..<count]),
                                   rankCenters: (0..<count).map { rankCenters[layerOf[$0]] },
                                   orderExtent: orderExtent, rankExtent: rankExtent, waypoints: waypoints)
    }

    /// Edges that close a cycle in a depth-first search over the nodes in input order.
    private static func findBackEdges(count: Int, successors: [[Int]]) -> Set<Pair> {
        var state = [UInt8](repeating: 0, count: count)
        var back: Set<Pair> = []
        for root in 0..<count where state[root] == 0 {
            var stack: [(node: Int, next: Int)] = [(root, 0)]
            state[root] = 1
            while let top = stack.last {
                if top.next < successors[top.node].count {
                    stack[stack.count - 1].next += 1
                    let target = successors[top.node][top.next]
                    if state[target] == 1 {
                        back.insert(Pair(from: top.node, to: target))
                    } else if state[target] == 0 {
                        state[target] = 1
                        stack.append((target, 0))
                    }
                } else {
                    state[top.node] = 2
                    stack.removeLast()
                }
            }
        }
        return back
    }

    /// Stable reorder of one layer by the mean position of its neighbors in the adjacent layer.
    private static func reorder(_ layer: inout [Int], neighbors: [[Int]], position: inout [Int]) {
        guard layer.count > 1 else { return }
        var keyed: [(node: Int, key: Double, previous: Int)] = []
        keyed.reserveCapacity(layer.count)
        for (index, node) in layer.enumerated() {
            let adjacent = neighbors[node]
            let key = adjacent.isEmpty ? Double(index) : Double(adjacent.reduce(0) { $0 + position[$1] }) / Double(adjacent.count)
            keyed.append((node, key, index))
        }
        keyed.sort { $0.key != $1.key ? $0.key < $1.key : $0.previous < $1.previous }
        for (index, entry) in keyed.enumerated() { layer[index] = entry.node; position[entry.node] = index }
    }

    /// Least-squares positions that keep the given order and minimum gaps: the pool-adjacent-
    /// violators algorithm on the targets with the cumulative gaps removed.
    static func orderPreservingPositions(targets: [CGFloat], gaps: [CGFloat]) -> [CGFloat] {
        let count = targets.count
        var offsets = [CGFloat](repeating: 0, count: count)
        for index in 1..<max(count, 1) { offsets[index] = offsets[index - 1] + gaps[index] }
        var blocks: [(sum: CGFloat, count: CGFloat)] = []
        var sizes: [Int] = []
        for index in 0..<count {
            blocks.append((targets[index] - offsets[index], 1))
            sizes.append(1)
            while blocks.count > 1,
                  blocks[blocks.count - 2].sum / blocks[blocks.count - 2].count > blocks[blocks.count - 1].sum / blocks[blocks.count - 1].count {
                let last = blocks.removeLast()
                let lastSize = sizes.removeLast()
                blocks[blocks.count - 1].sum += last.sum
                blocks[blocks.count - 1].count += last.count
                sizes[sizes.count - 1] += lastSize
            }
        }
        var result = [CGFloat](repeating: 0, count: count)
        var index = 0
        for (block, size) in zip(blocks, sizes) {
            let mean = block.sum / block.count
            for _ in 0..<size { result[index] = mean + offsets[index]; index += 1 }
        }
        return result
    }
}

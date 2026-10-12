import CoreGraphics
import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Layered layout")
struct LayeredLayoutTests {
    /// A tiny deterministic generator so graph shapes never depend on the platform.
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
    }

    private func input(nodes: Int, edges: [(Int, Int)], orderSize: CGFloat = 80, rankSize: CGFloat = 40) -> LayeredLayoutInput {
        LayeredLayoutInput(orderSizes: Array(repeating: orderSize, count: nodes), rankSizes: Array(repeating: rankSize, count: nodes),
                           edges: edges.map { .init(from: $0.0, to: $0.1, hasLabel: false) })
    }

    @Test func emptyAndSingleNodeGraphsLayOut() throws {
        let empty = try LayeredLayout.run(input(nodes: 0, edges: []))
        #expect(empty.orderCenters.isEmpty)
        let single = try LayeredLayout.run(input(nodes: 1, edges: []))
        #expect(single.orderCenters == [40])
        #expect(single.rankCenters == [20])
    }

    @Test func chainsRankDownwardWithSharedOrderPosition() throws {
        let output = try LayeredLayout.run(input(nodes: 4, edges: [(0, 1), (1, 2), (2, 3)]))
        #expect(output.rankCenters == output.rankCenters.sorted())
        #expect(Set(output.rankCenters).count == 4)
        #expect(Set(output.orderCenters).count == 1)
        #expect(output.waypoints.allSatisfy { $0.isEmpty })
    }

    @Test func diamondPutsTheBranchesOnOneRank() throws {
        let output = try LayeredLayout.run(input(nodes: 4, edges: [(0, 1), (0, 2), (1, 3), (2, 3)]))
        #expect(output.rankCenters[1] == output.rankCenters[2])
        #expect(output.rankCenters[0] < output.rankCenters[1] && output.rankCenters[1] < output.rankCenters[3])
        #expect(output.orderCenters[1] != output.orderCenters[2])
    }

    @Test func longEdgesGetOneWaypointPerSkippedRank() throws {
        let output = try LayeredLayout.run(input(nodes: 4, edges: [(0, 1), (1, 2), (2, 3), (0, 3)]))
        #expect(output.waypoints[3].count == 2)
        let ranks = output.waypoints[3].map(\.y)
        #expect(ranks == ranks.sorted())
        #expect(ranks[0] > output.rankCenters[0] && ranks[1] < output.rankCenters[3])
    }

    @Test func cyclesAndSelfLoopsAreBrokenWithoutLosingNodes() throws {
        let output = try LayeredLayout.run(input(nodes: 3, edges: [(0, 1), (1, 2), (2, 0), (1, 1)]))
        #expect(output.rankCenters.count == 3)
        #expect(Set(output.rankCenters).count == 3)
        #expect(output.waypoints.count == 4)
        #expect(output.waypoints[3].isEmpty)
    }

    @Test func aReversedEdgeRoutesFromItsOwnSourceToItsTarget() throws {
        // 0 -> 1 -> 2 -> 3 and a back edge 3 -> 0 that skips every rank.
        let output = try LayeredLayout.run(input(nodes: 4, edges: [(0, 1), (1, 2), (2, 3), (3, 0)]))
        let back = output.waypoints[3]
        #expect(back.count == 2)
        // Source (3) is the lowest node, so the route starts low and ends high.
        #expect(back[0].y > back[1].y)
    }

    @Test func parallelAndOppositeEdgesShareOneRankStep() throws {
        let output = try LayeredLayout.run(input(nodes: 2, edges: [(0, 1), (0, 1), (1, 0)]))
        #expect(output.rankCenters[0] != output.rankCenters[1])
        #expect(output.waypoints.allSatisfy { $0.isEmpty })
    }

    @Test func disconnectedComponentsShareRanks() throws {
        let output = try LayeredLayout.run(input(nodes: 4, edges: [(0, 1), (2, 3)]))
        #expect(output.rankCenters[0] == output.rankCenters[2])
        #expect(output.rankCenters[1] == output.rankCenters[3])
        #expect(output.orderCenters[0] != output.orderCenters[2])
    }

    @Test func nodesOnOneRankNeverOverlapAndLayoutIsDeterministic() throws {
        var generator = Generator(state: 0x5EED)
        for trial in 0..<12 {
            let count = 12 + trial * 9
            var edges: [(Int, Int)] = []
            for _ in 0..<(count * 2) { edges.append((generator.next(count), generator.next(count))) }
            var request = input(nodes: count, edges: edges)
            request.orderSizes = (0..<count).map { _ in CGFloat(40 + generator.next(100)) }
            request.rankSizes = (0..<count).map { _ in CGFloat(24 + generator.next(40)) }
            let first = try LayeredLayout.run(request)
            let second = try LayeredLayout.run(request)
            #expect(first.orderCenters == second.orderCenters)
            #expect(first.rankCenters == second.rankCenters)
            #expect(first.waypoints == second.waypoints)
            #expect(first.orderCenters.allSatisfy { $0.isFinite && $0 >= 0 })
            #expect(first.rankCenters.allSatisfy { $0.isFinite && $0 >= 0 })
            // Within a rank, neighbouring nodes keep their half-sizes apart.
            var byRank: [CGFloat: [Int]] = [:]
            for node in 0..<count { byRank[first.rankCenters[node], default: []].append(node) }
            for (_, nodes) in byRank {
                let sorted = nodes.sorted { first.orderCenters[$0] < first.orderCenters[$1] }
                for (a, b) in zip(sorted, sorted.dropFirst()) {
                    let gap = first.orderCenters[b] - first.orderCenters[a] - (request.orderSizes[a] + request.orderSizes[b]) / 2
                    #expect(gap >= 0, "Trial \(trial): nodes \(a) and \(b) overlap")
                }
            }
            #expect(first.orderExtent >= 0 && first.rankExtent > 0)
        }
    }

    @Test func rankSeparationStaysAboveTheLargestNodeOfEachRank() throws {
        var request = input(nodes: 3, edges: [(0, 1), (1, 2)])
        request.rankSizes = [30, 90, 30]
        let output = try LayeredLayout.run(request)
        #expect(output.rankCenters[1] - output.rankCenters[0] >= 15 + 45 + request.rankSeparation - 0.001)
        #expect(output.rankExtent >= output.rankCenters[2] + 15 - 0.001)
    }

    @Test func rankAndVirtualNodeLimitsDeclineInsteadOfAllocating() {
        let tooManyRanks = (0..<DiagramLimits.maximumRanks).map { ($0, $0 + 1) }
        #expect(throws: DiagramFailure.tooLarge) { try LayeredLayout.run(input(nodes: DiagramLimits.maximumRanks + 1, edges: tooManyRanks)) }
        // Eleven edges across a 1,999-rank chain would need more than 20,000 dummy nodes.
        var edges = (0..<1_999).map { ($0, $0 + 1) }
        edges += Array(repeating: (0, 1_999), count: 1)
        edges += (1..<11).map { ($0 - 1, 1_999 - $0 % 2) }
        #expect(throws: DiagramFailure.tooLarge) { try LayeredLayout.run(input(nodes: 2_000, edges: edges)) }
    }

    @Test func invalidIndicesAreRejected() {
        #expect(throws: DiagramFailure.malformed) { try LayeredLayout.run(input(nodes: 2, edges: [(0, 5)])) }
    }

    @Test func orderPreservingPositionsKeepOrderAndMinimumGaps() {
        let placed = LayeredLayout.orderPreservingPositions(targets: [10, 10, 10, 50], gaps: [0, 20, 20, 20])
        #expect(placed.count == 4)
        for index in 1..<placed.count { #expect(placed[index] - placed[index - 1] >= 20 - 0.0001) }
        // Three equal targets with 20-point gaps are centered on their target: -10, 10, 30.
        #expect(abs(placed[0] + 10) < 0.0001 && abs(placed[1] - 10) < 0.0001 && abs(placed[2] - 30) < 0.0001)
        #expect(abs(placed[3] - 50) < 0.0001)
        #expect(LayeredLayout.orderPreservingPositions(targets: [], gaps: []).isEmpty)
    }
}

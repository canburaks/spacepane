import Foundation

/// Explicit caps for diagram parsing, layout and drawing. Renderers receive no `RequestContext`
/// deadline, so every loop in the diagram family is bounded by one of these constants and a
/// document that exceeds any of them is declined (the caller keeps the Source mode) rather than
/// laid out partially.
enum DiagramLimits {
    /// Concealed source accepted by a diagram parser, in UTF-8 bytes.
    static let maximumSourceUTF8Bytes = 524_288
    static let maximumLines = 20_000
    static let maximumNodes = 2_000
    static let maximumEdges = 5_000
    static let maximumClusters = 500
    static let maximumClusterDepth = 16
    /// Characters kept from any one label; longer text ends in an ellipsis.
    static let maximumLabelCharacters = 400
    static let maximumLabelLines = 12
    /// Dummy nodes that route an edge across several ranks.
    static let maximumVirtualNodes = 20_000
    static let maximumRanks = 2_500
    static let maximumParticipants = 64
    static let maximumSequenceItems = 2_000
    static let maximumSlices = 100
    /// Member rows kept per class or entity.
    static let maximumRecordMembers = 60
    /// Fixed numbers of barycenter sweeps and coordinate relaxation passes.
    static let orderingSweeps = 12
    static let coordinatePasses = 8
    /// Largest scene extent in either dimension; larger layouts are declined.
    static let maximumSceneDimension: CGFloat = 300_000
    static let maximumDrawioCells = 5_000
    static let maximumDrawioDepth = 32
    static let maximumDrawioStylePairs = 64
    static let maximumEdgeWaypoints = 64
    /// Accessibility children created for one diagram; the edge summary names the remainder.
    static let maximumAccessibilityNodes = 500
    static let maximumAccessibilityConnections = 100
}

/// Parsing and layout fail closed: the diagram mode is not offered and Source stays available.
enum DiagramFailure: Error, Equatable {
    case tooLarge
    case malformed
    case unsupported
}

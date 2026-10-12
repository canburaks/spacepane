import Foundation

/// Value-free facts about a presentation, formatted by the renderer in the presentation locale. They live in
/// the contracts module so adapters and tests build them without AppKit; no fact ever carries a source value,
/// a file name or document text (decision 027, Q-32, amendment 3).
public struct PresentationFacts: Equatable, Sendable {
    public enum RecordKind: String, Equatable, Sendable { case records, cues, pages, cells, events, images }

    public enum Fact: Equatable, Sendable {
        case encoding(TextEncoding)
        case lines(Int)
        case size(Int64)
        case shownSize(shown: Int64, total: Int64)
        case grid(rows: Int, columns: Int, rowsAreLowerBound: Bool)
        case records(Int, RecordKind, isLowerBound: Bool = false)
        case nodes(Int, isLowerBound: Bool = false)
        case listing(files: Int, folders: Int, isLowerBound: Bool, listedBytes: Int64?)
        case geometry(faces: Int, bodies: Int?, extentMillimetres: SIMD3<Double>, unit: GeometryUnitProvenance, facesAreLowerBound: Bool = false)
        case playback(tracks: Int, seconds: Double)
        case pixels(width: Int, height: Int)
    }

    /// Facts shown in regular density, from the front of the list.
    public static let regularCount = 4
    /// Facts shown in compact density, from the front of the list.
    public static let compactCount = 2
    public static let none = PresentationFacts([])

    /// Priority order: the most useful fact first.
    public let facts: [Fact]

    public init(_ facts: [Fact]) { self.facts = facts }

    public var isEmpty: Bool { facts.isEmpty }

    /// Compatibility prefix of grouped facts. Renderers flatten groups into scalar labels before applying
    /// the density budget; a grid or geometry group can contribute several visible facts.
    public func shown(compact: Bool) -> [Fact] {
        Array(facts.prefix(compact ? Self.compactCount : Self.regularCount))
    }
}

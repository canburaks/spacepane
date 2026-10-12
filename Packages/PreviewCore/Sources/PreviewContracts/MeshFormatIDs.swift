import Foundation

/// Stable identities of the triangle-mesh formats. Raw values are persisted preference keys and
/// catalog identifiers; they never change when the product display name does.
public extension FormatID {
    static let meshSTL = FormatID(rawValue: "model.stl")
    static let meshOBJ = FormatID(rawValue: "model.obj")
    static let meshPLY = FormatID(rawValue: "model.ply")
    static let mesh3MF = FormatID(rawValue: "model.3mf")
}

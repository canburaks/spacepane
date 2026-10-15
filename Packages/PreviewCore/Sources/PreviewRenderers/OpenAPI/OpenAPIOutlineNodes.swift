import Foundation

/// Reads of a concealed outline node for the OpenAPI derivations. The outline writes an object as `{…}` and an array as
/// `[…]`; any other value is a string or a bare scalar and keeps its exact text. A repeated key resolves to its last
/// occurrence, as most JSON readers resolve it.
extension SafeOutlineNode {
    var isJSONObject: Bool { value == "{…}" }
    var isJSONArray: Bool { value == "[…]" }

    /// The text of a string or scalar value; nil for an object or an array.
    var scalarText: String? { isJSONObject || isJSONArray ? nil : value }

    /// The member of an object with this key.
    func jsonMember(named key: String) -> SafeOutlineNode? {
        children.last { $0.name == key }
    }

    /// The element of an array at this index, which the outline names `[index]`.
    func jsonElement(at index: Int) -> SafeOutlineNode? {
        children.first { $0.name == "[\(index)]" }
    }
}

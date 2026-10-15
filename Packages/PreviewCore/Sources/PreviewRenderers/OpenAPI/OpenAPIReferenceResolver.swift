import Foundation

/// Follows a local reference inside one document: a JSON Pointer in the fragment of a `#` reference (RFC 6901), read
/// over the concealed outline. A reference to another file, to a URL or to a location the document does not have
/// names nothing this preview can read, so it resolves to nil.
enum OpenAPIReferenceResolver {
    static func target(of reference: String, in root: SafeOutlineNode) -> SafeOutlineNode? {
        guard reference.hasPrefix("#"), let pointer = String(reference.dropFirst()).removingPercentEncoding,
              pointer.isEmpty || pointer.hasPrefix("/") else { return nil }
        // An empty pointer names the whole document. Otherwise each segment after the first slash is one key or index,
        // with `~1` standing for `/` and `~0` for `~`, in that order (RFC 6901 section 4).
        guard !pointer.isEmpty else { return root }
        var node = root
        for segment in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let token = segment.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            guard let child = child(of: node, token: token) else { return nil }
            node = child
        }
        return node
    }

    private static func child(of node: SafeOutlineNode, token: String) -> SafeOutlineNode? {
        if node.isJSONObject { return node.jsonMember(named: token) }
        // An array index is written canonically (no sign, no leading zero), so `[01]` does not name element 1.
        if node.isJSONArray, let index = Int(token), String(index) == token { return node.jsonElement(at: index) }
        return nil
    }
}

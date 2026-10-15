import Foundation
import PreviewContracts

/// The operations of an OpenAPI 3.x or Swagger 2.0 document, one row each (tier 1 item 5, workstream tq-openapi).
///
/// The rows come only from the concealed JSON outline that `SafePreviewModes` builds, never from source bytes, so a
/// value the privacy stage concealed reaches the table only as the concealment token. Recognition follows the document,
/// not the file name: the root object has a string `openapi` that begins with `3.`, or a string `swagger` equal to
/// `2.0`, and an object `paths`. The outline keeps no string-or-scalar flag, so a bare number such as `3.0` reads as the
/// string "3.0", and the string "true" marks an operation deprecated. Neither changes the result for a valid document.
struct OpenAPIEndpointList: Equatable, Sendable {
    /// Rows shown. Operations past this are still counted, so the limits notice can say how many were left out.
    static let maximumRows = 5_000
    /// Path items can refer to one another. A chain longer than this, or a cycle, counts as unresolved.
    static let maximumReferenceHops = 8
    private static let methods: Set<String> = ["get", "put", "post", "delete", "options", "head", "patch", "trace"]

    /// Method, Path, Summary and Deprecated columns, with the rows in the order the document gives them. Its origin is
    /// the file's own concealed text, so Source still holds every operation the table leaves out.
    let table: SafeTable
    /// Every operation the document lists, including those past `maximumRows`.
    let totalOperations: Int
    /// Path items whose `$ref` cannot be followed inside this document.
    let unresolvedReferences: Int

    /// The endpoint list of a recognized document, or nil for anything else, including a plain JSON object with `paths`.
    static func derive(from root: SafeOutlineNode?) -> OpenAPIEndpointList? {
        guard let root, root.isJSONObject, isSpecification(root),
              let paths = root.jsonMember(named: "paths"), paths.isJSONObject else { return nil }
        var rows: [[String]] = []
        var totalOperations = 0
        var unresolved = 0
        var truncated = false
        let deprecatedMarker = PreviewStrings.text(.summaryBooleanTrue)
        // Only keys that begin with `/` are path templates; `x-` keys are extensions, which the specification allows here.
        for item in paths.children where item.name.hasPrefix("/") && item.isJSONObject {
            let found = operations(of: item, root: root)
            if found.unresolved { unresolved += 1 }
            for operation in found.operations {
                totalOperations += 1
                guard rows.count < maximumRows else {
                    truncated = true
                    continue
                }
                rows.append([operation.name.uppercased(), item.name, summary(of: operation),
                             isDeprecated(operation) ? deprecatedMarker : ""])
            }
        }
        let columns = [PreviewStrings.text(.dataMethod), PreviewStrings.text(.summaryPath),
                       PreviewStrings.text(.previewModeSummary), PreviewStrings.text(.openAPIColumnDeprecated)]
        let table = SafeTable(columns: columns, rows: rows, truncation: truncated ? [.rows] : [], origin: .delimitedText)
        return OpenAPIEndpointList(table: table, totalOperations: totalOperations, unresolvedReferences: unresolved)
    }

    private static func isSpecification(_ root: SafeOutlineNode) -> Bool {
        if let version = root.jsonMember(named: "openapi")?.scalarText, version.hasPrefix("3.") { return true }
        return root.jsonMember(named: "swagger")?.scalarText == "2.0"
    }

    /// A path item's own operations. When it has none and a `$ref`, the operations of the local item it names. A `$ref`
    /// that cannot be followed is reported as unresolved even when the item has operations of its own.
    private static func operations(of item: SafeOutlineNode, root: SafeOutlineNode) -> (operations: [SafeOutlineNode], unresolved: Bool) {
        let own = operationNodes(in: item)
        guard let reference = item.jsonMember(named: "$ref")?.scalarText else { return (own, false) }
        guard let followed = followedOperations(reference, root: root, hops: 0) else { return (own, true) }
        return (own.isEmpty ? followed : own, false)
    }

    private static func followedOperations(_ reference: String, root: SafeOutlineNode, hops: Int) -> [SafeOutlineNode]? {
        guard hops < maximumReferenceHops, let target = OpenAPIReferenceResolver.target(of: reference, in: root),
              target.isJSONObject else { return nil }
        let own = operationNodes(in: target)
        if !own.isEmpty { return own }
        guard let next = target.jsonMember(named: "$ref")?.scalarText else { return [] }
        return followedOperations(next, root: root, hops: hops + 1)
    }

    private static func operationNodes(in item: SafeOutlineNode) -> [SafeOutlineNode] {
        item.children.filter { methods.contains($0.name) && $0.isJSONObject }
    }

    /// The summary, or the operation identifier when the summary is missing or empty.
    private static func summary(of operation: SafeOutlineNode) -> String {
        for key in ["summary", "operationId"] {
            if let text = operation.jsonMember(named: key)?.scalarText, !text.isEmpty { return text }
        }
        return ""
    }

    private static func isDeprecated(_ operation: SafeOutlineNode) -> Bool {
        operation.jsonMember(named: "deprecated")?.scalarText == "true"
    }
}

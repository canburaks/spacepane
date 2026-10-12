import Foundation
import PreviewContracts

/// A parsed Avro schema, checked against the public specification. Named types (records, enums,
/// fixed) are registered by full name so that a later reference, including a recursive one, is a
/// lookup rather than a cycle in the value tree. Parsing never resolves anything outside the
/// document and is bounded in depth, nodes and names.
struct AvroSchemaNode {
    enum Kind: String {
        case null, boolean, int, long, float, double, bytes, string
        case record, enumeration = "enum", array, map, fixed, union
        /// A use of a named type defined elsewhere in the same schema.
        case reference
    }

    var kind: Kind
    /// Full name of a named type or of the type a reference points to.
    var name: String?
    var logicalType: String?
    var fields: [(name: String, node: AvroSchemaNode)] = []
    var symbols: [String] = []
    var size = 0
    /// Array items, map values or union branches.
    var children: [AvroSchemaNode] = []

    init(_ kind: Kind) { self.kind = kind }
}

struct AvroSchema {
    let root: AvroSchemaNode
    let registry: [String: AvroSchemaNode]

    struct Limits {
        static let depth = 32
        static let namedTypes = 2_000
        static let fields = 4_000
        static let symbols = 4_000
    }

    static func parse(_ text: DataJSONValue, nodeAllowance: Int) throws -> AvroSchema {
        var parser = Parser(nodeAllowance: nodeAllowance)
        let root = try parser.node(text, namespace: nil, depth: 1)
        return AvroSchema(root: root, registry: parser.registry)
    }

    /// Resolves a reference node to its definition.
    func resolve(_ node: AvroSchemaNode) throws -> AvroSchemaNode {
        guard node.kind == .reference else { return node }
        guard let name = node.name, let target = registry[name] else { throw PreviewFailure.malformedDocument }
        return target
    }

    private struct Parser {
        var registry: [String: AvroSchemaNode] = [:]
        private var defined: Set<String> = []
        private var remainingNodes: Int
        private var fieldCount = 0
        private static let primitives: [String: AvroSchemaNode.Kind] = [
            "null": .null, "boolean": .boolean, "int": .int, "long": .long, "float": .float,
            "double": .double, "bytes": .bytes, "string": .string
        ]

        init(nodeAllowance: Int) { remainingNodes = nodeAllowance }

        mutating func node(_ json: DataJSONValue, namespace: String?, depth: Int) throws -> AvroSchemaNode {
            guard depth <= AvroSchema.Limits.depth else { throw PreviewFailure.structureTooDeep }
            guard remainingNodes > 0 else { throw PreviewFailure.tooManyNodes }
            remainingNodes -= 1
            switch json {
            case .string(let name):
                if let kind = Self.primitives[name] { return AvroSchemaNode(kind) }
                return try reference(name, namespace: namespace)
            case .array(let branches):
                var union = AvroSchemaNode(.union)
                for branch in branches { union.children.append(try node(branch, namespace: namespace, depth: depth + 1)) }
                return union
            case .object:
                return try complex(json, namespace: namespace, depth: depth)
            default:
                throw PreviewFailure.malformedDocument
            }
        }

        private mutating func complex(_ json: DataJSONValue, namespace: String?, depth: Int) throws -> AvroSchemaNode {
            guard let typeValue = json["type"] else { throw PreviewFailure.malformedDocument }
            let logical = json["logicalType"]?.stringValue.map { DataTable.clip($0, to: 64).0 }
            // `{"type": {...}}` and `{"type": "long", ...}` wrap another schema.
            guard case .string(let typeName) = typeValue else {
                var inner = try node(typeValue, namespace: namespace, depth: depth + 1)
                if inner.logicalType == nil { inner.logicalType = logical }
                return inner
            }
            if let kind = Self.primitives[typeName] {
                var result = AvroSchemaNode(kind)
                result.logicalType = logical
                return result
            }
            switch typeName {
            case "record", "error":
                guard let name = json["name"]?.stringValue else { throw PreviewFailure.malformedDocument }
                let (full, scope) = try define(name, explicitNamespace: json["namespace"]?.stringValue, enclosing: namespace)
                var result = AvroSchemaNode(.record)
                result.name = full
                result.logicalType = logical
                guard let fields = json["fields"]?.arrayValue else { throw PreviewFailure.malformedDocument }
                var seen: Set<String> = []
                for field in fields {
                    fieldCount += 1
                    guard fieldCount <= AvroSchema.Limits.fields else { throw PreviewFailure.tooManyNodes }
                    guard let fieldName = field["name"]?.stringValue, let type = field["type"],
                          seen.insert(fieldName).inserted else { throw PreviewFailure.malformedDocument }
                    result.fields.append((fieldName, try node(type, namespace: scope, depth: depth + 1)))
                }
                registry[full] = result
                return result
            case "enum":
                guard let name = json["name"]?.stringValue, let symbols = json["symbols"]?.arrayValue,
                      symbols.count <= AvroSchema.Limits.symbols else { throw PreviewFailure.malformedDocument }
                let (full, _) = try define(name, explicitNamespace: json["namespace"]?.stringValue, enclosing: namespace)
                var result = AvroSchemaNode(.enumeration)
                result.name = full
                result.symbols = try symbols.map {
                    guard let symbol = $0.stringValue else { throw PreviewFailure.malformedDocument }
                    return symbol
                }
                guard Set(result.symbols).count == result.symbols.count else { throw PreviewFailure.malformedDocument }
                registry[full] = result
                return result
            case "fixed":
                guard let name = json["name"]?.stringValue, let size = json["size"]?.integerValue, size >= 0 else {
                    throw PreviewFailure.malformedDocument
                }
                let (full, _) = try define(name, explicitNamespace: json["namespace"]?.stringValue, enclosing: namespace)
                var result = AvroSchemaNode(.fixed)
                result.name = full
                result.size = size
                result.logicalType = logical
                registry[full] = result
                return result
            case "array":
                guard let items = json["items"] else { throw PreviewFailure.malformedDocument }
                var result = AvroSchemaNode(.array)
                result.children = [try node(items, namespace: namespace, depth: depth + 1)]
                return result
            case "map":
                guard let values = json["values"] else { throw PreviewFailure.malformedDocument }
                var result = AvroSchemaNode(.map)
                result.children = [try node(values, namespace: namespace, depth: depth + 1)]
                return result
            default:
                // `{"type": "SomeName"}` is a reference written in its long form.
                return try reference(typeName, namespace: namespace)
            }
        }

        /// Registers a name before its body is parsed, so the body may refer to it recursively.
        private mutating func define(_ name: String, explicitNamespace: String?, enclosing: String?) throws -> (full: String, scope: String?) {
            guard !name.isEmpty, defined.count < AvroSchema.Limits.namedTypes else { throw PreviewFailure.malformedDocument }
            let full: String
            let scope: String?
            if let dot = name.lastIndex(of: ".") {
                full = name
                scope = String(name[..<dot])
            } else if let explicitNamespace, !explicitNamespace.isEmpty {
                full = explicitNamespace + "." + name
                scope = explicitNamespace
            } else {
                full = enclosing.map { $0 + "." + name } ?? name
                scope = enclosing
            }
            guard defined.insert(full).inserted else { throw PreviewFailure.malformedDocument }
            return (full, scope)
        }

        private func reference(_ name: String, namespace: String?) throws -> AvroSchemaNode {
            var candidates = [name]
            if !name.contains("."), let namespace { candidates.insert(namespace + "." + name, at: 0) }
            guard let full = candidates.first(where: defined.contains) else { throw PreviewFailure.malformedDocument }
            var result = AvroSchemaNode(.reference)
            result.name = full
            return result
        }
    }
}

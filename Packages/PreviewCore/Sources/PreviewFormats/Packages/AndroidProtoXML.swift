import Foundation
import PreviewContracts

/// A bounded reader for the protobuf XML (aapt2's `XmlNode`) that Android App Bundles use for their
/// manifests. Only the fields the manifest summary needs are read: an element's name, its attributes'
/// names and text values, and its children. Compiled item values, source positions and namespace
/// declarations are skipped. Protobuf wire data is untrusted: every varint and length is checked
/// against the remaining input, nesting and element counts are capped, and nothing is allocated from a
/// declared length before it has been verified.
enum AndroidProtoXML {
    private enum Field {
        static let nodeElement = 1
        static let elementName = 3
        static let elementAttribute = 4
        static let elementChild = 5
        static let attributeName = 2
        static let attributeValue = 3
    }
    private static let lengthDelimited = 2
    private static let maximumNameBytes = 256
    private static let maximumValueBytes = 4_096

    static func parseManifest(_ data: Data, context: RequestContext) throws -> AndroidManifestSummary {
        try context.checkpoint()
        var reader = Reader(context: context, bytes: [UInt8](data))
        var summary = AndroidManifestSummary()
        let rootRange = 0..<reader.bytes.count
        var sawManifest = false
        var cursor = Cursor(bytes: reader.bytes, position: rootRange.lowerBound, end: rootRange.upperBound)
        while !cursor.isAtEnd {
            let (field, wire) = try cursor.tag()
            if field == Field.nodeElement, wire == lengthDelimited {
                guard !sawManifest else { throw PreviewFailure.malformedDocument }
                let element = try cursor.lengthDelimited()
                sawManifest = try reader.element(element, parent: nil, depth: 0, summary: &summary) == "manifest"
            } else {
                try cursor.skip(wire: wire)
            }
        }
        guard sawManifest else { throw PreviewFailure.malformedDocument }
        return summary
    }

    private struct Reader {
        let context: RequestContext
        let bytes: [UInt8]
        var elements = 0

        /// Parses one `XmlElement`, applies it to the summary, then its children. Returns the element's name.
        mutating func element(_ range: Range<Int>, parent: String?, depth: Int, summary: inout AndroidManifestSummary) throws -> String {
            elements += 1
            if elements.isMultiple(of: 256) { try context.checkpoint() }
            guard elements <= context.budget.maxJSONNodes, depth < min(context.budget.maxJSONDepth, 64) else {
                throw PreviewFailure.tooManyNodes
            }
            var name = ""
            var attributes: [String: AndroidAttributeValue] = [:]
            var children: [Range<Int>] = []
            var cursor = Cursor(bytes: bytes, position: range.lowerBound, end: range.upperBound)
            while !cursor.isAtEnd {
                let (field, wire) = try cursor.tag()
                guard wire == AndroidProtoXML.lengthDelimited else { try cursor.skip(wire: wire); continue }
                switch field {
                case Field.elementName:
                    let span = try cursor.lengthDelimited()
                    name = AndroidProtoXML.text(span, in: bytes, limit: AndroidProtoXML.maximumNameBytes) ?? ""
                case Field.elementAttribute:
                    try attribute(try cursor.lengthDelimited(), into: &attributes)
                case Field.elementChild:
                    children.append(try cursor.lengthDelimited())
                    guard children.count <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                default:
                    _ = try cursor.lengthDelimited()
                }
            }
            summary.record(element: name, parent: parent, attributes: attributes, isRoot: depth == 0)
            for child in children {
                // A child is an `XmlNode`: only its element field matters; text nodes are skipped.
                var node = Cursor(bytes: bytes, position: child.lowerBound, end: child.upperBound)
                while !node.isAtEnd {
                    let (field, wire) = try node.tag()
                    if field == Field.nodeElement, wire == AndroidProtoXML.lengthDelimited {
                        _ = try element(try node.lengthDelimited(), parent: name, depth: depth + 1, summary: &summary)
                    } else {
                        try node.skip(wire: wire)
                    }
                }
            }
            return name
        }

        private func attribute(_ range: Range<Int>, into attributes: inout [String: AndroidAttributeValue]) throws {
            var name: String?
            var value: String?
            var cursor = Cursor(bytes: bytes, position: range.lowerBound, end: range.upperBound)
            while !cursor.isAtEnd {
                let (field, wire) = try cursor.tag()
                guard wire == AndroidProtoXML.lengthDelimited else { try cursor.skip(wire: wire); continue }
                let span = try cursor.lengthDelimited()
                switch field {
                case Field.attributeName: name = AndroidProtoXML.text(span, in: bytes, limit: AndroidProtoXML.maximumNameBytes)
                case Field.attributeValue: value = AndroidProtoXML.text(span, in: bytes, limit: AndroidProtoXML.maximumValueBytes)
                default: break
                }
            }
            if let name, !name.isEmpty, let value, attributes[name] == nil { attributes[name] = .text(value) }
        }
    }

    /// UTF-8 text of a length-delimited field, or `nil` when it exceeds `limit` (it is then simply not shown).
    private static func text(_ range: Range<Int>, in bytes: [UInt8], limit: Int) -> String? {
        guard range.count <= limit else { return nil }
        return String(decoding: bytes[range], as: UTF8.self)
    }

    /// Reads protobuf wire format within `[position, end)` and never beyond it.
    private struct Cursor {
        let bytes: [UInt8]
        var position: Int
        let end: Int
        var isAtEnd: Bool { position >= end }

        mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard position < end, shift < 64 else { throw PreviewFailure.malformedDocument }
                let byte = bytes[position]
                position += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        mutating func tag() throws -> (field: Int, wire: Int) {
            let value = try varint()
            guard value >> 3 > 0, value >> 3 <= 536_870_911 else { throw PreviewFailure.malformedDocument }
            return (Int(value >> 3), Int(value & 7))
        }

        mutating func lengthDelimited() throws -> Range<Int> {
            let length = try varint()
            guard length <= UInt64(end - position) else { throw PreviewFailure.malformedDocument }
            let range = position..<(position + Int(length))
            position = range.upperBound
            return range
        }

        mutating func skip(wire: Int) throws {
            switch wire {
            case 0: _ = try varint()
            case 1: try advance(8)
            case 2: _ = try lengthDelimited()
            case 5: try advance(4)
            default: throw PreviewFailure.malformedDocument
            }
        }

        private mutating func advance(_ count: Int) throws {
            guard count <= end - position else { throw PreviewFailure.malformedDocument }
            position += count
        }
    }
}

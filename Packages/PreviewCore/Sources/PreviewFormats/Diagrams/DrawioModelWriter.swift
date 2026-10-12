import Foundation
import PreviewContracts

/// Writes one draw.io `mxGraphModel` as normalized XML, one element per line with attributes in a
/// fixed order, while recording the UTF-8 ranges of every concealable value. The writer is the
/// only producer of the safe text, so labels, style strings and custom properties are all seen
/// here before the shared privacy filter replaces the recorded ranges.
///
/// Image data in style strings and very long values are shortened, text nodes are dropped (a
/// model has none), and nothing is resolved: entities were handled by `XMLParser`, which never
/// loads external resources.
final class DrawioModelWriter {
    private static let maximumValueBytes = 8_192
    private static let maximumStyleValueBytes = 512
    private static let attributeOrder = ["id", "label", "value", "style", "vertex", "edge", "source", "target", "parent", "as",
                                         "x", "y", "width", "height", "relative"]

    private struct Pending {
        let name: String
        let attributes: [String: String]
        let depth: Int
    }

    private let context: RequestContext
    private var bytes: [UInt8] = []
    private var pending: Pending?
    private var depth = 0
    private var elements = 0
    private(set) var sensitive: [SensitiveRange] = []

    init(context: RequestContext) {
        self.context = context
        bytes.reserveCapacity(4_096)
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }
    var isEmpty: Bool { bytes.isEmpty && pending == nil }

    func start(_ name: String, attributes: [String: String]) throws {
        if elements.isMultiple(of: 64) { try context.checkpoint() }
        try flushPending(hasChildren: true)
        elements += 1
        guard elements <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        depth += 1
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        pending = Pending(name: name, attributes: attributes, depth: depth)
    }

    func end(_ name: String) throws {
        if let pending {
            try emit(pending, selfClosing: true)
            self.pending = nil
        } else {
            append(String(repeating: " ", count: max(depth - 1, 0) * 2) + "</" + name + ">\n")
            try checkOutput()
        }
        depth -= 1
    }

    private func flushPending(hasChildren: Bool) throws {
        guard let pending else { return }
        try emit(pending, selfClosing: !hasChildren)
        self.pending = nil
    }

    private func emit(_ element: Pending, selfClosing: Bool) throws {
        append(String(repeating: " ", count: (element.depth - 1) * 2) + "<" + element.name)
        let names = element.attributes.keys.sorted { lhs, rhs in
            let left = Self.attributeOrder.firstIndex(of: lhs) ?? Self.attributeOrder.count
            let right = Self.attributeOrder.firstIndex(of: rhs) ?? Self.attributeOrder.count
            return left != right ? left < right : lhs < rhs
        }
        for name in names {
            guard let raw = element.attributes[name] else { continue }
            append(" " + name + "=\"")
            try appendValue(Self.bounded(raw, attribute: name), attribute: name)
            append("\"")
        }
        append(selfClosing ? "/>\n" : ">\n")
        try checkOutput()
    }

    /// Escapes a value into the output and records which parts to conceal.
    private func appendValue(_ value: String, attribute: String) throws {
        let scalars = Array(value.unicodeScalars)
        let spans = SecretFieldPolicy.isSensitive(attribute)
            ? (scalars.isEmpty ? [] : [0..<scalars.count])
            : try DiagramLabelPrivacy.spans(in: value, context: context)
        // Spans are ascending and disjoint: close the open one when its end is reached, then open the next.
        var next = 0
        var open: (start: Int, end: Int)?
        for (index, scalar) in scalars.enumerated() {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            if let current = open, index == current.end {
                try record(current.start..<bytes.count)
                open = nil
            }
            if open == nil, next < spans.count, spans[next].lowerBound == index {
                open = (bytes.count, spans[next].upperBound)
                next += 1
            }
            appendEscaped(scalar)
        }
        if let current = open { try record(current.start..<bytes.count) }
    }

    private func record(_ range: Range<Int>) throws {
        guard !range.isEmpty else { return }
        guard sensitive.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        sensitive.append(SensitiveRange(utf8Range: range))
    }

    private func appendEscaped(_ scalar: Unicode.Scalar) {
        switch scalar {
        case "&": bytes.append(contentsOf: Array("&amp;".utf8))
        case "<": bytes.append(contentsOf: Array("&lt;".utf8))
        case ">": bytes.append(contentsOf: Array("&gt;".utf8))
        case "\"": bytes.append(contentsOf: Array("&quot;".utf8))
        case "\n": bytes.append(contentsOf: Array("&#10;".utf8))
        case "\r": bytes.append(contentsOf: Array("&#13;".utf8))
        case "\t": bytes.append(contentsOf: Array("&#9;".utf8))
        default:
            if scalar.value < 0x20 { return }
            bytes.append(contentsOf: Array(String(scalar).utf8))
        }
    }

    private func append(_ text: String) { bytes.append(contentsOf: Array(text.utf8)) }

    private func checkOutput() throws {
        guard bytes.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
    }

    /// Shortens a value to a size a single line can hold. Style strings first lose oversized
    /// `key=value` pairs, which is where embedded image data lives.
    static func bounded(_ value: String, attribute: String) -> String {
        guard value.utf8.count > 256 else { return value }
        var result = value
        if attribute == "style" {
            result = value.split(separator: ";", omittingEmptySubsequences: true)
                .filter { $0.utf8.count <= maximumStyleValueBytes }.joined(separator: ";")
        }
        guard result.utf8.count > maximumValueBytes else { return result }
        var shortened = ""
        var size = 0
        for character in result {
            size += String(character).utf8.count
            if size > maximumValueBytes { break }
            shortened.append(character)
        }
        return shortened + "…"
    }
}

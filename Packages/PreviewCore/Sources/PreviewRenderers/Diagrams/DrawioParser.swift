import CoreGraphics
import Foundation

/// The cells of one draw.io page (`mxGraphModel`), as written by the format adapter. Colors,
/// images, links and custom data are not part of this model: only geometry, text and the shape
/// and arrow words of the style string.
struct DrawioModel: Equatable, Sendable {
    struct Geometry: Equatable, Sendable {
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
        var isRelative = false
        var points: [CGPoint] = []
        var sourcePoint: CGPoint?
        var targetPoint: CGPoint?
    }

    struct Cell: Equatable, Sendable {
        var id: String
        var parent: String?
        var value: String
        var style: String
        var isVertex: Bool
        var isEdge: Bool
        var source: String?
        var target: String?
        var isVisible: Bool
        var geometry: Geometry?
    }

    var cells: [Cell]
}

/// The `key=value;` words of a draw.io style string. Keys are matched case-insensitively and the
/// number of pairs is bounded; nothing in a style string is executed or fetched.
struct DrawioStyle: Equatable, Sendable {
    private(set) var tokens: Set<String> = []
    private(set) var values: [String: String] = [:]

    init(_ style: String) {
        var pairs = 0
        for piece in style.split(separator: ";", omittingEmptySubsequences: true) {
            guard pairs < DiagramLimits.maximumDrawioStylePairs else { break }
            pairs += 1
            if let equals = piece.firstIndex(of: "=") {
                let key = piece[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
                values[key] = String(piece[piece.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            } else {
                tokens.insert(piece.trimmingCharacters(in: .whitespaces).lowercased())
            }
        }
    }

    func value(_ key: String) -> String? { values[key.lowercased()] }
    func isOn(_ key: String) -> Bool { values[key.lowercased()] == "1" }
    func double(_ key: String) -> Double? {
        guard let text = value(key), let number = Double(text), number.isFinite else { return nil }
        return number
    }
    func has(_ token: String) -> Bool { tokens.contains(token.lowercased()) }
}

/// Reads an `mxGraphModel` document with `XMLParser`, which never loads external entities or
/// resources here. The element count and nesting are bounded, and a DTD is refused before parsing.
enum DrawioParser {
    static func parse(_ source: String) throws -> DrawioModel {
        guard source.utf8.count <= DiagramLimits.maximumSourceUTF8Bytes * 4 else { throw DiagramFailure.tooLarge }
        let lowered = source.lowercased()
        guard !lowered.contains("<!doctype"), !lowered.contains("<!entity") else { throw DiagramFailure.malformed }
        let reader = DrawioModelReader()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        guard parser.parse(), reader.failure == nil else { throw reader.failure ?? DiagramFailure.malformed }
        guard reader.sawModel, !reader.cells.isEmpty else { throw DiagramFailure.malformed }
        return DrawioModel(cells: reader.cells)
    }
}

private final class DrawioModelReader: NSObject, XMLParserDelegate {
    var cells: [DrawioModel.Cell] = []
    var failure: DiagramFailure?
    var sawModel = false
    private var depth = 0
    private var elements = 0
    private var wrapper: (id: String, label: String)?
    private var currentCell: Int?
    private var geometry: DrawioModel.Geometry?
    private var pointRole: String?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String]) {
        depth += 1
        elements += 1
        guard depth <= DiagramLimits.maximumDrawioDepth, elements <= DiagramLimits.maximumDrawioCells * 4 else {
            failure = .tooLarge
            parser.abortParsing()
            return
        }
        switch name {
        case "mxGraphModel":
            sawModel = true
        case "object", "UserObject", "XmlObject":
            wrapper = (attributeDict["id"] ?? "", attributeDict["label"] ?? attributeDict["value"] ?? "")
        case "mxCell":
            guard cells.count < DiagramLimits.maximumDrawioCells else {
                failure = .tooLarge
                parser.abortParsing()
                return
            }
            let id = attributeDict["id"] ?? wrapper?.id ?? ""
            let value = attributeDict["value"] ?? wrapper?.label ?? ""
            cells.append(.init(id: id, parent: attributeDict["parent"], value: value, style: attributeDict["style"] ?? "",
                               isVertex: attributeDict["vertex"] == "1", isEdge: attributeDict["edge"] == "1",
                               source: attributeDict["source"], target: attributeDict["target"],
                               isVisible: attributeDict["visible"] != "0", geometry: nil))
            currentCell = cells.count - 1
            wrapper = nil
        case "mxGeometry":
            guard currentCell != nil else { return }
            var value = DrawioModel.Geometry()
            value.x = Self.number(attributeDict["x"])
            value.y = Self.number(attributeDict["y"])
            value.width = Self.number(attributeDict["width"])
            value.height = Self.number(attributeDict["height"])
            value.isRelative = attributeDict["relative"] == "1"
            geometry = value
        case "Array":
            pointRole = attributeDict["as"]
        case "mxPoint":
            guard geometry != nil else { return }
            let point = CGPoint(x: Self.number(attributeDict["x"]), y: Self.number(attributeDict["y"]))
            switch attributeDict["as"] ?? pointRole {
            case "sourcePoint": geometry?.sourcePoint = point
            case "targetPoint": geometry?.targetPoint = point
            case "points":
                if geometry?.points.count ?? 0 < DiagramLimits.maximumEdgeWaypoints { geometry?.points.append(point) }
            default: break
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        depth -= 1
        switch name {
        case "mxGeometry":
            if let index = currentCell, let geometry { cells[index].geometry = geometry }
            geometry = nil
        case "Array": pointRole = nil
        case "mxCell": currentCell = nil
        case "object", "UserObject", "XmlObject": wrapper = nil
        default: break
        }
    }

    /// Numbers are clamped so a hostile coordinate cannot produce an enormous scene.
    private static func number(_ text: String?) -> Double {
        guard let text, let value = Double(text), value.isFinite else { return 0 }
        return min(max(value, -1_000_000), 1_000_000)
    }
}

import Foundation

/// Re-parses concealed XML for presentation only. External resources and declarations stay
/// disabled here as well as in the adapter, including manually constructed presentations.
enum SafeXMLDocument {
    static func nodes(_ source: String) -> [SafeOutlineNode]? {
        guard source.utf16.prefix(262_145).count <= 262_144,
              !source.contains("<!DOCTYPE"), !source.contains("<!ENTITY") else { return nil }
        let delegate = Builder()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse(), !delegate.failed else { return nil }
        return delegate.roots.map { $0.freeze() }
    }
    private final class Node {
        let id: Int
        let name: String
        var text = ""
        var children: [Node] = []
        init(id: Int, name: String) { self.id = id; self.name = name }
        func freeze() -> SafeOutlineNode {
            .init(id: id, name: name, value: text.trimmingCharacters(in: .whitespacesAndNewlines), children: children.map { $0.freeze() })
        }
    }
    private final class Builder: NSObject, XMLParserDelegate {
        var roots: [Node] = []
        var stack: [Node] = []
        var nextID = 0
        var characters = 0
        var failed = false
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            guard nextID + attributeDict.count < 20_000, stack.count < 64 else { failed = true; parser.abortParsing(); return }
            let node = Node(id: nextID, name: elementName); nextID += 1
            for key in attributeDict.keys.sorted() {
                let attribute = Node(id: nextID, name: "@" + key); nextID += 1
                attribute.text = attributeDict[key] ?? ""; node.children.append(attribute)
            }
            if let parent = stack.last { parent.children.append(node) } else { roots.append(node) }
            stack.append(node)
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            characters += string.utf16.count
            guard characters <= 262_144 else { failed = true; parser.abortParsing(); return }
            stack.last?.text.append(string)
        }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let text = String(data: CDATABlock, encoding: .utf8) else { failed = true; parser.abortParsing(); return }
            self.parser(parser, foundCharacters: text)
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    }
}

import Foundation
import PreviewContracts

/// Drives `XMLParser` over request-owned bytes with the limits the geographic formats need.
///
/// External entities are never resolved and no network or file access is possible through the
/// parser. Documents that declare any `<!ENTITY` are rejected outright, since neither GPX nor KML
/// needs a DTD and entity expansion is the usual amplification vector. Element nesting is capped by
/// the request's `maxJSONDepth`, and the parse is aborted when the request is cancelled or its
/// deadline passes. Parsing is event-driven: the document is never held as a tree.
enum GeoXML {
    static func run(_ data: Data, delegate: GeoXMLDelegate, context: RequestContext) throws {
        try context.checkpoint()
        guard data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        guard data.range(of: Data("<!ENTITY".utf8)) == nil else { throw PreviewFailure.malformedDocument }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        delegate.attach(parser)
        parser.delegate = delegate
        let completed = parser.parse()
        if let failure = delegate.failure { throw failure }
        guard completed else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
    }
}

/// Common event handling: depth and checkpoint limits, an element-name stack and bounded text
/// capture. Subclasses override the two element hooks and request text for elements they need.
class GeoXMLDelegate: NSObject, XMLParserDelegate {
    let context: RequestContext
    private(set) var failure: (any Error)?
    /// Local names (prefix removed) of the open elements, outermost first.
    private(set) var stack: [String] = []
    private weak var parser: XMLParser?
    private var events = 0
    private var captured: String?
    private var captureLimit = 0
    private var captureFull = false

    init(context: RequestContext) {
        self.context = context
        super.init()
    }

    func attach(_ parser: XMLParser) { self.parser = parser }

    /// Called after the element is pushed onto `stack`.
    func elementStarted(_ name: String, qualifiedName: String, attributes: [String: String]) {}
    /// Called before the element is popped; `text` is the captured text when one was requested.
    func elementEnded(_ name: String, qualifiedName: String, text: String?) {}

    /// Starts collecting character data for the current element, up to `limit` UTF-8 bytes.
    final func captureText(limit: Int) {
        captured = ""
        captureLimit = limit
        captureFull = false
    }

    /// The local name of the element `levels` above the current one (1 = parent).
    final func ancestor(_ levels: Int) -> String? {
        let index = stack.count - 1 - levels
        return stack.indices.contains(index) ? stack[index] : nil
    }

    final func fail(_ error: any Error) {
        if failure == nil { failure = error }
        parser?.abortParsing()
    }

    // MARK: XMLParserDelegate

    final func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard failure == nil else { return }
        guard tick() else { return }
        guard stack.count < context.budget.maxJSONDepth else { fail(PreviewFailure.structureTooDeep); return }
        stack.append(Self.localName(elementName))
        captured = nil
        elementStarted(stack[stack.count - 1], qualifiedName: elementName, attributes: attributeDict)
    }

    final func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                      qualifiedName qName: String?) {
        guard failure == nil, !stack.isEmpty else { return }
        let text = captured
        captured = nil
        elementEnded(stack[stack.count - 1], qualifiedName: elementName, text: text)
        stack.removeLast()
    }

    final func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard captured != nil, failure == nil else { return }
        append(string)
    }

    final func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard captured != nil, failure == nil else { return }
        append(String(decoding: CDATABlock, as: UTF8.self))
    }

    private func append(_ string: String) {
        guard !captureFull else { return }
        captured?.append(string)
        if let count = captured?.utf8.count, count > captureLimit {
            captured = String(decoding: Array((captured ?? "").utf8.prefix(captureLimit)), as: UTF8.self)
            captureFull = true
        }
    }

    private func tick() -> Bool {
        events += 1
        guard events.isMultiple(of: 256) else { return true }
        do { try context.checkpoint() } catch { fail(error); return false }
        return true
    }

    static func localName(_ qualified: String) -> String {
        guard let colon = qualified.lastIndex(of: ":") else { return qualified }
        return String(qualified[qualified.index(after: colon)...])
    }
}

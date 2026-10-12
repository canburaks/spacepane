import Foundation
import PreviewContracts

/// Guard rails for the XMLParser-based readers: depth and node ceilings taken from the request
/// budget, periodic cancellation checks, no external entities, and no DTD at all. A document type
/// declaration, entity, notation or attribute-list declaration aborts the parse, so entity
/// expansion cannot amplify the input. Subclasses override only `startElement` and `endElement`.
class BoundedXMLDelegate: NSObject, XMLParserDelegate {
    let context: RequestContext
    private let maximumDepth: Int
    private let maximumNodes: Int
    private(set) var depth = 0
    /// Elements and namespace declarations seen so far.
    private(set) var nodes = 0
    private(set) var failure: Error?
    private var prefixes: [String: String] = [:]
    private static let maximumPrefixes = 64

    init(context: RequestContext, nodeAllowance: Int) {
        self.context = context
        maximumDepth = context.budget.maxJSONDepth
        maximumNodes = nodeAllowance
    }

    /// Called for each element with its local name and namespace URI ("" when it has none).
    func startElement(_ name: String, namespace: String, attributes: [String: String]) throws {}
    func endElement(_ name: String, namespace: String) throws {}

    /// Runs the parser over bounded bytes and rethrows the first typed failure.
    final func run(_ data: Data) throws {
        // These formats never carry a document type declaration. Refusing any outright means no
        // entity, internal or external, is ever declared; the delegate callbacks below cover
        // encodings in which this byte search cannot see the declaration.
        let declaresDocumentType = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress, raw.count >= 9 else { return false }
            return memmem(base, raw.count, "<!DOCTYPE", 9) != nil
        }
        guard !declaresDocumentType else { throw PreviewFailure.malformedDocument }
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        let parsed = withExtendedLifetime(self) { parser.parse() }
        if let failure { throw failure }
        guard parsed else { throw PreviewFailure.malformedDocument }
    }

    /// A namespaced attribute written with any prefix bound to `namespace`, such as `p:path`.
    final func attribute(_ local: String, namespace: String, in attributes: [String: String]) -> String? {
        for (key, value) in attributes {
            guard let colon = key.firstIndex(of: ":"), key[key.index(after: colon)...] == local,
                  prefixes[String(key[..<colon])] == namespace else { continue }
            return value
        }
        return nil
    }

    private func abort(_ error: Error, _ parser: XMLParser) {
        if failure == nil { failure = error }
        parser.abortParsing()
    }

    // MARK: XMLParserDelegate

    final func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                      qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard failure == nil else { return }
        depth += 1
        nodes += 1
        guard depth <= maximumDepth else { return abort(PreviewFailure.structureTooDeep, parser) }
        guard nodes <= maximumNodes else { return abort(PreviewFailure.tooManyNodes, parser) }
        do {
            if nodes & 0xFFF == 0 { try context.checkpoint() }
            try startElement(elementName, namespace: namespaceURI ?? "", attributes: attributeDict)
        } catch { abort(error, parser) }
    }

    final func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                      qualifiedName qName: String?) {
        guard failure == nil else { return }
        depth -= 1
        do { try endElement(elementName, namespace: namespaceURI ?? "") } catch { abort(error, parser) }
    }

    final func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        guard failure == nil else { return }
        nodes += 1
        guard prefixes.count < Self.maximumPrefixes, nodes <= maximumNodes else {
            return abort(PreviewFailure.tooManyNodes, parser)
        }
        prefixes[prefix] = namespaceURI
    }

    final func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        abort(PreviewFailure.malformedDocument, parser)
    }

    final func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        abort(PreviewFailure.malformedDocument, parser)
    }

    final func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?,
                      systemID: String?, notationName: String?) {
        abort(PreviewFailure.malformedDocument, parser)
    }

    final func parser(_ parser: XMLParser, foundNotationDeclarationWithName name: String, publicID: String?, systemID: String?) {
        abort(PreviewFailure.malformedDocument, parser)
    }

    final func parser(_ parser: XMLParser, foundAttributeDeclarationWithName attributeName: String, forElement elementName: String,
                      type: String?, defaultValue: String?) {
        abort(PreviewFailure.malformedDocument, parser)
    }

    final func parser(_ parser: XMLParser, foundElementDeclarationWithName elementName: String, model: String) {
        abort(PreviewFailure.malformedDocument, parser)
    }

    final func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        abort(PreviewFailure.malformedDocument, parser)
        return nil
    }
}

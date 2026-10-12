import Foundation
import PreviewContracts

/// Extracts the first page of a draw.io document as normalized `mxGraphModel` XML.
///
/// A `.drawio` file is an `mxfile` holding one `diagram` per page. A page is either the plain
/// model as child XML, or compressed text: base64 of a raw DEFLATE stream of the percent-encoded
/// model. Everything is bounded and read-only. DTDs and entity declarations are refused before
/// parsing, `XMLParser` never resolves external entities or URLs, and decompression, base64 and
/// percent-decoding all enforce an output cap before allocation.
enum DrawioDocumentReader {
    struct Page {
        let text: String
        let sensitive: [SensitiveRange]
        let pageCount: Int
    }

    static func firstPage(of source: String, context: RequestContext) throws -> Page {
        try context.checkpoint()
        try rejectDeclarations(in: source, context: context)
        let outer = OuterReader(context: context)
        try run(source, delegate: outer, context: context)
        guard outer.sawRoot else { throw PreviewFailure.malformedDocument }
        let writer = outer.writer
        if !writer.isEmpty {
            return Page(text: writer.text, sensitive: writer.sensitive, pageCount: max(outer.pageCount, 1))
        }
        guard outer.pageCount > 0 else { throw PreviewFailure.malformedDocument }
        let model = try decodeCompressed(outer.firstDiagramText, context: context)
        try rejectDeclarations(in: model, context: context)
        let inner = ModelReader(context: context)
        try run(model, delegate: inner, context: context)
        guard !inner.writer.isEmpty else { throw PreviewFailure.malformedDocument }
        return Page(text: inner.writer.text, sensitive: inner.writer.sensitive, pageCount: outer.pageCount)
    }

    // MARK: Decoding

    /// base64 → raw DEFLATE → percent-decoding. A page stored as percent-encoded XML skips the first two steps.
    static func decodeCompressed(_ text: String, context: RequestContext) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PreviewFailure.malformedDocument }
        let maximum = context.budget.maxOutputUTF8Bytes
        if trimmed.hasPrefix("<") { guard trimmed.utf8.count <= maximum else { throw PreviewFailure.outputTooLarge }; return trimmed }
        let encoded: String
        if trimmed.hasPrefix("%3C") || trimmed.hasPrefix("%3c") {
            encoded = trimmed
        } else {
            guard trimmed.utf8.count <= context.budget.maxInputBytes,
                  let compressed = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters), !compressed.isEmpty else {
                throw PreviewFailure.malformedDocument
            }
            try context.checkpoint()
            // Percent-encoding triples the size of non-ASCII text, so the inflated cap is three times the output cap.
            let inflated = try BoundedDecompression.rawDeflate(compressed, context: context, maximum: min(maximum * 3, 33_554_432))
            guard let decoded = String(data: inflated, encoding: .utf8) else { throw PreviewFailure.malformedDocument }
            encoded = decoded
        }
        try context.checkpoint()
        guard let model = encoded.removingPercentEncoding else { throw PreviewFailure.malformedDocument }
        guard model.utf8.count <= maximum else { throw PreviewFailure.outputTooLarge }
        return model
    }

    /// Refuses any `<!` construct other than comments and CDATA: no DOCTYPE, no ENTITY declarations.
    static func rejectDeclarations(in text: String, context: RequestContext) throws {
        let bytes = Array(text.utf8)
        var index = 0
        while index + 1 < bytes.count {
            if index.isMultiple(of: 4_096) { try context.checkpoint() }
            if bytes[index] == 60, bytes[index + 1] == 33 {
                let rest = bytes[(index + 2)...]
                let isComment = rest.starts(with: [45, 45])
                let isCDATA = rest.starts(with: Array("[CDATA[".utf8))
                guard isComment || isCDATA else { throw PreviewFailure.malformedDocument }
            }
            index += 1
        }
    }

    private static func run(_ text: String, delegate: DrawioReaderBase, context: RequestContext) throws {
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.externalEntityResolvingPolicy = .never
        delegate.parser = parser
        parser.delegate = delegate
        let succeeded = parser.parse()
        if let failure = delegate.failure { throw failure }
        guard succeeded else { throw PreviewFailure.malformedDocument }
    }

    // MARK: SAX readers

    /// Shared failure handling: callbacks cannot throw, so they record the failure and abort parsing.
    private class DrawioReaderBase: NSObject, XMLParserDelegate {
        let context: RequestContext
        var failure: (any Error)?
        weak var parser: XMLParser?
        init(context: RequestContext) { self.context = context }

        func guarded(_ body: () throws -> Void) {
            guard failure == nil else { return }
            do { try body() } catch { failure = error; parser?.abortParsing() }
        }
    }

    /// Reads an `mxfile`, `diagram` pages or a bare `mxGraphModel` root.
    private final class OuterReader: DrawioReaderBase {
        let writer: DrawioModelWriter
        private(set) var sawRoot = false
        private(set) var pageCount = 0
        private(set) var firstDiagramText = ""
        private var stack: [String] = []
        private var isWritingModel = false
        private var modelDepth = 0
        private var elements = 0

        override init(context: RequestContext) {
            writer = DrawioModelWriter(context: context)
            super.init(context: context)
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes attributeDict: [String: String]) {
            guarded {
                elements += 1
                guard elements <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                if elements.isMultiple(of: 64) { try context.checkpoint() }
                guard stack.count < context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
                if stack.isEmpty {
                    guard name == "mxfile" || name == "mxGraphModel" else { throw PreviewFailure.malformedDocument }
                    sawRoot = true
                    if name == "mxGraphModel" { pageCount = 1 }
                }
                if name == "diagram", stack.last == "mxfile" { pageCount += 1 }
                let startsFirstModel = name == "mxGraphModel" && !isWritingModel && writer.isEmpty
                    && ((stack.last == "diagram" && pageCount == 1) || stack.isEmpty)
                if startsFirstModel { isWritingModel = true; modelDepth = 0 }
                if isWritingModel {
                    modelDepth += 1
                    try writer.start(name, attributes: attributeDict)
                }
                stack.append(name)
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guarded {
                stack.removeLast()
                if isWritingModel {
                    try writer.end(name)
                    modelDepth -= 1
                    if modelDepth == 0 { isWritingModel = false }
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { collect(string) }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { collect(String(decoding: CDATABlock, as: UTF8.self)) }

        /// Text directly inside the first page is its compressed model.
        private func collect(_ text: String) {
            guarded {
                guard stack.last == "diagram", pageCount == 1 else { return }
                guard firstDiagramText.utf8.count + text.utf8.count <= context.budget.maxInputBytes else {
                    throw PreviewFailure.inputTooLarge
                }
                firstDiagramText += text
            }
        }
    }

    /// Reads the decompressed model, whose root must be `mxGraphModel`.
    private final class ModelReader: DrawioReaderBase {
        let writer: DrawioModelWriter
        private var depth = 0

        override init(context: RequestContext) {
            writer = DrawioModelWriter(context: context)
            super.init(context: context)
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes attributeDict: [String: String]) {
            guarded {
                if depth == 0 { guard name == "mxGraphModel" else { throw PreviewFailure.malformedDocument } }
                depth += 1
                try writer.start(name, attributes: attributeDict)
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guarded {
                depth -= 1
                try writer.end(name)
            }
        }
    }
}

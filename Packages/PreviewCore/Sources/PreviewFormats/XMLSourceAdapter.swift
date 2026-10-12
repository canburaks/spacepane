import Foundation
import PreviewContracts

/// Strict XML source validation. DTDs/entity declarations are rejected before Foundation
/// sees the input; this adapter never resolves external entities or runs XSLT.
public struct XMLSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        var scanner = XMLSourceScanner(bytes: Array(input.text.utf8), context: context)
        try scanner.scan()
        let parser = XMLParser(data: Data(input.text.utf8))
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        let delegate = XMLValidationDelegate(context: context)
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil else {
            if let failure = delegate.failure { throw failure }
            throw PreviewFailure.malformedDocument
        }
        try context.checkpoint()
        return ParsedTextDocument(text: input.text, sensitiveRanges: scanner.sensitive,
                                  usesStructuredPrivacy: true, syntax: .xml)
    }
}

private final class XMLValidationDelegate: NSObject, XMLParserDelegate {
    let context: RequestContext
    var failure: (any Error)?
    init(context: RequestContext) { self.context = context }
    func parser(_ parser: XMLParser, foundCharacters string: String) { checkpoint(parser) }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { checkpoint(parser) }
    private func checkpoint(_ parser: XMLParser) {
        do { try context.checkpoint() }
        catch { failure = error; parser.abortParsing() }
    }
}

/// The lexical scan establishes structure budgets and precise secret spans before native parsing.
struct XMLSourceScanner {
    let bytes: [UInt8]
    let context: RequestContext
    var index = 0
    var nodes = 0
    var sensitive: [SensitiveRange] = []
    /// Also treats every text run between tags as free text: a run that assigns a secret is concealed
    /// whole, leaving markup intact. Off for ordinary XML, whose element text is data; on for caption
    /// documents, whose element text is prose that may quote credentials.
    var annotatesTextRuns = false
    private var stack: [(name: String, contentStart: Int, sensitive: Bool)] = []

    init(bytes: [UInt8], context: RequestContext) { self.bytes = bytes; self.context = context }
    mutating func scan() throws {
        var textStart = 0
        while index < bytes.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            guard bytes[index] == 60 else { index += 1; continue }
            if textStart < index {
                if annotatesTextRuns { try annotateNonField(textStart..<index) }
                try annotateEscapedValue(textStart..<index)
            }
            if matches("<!--") {
                let contentStart = index + 4
                try skip(until: "-->")
                try annotateNonField(contentStart..<(index - 3))
                textStart = index
                continue
            }
            if matches("<![CDATA[") {
                let contentStart = index + 9
                try skip(until: "]]>")
                try annotateNonField(contentStart..<(index - 3))
                textStart = index
                continue
            }
            if matches("<?") {
                // Retain the instruction target and separator so concealment cannot
                // turn otherwise valid XML into malformed safe outline input.
                var contentStart = index + 2
                while contentStart < bytes.count, !whitespace(bytes[contentStart]), bytes[contentStart] != 63 {
                    if contentStart.isMultiple(of: 512) { try context.checkpoint() }
                    contentStart += 1
                }
                while contentStart < bytes.count, whitespace(bytes[contentStart]) { contentStart += 1 }
                try skip(until: "?>")
                try annotateNonField(contentStart..<(index - 2))
                textStart = index
                continue
            }
            guard !matches("<!") else { throw PreviewFailure.malformedDocument }
            let tagStart = index
            index += 1
            let closing = index < bytes.count && bytes[index] == 47
            if closing { index += 1 }
            let nameStart = index
            while index < bytes.count, ![9, 10, 13, 32, 47, 62].contains(bytes[index]) { index += 1 }
            guard index > nameStart else { throw PreviewFailure.malformedDocument }
            let name = String(decoding: bytes[nameStart..<index], as: UTF8.self)
            var selfClosing = false
            var sensitiveElement = SecretFieldPolicy.isSensitive(name)
            var namedValues: [Range<Int>] = []
            while index < bytes.count, bytes[index] != 62 {
                try context.checkpoint()
                if whitespace(bytes[index]) { index += 1; continue }
                if bytes[index] == 47 { selfClosing = true; index += 1; continue }
                guard !closing else { throw PreviewFailure.malformedDocument }
                let attributeStart = index
                while index < bytes.count, !whitespace(bytes[index]), ![61, 62].contains(bytes[index]) { index += 1 }
                nodes += 1
                guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                let attribute = String(decoding: bytes[attributeStart..<index], as: UTF8.self)
                while index < bytes.count, whitespace(bytes[index]) { index += 1 }
                guard index < bytes.count, bytes[index] == 61 else { throw PreviewFailure.malformedDocument }
                index += 1
                while index < bytes.count, whitespace(bytes[index]) { index += 1 }
                guard index < bytes.count, [34, 39].contains(bytes[index]) else { throw PreviewFailure.malformedDocument }
                let quote = bytes[index]; index += 1
                let valueStart = index
                while index < bytes.count, bytes[index] != quote {
                    if index.isMultiple(of: 512) { try context.checkpoint() }
                    index += 1
                }
                guard index < bytes.count else { throw PreviewFailure.malformedDocument }
                let valueRange = valueStart..<index
                if SecretFieldPolicy.isSensitive(attribute) { try addSensitive(valueRange) }
                switch SecretFieldPolicy.namedValueRole(attribute) {
                case .name:
                    let decodedName = try decoded(valueRange)
                    sensitiveElement = sensitiveElement || SecretFieldPolicy.isSensitive(decodedName)
                case .value: namedValues.append(valueRange)
                case nil: break
                }
                try annotateEscapedValue(valueRange)
                index += 1
            }
            guard index < bytes.count, bytes[index] == 62 else { throw PreviewFailure.malformedDocument }
            index += 1
            textStart = index
            if closing {
                guard let open = stack.popLast(), open.name == name else { throw PreviewFailure.malformedDocument }
                if open.sensitive, tagStart > open.contentStart { try addSensitive(open.contentStart..<tagStart) }
            } else {
                nodes += 1
                guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                guard stack.count + 1 <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
                if sensitiveElement { for range in namedValues { try addSensitive(range) } }
                if !selfClosing { stack.append((name, index, sensitiveElement)) }
            }
        }
        guard stack.isEmpty else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
    }
    private mutating func addSensitive(_ range: Range<Int>) throws {
        guard sensitive.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        sensitive.append(.init(utf8Range: range))
    }

    private mutating func annotateEscapedValue(_ range: Range<Int>) throws {
        guard bytes[range].contains(38) else { return }
        if try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded(range), originalText: String(decoding: bytes[range], as: UTF8.self), context: context) {
            try addSensitive(range)
        }
    }

    /// Reuse the inert entity decoder in bounded chunks, retaining both UTF-8 scalar and reference
    /// boundaries. DTDs/external references remain prohibited by this scanner and native validation.
    private func decoded(_ range: Range<Int>) throws -> String {
        var result = ""
        result.reserveCapacity(range.count)
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            try context.checkpoint()
            var end = min(range.upperBound, cursor + 4_096)
            if end < range.upperBound {
                while end > cursor, bytes[end] & 0xC0 == 0x80 { end -= 1 }
                let tail = max(cursor, end - HTMLEntities.maximumReferenceLength - 2)
                if let ampersand = bytes[tail..<end].lastIndex(of: 38), ampersand > cursor,
                   !bytes[ampersand..<end].contains(59) { end = ampersand }
            }
            result += HTMLEntities.decode(bytes[cursor..<end])
            cursor = end
        }
        try context.checkpoint()
        return result
    }

    private func matches(_ marker: String) -> Bool {
        let candidate = Array(marker.utf8)
        return index + candidate.count <= bytes.count && bytes[index..<(index + candidate.count)].elementsEqual(candidate)
    }
    private mutating func annotateNonField(_ content: Range<Int>) throws {
        if let range = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: content, context: context) {
            guard sensitive.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            sensitive.append(range)
        }
    }
    private mutating func skip(until marker: String) throws {
        let marker = Array(marker.utf8)
        index += 2
        while index + marker.count <= bytes.count {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            if bytes[index..<(index + marker.count)].elementsEqual(marker) { index += marker.count; return }
            index += 1
        }
        throw PreviewFailure.malformedDocument
    }
    private func whitespace(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
}

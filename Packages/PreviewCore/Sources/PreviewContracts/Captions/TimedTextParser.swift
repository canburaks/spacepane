import Foundation

/// TTML and DFXP: the `<p>` elements of a `<tt>` document become cues.
///
/// Only the timing and text of paragraphs are read. `begin`, `end` and `dur` must be valid TTML time
/// expressions when present: a clock time (`hh:mm:ss`, an optional fraction or `:frames`) or an offset
/// time (`10s`, `1.5m`, `250ms`, `24f`, `1000t`); they are shown as written and never converted, because
/// frame and tick rates live in attributes this parser does not interpret. `<br/>` is a line break,
/// `<span>` and other inline elements contribute their text, and whitespace collapses as in
/// `xml:space="default"`. Styles, regions, layout, `<metadata>` and scripting are inert. A document type
/// declaration or entity declaration is rejected before Foundation sees the input, external entities
/// are never resolved, and nesting, cue count and cue size are bounded.
enum TimedTextParser {
    static func parse(_ bytes: [UInt8], limits: CaptionLimits, checkpoint: () throws -> Void) throws -> CaptionDocument {
        try checkpoint()
        // Declarations are the only way XML names external or recursive content; refuse them outright.
        let text = String(decoding: bytes, as: UTF8.self)
        guard !text.contains("<!DOCTYPE"), !text.contains("<!ENTITY"), !text.contains("<!doctype") else {
            throw PreviewFailure.malformedDocument
        }
        // The delegate only lives for this call, so the non-escaping checkpoint may be lent to it.
        let cues: [CaptionCue] = try withoutActuallyEscaping(checkpoint) { poll in
            let parser = XMLParser(data: Data(bytes))
            parser.shouldResolveExternalEntities = false
            parser.externalEntityResolvingPolicy = .never
            let builder = Builder(limits: limits, checkpoint: poll)
            parser.delegate = builder
            let parsed = parser.parse()
            if let failure = builder.failure { throw failure }
            guard parsed, builder.rootIsTT else { throw PreviewFailure.malformedDocument }
            return builder.cues
        }
        try checkpoint()
        return CaptionDocument(cues: cues)
    }

    // MARK: Time expressions

    static func isTimeExpression(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return false }
        if bytes.contains(58) { return isClock(bytes) }
        return isOffset(bytes)
    }

    private static func isClock(_ bytes: [UInt8]) -> Bool {
        let parts = bytes.split(separator: 58, omittingEmptySubsequences: false)
        guard parts.count == 3 || parts.count == 4, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        func digits(_ part: ArraySlice<UInt8>) -> Bool { part.allSatisfy { $0 >= 48 && $0 <= 57 } }
        func fractional(_ part: ArraySlice<UInt8>, wholeDigits: Int) -> Bool {
            let pieces = part.split(separator: 46, maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count >= 1, pieces[pieces.startIndex].count == wholeDigits, digits(pieces[pieces.startIndex]) else { return false }
            return pieces.count == 1 || (!pieces[pieces.startIndex + 1].isEmpty && digits(pieces[pieces.startIndex + 1]))
        }
        func twoDigitValue(_ part: ArraySlice<UInt8>) -> Int? {
            let head = part.prefix(2)
            guard head.count == 2, digits(head) else { return nil }
            return Int(head[head.startIndex] - 48) * 10 + Int(head[head.startIndex + 1] - 48)
        }
        guard parts[parts.startIndex].count >= 2, digits(parts[parts.startIndex]),
              parts[parts.startIndex + 1].count == 2, digits(parts[parts.startIndex + 1]),
              let minutes = twoDigitValue(parts[parts.startIndex + 1]), minutes <= 59,
              let seconds = twoDigitValue(parts[parts.startIndex + 2]), seconds <= 59 else { return false }
        if parts.count == 3 { return fractional(parts[parts.startIndex + 2], wholeDigits: 2) }
        return parts[parts.startIndex + 2].count == 2 && digits(parts[parts.startIndex + 2])
            && fractional(parts[parts.startIndex + 3], wholeDigits: 2)
    }

    private static func isOffset(_ bytes: [UInt8]) -> Bool {
        var index = 0
        var integerDigits = 0
        while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1; integerDigits += 1 }
        guard integerDigits > 0 else { return false }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            var fractionDigits = 0
            while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 { index += 1; fractionDigits += 1 }
            guard fractionDigits > 0 else { return false }
        }
        let unit = String(decoding: bytes[index...], as: UTF8.self)
        return ["h", "m", "s", "ms", "f", "t"].contains(unit)
    }

    // MARK: Delegate

    private final class Builder: NSObject, XMLParserDelegate {
        let limits: CaptionLimits
        let checkpoint: () throws -> Void
        var failure: PreviewFailure?
        var cues: [CaptionCue] = []
        var rootIsTT = false
        private var depth = 0
        private var paragraph: (start: String, end: String?, text: String)?
        private static let lineBreak = "\u{1}"

        init(limits: CaptionLimits, checkpoint: @escaping () throws -> Void) {
            self.limits = limits
            self.checkpoint = checkpoint
        }

        private func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

        private func fail(_ parser: XMLParser, _ error: PreviewFailure) {
            failure = failure ?? error
            parser.abortParsing()
        }

        private func poll(_ parser: XMLParser) {
            do { try checkpoint() }
            catch let error as PreviewFailure { fail(parser, error) }
            catch { failure = failure ?? .deadlineExceeded; parser.abortParsing() }
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            poll(parser)
            depth += 1
            guard depth <= limits.maximumDepth else { return fail(parser, .structureTooDeep) }
            let name = local(elementName)
            if depth == 1 {
                rootIsTT = name == "tt"
                guard rootIsTT else { return fail(parser, .malformedDocument) }
                return
            }
            if name == "p", paragraph == nil {
                guard cues.count < limits.maximumCues else { return fail(parser, .tooManyNodes) }
                let begin = attributeDict["begin"]
                let end = attributeDict["end"]
                let duration = attributeDict["dur"]
                for value in [begin, end, duration].compactMap({ $0 }) where !TimedTextParser.isTimeExpression(value) {
                    return fail(parser, .malformedDocument)
                }
                paragraph = (begin ?? "", end ?? duration.map { "+" + $0 }, "")
            } else if name == "br", paragraph != nil {
                paragraph?.text += Self.lineBreak
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            poll(parser)
            guard paragraph != nil else { return }
            paragraph?.text += string
            if (paragraph?.text.utf8.count ?? 0) > limits.maximumCueTextUTF8Bytes { fail(parser, .malformedDocument) }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard paragraph != nil else { return }
            guard let text = String(data: CDATABlock, encoding: .utf8) else { return fail(parser, .malformedDocument) }
            self.parser(parser, foundCharacters: text)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if local(elementName) == "p", let finished = paragraph, depth > 1 {
                paragraph = nil
                let lines = finished.text.components(separatedBy: Self.lineBreak).map(Self.collapsed)
                cues.append(CaptionCue(start: finished.start, end: finished.end,
                                       lines: lines.allSatisfy(\.isEmpty) ? [] : lines))
            }
            depth -= 1
        }

        /// `xml:space="default"` whitespace: runs collapse to one space and the ends are trimmed.
        private static func collapsed(_ text: String) -> String {
            text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
        }
    }
}

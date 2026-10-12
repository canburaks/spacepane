import Foundation
import PreviewContracts

struct MarkupAttribute: Equatable, Sendable {
    /// Lowercased name without a namespace prefix: `href` for `xlink:href`.
    let name: String
    /// Lowercased name exactly as written: `epub:type`.
    let qualifiedName: String
    let value: String
}

enum MarkupEvent: Equatable, Sendable {
    case start(name: String, attributes: [MarkupAttribute], selfClosing: Bool)
    case end(name: String)
    /// Character references are already decoded.
    case text(String)
}

/// Elements that never have content in HTML. XML-structured documents (package files, FictionBook)
/// pass an empty set so a self-closing tag is the only way to end an element early.
enum HTMLVoidElements {
    static let names: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
                                     "source", "track", "wbr"]
}

/// A tolerant, bounded tokenizer shared by every ebook and web-archive format. It reads valid UTF-8 text
/// and produces start tags, end tags and decoded text. It never loads a resource, never expands a declared
/// entity (DOCTYPE, processing instructions and comments are skipped) and never evaluates anything, so
/// malformed XHTML, HTML and mixed-case tags are tolerated rather than rejected.
///
/// Work is charged to the request: the cooperative checkpoint runs at regular intervals while scanning,
/// every tag is limited to `maximumTagBytes`, and at most `maximumAttributes` attributes are kept.
struct MarkupTokenizer {
    static let maximumTagBytes = 65_536
    static let maximumAttributes = 64
    static let maximumAttributeValueBytes = 4_096

    private let bytes: [UInt8]
    private let context: RequestContext
    private let rawTextElements: Set<String>
    private let voidElements: Set<String>
    private var position = 0
    private var pendingRawText: String?
    private var work = 0
    /// Number of events produced so far; callers use it to enforce node budgets.
    private(set) var eventCount = 0

    init(_ text: String, rawTextElements: Set<String> = ["script", "style"],
         voidElements: Set<String> = HTMLVoidElements.names, context: RequestContext) {
        bytes = Array(text.utf8)
        self.context = context
        self.rawTextElements = rawTextElements
        self.voidElements = voidElements
    }

    /// Returns the next event, or `nil` at the end of input.
    mutating func next() throws -> MarkupEvent? {
        while true {
            try tick(32)
            if let raw = pendingRawText {
                pendingRawText = nil
                try skipRawText(named: raw)
                continue
            }
            guard position < bytes.count else { return nil }
            if bytes[position] != Byte.lessThan {
                eventCount += 1
                return try text()
            }
            if let event = try markup() {
                eventCount += 1
                return event
            }
        }
    }

    // MARK: Scanning

    private enum Byte {
        static let lessThan: UInt8 = 60, greaterThan: UInt8 = 62, slash: UInt8 = 47, bang: UInt8 = 33
        static let question: UInt8 = 63, equals: UInt8 = 61, doubleQuote: UInt8 = 34, singleQuote: UInt8 = 39
        static let openBracket: UInt8 = 91, closeBracket: UInt8 = 93, dash: UInt8 = 45
    }

    private mutating func tick(_ units: Int) throws {
        work += units
        if work >= 4_096 {
            work = 0
            try context.checkpoint()
        }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 || byte == 12 }
    private func isNameStart(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 || byte == 58 || byte >= 128
    }

    private mutating func text() throws -> MarkupEvent {
        let start = position
        while position < bytes.count, bytes[position] != Byte.lessThan { position += 1 }
        try tick(position - start)
        return .text(HTMLEntities.decode(bytes[start..<position]))
    }

    private func matches(_ marker: String, at index: Int) -> Bool {
        let candidate = Array(marker.utf8)
        guard index + candidate.count <= bytes.count else { return false }
        return bytes[index..<(index + candidate.count)].elementsEqual(candidate)
    }

    /// Index of the first occurrence of `marker` at or after `from`, or `nil`.
    private mutating func find(_ marker: String, from: Int) throws -> Int? {
        let needle = Array(marker.utf8)
        guard let first = needle.first, bytes.count >= needle.count else { return nil }
        var index = from
        let last = bytes.count - needle.count
        while index <= last {
            if bytes[index] == first, bytes[index..<(index + needle.count)].elementsEqual(needle) {
                try tick(index - from)
                return index
            }
            index += 1
        }
        try tick(bytes.count - from)
        return nil
    }

    /// Handles a construct starting with `<`. Returns `nil` when the construct produces no event.
    private mutating func markup() throws -> MarkupEvent? {
        let start = position
        guard start + 1 < bytes.count else {
            position += 1
            return .text("<")
        }
        let next = bytes[start + 1]
        if next == Byte.bang {
            if matches("<!--", at: start) {
                position = try find("-->", from: start + 4).map { $0 + 3 } ?? bytes.count
                return nil
            }
            if matches("<![CDATA[", at: start) {
                let contentStart = start + 9
                let end = try find("]]>", from: contentStart)
                position = end.map { $0 + 3 } ?? bytes.count
                let content = bytes[contentStart..<(end ?? bytes.count)]
                return content.isEmpty ? nil : .text(String(decoding: content, as: UTF8.self))
            }
            try skipDeclaration(from: start)
            return nil
        }
        if next == Byte.question {
            if let end = try find("?>", from: start + 2) { position = end + 2 }
            else if let end = try find(">", from: start + 2) { position = end + 1 }
            else { position = bytes.count }
            return nil
        }
        if next == Byte.slash { return try endTag(from: start) }
        guard isNameStart(next) else {
            position += 1
            return .text("<")
        }
        return try startTag(from: start)
    }

    /// `<!DOCTYPE …>` including an internal subset in brackets. The content is discarded, never interpreted.
    private mutating func skipDeclaration(from start: Int) throws {
        var index = start + 2
        var depth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == Byte.openBracket { depth += 1 }
            else if byte == Byte.closeBracket, depth > 0 { depth -= 1 }
            else if byte == Byte.greaterThan, depth == 0 { break }
            index += 1
            if index - start > Self.maximumTagBytes * 16 { break }
        }
        try tick(index - start)
        position = min(bytes.count, index + 1)
    }

    private mutating func endTag(from start: Int) throws -> MarkupEvent? {
        var index = start + 2
        let nameStart = index
        while index < bytes.count, !isWhitespace(bytes[index]), bytes[index] != Byte.greaterThan,
              bytes[index] != Byte.slash { index += 1 }
        let name = Self.localName(of: bytes[nameStart..<index])
        while index < bytes.count, bytes[index] != Byte.greaterThan {
            index += 1
            if index - start > Self.maximumTagBytes { break }
        }
        try tick(index - start)
        position = min(bytes.count, index + 1)
        return name.isEmpty ? nil : .end(name: name)
    }

    private mutating func startTag(from start: Int) throws -> MarkupEvent? {
        var index = start + 1
        let nameStart = index
        while index < bytes.count, !isWhitespace(bytes[index]), bytes[index] != Byte.greaterThan,
              bytes[index] != Byte.slash { index += 1 }
        let name = Self.localName(of: bytes[nameStart..<index])
        var attributes: [MarkupAttribute] = []
        var selfClosing = false
        var closed = false
        let limit = min(bytes.count, start + Self.maximumTagBytes)
        scan: while index < limit {
            let byte = bytes[index]
            if isWhitespace(byte) { index += 1; continue }
            if byte == Byte.greaterThan { index += 1; closed = true; break }
            if byte == Byte.slash {
                if index + 1 < bytes.count, bytes[index + 1] == Byte.greaterThan {
                    selfClosing = true
                    index += 2
                    closed = true
                    break scan
                }
                index += 1
                continue
            }
            let attributeStart = index
            while index < limit, !isWhitespace(bytes[index]), bytes[index] != Byte.equals,
                  bytes[index] != Byte.greaterThan, bytes[index] != Byte.slash { index += 1 }
            if index == attributeStart { index += 1; continue }
            let qualified = String(decoding: bytes[attributeStart..<index], as: UTF8.self).lowercased()
            while index < limit, isWhitespace(bytes[index]) { index += 1 }
            var value = ""
            if index < limit, bytes[index] == Byte.equals {
                index += 1
                while index < limit, isWhitespace(bytes[index]) { index += 1 }
                if index < limit, bytes[index] == Byte.doubleQuote || bytes[index] == Byte.singleQuote {
                    let quote = bytes[index]
                    index += 1
                    let valueStart = index
                    while index < limit, bytes[index] != quote { index += 1 }
                    value = Self.attributeValue(bytes[valueStart..<index])
                    if index < limit { index += 1 }
                } else {
                    let valueStart = index
                    while index < limit, !isWhitespace(bytes[index]), bytes[index] != Byte.greaterThan { index += 1 }
                    value = Self.attributeValue(bytes[valueStart..<index])
                }
            }
            if attributes.count < Self.maximumAttributes {
                attributes.append(MarkupAttribute(name: Self.localAttributeName(qualified), qualifiedName: qualified, value: value))
            }
        }
        try tick(index - start)
        guard closed else {
            // No terminating `>` within the tag bound. Dropping the scanned span (rather than rescanning
            // from the next `<`) keeps a run of unterminated tags linear in the input size.
            position = index
            return nil
        }
        position = index
        if voidElements.contains(name) { selfClosing = true }
        if !selfClosing, rawTextElements.contains(name) { pendingRawText = name }
        return .start(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    /// Discards the content of a raw-text element (script, style, base64 payloads) up to its end tag. The
    /// end tag itself is left for the next call so tree builders see a balanced pair.
    private mutating func skipRawText(named name: String) throws {
        let marker = Array("</\(name)".utf8)
        var index = position
        while index + marker.count <= bytes.count {
            if bytes[index] == Byte.lessThan, matchesCaseInsensitive(marker, at: index) {
                let after = index + marker.count
                if after >= bytes.count || isWhitespace(bytes[after]) || bytes[after] == Byte.greaterThan
                    || bytes[after] == Byte.slash {
                    try tick(index - position)
                    position = index
                    return
                }
            }
            index += 1
        }
        try tick(bytes.count - position)
        position = bytes.count
    }

    private func matchesCaseInsensitive(_ marker: [UInt8], at index: Int) -> Bool {
        for (offset, expected) in marker.enumerated() {
            var byte = bytes[index + offset]
            if (65...90).contains(byte) { byte += 32 }
            if byte != expected { return false }
        }
        return true
    }

    private static func attributeValue(_ slice: ArraySlice<UInt8>) -> String {
        HTMLEntities.decode(slice.prefix(maximumAttributeValueBytes))
    }

    /// Lowercased element name with any namespace prefix removed.
    private static func localName(of slice: ArraySlice<UInt8>) -> String {
        localAttributeName(String(decoding: slice, as: UTF8.self).lowercased())
    }

    private static func localAttributeName(_ qualified: String) -> String {
        guard let colon = qualified.lastIndex(of: ":") else { return qualified }
        return String(qualified[qualified.index(after: colon)...])
    }
}

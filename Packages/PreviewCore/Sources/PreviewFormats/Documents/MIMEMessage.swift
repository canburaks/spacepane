import Foundation
import PreviewContracts

/// Header fields of one MIME entity. Names are lowercased; folded lines are joined with a single space.
struct MIMEHeaders: Equatable, Sendable {
    static let maximumBytes = 65_536
    static let maximumFields = 256

    private(set) var fields: [(name: String, value: String)] = []

    static func == (lhs: MIMEHeaders, rhs: MIMEHeaders) -> Bool {
        lhs.fields.count == rhs.fields.count && zip(lhs.fields, rhs.fields).allSatisfy { $0 == $1 }
    }

    func value(_ name: String) -> String? { fields.first { $0.name == name }?.value }

    init(_ bytes: ArraySlice<UInt8>) {
        let text = String(decoding: bytes.prefix(Self.maximumBytes), as: UTF8.self)
        var current: (name: String, value: String)?
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine[...]
            if let first = line.first, first == " " || first == "\t" {
                current?.value += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let finished = current, fields.count < Self.maximumFields { fields.append(finished) }
            current = nil
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, !name.contains(" ") else { continue }
            current = (name, line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        if let finished = current, fields.count < Self.maximumFields { fields.append(finished) }
    }
}

/// `type/subtype; parameter=value` with quoted-string parameters.
struct MIMEContentType: Equatable, Sendable {
    var type = "text"
    var subtype = "plain"
    var parameters: [String: String] = [:]

    var essence: String { "\(type)/\(subtype)" }

    init(_ header: String?) {
        guard let header, !header.isEmpty else { return }
        var pieces: [String] = []
        var current = ""
        var quoted = false
        for character in header {
            if character == "\"" { quoted.toggle() }
            if character == ";", !quoted { pieces.append(current); current = ""; continue }
            current.append(character)
        }
        pieces.append(current)
        let essence = pieces[0].trimmingCharacters(in: .whitespaces).lowercased().split(separator: "/", maxSplits: 1)
        if essence.count == 2 { type = String(essence[0]); subtype = String(essence[1]) }
        for piece in pieces.dropFirst().prefix(16) {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let name = piece[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            if !name.isEmpty { parameters[name] = value }
        }
    }
}

/// One MIME entity: its headers and the byte range of its (still encoded) body.
struct MIMEEntity: Sendable {
    let headers: MIMEHeaders
    let contentType: MIMEContentType
    let body: Range<Int>
    var contentID: String? { headers.value("content-id")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")) }
    var location: String? { headers.value("content-location") ?? headers.value("snapshot-content-location") }
    var transferEncoding: String { headers.value("content-transfer-encoding")?.lowercased() ?? "7bit" }
}

/// A bounded MIME multipart reader for saved web pages. It splits entities on their boundaries and decodes
/// only the part the caller asks for; nothing is fetched, rendered or evaluated.
enum MIMEMessage {
    static let maximumParts = 500
    static let maximumDepth = 4

    /// Parses `bytes` into the top-level entity and every leaf entity in document order. A message that is
    /// not multipart has itself as its only leaf.
    static func parse(_ bytes: [UInt8], context: RequestContext) throws -> (top: MIMEEntity, leaves: [MIMEEntity]) {
        guard let top = try entity(in: bytes, range: 0..<bytes.count, context: context), !top.headers.fields.isEmpty else {
            throw PreviewFailure.malformedDocument
        }
        var leaves: [MIMEEntity] = []
        try collect(top, in: bytes, depth: 0, into: &leaves, context: context)
        return (top, leaves)
    }

    private static func entity(in bytes: [UInt8], range: Range<Int>, context: RequestContext) throws -> MIMEEntity? {
        try context.checkpoint()
        guard let split = headerEnd(in: bytes, range: range) else { return nil }
        let headers = MIMEHeaders(bytes[range.lowerBound..<split.headerEnd])
        return MIMEEntity(headers: headers, contentType: MIMEContentType(headers.value("content-type")),
                          body: split.bodyStart..<range.upperBound)
    }

    /// The blank line that ends the headers: LF LF or CRLF CRLF. A range that begins with a blank line has no headers.
    private static func headerEnd(in bytes: [UInt8], range: Range<Int>) -> (headerEnd: Int, bodyStart: Int)? {
        var index = range.lowerBound
        let limit = min(range.upperBound, range.lowerBound + MIMEHeaders.maximumBytes)
        while index < limit {
            if bytes[index] == 10 {
                if index + 1 < range.upperBound, bytes[index + 1] == 10 { return (index, index + 2) }
                if index + 2 < range.upperBound, bytes[index + 1] == 13, bytes[index + 2] == 10 { return (index, index + 3) }
            }
            index += 1
        }
        // Headers that run to the end of the range with no body at all.
        return index >= range.upperBound ? (range.upperBound, range.upperBound) : nil
    }

    private static func collect(_ entity: MIMEEntity, in bytes: [UInt8], depth: Int, into leaves: inout [MIMEEntity],
                                context: RequestContext) throws {
        guard entity.contentType.type == "multipart", let boundary = entity.contentType.parameters["boundary"], !boundary.isEmpty,
              depth < maximumDepth else {
            leaves.append(entity)
            return
        }
        for range in try partRanges(in: bytes, body: entity.body, boundary: boundary, context: context) {
            guard leaves.count < maximumParts else { return }
            if let part = try self.entity(in: bytes, range: range, context: context) {
                try collect(part, in: bytes, depth: depth + 1, into: &leaves, context: context)
            }
        }
    }

    /// Byte ranges between `--boundary` delimiter lines. The line break before a delimiter belongs to the
    /// delimiter, as RFC 2046 specifies.
    private static func partRanges(in bytes: [UInt8], body: Range<Int>, boundary: String,
                                   context: RequestContext) throws -> [Range<Int>] {
        let delimiter = Array(("--" + boundary).utf8)
        var starts: [(delimiterStart: Int, contentStart: Int, isClosing: Bool)] = []
        var index = body.lowerBound
        let last = body.upperBound - delimiter.count
        var checks = 0
        while index <= last, starts.count <= maximumParts + 1 {
            checks += 1
            if checks.isMultiple(of: 4_096) { try context.checkpoint() }
            guard bytes[index] == delimiter[0], index == body.lowerBound || bytes[index - 1] == 10,
                  bytes[index..<(index + delimiter.count)].elementsEqual(delimiter) else { index += 1; continue }
            let after = index + delimiter.count
            // The boundary must end the delimiter line: a longer boundary that merely starts with it is content.
            guard after >= body.upperBound || [10, 13, 32, 9, 45].contains(bytes[after]) else { index += 1; continue }
            let isClosing = after + 1 < body.upperBound && bytes[after] == 45 && bytes[after + 1] == 45
            var lineEnd = after
            while lineEnd < body.upperBound, bytes[lineEnd] != 10 { lineEnd += 1 }
            starts.append((index, min(body.upperBound, lineEnd + 1), isClosing))
            if isClosing { break }
            index = lineEnd
        }
        var ranges: [Range<Int>] = []
        for (position, start) in starts.enumerated() where !start.isClosing {
            let nextStart = position + 1 < starts.count ? starts[position + 1].delimiterStart : body.upperBound
            var end = nextStart
            if end > start.contentStart, bytes[end - 1] == 10 { end -= 1 }
            if end > start.contentStart, bytes[end - 1] == 13 { end -= 1 }
            if end >= start.contentStart { ranges.append(start.contentStart..<end) }
        }
        return ranges
    }

    // MARK: Body decoding

    /// The decoded bytes of `entity`'s body. Only base64, quoted-printable and identity encodings are known.
    static func decodedBody(of entity: MIMEEntity, in bytes: [UInt8], context: RequestContext) throws -> Data {
        try context.checkpoint()
        let slice = bytes[entity.body]
        switch entity.transferEncoding {
        case "base64":
            let text = String(decoding: slice, as: UTF8.self)
            return Data(base64Encoded: text, options: .ignoreUnknownCharacters) ?? Data()
        case "quoted-printable":
            return try quotedPrintable(slice, context: context)
        default:
            return Data(slice)
        }
    }

    static func quotedPrintable(_ bytes: ArraySlice<UInt8>, context: RequestContext) throws -> Data {
        var output = Data()
        output.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if index.isMultiple(of: 8_192) { try context.checkpoint() }
            let byte = bytes[index]
            guard byte == 61 else { output.append(byte); index += 1; continue }
            // `=` at a line end is a soft break; `=XX` is one byte; anything else stays literal.
            if index + 1 < bytes.endIndex, bytes[index + 1] == 10 { index += 2; continue }
            if index + 2 < bytes.endIndex, bytes[index + 1] == 13, bytes[index + 2] == 10 { index += 3; continue }
            if index + 2 < bytes.endIndex, let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) {
                output.append(UInt8(high << 4 | low))
                index += 3
                continue
            }
            if index + 1 == bytes.endIndex { index += 1; continue }
            output.append(byte)
            index += 1
        }
        return output
    }

    private static func hex(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: Int(byte) - 48
        case 65...70: Int(byte) - 55
        case 97...102: Int(byte) - 87
        default: nil
        }
    }

    // MARK: Header text

    /// Decodes RFC 2047 encoded words (`=?utf-8?B?…?=`) in a header value.
    static func decodeHeaderText(_ value: String) -> String {
        guard value.contains("=?"), value.utf8.count <= 4_096,
              let pattern = try? NSRegularExpression(pattern: #"=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?="#) else { return value }
        let source = value as NSString
        var result = ""
        var cursor = 0
        var previousWasEncoded = false
        for match in pattern.matches(in: value, range: NSRange(location: 0, length: source.length)) {
            let gap = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            // Whitespace between two adjacent encoded words is not part of the text.
            if !(previousWasEncoded && gap.allSatisfy(\.isWhitespace)) { result += gap }
            let charset = source.substring(with: match.range(at: 1))
            let isBase64 = source.substring(with: match.range(at: 2)).lowercased() == "b"
            let payload = source.substring(with: match.range(at: 3))
            var decoded: Data?
            if isBase64 { decoded = Data(base64Encoded: payload) }
            else {
                let bytes = Array(payload.replacingOccurrences(of: "_", with: " ").utf8)
                decoded = try? quotedPrintable(bytes[...], context: RequestContext(budget: .standard))
            }
            let encoding = MarkupDecoder.encoding(named: charset.split(separator: "*").first.map(String.init) ?? charset) ?? .utf8
            if let decoded, let text = String(data: decoded, encoding: encoding) {
                result += text
            } else {
                result += source.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
            previousWasEncoded = true
        }
        result += source.substring(from: cursor)
        return result
    }
}

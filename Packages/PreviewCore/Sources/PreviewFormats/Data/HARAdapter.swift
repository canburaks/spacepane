import Foundation
import PreviewContracts

/// HTTP Archive (HAR 1.2) captures: tool and browser identity, page and entry counts, and a table
/// of the first requests.
///
/// The document is walked with the cursor reader, so headers, cookies, post data, response
/// bodies, timings and every other member are skipped without being decoded. The table shows only
/// method, scheme + host + path, status, MIME type, size and total time. Credentials in a URL's
/// authority and the fragment are dropped, and every query value is replaced by a concealed
/// placeholder (the value itself never enters the document); parameter names remain.
public struct HARAdapter: BinaryFormatAdapter {
    public init() {}

    static let maximumRows = 300
    private static let maximumQueryParameters = 8

    private struct Log {
        var found = false
        var version: String?
        var creator: String?
        var browser: String?
        var pageCount = 0
        var entryCount = 0
        var sawEntries = false
        var table = DataTable(kind: .identifiers,
                              columns: ["method", "url", "status", "mimeType", "size", "time"],
                              limits: .init(maximumRows: HARAdapter.maximumRows, maximumCellCharacters: 300,
                                            maximumBytes: 140_000))
    }

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        var reader = DataJSONReader(bytes: [UInt8](input.data), context: context)
        var log = Log()
        try reader.document { reader in
            guard try reader.peekKind() == .object else { throw PreviewFailure.malformedDocument }
            try reader.forEachMember(depth: 1) { key, reader in
                guard key == "log", try reader.peekKind() == .object else { return }
                log.found = true
                try Self.readLog(&reader, into: &log, context: context)
            }
        }
        guard log.found, log.sawEntries else { throw PreviewFailure.malformedDocument }
        return try Self.document(log, context: context)
    }

    // MARK: Reading

    private static func readLog(_ reader: inout DataJSONReader, into log: inout Log, context: RequestContext) throws {
        try reader.forEachMember(depth: 2) { key, reader in
            switch key {
            case "version": log.version = try optionalString(&reader, limit: 32)
            case "creator": log.creator = try identity(&reader)
            case "browser": log.browser = try identity(&reader)
            case "pages":
                guard try reader.peekKind() == .array else { return }
                try reader.forEachElement(depth: 3) { _, _ in log.pageCount += 1 }
            case "entries":
                guard try reader.peekKind() == .array else { return }
                log.sawEntries = true
                try reader.forEachElement(depth: 3) { _, reader in
                    log.entryCount += 1
                    guard try reader.peekKind() == .object else { return }
                    if log.table.isFull { log.table.markTruncated(); return }
                    log.table.append(try readEntry(&reader, context: context))
                }
            default: return
            }
        }
    }

    private struct Fields {
        var method = ""
        var url = ""
        var status: Double?
        var mimeType = ""
        var contentSize: Double?
        var bodySize: Double?
        var time: Double?
    }

    private static func readEntry(_ reader: inout DataJSONReader, context: RequestContext) throws -> [DataCell] {
        var fields = Fields()
        try reader.forEachMember(depth: 4) { key, reader in
            switch key {
            case "time": fields.time = try optionalNumber(&reader)
            case "request":
                guard try reader.peekKind() == .object else { return }
                try reader.forEachMember(depth: 5) { key, reader in
                    switch key {
                    case "method": fields.method = try optionalString(&reader, limit: 16) ?? ""
                    case "url": fields.url = try optionalString(&reader, limit: 4_096) ?? ""
                    default: return
                    }
                }
            case "response":
                guard try reader.peekKind() == .object else { return }
                try reader.forEachMember(depth: 5) { key, reader in
                    switch key {
                    case "status": fields.status = try optionalNumber(&reader)
                    case "bodySize": fields.bodySize = try optionalNumber(&reader)
                    case "content":
                        guard try reader.peekKind() == .object else { return }
                        try reader.forEachMember(depth: 6) { key, reader in
                            switch key {
                            case "size": fields.contentSize = try optionalNumber(&reader)
                            case "mimeType": fields.mimeType = try optionalString(&reader, limit: 128) ?? ""
                            default: return
                            }
                        }
                    default: return
                    }
                }
            default: return
            }
        }
        let size = [fields.contentSize, fields.bodySize].compactMap { $0 }.first { $0 >= 0 }
        return [
            .text(fields.method.uppercased()),
            .segments(displayURL(fields.url)),
            .text(fields.status.flatMap { Int(exactly: $0.rounded()) }.map(String.init) ?? ""),
            .text(String(fields.mimeType.split(separator: ";", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)),
            .text(size.flatMap { Int64(exactly: $0.rounded()) }.map(String.init) ?? ""),
            .text(fields.time.flatMap { $0 >= 0 ? String(format: "%.1f", $0) : nil } ?? "")
        ]
    }

    /// `name` and `version` of a creator or browser object, joined as the tools write them.
    private static func identity(_ reader: inout DataJSONReader) throws -> String? {
        guard try reader.peekKind() == .object else { return nil }
        var name = "", version = ""
        try reader.forEachMember(depth: 3) { key, reader in
            switch key {
            case "name": name = try optionalString(&reader, limit: 100) ?? ""
            case "version": version = try optionalString(&reader, limit: 50) ?? ""
            default: return
            }
        }
        let joined = [name, version].filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// A string value, or nil without consuming a value of another kind.
    private static func optionalString(_ reader: inout DataJSONReader, limit: Int) throws -> String? {
        guard try reader.peekKind() == .string else { return nil }
        return try reader.string(maximumBytes: limit).text
    }

    private static func optionalNumber(_ reader: inout DataJSONReader) throws -> Double? {
        guard try reader.peekKind() == .number else { return nil }
        let span = try reader.numberSpan()
        guard let value = Double(reader.lexeme(span)), value.isFinite else { return nil }
        return value
    }

    // MARK: URLs

    /// The parts of a URL that are shown, as segments. Concealed query values are single-character
    /// placeholders, so the document never holds the real value.
    static func displayURL(_ raw: String) -> [(text: String, sensitive: Bool)] {
        var text = raw
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        var query: String?
        if let mark = text.firstIndex(of: "?") {
            query = String(text[text.index(after: mark)...])
            text = String(text[..<mark])
        }
        var base = text
        if let range = text.range(of: "://") {
            let scheme = text[..<range.lowerBound]
            let rest = text[range.upperBound...]
            let authorityEnd = rest.firstIndex(of: "/") ?? rest.endIndex
            var authority = rest[..<authorityEnd]
            // Credentials before an `@` never appear.
            if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
            base = String(scheme) + "://" + String(authority) + String(rest[authorityEnd...])
        } else if let colon = text.firstIndex(of: ":"), text[..<colon].allSatisfy({ $0.isLetter }) {
            // `data:`, `javascript:` and similar carry their payload after the colon; it is not shown.
            let scheme = text[...colon].lowercased()
            if ["about:", "mailto:"].contains(scheme) == false { base = scheme + "…" }
        }
        var segments: [(text: String, sensitive: Bool)] = []
        guard let query, !query.isEmpty else { return [(DataTable.clip(base, to: 300).0, false)] }
        // Each parameter is written as separate parts: its name, the equals sign and a concealed
        // placeholder. Keeping name and `=` apart stops the shared assignment heuristic from also
        // concealing the host and path that precede a secret-looking name; no value is ever present.
        segments.append((DataTable.clip(base, to: 300).0 + "?", false))
        let parameters = query.split(separator: "&", omittingEmptySubsequences: true)
        for (index, parameter) in parameters.prefix(maximumQueryParameters).enumerated() {
            let parts = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            segments.append(((index > 0 ? "&" : "") + DataTable.clip(String(parts[0]), to: 64).0, false))
            guard parts.count == 2 else { continue }
            segments.append(("=", false))
            if !parts[1].isEmpty { segments.append(("x", true)) }
        }
        if parameters.count > maximumQueryParameters { segments.append(("&…", false)) }
        return segments
    }

    // MARK: Presentation

    private static func document(_ log: Log, context: RequestContext) throws -> ParsedTextDocument {
        var members: [(String, SummaryValue)] = [("dataFormat", .string("HAR"))]
        if let version = DataDocument.string(log.version, clippedTo: 32) { members.append(("formatVersion", version)) }
        if let creator = DataDocument.string(log.creator) { members.append(("creator", creator)) }
        if let browser = DataDocument.string(log.browser) { members.append(("browser", browser)) }
        members.append(("pageCount", .integer(log.pageCount)))
        members.append(("entryCount", .integer(log.entryCount)))
        if log.entryCount > log.table.rows.count { members.append(("partial", .boolean(true))) }
        if !log.table.rows.isEmpty { members.append((DataSummaryKeys.table, log.table.summary)) }
        return try DataDocument.make(members, context: context)
    }
}

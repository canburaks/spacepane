import Foundation
import Synchronization
import PreviewContracts

/// Limits are cumulative per request, including payload bytes skipped while scanning.
struct ContainerLimits {
    let context: RequestContext
    var maxEntries: Int { min(10_000, context.budget.maxJSONNodes) }
    var maxDecodedBytes: Int { min(67_108_864, context.budget.maxInputBytes.multipliedReportingOverflow(by: 64).partialValue) }
    var maxMetadataBytes: Int { min(4_194_304, context.budget.maxOutputUTF8Bytes) }
    var maxDirectoryBytes: Int { min(8_388_608, context.budget.maxInputBytes) }
    func validateInput(_ data: Data) throws {
        try context.checkpoint()
        guard data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
    }
}

struct BinaryCursor {
    let bytes: [UInt8]
    var offset: Int = 0
    var remaining: Int { bytes.count - offset }
    init(_ data: Data) { bytes = Array(data) }
    mutating func read(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw PreviewFailure.malformedDocument }
        let result = bytes[offset..<(offset + count)]
        offset += count
        return result
    }
    mutating func integer(_ width: Int, littleEndian: Bool = false) throws -> UInt64 {
        guard (1...8).contains(width) else { throw PreviewFailure.malformedDocument }
        let part = try read(width)
        return (littleEndian ? Array(part.reversed()) : Array(part)).reduce(0) { ($0 << 8) | UInt64($1) }
    }
    func integer(at offset: Int, width: Int, littleEndian: Bool = false) throws -> UInt64 {
        guard offset >= 0, offset <= bytes.count else { throw PreviewFailure.malformedDocument }
        var copy = self
        copy.offset = offset
        return try copy.integer(width, littleEndian: littleEndian)
    }
}

final class DataByteSource: PreviewByteSource {
    let data: Data
    private let reads = Mutex(0)
    var byteCount: Int64 { Int64(data.count) }
    init(_ data: Data) { self.data = data }
    func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard offset >= 0, offset <= byteCount, count >= 0, Int64(count) <= byteCount - offset else { throw PreviewFailure.malformedDocument }
        try reads.withLock { bytes in
            guard count <= context.budget.maxInputBytes - bytes else { throw PreviewFailure.inputTooLarge }
            bytes += count
        }
        let start = Int(offset)
        return data.subdata(in: start..<(start + count))
    }
}

func boundedInt(_ value: UInt64) throws -> Int {
    guard value <= UInt64(Int.max) else { throw PreviewFailure.malformedDocument }
    return Int(value)
}

/// Decoded entry names are listed exactly as stored, including absolute paths, drive letters and `..`
/// components: listing never extracts, so `ArchiveRiskAnalyzer` reports them instead of failing the
/// archive. Names that cannot be shown as inert text still fail: empty names, NUL and other C0 controls.
func listableArchivePath(_ path: String) throws -> String {
    guard !path.isEmpty, !path.unicodeScalars.contains(where: { $0.value < 32 }) else {
        throw PreviewFailure.malformedDocument
    }
    return path
}

/// The strict form for formats that resolve or read members by name (EPUB, comics, application
/// packages, 3MF, installer tables of contents, torrent file lists): absolute paths, drive letters
/// and `..` components are refused as malformed rather than listed.
func safeArchivePath(_ path: String) throws -> String {
    let listed = try listableArchivePath(path)
    guard !listed.hasPrefix("/"), !listed.hasPrefix("\\"),
          !listed.replacingOccurrences(of: "\\", with: "/").split(separator: "/").contains(".."),
          !(listed.count >= 2 && listed[listed.index(after: listed.startIndex)] == ":") else {
        throw PreviewFailure.malformedDocument
    }
    return listed
}

enum SummaryValue {
    case string(String, sensitive: Bool = false), integer(Int), boolean(Bool), null
    case array([SummaryValue]), object([(String, SummaryValue)])
}

/// JSON escaping and privacy ranges are generated together before presentation.
struct SummaryWriter {
    let context: RequestContext
    private(set) var text = ""
    private(set) var ranges: [SensitiveRange] = []
    private var nodes = 0
    private var outputBytes = 0
    // Explicit: the synthesized memberwise initializer is private because of the private counters, and the
    // hosted compiler rejects its use from other files.
    init(context: RequestContext) { self.context = context }
    mutating func document(_ value: SummaryValue, findings: [PreviewFinding] = [],
                           facts: PresentationFacts = .none) throws -> ParsedTextDocument {
        try write(value, depth: 0)
        // Every summary is app-made text about the file, never the file's own text.
        return ParsedTextDocument(text: text, sensitiveRanges: ranges, usesStructuredPrivacy: true, syntax: .json,
                                  findings: findings, origin: .summary, facts: facts)
    }
    private mutating func append(_ value: String) throws {
        let count = value.utf8.count
        guard outputBytes + count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        outputBytes += count
        text += value
    }
    private mutating func write(_ value: SummaryValue, depth: Int) throws {
        try context.checkpoint()
        nodes += 1
        guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        switch value {
        case let .string(string, sensitive):
            guard string.utf8.count <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let escaped = String(decoding: try encoder.encode(string), as: UTF8.self)
            let start = outputBytes + 1
            try append(escaped)
            if (sensitive || containsSensitiveAssignment(string)) && escaped.utf8.count > 2 {
                ranges.append(SensitiveRange(utf8Range: start..<(outputBytes - 1)))
            }
        case let .integer(number): try append(String(number))
        case let .boolean(flag): try append(flag ? "true" : "false")
        case .null: try append("null")
        case let .array(values):
            try append("[")
            for (index, item) in values.enumerated() {
                if index > 0 { try append(",") }
                try append("\n" + String(repeating: "  ", count: depth + 1))
                try write(item, depth: depth + 1)
            }
            if !values.isEmpty { try append("\n" + String(repeating: "  ", count: depth)) }
            try append("]")
        case let .object(values):
            try append("{")
            for (index, pair) in values.enumerated() {
                if index > 0 { try append(",") }
                try append("\n" + String(repeating: "  ", count: depth + 1))
                try write(.string(pair.0), depth: depth + 1)
                try append(": ")
                try write(pair.1, depth: depth + 1)
            }
            if !values.isEmpty { try append("\n" + String(repeating: "  ", count: depth)) }
            try append("}")
        }
    }
    /// Compiled once per writer: a listing writes thousands of strings and each one is checked.
    private let assignmentPattern = try? NSRegularExpression(pattern: #"(?i)(?<![a-z0-9_.\#(SecretFieldPolicy.invisibleKeyCharacterClass)-])([a-z_\#(SecretFieldPolicy.invisibleKeyCharacterClass)][a-z0-9_.\#(SecretFieldPolicy.invisibleKeyCharacterClass)-]*)[\t ]*[:=]"#)
    private func containsSensitiveAssignment(_ string: String) -> Bool {
        guard let pattern = assignmentPattern else { return true }
        let source = string as NSString
        return pattern.matches(in: string, range: NSRange(location: 0, length: source.length)).contains {
            SecretFieldPolicy.isSensitive(source.substring(with: $0.range(at: 1)))
        }
    }
}

enum ContainerEntryKind: String {
    case file, directory, symlink, hardlink, special
}

/// What a listing already read about one entry. Adapters fill the facts their format exposes and
/// `ArchiveRiskAnalyzer` derives every risk from them; nothing is read beyond the listing.
struct ContainerEntry {
    let path: String
    let kind: String
    let size: Int?
    /// Bytes the archive stores for the entry, when the format records them per entry.
    var storedSize: Int?
    /// Unix mode bits, only when the format records them from a Unix host.
    var mode: UInt32?
    /// Target text of a symbolic or hard link. `nil` when it was not read or cannot be represented.
    var linkTarget: String?
    /// Modification time, written as `modified` only when known so existing listings keep their exact output.
    var modified: Date?
    var isEncrypted: Bool
    /// Direct children of a folder, written as `items` only when the adapter counted them exactly.
    var itemCount: Int?

    init(path: String, kind: String, size: Int?, storedSize: Int? = nil, mode: UInt32? = nil,
         linkTarget: String? = nil, modified: Date? = nil, isEncrypted: Bool = false, itemCount: Int? = nil) {
        self.path = path
        self.kind = kind
        self.size = size
        self.storedSize = storedSize
        self.mode = mode
        self.linkTarget = linkTarget
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.itemCount = itemCount
    }
    init(path: String, kind: ContainerEntryKind, size: Int?, storedSize: Int? = nil, mode: UInt32? = nil,
         linkTarget: String? = nil, modified: Date? = nil, isEncrypted: Bool = false, itemCount: Int? = nil) {
        self.init(path: path, kind: kind.rawValue, size: size, storedSize: storedSize, mode: mode,
                  linkTarget: linkTarget, modified: modified, isEncrypted: isEncrypted, itemCount: itemCount)
    }

    /// Number of fields `summary` writes without risks; `ListingBudget` prices an entry from it.
    /// Risk annotations are optional: `listingDocument` drops them when they would not fit.
    var fieldCount: Int { 3 + (modified == nil ? 0 : 1) + (isEncrypted ? 1 : 0) + (itemCount == nil ? 0 : 1) }

    /// Optional facts and `risks` are written only when present, so clean entries keep their exact summary.
    func summary(risks: [ArchiveEntryRisk] = []) -> SummaryValue {
        var fields: [(String, SummaryValue)] = [
            ("path", .string(path)), ("type", .string(kind)), ("bytes", size.map { .integer($0) } ?? .null)
        ]
        if let modified { fields.append(("modified", .string(modified.formatted(.iso8601)))) }
        if isEncrypted { fields.append(("encrypted", .boolean(true))) }
        if let itemCount { fields.append(("items", .integer(itemCount))) }
        if !risks.isEmpty { fields.append(("risks", .array(risks.map { .string($0.rawValue) }))) }
        return .object(fields)
    }
}

/// Admits listing entries only while the finished summary is certain to fit the shared writer's
/// node, line and byte budgets, so an oversized listing becomes a flagged partial listing instead
/// of failing as a whole. Every entry is priced before anything is written; the byte price is a
/// conservative upper bound (fixed JSON syntax plus the exactly escaped path), never an estimate
/// of the average.
struct ListingBudget {
    private let maxEntries: Int
    private var remainingNodes: Int
    private var remainingLines: Int
    private var remainingBytes: Int
    private(set) var admitted = 0

    /// `reservedNodes`, `reservedLines` and `reservedBytes` cover the root object's own fields.
    init(context: RequestContext, reservedNodes: Int = 64, reservedLines: Int = 48, reservedBytes: Int = 8_192) {
        let budget = context.budget
        maxEntries = ContainerLimits(context: context).maxEntries
        remainingNodes = budget.maxJSONNodes - reservedNodes
        remainingLines = budget.maxTextLines - reservedLines
        remainingBytes = budget.maxOutputUTF8Bytes - reservedBytes
    }

    /// Returns whether `entry` still fits. A refused entry leaves the budget unchanged.
    mutating func admit(_ entry: ContainerEntry) -> Bool {
        let nodes = 1 + 2 * entry.fieldCount
        let lines = 2 + entry.fieldCount
        let bytes = 256 + Self.escapedUTF8Count(entry.path)
        guard admitted < maxEntries, nodes <= remainingNodes, lines <= remainingLines, bytes <= remainingBytes else { return false }
        remainingNodes -= nodes
        remainingLines -= lines
        remainingBytes -= bytes
        admitted += 1
        return true
    }

    /// The writer rejects a single string above the line budget; such a path cannot be listed.
    static func fitsLine(_ entry: ContainerEntry, context: RequestContext) -> Bool {
        escapedUTF8Count(entry.path) + 2 <= context.budget.maxLineUTF8Bytes
    }

    /// Exact byte length of the JSON-escaped spelling, without the surrounding quotes.
    static func escapedUTF8Count(_ string: String) -> Int {
        var count = 0
        for byte in string.utf8 {
            switch byte {
            case 0x22, 0x5C, 0x08, 0x09, 0x0A, 0x0C, 0x0D: count += 2
            case 0x00..<0x20, 0x7F: count += 6
            default: count += 1
            }
        }
        return count
    }
}

/// `assessRisks` is for archives only: it adds per-entry risks and findings from `ArchiveRiskAnalyzer`.
/// `assessNameRisks` adds only shared name checks to a folder listing.
/// Per-entry annotations add summary nodes and bytes; when they alone exceed the budget the listing is
/// written without them, so a listing that fit before assessment never starts failing.
func listingDocument(format: String, entries: [ContainerEntry], context: RequestContext,
                     partial: Bool = false, extra: [(String, SummaryValue)] = [],
                     assessRisks: Bool = false, assessNameRisks: Bool = false,
                     findings added: [PreviewFinding] = []) throws -> ParsedTextDocument {
    let report: ArchiveRiskReport?
    if assessRisks { report = try ArchiveRiskAnalyzer.analyze(entries, context: context) }
    else if assessNameRisks { report = try ListingNameRiskAnalyzer.analyze(entries, context: context) }
    else { report = nil }
    func write(annotated: Bool) throws -> ParsedTextDocument {
        var writer = SummaryWriter(context: context)
        let summaries = entries.enumerated().map { index, entry in
            entry.summary(risks: annotated ? report?.entryRisks[index] ?? [] : [])
        }
        return try writer.document(.object([
            ("archiveFormat", .string(format)), ("listedEntries", .integer(entries.count)),
            ("partial", .boolean(partial)), ("entries", .array(summaries))
        ] + extra), findings: (report?.findings ?? []) + added)
    }
    guard let report, report.annotatesEntries else { return try write(annotated: false) }
    do { return try write(annotated: true) }
    catch PreviewFailure.tooManyNodes { return try write(annotated: false) }
    catch PreviewFailure.outputTooLarge { return try write(annotated: false) }
}

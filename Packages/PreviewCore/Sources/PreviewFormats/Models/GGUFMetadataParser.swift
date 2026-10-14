import Foundation
import PreviewContracts

/// A value kept for the other-metadata list: a scalar, or an array reduced to its item count.
/// (A value type of its own, because the compiler cannot infer `Sendable` for a struct that stores
/// `SummaryValue` tuples.)
enum GGUFOtherValue {
    case integer(Int), text(String, sensitive: Bool), boolean(Bool)

    var summary: SummaryValue {
        switch self {
        case .integer(let number): SummaryValue.integer(number)
        case .text(let text, let sensitive): SummaryValue.string(text, sensitive: sensitive)
        case .boolean(let flag): SummaryValue.boolean(flag)
        }
    }
}

struct GGUFOtherEntry {
    let key: String
    let value: GGUFOtherValue
    /// Whether the parser already scanned the whole string for hidden characters (named chat templates).
    var isScanned = false
}

/// The facts a GGUF header's key/value section holds. Large arrays are reduced to counts and strings are
/// clipped, so holding it costs a few kilobytes whatever the file declares.
struct GGUFMetadata {
    var name, architecture, sizeLabel, license, author, organization, quantizedBy, tokenizerModel: String?
    var fileTypeCode: UInt64?
    var chatTemplate: String?
    /// Byte length of the template as stored, even when its text was too large to keep.
    var chatTemplateBytes: Int?
    var vocabularySize: Int?
    var tags: [String] = []
    var languages: [String] = []
    var baseModelNames: [Int: String] = [:]
    var alignment: UInt64 = 32
    /// Numbers under keys of the form `<anything>.context_length` and its siblings, by full key.
    var architectureNumbers: [String: UInt64] = [:]
    /// Remaining scalar keys in file order, plus arrays as their item counts. Trimmed by `finish`.
    var other: [GGUFOtherEntry] = []
}

/// Reads the key/value section of a GGUF header (format version 2 or 3) without keeping what it
/// does not show: vocabularies and merge lists are walked and counted, numeric arrays are jumped over,
/// and a string above its cap is skipped. Strings that hold file text are scanned for hidden characters
/// as they are read, so the scan sees the whole string and not only the clipped copy.
struct GGUFMetadataParser {
    static let maximumEntries = 10_000
    static let maximumKeyBytes = 65_536
    static let maximumValueBytes = 1_048_576
    static let maximumArrayDepth = 4
    static let keptListItems = 16
    static let keptOtherEntries = 64
    static let maximumBaseModels = 64
    static let chatTemplateTextBytes = 8_192
    /// Escaped template text stays well inside the summary writer's 32 KiB line limit.
    static let chatTemplateEscapedBytes = 24_000

    /// Key suffixes whose numbers describe the architecture named by `general.architecture`.
    static let architectureSuffixes = [
        "context_length", "block_count", "embedding_length", "attention.head_count", "attention.head_count_kv",
        "expert_count", "expert_used_count"
    ]
    /// Entries kept before the architecture is known, so removing the keys that fill dedicated fields
    /// still leaves `keptOtherEntries`.
    private static let candidateLimit = keptOtherEntries + architectureSuffixes.count

    private(set) var metadata = GGUFMetadata()
    private(set) var hidden = ModelHiddenText()
    private var seenKeys = Set<String>()
    private let context: RequestContext

    init(context: RequestContext) { self.context = context }

    mutating func parse(count: Int, reader: inout GGUFByteReader) throws {
        for _ in 0..<count {
            try context.checkpoint()
            let key = try readKey(&reader)
            let typeCode = try reader.uint32()
            try readValue(key: key, typeCode: typeCode, reader: &reader)
        }
    }

    // MARK: Keys

    private func readKey(_ reader: inout GGUFByteReader) throws -> String {
        let length = try reader.uint64()
        guard length <= UInt64(Self.maximumKeyBytes) else { throw PreviewFailure.malformedDocument }
        return String(decoding: try reader.bytes(Int(length)), as: UTF8.self)
    }

    private enum Role {
        case name, architecture, sizeLabel, license, author, organization, quantizedBy, tokenizerModel
        case chatTemplate, baseModelName(Int)
        case fileType, alignment, tags, languages, tokens, architectureNumber

        init?(key: String) {
            switch key {
            case "general.name": self = .name
            case "general.architecture": self = .architecture
            case "general.size_label": self = .sizeLabel
            case "general.license": self = .license
            case "general.author": self = .author
            case "general.organization": self = .organization
            case "general.quantized_by": self = .quantizedBy
            case "tokenizer.ggml.model": self = .tokenizerModel
            case "tokenizer.chat_template": self = .chatTemplate
            case "general.file_type": self = .fileType
            case "general.alignment": self = .alignment
            case "general.tags": self = .tags
            case "general.languages": self = .languages
            case "tokenizer.ggml.tokens": self = .tokens
            default:
                if GGUFMetadataParser.architectureSuffixes.contains(where: { key.hasSuffix("." + $0) }) {
                    self = .architectureNumber
                } else if key.hasPrefix("general.base_model."), key.hasSuffix(".name"),
                          let index = Int(key.dropFirst("general.base_model.".count).dropLast(".name".count)),
                          (0..<GGUFMetadataParser.maximumBaseModels).contains(index) {
                    self = .baseModelName(index)
                } else {
                    return nil
                }
            }
        }
    }

    // MARK: Values

    private mutating func readValue(key: String, typeCode: UInt32, reader: inout GGUFByteReader) throws {
        let role = Role(key: key)
        switch typeCode {
        case 8: try readString(key: key, role: role, reader: &reader)
        case 9: try readArray(key: key, role: role, reader: &reader)
        case 0...7, 10...12: store(key: key, role: role, scalar: try readScalar(typeCode, reader: &reader))
        default: throw PreviewFailure.malformedDocument
        }
    }

    private enum Scalar {
        case unsigned(UInt64), signed(Int64), float(String), bool(Bool)

        var number: UInt64? {
            switch self {
            case .unsigned(let value): value
            case .signed(let value): value >= 0 ? UInt64(value) : nil
            case .float, .bool: nil
            }
        }

        var summary: GGUFOtherValue {
            switch self {
            case .unsigned(let value):
                value <= UInt64(Int.max) ? GGUFOtherValue.integer(Int(value)) : GGUFOtherValue.text(String(value), sensitive: false)
            case .signed(let value): GGUFOtherValue.integer(Int(value))
            case .float(let text): GGUFOtherValue.text(text, sensitive: false)
            case .bool(let flag): GGUFOtherValue.boolean(flag)
            }
        }
    }

    /// Byte widths of the fixed-size value types.
    static func width(ofType code: UInt32) -> Int? {
        switch code {
        case 0, 1, 7: 1
        case 2, 3: 2
        case 4, 5, 6: 4
        case 10, 11, 12: 8
        default: nil
        }
    }

    private func readScalar(_ typeCode: UInt32, reader: inout GGUFByteReader) throws -> Scalar {
        let width = Self.width(ofType: typeCode) ?? 1
        let raw = try reader.integer(width: width)
        switch typeCode {
        case 1, 3, 5, 11:
            let shift = UInt64(64 - width * 8)
            return .signed(Int64(bitPattern: raw << shift) >> Int64(shift))
        case 6: return .float(String(describing: Float(bitPattern: UInt32(truncatingIfNeeded: raw))))
        case 12: return .float(String(describing: Double(bitPattern: raw)))
        case 7: return .bool(raw != 0)
        default: return .unsigned(raw)
        }
    }

    private mutating func store(key: String, role: Role?, scalar: Scalar) {
        switch role {
        case .fileType?: if metadata.fileTypeCode == nil, let value = scalar.number { metadata.fileTypeCode = value; return }
        case .alignment?: if let value = scalar.number { metadata.alignment = value; return }
        case .architectureNumber?: if let value = scalar.number { metadata.architectureNumbers[key] = value }
        default: break
        }
        addOther(key: key, value: scalar.summary)
    }

    private mutating func addOther(key: String, value: GGUFOtherValue, scanned: Bool = false) {
        guard metadata.other.count < Self.candidateLimit, seenKeys.insert(key).inserted else { return }
        metadata.other.append(GGUFOtherEntry(key: PackageSummary.clipped(key, limit: 256), value: value, isScanned: scanned))
    }

    // MARK: Strings

    private mutating func readString(key: String, role: Role?, reader: inout GGUFByteReader) throws {
        let length = try reader.uint64()
        guard length <= UInt64(max(0, reader.remaining)) else { throw PreviewFailure.malformedDocument }
        let isTemplate = key.hasPrefix("tokenizer.chat_template")
        if case .chatTemplate? = role, metadata.chatTemplateBytes == nil {
            metadata.chatTemplateBytes = Int(clamping: length)
        }
        let hasTextRole = role.map(isTextRole) ?? false
        let hasRoom = metadata.other.count < Self.candidateLimit && !seenKeys.contains(key)
        guard hasTextRole || isTemplate || hasRoom, length <= UInt64(Self.maximumValueBytes) else {
            try reader.skip(length)
            return
        }
        let text = String(decoding: try reader.bytes(Int(length)), as: UTF8.self)
        if isTemplate || hasTextRole { try hidden.scan(text, context: context) }
        switch role {
        case .chatTemplate?:
            if metadata.chatTemplate == nil { metadata.chatTemplate = Self.clippedTemplate(text) }
        case .baseModelName(let index)?:
            if metadata.baseModelNames[index] == nil { metadata.baseModelNames[index] = PackageSummary.clipped(text, limit: 256) }
        case let role? where hasTextRole:
            assign(role, PackageSummary.clipped(text))
        default:
            addOther(key: key, value: .text(PackageSummary.clipped(text), sensitive: SecretFieldPolicy.isSensitive(key)),
                     scanned: isTemplate)
        }
    }

    private func isTextRole(_ role: Role) -> Bool {
        switch role {
        case .name, .architecture, .sizeLabel, .license, .author, .organization, .quantizedBy, .tokenizerModel,
             .chatTemplate, .baseModelName: true
        case .fileType, .alignment, .tags, .languages, .tokens, .architectureNumber: false
        }
    }

    private mutating func assign(_ role: Role, _ text: String) {
        switch role {
        case .name: metadata.name = metadata.name ?? text
        case .architecture: metadata.architecture = metadata.architecture ?? text
        case .sizeLabel: metadata.sizeLabel = metadata.sizeLabel ?? text
        case .license: metadata.license = metadata.license ?? text
        case .author: metadata.author = metadata.author ?? text
        case .organization: metadata.organization = metadata.organization ?? text
        case .quantizedBy: metadata.quantizedBy = metadata.quantizedBy ?? text
        case .tokenizerModel: metadata.tokenizerModel = metadata.tokenizerModel ?? text
        case .chatTemplate, .baseModelName, .fileType, .alignment, .tags, .languages, .tokens, .architectureNumber: break
        }
    }

    /// The template clipped by whole characters, so no character is cut, and so that its JSON-escaped
    /// form fits one summary line.
    static func clippedTemplate(_ text: String) -> String {
        var kept = ""
        var bytes = 0
        var escaped = 0
        for character in text {
            let width = character.utf8.count
            let cost = ListingBudget.escapedUTF8Count(String(character))
            if bytes + width > chatTemplateTextBytes - 3 || escaped + cost > chatTemplateEscapedBytes { return kept + "…" }
            kept.append(character)
            bytes += width
            escaped += cost
        }
        return kept
    }

    // MARK: Arrays

    private mutating func readArray(key: String, role: Role?, reader: inout GGUFByteReader) throws {
        let elementType = try reader.uint32()
        let count = try reader.uint64()
        if elementType == 8 {
            guard count <= UInt64(max(0, reader.remaining)) / 8 else { throw PreviewFailure.malformedDocument }
            switch role {
            case .tags?:
                metadata.tags = try keepStrings(count: count, reader: &reader)
                return
            case .languages?:
                metadata.languages = try keepStrings(count: count, reader: &reader)
                return
            case .tokens?:
                try skipStrings(count: count, reader: &reader)
                metadata.vocabularySize = Int(clamping: count)
                return
            default:
                try skipStrings(count: count, reader: &reader)
            }
        } else {
            try skipElements(type: elementType, count: count, depth: 1, reader: &reader)
        }
        addOther(key: key, value: .integer(Int(clamping: count)))
    }

    private mutating func keepStrings(count: UInt64, reader: inout GGUFByteReader) throws -> [String] {
        var kept: [String] = []
        for index in 0..<count {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            let length = try reader.uint64()
            guard length <= UInt64(max(0, reader.remaining)) else { throw PreviewFailure.malformedDocument }
            if kept.count < Self.keptListItems, length <= UInt64(Self.maximumValueBytes) {
                let text = String(decoding: try reader.bytes(Int(length)), as: UTF8.self)
                try hidden.scan(text, context: context)
                kept.append(PackageSummary.clipped(text, limit: 256))
            } else {
                try reader.skip(length)
            }
        }
        return kept
    }

    private func skipStrings(count: UInt64, reader: inout GGUFByteReader) throws {
        for index in 0..<count {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            try reader.skip(try reader.uint64())
        }
    }

    private func skipElements(type: UInt32, count: UInt64, depth: Int, reader: inout GGUFByteReader) throws {
        if let width = Self.width(ofType: type) {
            let (bytes, overflow) = count.multipliedReportingOverflow(by: UInt64(width))
            guard !overflow else { throw PreviewFailure.malformedDocument }
            try reader.skip(bytes)
            return
        }
        let remaining = UInt64(max(0, reader.remaining))
        switch type {
        case 8:
            guard count <= remaining / 8 else { throw PreviewFailure.malformedDocument }
            try skipStrings(count: count, reader: &reader)
        case 9:
            guard depth < Self.maximumArrayDepth else { throw PreviewFailure.structureTooDeep }
            guard count <= remaining / 12 else { throw PreviewFailure.malformedDocument }
            for index in 0..<count {
                if index.isMultiple(of: 1_024) { try context.checkpoint() }
                let innerType = try reader.uint32()
                let innerCount = try reader.uint64()
                try skipElements(type: innerType, count: innerCount, depth: depth + 1, reader: &reader)
            }
        default:
            throw PreviewFailure.malformedDocument
        }
    }

    // MARK: Result

    /// The metadata with the other-metadata list reduced to the keys that no dedicated field already
    /// shows (the architecture's own numbers) and to `keptOtherEntries`.
    func finished() -> GGUFMetadata {
        var result = metadata
        if let architecture = result.architecture {
            let dedicated = Set(Self.architectureSuffixes.map { "\(architecture).\($0)" }
                .filter { metadata.architectureNumbers[$0] != nil })
            result.other.removeAll { dedicated.contains($0.key) }
        }
        result.other = Array(result.other.prefix(Self.keptOtherEntries))
        return result
    }
}

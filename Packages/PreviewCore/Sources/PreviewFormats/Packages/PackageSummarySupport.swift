import Foundation
import PreviewContracts

/// Shared construction helpers for the package, certificate and disk-image summaries. Every summary
/// is one bounded JSON object written by `SummaryWriter`, which generates the privacy ranges in the
/// same pass, so no value reaches presentation without the shared concealment decision.
enum PackageSummary {
    /// Longest single text value kept in a summary. Longer document-supplied text is clipped by whole
    /// characters so one oversized field cannot fail the preview of everything else.
    static let maximumTextBytes = 1_024
    /// Items kept from a document-supplied list (permissions, trackers, entitlement keys, ...).
    static let maximumListItems = 64

    static func clipped(_ value: String, limit: Int = maximumTextBytes) -> String {
        guard value.utf8.count > limit else { return value }
        var result = ""
        var bytes = 0
        for character in value {
            let width = character.utf8.count
            guard bytes + width <= limit - 3 else { break }
            result.append(character)
            bytes += width
        }
        return result + "…"
    }

    /// The listing size that always fits the request's node and line budgets, so a large package is
    /// reported as partial instead of failing the whole preview. A listed entry costs nine summary
    /// nodes and six lines at most; the remainder is reserved for the descriptive fields.
    static func listingCapacity(_ context: RequestContext) -> Int {
        let byNodes = (context.budget.maxJSONNodes - 512) / 9
        let byLines = (context.budget.maxTextLines - 512) / 6
        return max(0, min(ContainerLimits(context: context).maxEntries, byNodes, byLines))
    }

    /// Writes the document. Images are encoded picture content, never text, so they bypass concealment
    /// and are attached only by adapters that extract pictures which are themselves document content.
    static func document(_ root: SummaryValue, context: RequestContext, images: [PreviewImage] = []) throws -> ParsedTextDocument {
        var writer = SummaryWriter(context: context)
        let written = try writer.document(root)
        return ParsedTextDocument(text: written.text, sensitiveRanges: written.sensitiveRanges,
                                  usesStructuredPrivacy: true, syntax: .json, images: images, origin: written.origin)
    }

    static func isoDate(_ date: Date) -> String { date.formatted(.iso8601) }
}

/// An ordered list of summary fields that omits absent values, so a document missing a key simply
/// shows less rather than a placeholder.
struct SummaryFields {
    private(set) var items: [(String, SummaryValue)] = []

    var value: SummaryValue { .object(items) }

    mutating func add(_ key: String, _ value: SummaryValue) { items.append((key, value)) }

    mutating func text(_ key: String, _ value: String?, sensitive: Bool = false) {
        guard let value, !value.isEmpty else { return }
        items.append((key, .string(PackageSummary.clipped(value), sensitive: sensitive)))
    }

    mutating func number(_ key: String, _ value: Int?) {
        guard let value else { return }
        items.append((key, .integer(value)))
    }

    mutating func number(_ key: String, _ value: Int64?) {
        guard let value else { return }
        items.append((key, .integer(Int(clamping: value))))
    }

    mutating func flag(_ key: String, _ value: Bool?) {
        guard let value else { return }
        items.append((key, .boolean(value)))
    }

    mutating func date(_ key: String, _ value: Date?) {
        guard let value else { return }
        items.append((key, .string(PackageSummary.isoDate(value))))
    }

    /// Adds a bounded array of strings; an empty list is omitted.
    mutating func list(_ key: String, _ values: [String], sensitive: Bool = false,
                       limit: Int = PackageSummary.maximumListItems) {
        guard !values.isEmpty else { return }
        items.append((key, .array(values.prefix(limit).map {
            .string(PackageSummary.clipped($0), sensitive: sensitive)
        })))
    }

    /// Adds the standard listing fields, with the entries last so the descriptive fields lead the Summary.
    mutating func listing(format: String, entries: [ContainerEntry], partial: Bool) {
        items.append(("archiveFormat", .string(format)))
        items.append(("listedEntries", .integer(entries.count)))
        items.append(("partial", .boolean(partial)))
        items.append(("entries", .array(entries.map { $0.summary() })))
    }
}

/// Typed access to the few keys a package summary needs from a decoded property list.
enum PlistAccess {
    static func string(_ dictionary: [String: Any], _ key: String) -> String? {
        (dictionary[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    static func strings(_ dictionary: [String: Any], _ key: String) -> [String] {
        (dictionary[key] as? [Any])?.compactMap { $0 as? String } ?? []
    }
    static func array(_ dictionary: [String: Any], _ key: String) -> [Any] { dictionary[key] as? [Any] ?? [] }
    static func dictionaries(_ dictionary: [String: Any], _ key: String) -> [[String: Any]] {
        (dictionary[key] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }
    static func date(_ dictionary: [String: Any], _ key: String) -> Date? { dictionary[key] as? Date }
    static func bool(_ dictionary: [String: Any], _ key: String) -> Bool? {
        guard let number = dictionary[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    static func integer(_ dictionary: [String: Any], _ key: String) -> Int? {
        guard let number = dictionary[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number) else { return nil }
        return Int(clamping: number.int64Value)
    }
}

/// Bounded conversion of a decoded property-list value into summary values, used for entitlements.
/// Data payloads are reduced to nothing; strings under a sensitive-looking key are concealed.
enum PlistValueSummary {
    static let maximumDepth = 3
    static let maximumItems = 32

    static func value(_ object: Any, sensitive: Bool, depth: Int = 0) -> SummaryValue? {
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean(number.boolValue) }
            if CFNumberIsFloatType(number) { return .string(number.stringValue) }
            return .integer(Int(clamping: number.int64Value))
        }
        if let text = object as? String { return .string(PackageSummary.clipped(text), sensitive: sensitive) }
        if let date = object as? Date { return .string(PackageSummary.isoDate(date)) }
        guard depth < maximumDepth else { return nil }
        if let values = object as? [Any] {
            return .array(values.prefix(maximumItems).compactMap { value($0, sensitive: sensitive, depth: depth + 1) })
        }
        if let values = object as? [String: Any] {
            return .object(values.keys.sorted().prefix(maximumItems).compactMap { key in
                value(values[key] as Any, sensitive: sensitive || SecretFieldPolicy.isSensitive(key), depth: depth + 1)
                    .map { (PackageSummary.clipped(key, limit: 256), $0) }
            })
        }
        return nil
    }

    /// Entitlements as a key-ordered object. Key names are exact technical identifiers; the values of
    /// keys that look like credentials are concealed, along with anything nested below them.
    static func entitlements(_ dictionary: [String: Any]) -> SummaryValue? {
        let keys = dictionary.keys.sorted().prefix(PackageSummary.maximumListItems)
        let items: [(String, SummaryValue)] = keys.compactMap { key in
            value(dictionary[key] as Any, sensitive: SecretFieldPolicy.isSensitive(key))
                .map { (PackageSummary.clipped(key, limit: 256), $0) }
        }
        return items.isEmpty ? nil : .object(items)
    }
}

/// Property lists inside packages are validated by the shared bounded property-list path (size, depth,
/// node, reference-cycle and entity checks) before Foundation builds a native graph from them.
enum BoundedPropertyList {
    static func dictionary(_ data: Data, context: RequestContext) throws -> [String: Any] {
        try context.checkpoint()
        // The shared adapter throws for every structural or budget violation. Its normalized output is
        // discarded: the raw native value is needed here for data fields such as embedded certificates.
        _ = try PropertyListSourceAdapter().parse(data: data, context: context)
        try context.checkpoint()
        let object: Any
        do { object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        catch { throw PreviewFailure.malformedDocument }
        guard let dictionary = object as? [String: Any] else { throw PreviewFailure.malformedDocument }
        return dictionary
    }
}

extension Data {
    /// Uppercase hexadecimal bytes joined by `separator`, as certificate tools conventionally print them.
    func hexadecimal(separator: String = "") -> String {
        map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}

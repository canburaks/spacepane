import Foundation
import PreviewContracts

/// One family's adapter-owned summary schema. Only the fields it names at the given paths are
/// translated; table/column names, file paths, SQL, source lexemes and user JSON keys stay
/// untouched even when they match these words.
struct SummaryLabelSet: Sendable {
    let formats: Set<FormatID>
    /// Translatable field names for a parent path, where "[]" stands for any array element.
    /// Returns nil when the path is not owned by the adapter's schema.
    let fields: @Sendable ([String]) -> Set<String>?
    let keys: [String: PreviewStrings.Key]
    /// Fields whose values are user or document content and are never reformatted.
    var verbatimFields: Set<String> = []
    var booleanFields: Set<String> = []
    /// Integral counts formatted with the presentation locale.
    var countFields: Set<String> = []
    /// Localized labels for enumerated adapter values: field → raw value → key.
    var valueLabels: [String: [String: PreviewStrings.Key]] = [:]

    /// Reuses this schema for further formats, such as new archive containers sharing the listing schema.
    func applying(to formats: Set<FormatID>) -> SummaryLabelSet {
        SummaryLabelSet(formats: formats, fields: fields, keys: keys, verbatimFields: verbatimFields,
                        booleanFields: booleanFields, countFields: countFields, valueLabels: valueLabels)
    }
}

enum SafeSchemaLabels {
    /// Every family registers one set per line below its marker; a format belongs to at most one set.
    static let labelSets: [SummaryLabelSet] = [
        .containers, .database, .midi,
        // [archives]
        .archives,
        // [listings]
        // [packages]
        .packages,
        // [data]
        .dataParquet, .dataAvro, .dataArrow, .dataNumPy, .dataNumPyArchive, .dataHAR,
        .dataGeoJSON, .dataGPX, .dataKML,
        // [ebooks]
        .comicBook,
        // [code]
    ]
    static let formats: Set<FormatID> = labelSets.reduce(into: []) { $0.formUnion($1.formats) }
    /// Listings whose adapters assess archive risks or shared name risks.
    static let riskFormats: Set<FormatID> = [.zip, .tar, .gzip, .xip, .rar, .sevenZip, .bzip2, .xz, .folder]

    static func labelSet(for format: FormatID) -> SummaryLabelSet? {
        labelSets.first { $0.formats.contains(format) }
    }

    static func localize(_ roots: [SafeOutlineNode], formatID: FormatID, locale: Locale) -> [SafeOutlineNode] {
        guard let set = labelSet(for: formatID) else { return roots }
        // Archive and folder listings carry per-entry risk codes (`entries[].risks[]`).
        let annotatesRisks = riskFormats.contains(formatID)
        func transform(_ node: SafeOutlineNode, path: [String], parentIsArray: Bool) -> SafeOutlineNode {
            let component = parentIsArray ? "[]" : node.name
            let isRoot = path.isEmpty && node.name == "$"
            let label = isRoot ? PreviewStrings.Key.previewModeSummary : key(node.name, parent: path, set: set)
            let childPath = isRoot ? [] : path + [component]
            var value = label == nil ? node.value : displayValue(node.value, field: node.name, set: set, locale: locale)
            var isIssue = node.isIssue
            if annotatesRisks {
                // Risk codes are adapter-owned values; an entry that carries any is highlighted.
                if parentIsArray, path == ["entries", "[]", "risks"] { value = riskText(node.value) }
                if path == ["entries"], node.children.contains(where: { $0.name == "risks" && !$0.children.isEmpty }) { isIssue = true }
            }
            return .init(id: node.id, name: label.map { PreviewStrings.text($0) } ?? node.name, value: value,
                         children: node.children.map { transform($0, path: childPath, parentIsArray: node.value == "[…]") },
                         isDuplicateKey: node.isDuplicateKey, isIssue: isIssue)
        }
        return roots.map { transform($0, path: [], parentIsArray: false) }
    }

    private static func key(_ name: String, parent: [String], set: SummaryLabelSet) -> PreviewStrings.Key? {
        guard let allowed = set.fields(parent), allowed.contains(name) else { return nil }
        return set.keys[name]
    }

    private static func displayValue(_ value: String, field: String, set: SummaryLabelSet, locale: Locale) -> String {
        if set.verbatimFields.contains(field) { return value }
        if set.booleanFields.contains(field), value == "true" { return PreviewStrings.text(.summaryBooleanTrue) }
        if set.booleanFields.contains(field), value == "false" { return PreviewStrings.text(.summaryBooleanFalse) }
        if let key = set.valueLabels[field]?[value] { return PreviewStrings.text(key) }
        if set.countFields.contains(field), let number = Int64(value) { return number.formatted(.number.locale(locale)) }
        return value
    }
    /// Unknown codes stay as written rather than being guessed at.
    private static func riskText(_ code: String) -> String {
        guard let risk = ArchiveEntryRisk(rawValue: code) else { return code }
        return PreviewStrings.text(riskKey(risk))
    }
    private static func riskKey(_ risk: ArchiveEntryRisk) -> PreviewStrings.Key {
        switch risk {
        case .unsafePath: .archiveRiskUnsafePath
        case .linkEscape: .archiveRiskLinkEscape
        case .link: .archiveRiskLink
        case .executable: .archiveRiskExecutable
        case .disguisedName: .archiveRiskDisguisedName
        case .directionalName: .archiveRiskDirectionalName
        case .encrypted: .archiveRiskEncrypted
        case .nested: .archiveRiskNested
        case .highCompression: .archiveRiskHighCompression
        case .hidden: .archiveRiskHidden
        case .caseCollision: .archiveRiskCaseCollision
        case .macMetadata: .archiveRiskMacMetadata
        case .hiddenCharacters: .listingRiskHiddenCharacters
        }
    }
}

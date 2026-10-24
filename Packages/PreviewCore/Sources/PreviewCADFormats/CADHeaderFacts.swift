import Foundation

// Moved from PreviewContracts on 2026-10-24 (decision 031): a build without CAD carries no STEP or IGES types. The
// facts are read by `CADHeaderReader` and used for unit provenance; showing them in the viewer returns with CAD
// (decision 028, "Bringing CAD back").

/// IGES Global-section revision flag (parameter 23). Display names are technical and not localized.
public enum IGESRevision: Int, CaseIterable, Sendable {
    case version1_0 = 1, version2_0 = 3, version3_0 = 4, version4_0 = 6
    case version5_0 = 8, version5_1 = 9, version5_2 = 10, version5_3 = 11
    public var displayName: String {
        switch self {
        case .version1_0: "1.0"
        case .version2_0: "2.0"
        case .version3_0: "3.0"
        case .version4_0: "4.0"
        case .version5_0: "5.0"
        case .version5_1: "5.1"
        case .version5_2: "5.2"
        case .version5_3: "5.3"
        }
    }
}

/// Recognized exchange schema. Unknown STEP schemas are omitted rather than shown as raw file text.
public enum CADSchema: Equatable, Sendable {
    case stepAP203, stepAP203Edition2, stepAP214, stepAP242
    case iges(IGESRevision)
    /// Technical protocol names; deliberately not localized.
    public var displayName: String {
        switch self {
        case .stepAP203: "AP203"
        case .stepAP203Edition2: "AP203e2"
        case .stepAP214: "AP214"
        case .stepAP242: "AP242"
        case .iges(let revision): "IGES " + revision.displayName
        }
    }
}

/// Non-personal header facts. Author, organization, file name and timestamps are never represented here.
public struct CADHeaderFacts: Equatable, Sendable {
    public static let maximumSystemNameLength = 64
    public let schema: CADSchema?
    /// The CAD system named by the file, only when short and limited to a safe technical alphabet.
    public let originatingSystem: String?
    /// Short IGES length-unit code such as `MM`. Not shown today; the displayed bounds are always millimetres.
    public let sourceUnit: String?
    public var isEmpty: Bool { schema == nil && originatingSystem == nil && sourceUnit == nil }

    public init(schema: CADSchema? = nil, originatingSystem: String? = nil, sourceUnit: String? = nil) {
        self.schema = schema
        self.originatingSystem = Self.safeLabel(originatingSystem, maximumLength: Self.maximumSystemNameLength)
        self.sourceUnit = Self.safeLabel(sourceUnit, maximumLength: 16)
    }

    /// Trimmed text of at most `maximumLength` bytes from `[A-Za-z0-9 ._()/+-]`; otherwise `nil`.
    /// Free text beyond this alphabet could carry names, paths or addresses, so it is omitted instead.
    public static func safeLabel(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumLength,
              trimmed.utf8.allSatisfy({ safeLabelBytes.contains($0) }) else { return nil }
        return trimmed
    }

    private static let safeLabelBytes: Set<UInt8> = Set(
        Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._()/+-".utf8))
}

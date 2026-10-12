import Foundation

/// A typed fact a request found about a file: what it is, how much it matters, how often it occurs
/// and where it sits in the displayed text. Findings never carry source values; presentation code
/// supplies localized wording. The one exception is `PreviewFindingDetail.decodedText`, which holds
/// privacy-filtered, bounded text decoded from invisible characters so it can be read inertly.
/// See docs/decisions/012-safety-findings.md.
public struct PreviewFinding: Equatable, Sendable {
    /// Line positions kept per finding. Further occurrences still count toward `count`.
    public static let maximumLines = 64
    /// Values kept in a sequence or cell-list detail.
    public static let maximumDetailValues = 32
    /// Characters kept in a decoded-text detail.
    public static let maximumDecodedCharacters = 512

    public let kind: PreviewFindingKind
    public let severity: PreviewFindingSeverity
    /// Occurrences; always at least one.
    public let count: Int
    /// One-based logical lines of the displayed, already concealed text: ascending, unique and bounded.
    /// Empty when the finding has no text position (archive entries, notebook cells, whole-file facts).
    public let lines: [Int]
    public let detail: PreviewFindingDetail

    public init(kind: PreviewFindingKind, severity: PreviewFindingSeverity? = nil, count: Int,
                lines: [Int] = [], detail: PreviewFindingDetail = .none) {
        self.kind = kind
        self.severity = severity ?? kind.defaultSeverity
        self.count = max(1, count)
        self.lines = Array(Set(lines.filter { $0 > 0 }).sorted().prefix(Self.maximumLines))
        self.detail = detail.bounded
    }
}

public enum PreviewFindingSeverity: Int, Comparable, Sendable {
    /// Worth knowing; not a risk on its own.
    case info
    /// Check before trusting or using the file.
    case caution
    /// Likely to cause harm or deception if ignored.
    case warning
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Stable identities. Raw values are technical identifiers: never localized, safe to persist or log.
/// Each feature owns one group; the renderer's exhaustive wording switch makes a kind without
/// localized text a compile error.
public enum PreviewFindingKind: String, CaseIterable, Sendable {
    // MARK: Notebook health — PreviewFormats/Notebooks
    case notebookOutOfOrder = "notebook.outOfOrder"
    case notebookExecutionGaps = "notebook.executionGaps"
    case notebookUnexecutedCells = "notebook.unexecutedCells"
    case notebookNotExecuted = "notebook.notExecuted"
    case notebookErrorOutputs = "notebook.errorOutputs"
    case notebookMayNotReproduce = "notebook.mayNotReproduce"

    // MARK: Archive risks — PreviewFormats/Containers
    case archiveUnsafePath = "archive.unsafePath"
    case archiveLinkEscape = "archive.linkEscape"
    case archiveLinks = "archive.links"
    case archiveExecutables = "archive.executables"
    case archiveDisguisedName = "archive.disguisedName"
    case archiveDirectionalName = "archive.directionalName"
    case archiveEncrypted = "archive.encrypted"
    case archiveNested = "archive.nested"
    case archiveHighCompression = "archive.highCompression"
    case archiveLargeExpansion = "archive.largeExpansion"
    case archiveHiddenEntries = "archive.hiddenEntries"
    case archiveCaseCollisions = "archive.caseCollisions"
    case archiveMacMetadata = "archive.macMetadata"

    // MARK: Listing name risks — PreviewFormats/Containers
    case listingHiddenCharacters = "listing.hiddenCharacters"

    // MARK: Secret inventory — PreviewCore privacy
    case secretPrivateKey = "secret.privateKey"
    case secretCloudAccessKey = "secret.cloudAccessKey"
    case secretCodeHostingToken = "secret.codeHostingToken"
    case secretAPIKey = "secret.apiKey"
    case secretWebToken = "secret.webToken"
    case secretAuthorizationHeader = "secret.authorizationHeader"
    case secretSensitiveField = "secret.sensitiveField"
    case secretSyncedFolder = "secret.syncedFolder"

    // MARK: Hidden content — PreviewCore scanner
    case hiddenBidirectionalControls = "hidden.bidirectionalControls"
    case hiddenZeroWidth = "hidden.zeroWidth"
    case hiddenUnicodeTags = "hidden.unicodeTags"
    case hiddenVariationSelectors = "hidden.variationSelectors"
    case hiddenPrivateUse = "hidden.privateUse"
    case hiddenMixedScripts = "hidden.mixedScripts"
    case hiddenMarkdownComments = "hidden.markdownComments"
    case hiddenAgentInstructions = "hidden.agentInstructions"

    public var defaultSeverity: PreviewFindingSeverity {
        switch self {
        case .archiveUnsafePath, .archiveLinkEscape, .archiveExecutables, .archiveDisguisedName,
             .archiveDirectionalName, .secretSyncedFolder, .hiddenBidirectionalControls, .hiddenUnicodeTags:
            .warning
        case .notebookOutOfOrder, .notebookExecutionGaps, .notebookUnexecutedCells, .notebookErrorOutputs,
             .archiveLinks, .archiveEncrypted, .archiveNested, .archiveHighCompression, .archiveLargeExpansion,
             .archiveCaseCollisions, .listingHiddenCharacters, .hiddenZeroWidth, .hiddenVariationSelectors, .hiddenMixedScripts,
             .hiddenMarkdownComments, .hiddenAgentInstructions:
            .caution
        case .notebookNotExecuted, .notebookMayNotReproduce, .archiveHiddenEntries, .archiveMacMetadata,
             .secretPrivateKey, .secretCloudAccessKey, .secretCodeHostingToken, .secretAPIKey, .secretWebToken,
             .secretAuthorizationHeader, .secretSensitiveField, .hiddenPrivateUse:
            .info
        }
    }

    /// Declaration order, used as the stable tie-breaker between findings of equal severity.
    var order: Int { Self.allCases.firstIndex(of: self) ?? Int.max }
}

/// Typed values that complete a finding's wording. Only `decodedText` holds text, and it is
/// privacy-filtered before it is attached.
public enum PreviewFindingDetail: Equatable, Sendable {
    case none
    /// Notebook execution counts in cell order, starting at the first out-of-order step.
    case executionSequence([Int])
    /// One-based notebook cell positions, ascending.
    case cells([Int])
    /// Largest declared expansion ratio (unpacked bytes per stored byte), rounded down.
    case compressionRatio(Int)
    /// Total declared bytes after extraction.
    case expandedBytes(Int64)
    /// The service that syncs the file's folder. The folder name itself is never carried:
    /// cloud-storage folder names can contain an account address.
    case syncProvider(PreviewSyncProvider)
    /// Privacy-filtered, bounded text decoded from invisible characters. Display only as inert text.
    case decodedText(String)

    var bounded: Self {
        switch self {
        case .executionSequence(let values): .executionSequence(Array(values.prefix(PreviewFinding.maximumDetailValues)))
        case .cells(let values):
            .cells(Array(Set(values.filter { $0 > 0 }).sorted().prefix(PreviewFinding.maximumDetailValues)))
        case .compressionRatio(let ratio): .compressionRatio(max(0, ratio))
        case .expandedBytes(let bytes): .expandedBytes(max(0, bytes))
        case .decodedText(let text): .decodedText(String(text.prefix(PreviewFinding.maximumDecodedCharacters)))
        case .none, .syncProvider: self
        }
    }

    // Decoded text compares exact code units: canonically equivalent String equality could keep
    // stale wording when a replacement differs only that way.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.executionSequence(a), .executionSequence(b)): a == b
        case let (.cells(a), .cells(b)): a == b
        case let (.compressionRatio(a), .compressionRatio(b)): a == b
        case let (.expandedBytes(a), .expandedBytes(b)): a == b
        case let (.syncProvider(a), .syncProvider(b)): a == b
        case let (.decodedText(a), .decodedText(b)): a.utf8.elementsEqual(b.utf8)
        default: false
        }
    }
}

public enum PreviewSyncProvider: String, CaseIterable, Sendable {
    case iCloudDrive, dropbox, googleDrive, oneDrive, box, other
}

/// Per-entry risk codes written into archive and folder summaries. Raw values are the summary's wire values;
/// the renderer localizes them. Findings report the totals.
public enum ArchiveEntryRisk: String, CaseIterable, Sendable {
    case unsafePath, linkEscape, link, executable, disguisedName, directionalName
    case encrypted, nested, highCompression, hidden, caseCollision, macMetadata
    case hiddenCharacters
}

public enum PreviewFindings {
    /// Findings kept per presentation, after merging.
    public static let maximumCount = 32

    /// Merges findings of the same kind (summing counts, uniting lines, keeping the highest severity
    /// and the first non-empty detail), then orders by severity, most serious first, and kind.
    public static func normalized(_ findings: [PreviewFinding]) -> [PreviewFinding] {
        var merged: [PreviewFindingKind: PreviewFinding] = [:]
        for finding in findings {
            guard let existing = merged[finding.kind] else { merged[finding.kind] = finding; continue }
            let (total, overflow) = existing.count.addingReportingOverflow(finding.count)
            merged[finding.kind] = PreviewFinding(
                kind: finding.kind, severity: max(existing.severity, finding.severity),
                count: overflow ? Int.max : total, lines: existing.lines + finding.lines,
                detail: existing.detail == .none ? finding.detail : existing.detail)
        }
        return Array(merged.values.sorted {
            $0.severity != $1.severity ? $0.severity > $1.severity : $0.kind.order < $1.kind.order
        }.prefix(maximumCount))
    }
}

import Foundation
import PreviewContracts

/// Per-entry risks, parallel to the analyzed entries, and the listing findings they add up to.
struct ArchiveRiskReport {
    let entryRisks: [[ArchiveEntryRisk]]
    let findings: [PreviewFinding]
    var annotatesEntries: Bool { entryRisks.contains { !$0.isEmpty } }
}

/// Derives archive risks from facts a listing already read. It is pure and bounded: it never extracts,
/// never follows a link on disk and never opens a nested archive, so it owns these archive-specific
/// rules and delegates shared name checks. Names are displayed exactly as decoded; findings carry
/// counts and numbers only, never names. See docs/decisions/012-safety-findings.md.
enum ArchiveRiskAnalyzer {
    /// Things that run when opened or installed. Ordinary source files (`.sh`, `.py`, `.js`) are not here:
    /// an extension alone does not make them a hazard.
    static let executableExtensions: Set<String> = [
        "app", "command", "tool", "pkg", "mpkg", "scpt", "scptd", "applescript", "workflow", "action",
        "terminal", "jar", "exe", "msi", "bat", "cmd", "com", "scr", "ps1", "vbs", "wsf"
    ]
    /// Document, media and data types a disguised executable pretends to be.
    static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "pages", "numbers", "key",
        "jpg", "jpeg", "png", "gif", "heic", "mp3", "mp4", "mov", "zip"
    ]
    /// Archive and disk-image extensions. A double extension such as `.tar.gz` ends in one of these.
    static let nestedExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "zst", "7z", "rar", "xip", "dmg", "iso",
        "sparseimage", "cpio", "pax"
    ]
    static let sparseBundleExtension = "sparsebundle"
    static let macMetadataFolder = "__MACOSX"
    /// Declared total after extraction that earns the large-expansion finding (1 GiB).
    static let largeExpansionBytes: Int64 = 1 << 30
    /// An entry is unusually compressed from this declared size and ratio.
    static let highCompressionMinimumBytes = 1_048_576
    static let highCompressionRatio = 100

    static func analyze(_ entries: [ContainerEntry], context: RequestContext) throws -> ArchiveRiskReport {
        try context.checkpoint()
        guard entries.count <= ContainerLimits(context: context).maxEntries else { throw PreviewFailure.tooManyNodes }
        var parts: [[String]] = []
        parts.reserveCapacity(entries.count)
        var listed: Set<String> = []
        for entry in entries {
            try context.checkpoint()
            let components = pathComponents(entry.path)
            parts.append(components)
            listed.insert(components.joined(separator: "/"))
        }

        var risks = Array(repeating: Set<ArchiveEntryRisk>(), count: entries.count)
        var flaggedBundles: Set<String> = []
        var expandedBytes: Int64 = 0
        var largestRatio = 0
        for (index, entry) in entries.enumerated() {
            try context.checkpoint()
            let components = parts[index]
            let kind = ContainerEntryKind(rawValue: entry.kind)
            if isUnsafe(entry.path, components: components) { risks[index].insert(.unsafePath) }
            risks[index].formUnion(try ListingNameRiskAnalyzer.risks(in: entry.path, context: context))
            if entry.isEncrypted { risks[index].insert(.encrypted) }
            if kind == .symlink || kind == .hardlink,
               let link = linkRisk(entry, components: components, hard: kind == .hardlink) {
                risks[index].insert(link)
            }
            insertExecutableRisks(for: entry, kind: kind, components: components, listed: listed,
                                  flaggedBundles: &flaggedBundles, into: &risks[index])
            if let last = components.last {
                let name = extensionParts(last)?.extension
                if let name, kind == .directory ? name == sparseBundleExtension : nestedExtensions.contains(name) {
                    risks[index].insert(.nested)
                }
            }
            if components.first == macMetadataFolder { risks[index].insert(.macMetadata) }
            else if components.contains(where: isHiddenComponent) { risks[index].insert(.hidden) }
            if kind == .file, let size = entry.size {
                let (total, overflow) = expandedBytes.addingReportingOverflow(Int64(size))
                expandedBytes = overflow ? .max : total
                if size >= highCompressionMinimumBytes, let stored = entry.storedSize, stored > 0,
                   size / stored >= highCompressionRatio {
                    risks[index].insert(.highCompression)
                    largestRatio = max(largestRatio, size / stored)
                }
            }
        }
        try insertCaseCollisions(entries, parts: parts, context: context, into: &risks)

        let ordered = risks.map { found in ArchiveEntryRisk.allCases.filter(found.contains) }
        var counts: [ArchiveEntryRisk: Int] = [:]
        for entryRisks in ordered { for risk in entryRisks { counts[risk, default: 0] += 1 } }
        var findings = ArchiveEntryRisk.allCases.compactMap { risk -> PreviewFinding? in
            guard let count = counts[risk] else { return nil }
            return PreviewFinding(kind: risk.findingKind, count: count,
                                  detail: risk == .highCompression ? .compressionRatio(largestRatio) : .none)
        }
        if expandedBytes >= largeExpansionBytes {
            findings.append(PreviewFinding(kind: .archiveLargeExpansion, count: 1, detail: .expandedBytes(expandedBytes)))
        }
        return ArchiveRiskReport(entryRisks: ordered, findings: findings)
    }

    // MARK: Path rules

    /// Components split on `/` and `\` by scalar, so a combining mark after a separator cannot hide it.
    /// Empty components are dropped; `.` and `..` are kept.
    static func pathComponents(_ path: String) -> [String] {
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in path.unicodeScalars {
            if scalar == "/" || scalar == "\\" {
                if !current.isEmpty { result.append(String(current)) }
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }

    private static func isUnsafe(_ path: String, components: [String]) -> Bool {
        isAbsolute(path) || components.contains("..")
    }

    /// A leading separator or a drive letter such as `C:`.
    private static func isAbsolute(_ path: String) -> Bool {
        var scalars = path.unicodeScalars.makeIterator()
        guard let first = scalars.next() else { return false }
        if first == "/" || first == "\\" { return true }
        return first.isASCII && first.properties.isAlphabetic && scalars.next() == ":"
    }

    private static func isHiddenComponent(_ component: String) -> Bool {
        component.unicodeScalars.first == "." && component != "." && component != ".."
    }

    /// The text before and after the last dot, with the extension lowercased. A leading dot alone
    /// (`.profile`) is a hidden name, not an extension.
    private static func extensionParts(_ name: String) -> (stem: String, extension: String)? {
        let scalars = name.unicodeScalars
        guard let dot = scalars.lastIndex(of: "."), dot != scalars.startIndex else { return nil }
        let suffix = String(scalars[scalars.index(after: dot)...])
        guard !suffix.isEmpty else { return nil }
        return (String(scalars[..<dot]), suffix.lowercased())
    }

    // MARK: Executables

    /// Flags the entry that is, or stands for, an app, installer, script or program. A bundle such as
    /// `Foo.app` counts once, on its directory entry or, when none is listed, on its first listed member.
    private static func insertExecutableRisks(for entry: ContainerEntry, kind: ContainerEntryKind?,
                                              components: [String], listed: Set<String>,
                                              flaggedBundles: inout Set<String>, into risks: inout Set<ArchiveEntryRisk>) {
        guard let rootIndex = components.firstIndex(where: {
            extensionParts($0).map { executableExtensions.contains($0.extension) } ?? false
        }) else {
            if kind == .file, let mode = entry.mode, mode & 0o111 != 0 { risks.insert(.executable) }
            return
        }
        let name: String
        if rootIndex == components.count - 1 {
            name = components[rootIndex]
        } else {
            let root = components[...rootIndex].joined(separator: "/")
            guard !listed.contains(root), flaggedBundles.insert(root).inserted else { return }
            name = components[rootIndex]
        }
        risks.insert(.executable)
        if isDisguised(name) { risks.insert(.disguisedName) }
    }

    /// A document or media extension followed, possibly after padding, by an executable one.
    private static func isDisguised(_ name: String) -> Bool {
        guard let parts = extensionParts(name), executableExtensions.contains(parts.extension) else { return false }
        // Only the comparison stem ignores formatting. The final executable suffix and displayed
        // name keep their raw spelling, so an interrupted suffix never becomes an executable.
        var stem = String(String.UnicodeScalarView(parts.stem.unicodeScalars.filter {
            $0.properties.generalCategory != .format && $0.value != 0x2800
        }))
        while let last = stem.last, last.isWhitespace { stem.removeLast() }
        guard let previous = extensionParts(stem)?.extension else { return false }
        return documentExtensions.contains(previous)
    }

    // MARK: Links

    /// Symbolic links resolve from their own directory; a hard link names a member by its archive path.
    /// Targets that leave the archive root are escapes, unreadable targets are only reported as links,
    /// and targets that stay inside the archive carry no risk.
    private static func linkRisk(_ entry: ContainerEntry, components: [String], hard: Bool) -> ArchiveEntryRisk? {
        guard let target = entry.linkTarget, !target.isEmpty else { return .link }
        if isAbsolute(target) { return .linkEscape }
        var depth = 0
        if !hard {
            for component in components.dropLast() {
                if component == ".." { depth = max(0, depth - 1) } else if component != "." { depth += 1 }
            }
        }
        for component in pathComponents(target) {
            if component == "." { continue }
            if component == ".." {
                guard depth > 0 else { return .linkEscape }
                depth -= 1
            } else {
                depth += 1
            }
        }
        return nil
    }

    // MARK: Case collisions

    /// Groups paths that differ exactly but are the same name on a case- and normalization-insensitive
    /// volume, such as APFS defaults. A dictionary keeps this linear in the entry count.
    private static func insertCaseCollisions(_ entries: [ContainerEntry], parts: [[String]], context: RequestContext,
                                             into risks: inout [Set<ArchiveEntryRisk>]) throws {
        struct Group { let path: String; var members: [Int]; var differs: Bool }
        var groups: [String: Group] = [:]
        for index in entries.indices {
            try context.checkpoint()
            let normalized = parts[index].joined(separator: "/")
            let key = normalized.decomposedStringWithCanonicalMapping
                .folding(options: .caseInsensitive, locale: nil).decomposedStringWithCanonicalMapping
            guard var group = groups[key] else { groups[key] = Group(path: normalized, members: [index], differs: false); continue }
            group.members.append(index)
            // Swift String equality ignores canonical equivalence; collisions compare exact code units.
            if !group.path.utf8.elementsEqual(normalized.utf8) { group.differs = true }
            groups[key] = group
        }
        for group in groups.values where group.differs {
            for index in group.members { risks[index].insert(.caseCollision) }
        }
    }
}

extension ArchiveEntryRisk {
    /// The listing finding that totals this per-entry risk.
    var findingKind: PreviewFindingKind {
        switch self {
        case .unsafePath: .archiveUnsafePath
        case .linkEscape: .archiveLinkEscape
        case .link: .archiveLinks
        case .executable: .archiveExecutables
        case .disguisedName: .archiveDisguisedName
        case .directionalName: .archiveDirectionalName
        case .encrypted: .archiveEncrypted
        case .nested: .archiveNested
        case .highCompression: .archiveHighCompression
        case .hidden: .archiveHiddenEntries
        case .caseCollision: .archiveCaseCollisions
        case .macMetadata: .archiveMacMetadata
        case .hiddenCharacters: .listingHiddenCharacters
        }
    }
}

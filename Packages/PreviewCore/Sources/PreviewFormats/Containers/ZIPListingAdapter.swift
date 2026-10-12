import Foundation
import PreviewContracts

/// Lists a ZIP or ZIP64 central directory without extracting anything.
///
/// Encrypted members and names that would be unsafe to extract are listed and reported by
/// `ArchiveRiskAnalyzer` rather than failing the whole listing: ZIP encrypts member payloads, not
/// names, and listing never resolves a path. `ZIPArchiveReader.readMember` still refuses both.
/// Modification times are the stored MS-DOS wall-clock values (or UTC instants from the extended
/// timestamp field); the summary marks them `timeZone: UTC` so views show the stored digits unchanged.
public struct ZIPListingAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    /// A symbolic link's payload is its target. Only a small stored payload is read, and only after the
    /// listing validated, so a link-heavy archive can neither fail nor exhaust the read budget.
    private static let maximumLinkTargetBytes = 4_096
    private static let maximumTotalLinkTargetBytes = 65_536
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }
    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        let archive = try ZIPArchiveReader.read(source, context: context, encryptedEntries: .list, paths: .listing)
        // A directory larger than the shared summary budgets lists its first entries and says so.
        var budget = ListingBudget(context: context)
        var entries: [ContainerEntry] = []
        var linkPayloads: [LinkPayload] = []
        var partial = false
        for (index, member) in archive.entries.enumerated() {
            if index.isMultiple(of: 256) { try context.checkpoint() }
            // Unix permission bits are meaningful only when a Unix or Darwin host wrote the entry.
            let host = member.versionMadeBy >> 8
            let entry = ContainerEntry(path: member.path, kind: member.kind, size: member.uncompressedSize,
                                       storedSize: member.compressedSize,
                                       mode: host == 3 || host == 19 ? UInt32(truncatingIfNeeded: member.externalAttributes >> 16) : nil,
                                       modified: member.modified, isEncrypted: member.isEncrypted)
            guard ListingBudget.fitsLine(entry, context: context) else { partial = true; continue }
            guard budget.admit(entry) else { partial = true; break }
            if member.kind == ContainerEntryKind.symlink.rawValue, member.method == 0, !member.isEncrypted,
               member.compressedSize == member.uncompressedSize, (1...Self.maximumLinkTargetBytes).contains(member.compressedSize) {
                linkPayloads.append(LinkPayload(entry: entries.count, offset: member.payloadOffset,
                                                count: member.compressedSize, encoding: member.nameEncoding))
            }
            entries.append(entry)
        }
        try readLinkTargets(linkPayloads, into: &entries, from: source, context: context)
        let hasDates = entries.contains { $0.modified != nil }
        return try listingDocument(format: archive.isZip64 ? "ZIP64" : "ZIP", entries: entries, context: context,
                                   partial: partial, extra: hasDates ? [("timeZone", .string("UTC"))] : [],
                                   assessRisks: true)
    }

    private struct LinkPayload {
        let entry: Int
        let offset: Int
        let count: Int
        let encoding: String.Encoding
    }

    /// Reads the targets of stored symbolic links in one bounded pass. A target that is not read, not
    /// text, or beyond the read budget stays `nil`, which the analyzer reports as a plain link.
    private func readLinkTargets(_ payloads: [LinkPayload], into entries: inout [ContainerEntry],
                                 from source: any PreviewByteSource, context: RequestContext) throws {
        var total = 0
        for payload in payloads {
            try context.checkpoint()
            guard payload.count <= Self.maximumTotalLinkTargetBytes - total else { return }
            let data: Data
            do { data = try source.read(offset: Int64(payload.offset), count: payload.count, context: context) }
            catch PreviewFailure.inputTooLarge { return }
            total += payload.count
            if let target = String(data: data, encoding: payload.encoding),
               !target.unicodeScalars.contains(where: { $0.value == 0 }) {
                entries[payload.entry].linkTarget = target
            }
        }
    }
}

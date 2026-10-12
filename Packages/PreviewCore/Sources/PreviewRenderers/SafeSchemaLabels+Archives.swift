import Foundation
import PreviewContracts

/// Summary schema of the archive family: RAR, 7z and the bzip2/xz streams. It extends the shared
/// listing fields with the archive-level flags and per-entry dates and encryption these adapters write.
/// Entry paths and ISO 8601 dates stay verbatim; flags and counts use the presentation locale.
extension SummaryLabelSet {
    static let archives = SummaryLabelSet(
        formats: [.rar, .sevenZip, .bzip2, .xz],
        fields: { parent in
            if parent.isEmpty {
                return ["archiveFormat", "listedEntries", "partial", "entries", "decodedBytes", "payloadKind",
                        "solid", "multiVolume", "volumeNumber", "locked", "recoveryRecord"]
            }
            return parent == ["entries", "[]"] ? ["path", "type", "bytes", "modified", "encrypted", "risks"] : nil
        },
        keys: archiveKeys,
        verbatimFields: ["path", "modified"],
        booleanFields: ["partial", "solid", "multiVolume", "locked", "recoveryRecord", "encrypted"],
        countFields: ["listedEntries", "decodedBytes", "bytes", "volumeNumber"],
        valueLabels: ["type": entryKinds, "payloadKind": entryKinds])

    private static let archiveKeys: [String: PreviewStrings.Key] = sharedKeys.merging([
        "solid": .archiveSolid, "multiVolume": .archiveMultiVolume, "volumeNumber": .archiveVolumeNumber,
        "locked": .archiveLocked, "recoveryRecord": .archiveRecoveryRecord,
        "modified": .archiveEntryModified, "encrypted": .archiveEntryEncrypted
    ]) { _, archive in archive }
}

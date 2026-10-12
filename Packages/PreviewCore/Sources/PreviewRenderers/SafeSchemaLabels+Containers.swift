import Foundation
import PreviewContracts

/// Listing, database and MIDI summary schemas written by the container adapters.
extension SummaryLabelSet {
    static let containers = SummaryLabelSet(
        formats: [.zip, .tar, .gzip, .xip, .folder],
        fields: { parent in
            if parent.isEmpty {
                return ["archiveFormat", "listedEntries", "partial", "entries", "payloadsRead", "signatureVerified",
                        "innerArchiveFormat", "scope", "inaccessibleEntries", "recursive", "decodedBytes", "payloadKind",
                        "depth", "hiddenEntries", "fileCount", "folderCount", "listedBytes", "timeZone", "largestItems"]
            }
            // `modified` is an ISO 8601 value and stays exact; `items` is a folder's direct child count.
            if parent == ["entries", "[]"] { return ["path", "type", "bytes", "modified", "encrypted", "items", "risks"] }
            return parent == ["largestItems", "[]"] ? ["path", "bytes"] : nil
        },
        keys: sharedKeys,
        verbatimFields: ["path"],
        booleanFields: ["partial", "payloadsRead", "signatureVerified", "recursive", "encrypted"],
        countFields: ["listedEntries", "inaccessibleEntries", "decodedBytes", "bytes", "items", "depth", "hiddenEntries",
                      "fileCount", "folderCount", "listedBytes"],
        valueLabels: [
            "archiveFormat": ["directory": .summaryKindDirectory],
            "scope": ["immediateChildren": .summaryScopeImmediateChildren, "nestedFolders": .listingScopeNestedFolders],
            "type": entryKinds,
            "payloadKind": entryKinds
        ])

    static let database = SummaryLabelSet(
        formats: [.sqlite],
        fields: { parent in
            if parent.isEmpty {
                return ["databaseFormat", "sourceReadOnly", "schemaPartial", "schema", "rowLimit", "cellByteLimit",
                        "tablesWithRows", "tableCount", "pages", "table"]
            }
            // The schema grid (data workstream) shares the data envelope's `table` member.
            if parent == ["table"] { return ["columns", "rows", "truncated"] }
            if parent == ["schema", "[]"] { return ["type", "name", "table", "sql", "virtual"] }
            if parent == ["pages", "[]"] { return ["table", "columns", "offset", "loadedRows", "partial", "rows"] }
            if parent.count == 5, Array(parent.prefix(4)) == ["pages", "[]", "rows", "[]"] {
                return ["value", "truncated", "sourceType", "blobBytes"]
            }
            if parent.count == 6, Array(parent.prefix(4)) == ["pages", "[]", "rows", "[]"], parent.last == "value" {
                return ["blobBytes"]
            }
            return nil
        },
        keys: sharedKeys,
        verbatimFields: ["name", "table", "sql", "columns", "value"],
        booleanFields: ["partial", "sourceReadOnly", "schemaPartial", "virtual", "truncated"],
        countFields: ["rowLimit", "cellByteLimit", "tablesWithRows", "tableCount", "offset", "loadedRows", "blobBytes"])

    static let midi = SummaryLabelSet(
        formats: [.midi],
        fields: { parent in
            parent.isEmpty ? ["MIDIFormat", "tracks", "ticksPerQuarter", "channelEvents", "textMetadataRetained",
                              "systemExclusiveRetained", "autoplay"] : nil
        },
        keys: sharedKeys,
        booleanFields: ["textMetadataRetained", "systemExclusiveRetained", "autoplay"],
        countFields: ["MIDIFormat", "tracks", "ticksPerQuarter", "channelEvents"])

    static let entryKinds: [String: PreviewStrings.Key] = [
        "file": .summaryKindFile, "directory": .summaryKindDirectory, "symlink": .summaryKindSymlink,
        "hardlink": .summaryKindHardlink, "special": .summaryKindSpecial, "binary": .summaryKindBinary,
        "package": .listingKindPackage
    ]

    static let sharedKeys: [String: PreviewStrings.Key] = [
        "archiveFormat": .summaryArchiveFormat, "listedEntries": .summaryListedEntries, "partial": .summaryPartial,
        "entries": .summaryEntries, "payloadsRead": .summaryPayloadsRead, "signatureVerified": .summarySignatureVerified,
        "innerArchiveFormat": .summaryInnerArchiveFormat, "scope": .summaryScope, "inaccessibleEntries": .summaryInaccessibleEntries,
        "recursive": .summaryRecursive, "decodedBytes": .summaryDecodedBytes, "payloadKind": .summaryPayloadKind,
        "path": .summaryPath, "type": .summaryType, "bytes": .summaryBytes, "databaseFormat": .summaryDatabaseFormat,
        "sourceReadOnly": .summarySourceReadOnly, "schemaPartial": .summarySchemaPartial, "schema": .summarySchema,
        "rowLimit": .summaryRowLimit, "cellByteLimit": .summaryCellByteLimit, "tablesWithRows": .summaryTablesWithRows,
        "tableCount": .summaryTableCount, "pages": .summaryPages, "name": .summaryName, "table": .summaryTable,
        "sql": .summarySql, "virtual": .summaryVirtual, "columns": .summaryColumns, "offset": .summaryOffset,
        "loadedRows": .summaryLoadedRows, "rows": .summaryRows, "value": .summaryValue, "truncated": .summaryTruncated,
        "sourceType": .summarySourceType, "blobBytes": .summaryBlobBytes, "MIDIFormat": .summaryMIDIFormat,
        "tracks": .summaryTracks, "ticksPerQuarter": .summaryTicksPerQuarter, "channelEvents": .summaryChannelEvents,
        "textMetadataRetained": .summaryTextMetadataRetained, "systemExclusiveRetained": .summarySystemExclusiveRetained,
        "autoplay": .summaryAutoplay, "risks": .summaryRisks, "modified": .listingModified, "encrypted": .listingEncrypted,
        "hiddenEntries": .listingHiddenEntries, "fileCount": .listingFileCount, "folderCount": .listingFolderCount,
        "listedBytes": .listingListedBytes, "depth": .listingDepth, "timeZone": .listingTimeZone,
        "items": .listingItems, "largestItems": .listingLargestFiles
    ]
}

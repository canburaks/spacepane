import Foundation
import PreviewContracts

/// Summary schema written by the pickle and PyTorch scan (decision 030). Only the app-owned field names and
/// the enumerated values listed here are translated. The container's name and the import names are exactly
/// as the scan wrote them: they are technical identifiers and the file's own content.
extension SummaryLabelSet {
    static let pickle = SummaryLabelSet(
        formats: [.pickle],
        fields: { parent in
            switch parent {
            case []:
                return ["container", "pickleProtocol", "pickles", "persistentIDs", "storages", "storageBytes",
                        "checksumErrors", "imports", "checked", "partial"]
            case ["imports", "[]"]: return ["name", "count", "kind"]
            default: return nil
            }
        },
        keys: [
            "container": .packageContainerFormat, "pickleProtocol": .picklePickleProtocol, "pickles": .pickleScanned,
            "persistentIDs": .picklePersistentIDs, "storages": .pickleStorages, "storageBytes": .pickleStorageBytes,
            "checksumErrors": .pickleChecksumErrors, "imports": .pickleImports, "name": .summaryName,
            "count": .pickleImportCount, "kind": .pickleImportKind, "checked": .pickleChecked, "partial": .picklePartial
        ],
        verbatimFields: ["container", "name"],
        booleanFields: ["partial"],
        countFields: ["pickles", "persistentIDs", "storages", "storageBytes", "checksumErrors", "count"],
        valueLabels: [
            "kind": ["code": .pickleKindCode, "networkOrFiles": .pickleKindNetworkOrFiles,
                     "uncommon": .pickleKindUncommon, "expected": .pickleKindExpected],
            "checked": ["importsOnly": .pickleCheckedImportsOnly]
        ])
}

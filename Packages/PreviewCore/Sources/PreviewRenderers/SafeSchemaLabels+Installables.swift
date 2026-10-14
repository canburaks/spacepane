import Foundation
import PreviewContracts

/// Summary schema written by `PythonWheelAdapter` (decision 030). Only the app-owned field names listed
/// here are translated. The package's name, version, summary, requirements, license, tags, commands, file
/// names, scripts and every archive path stay exactly as stored: they are the package author's text, not
/// the app's. Flags and counts use the presentation locale.
extension SummaryLabelSet {
    static let installables = SummaryLabelSet(
        formats: [.pythonWheel],
        fields: { parent in
            switch parent {
            case []:
                return ["name", "version", "summary", "requiresPython", "dependencies", "license", "wheelVersion", "generator",
                        "pureLibrary", "tags", "commands", "startupFiles", "installedScripts", "nativeModules",
                        "archiveFormat", "listedEntries", "partial", "entries"]
            case ["entries", "[]"]: return ["path", "type", "bytes", "modified"]
            default: return nil
            }
        },
        keys: [
            "name": .summaryName, "version": .packageVersion, "summary": .installSummary,
            "requiresPython": .installRequiresPython, "dependencies": .installDependencies, "license": .installLicense,
            "wheelVersion": .installWheelVersion, "generator": .installGenerator, "pureLibrary": .installPureLibrary,
            "tags": .installTags, "commands": .installCommands, "startupFiles": .installStartupFiles,
            "installedScripts": .installInstalledScripts, "nativeModules": .installNativeModules,
            "archiveFormat": .packageContainerFormat, "listedEntries": .summaryListedEntries, "partial": .summaryPartial,
            "entries": .summaryEntries, "path": .summaryPath, "type": .summaryType, "bytes": .summaryBytes,
            "modified": .packageModified
        ],
        verbatimFields: ["name", "version", "summary", "requiresPython", "license", "wheelVersion", "generator", "path", "modified"],
        booleanFields: ["partial", "pureLibrary"],
        countFields: ["listedEntries", "bytes", "nativeModules"],
        valueLabels: ["type": entryKinds])
}

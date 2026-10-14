import Foundation
import PreviewContracts

/// Localized wording for typed findings. The switch is exhaustive, so a new kind without wording
/// does not compile. Counts and numbers use the presentation locale; source values never appear,
/// except privacy-filtered decoded text, which is shown verbatim as inert text.
enum FindingText {
    /// Line or cell numbers listed before "and N more".
    static let listedPositions = 8

    static func message(for finding: PreviewFinding, locale: Locale) -> String {
        let count = Int64(finding.count)
        switch finding.kind {
        case .notebookOutOfOrder:
            return PreviewStrings.format(.findingNotebookOutOfOrder, arguments: [sequence(finding.detail, locale: locale)], locale: locale)
        case .notebookExecutionGaps:
            return PreviewStrings.format(.findingNotebookExecutionGaps, arguments: [count], locale: locale)
        case .notebookUnexecutedCells:
            return PreviewStrings.format(.findingNotebookUnexecutedCells, arguments: [count], locale: locale)
        case .notebookNotExecuted: return PreviewStrings.text(.findingNotebookNotExecuted)
        case .notebookErrorOutputs:
            return PreviewStrings.format(.findingNotebookErrorOutputs, arguments: [count], locale: locale)
        case .notebookMayNotReproduce: return PreviewStrings.text(.findingNotebookMayNotReproduce)
        case .archiveUnsafePath:
            return PreviewStrings.format(.findingArchiveUnsafePath, arguments: [count], locale: locale)
        case .archiveLinkEscape:
            return PreviewStrings.format(.findingArchiveLinkEscape, arguments: [count], locale: locale)
        case .archiveLinks:
            return PreviewStrings.format(.findingArchiveLinks, arguments: [count], locale: locale)
        case .archiveExecutables:
            return PreviewStrings.format(.findingArchiveExecutables, arguments: [count], locale: locale)
        case .archiveDisguisedName:
            return PreviewStrings.format(.findingArchiveDisguisedName, arguments: [count], locale: locale)
        case .archiveDirectionalName:
            return PreviewStrings.format(.findingArchiveDirectionalName, arguments: [count], locale: locale)
        case .archiveEncrypted:
            return PreviewStrings.format(.findingArchiveEncrypted, arguments: [count], locale: locale)
        case .archiveNested:
            return PreviewStrings.format(.findingArchiveNested, arguments: [count], locale: locale)
        case .archiveHighCompression:
            let ratio: Int64
            if case .compressionRatio(let value) = finding.detail { ratio = Int64(value) } else { ratio = 0 }
            return PreviewStrings.format(.findingArchiveHighCompression, arguments: [count, ratio], locale: locale)
        case .archiveLargeExpansion:
            let bytes: Int64
            if case .expandedBytes(let value) = finding.detail { bytes = value } else { bytes = 0 }
            let size = bytes.formatted(.byteCount(style: .file).locale(locale))
            return PreviewStrings.format(.findingArchiveLargeExpansion, arguments: [size], locale: locale)
        case .archiveHiddenEntries:
            return PreviewStrings.format(.findingArchiveHiddenEntries, arguments: [count], locale: locale)
        case .archiveCaseCollisions:
            return PreviewStrings.format(.findingArchiveCaseCollisions, arguments: [count], locale: locale)
        case .archiveMacMetadata:
            return PreviewStrings.format(.findingArchiveMacMetadata, arguments: [count], locale: locale)
        case .listingHiddenCharacters:
            return PreviewStrings.count(.findingListingHiddenCharacters, finding.count, locale: locale)
        case .secretPrivateKey:
            return PreviewStrings.format(.findingSecretPrivateKey, arguments: [count], locale: locale)
        case .secretCloudAccessKey:
            return PreviewStrings.format(.findingSecretCloudAccessKey, arguments: [count], locale: locale)
        case .secretCodeHostingToken:
            return PreviewStrings.format(.findingSecretCodeHostingToken, arguments: [count], locale: locale)
        case .secretAPIKey:
            return PreviewStrings.format(.findingSecretAPIKey, arguments: [count], locale: locale)
        case .secretWebToken:
            return PreviewStrings.format(.findingSecretWebToken, arguments: [count], locale: locale)
        case .secretAuthorizationHeader:
            return PreviewStrings.format(.findingSecretAuthorizationHeader, arguments: [count], locale: locale)
        case .secretSensitiveField:
            return PreviewStrings.format(.findingSecretSensitiveField, arguments: [count], locale: locale)
        case .secretSyncedFolder:
            let provider: PreviewSyncProvider
            if case .syncProvider(let value) = finding.detail { provider = value } else { provider = .other }
            return PreviewStrings.format(.findingSecretSyncedFolder, arguments: [providerName(provider)], locale: locale)
        case .hiddenBidirectionalControls:
            return PreviewStrings.format(.findingHiddenBidirectionalControls, arguments: [count], locale: locale)
        case .hiddenZeroWidth:
            return PreviewStrings.format(.findingHiddenZeroWidth, arguments: [count], locale: locale)
        case .hiddenUnicodeTags:
            return PreviewStrings.format(.findingHiddenUnicodeTags, arguments: [count], locale: locale)
        case .hiddenVariationSelectors:
            return PreviewStrings.format(.findingHiddenVariationSelectors, arguments: [count], locale: locale)
        case .hiddenPrivateUse:
            return PreviewStrings.format(.findingHiddenPrivateUse, arguments: [count], locale: locale)
        case .hiddenMixedScripts:
            return PreviewStrings.format(.findingHiddenMixedScripts, arguments: [count], locale: locale)
        case .hiddenMarkdownComments:
            return PreviewStrings.format(.findingHiddenMarkdownComments, arguments: [count], locale: locale)
        case .hiddenAgentInstructions: return PreviewStrings.text(.findingHiddenAgentInstructions)
        // Decision 029. Counted findings are plural keys; the count is formatted for the locale.
        case .scriptDownloadAndRun: return PreviewStrings.count(.findingScriptDownloadAndRun, finding.count, locale: locale)
        case .scriptDecodeAndRun: return PreviewStrings.count(.findingScriptDecodeAndRun, finding.count, locale: locale)
        case .scriptRemovesQuarantine: return PreviewStrings.count(.findingScriptRemovesQuarantine, finding.count, locale: locale)
        case .scriptDisablesProtection: return PreviewStrings.count(.findingScriptDisablesProtection, finding.count, locale: locale)
        case .scriptAsksForPassword: return PreviewStrings.count(.findingScriptAsksForPassword, finding.count, locale: locale)
        case .scriptReadsSecrets: return PreviewStrings.count(.findingScriptReadsSecrets, finding.count, locale: locale)
        case .scriptPersistence: return PreviewStrings.count(.findingScriptPersistence, finding.count, locale: locale)
        case .scriptElevates: return PreviewStrings.count(.findingScriptElevates, finding.count, locale: locale)
        case .scriptUploadsFiles: return PreviewStrings.count(.findingScriptUploadsFiles, finding.count, locale: locale)
        case .autorunFolderOpenTask: return PreviewStrings.count(.findingAutorunFolderOpenTask, finding.count, locale: locale)
        case .autorunHostCommand: return PreviewStrings.count(.findingAutorunHostCommand, finding.count, locale: locale)
        case .autorunAgentHooks: return PreviewStrings.count(.findingAutorunAgentHooks, finding.count, locale: locale)
        case .autorunAgentPermissions: return PreviewStrings.count(.findingAutorunAgentPermissions, finding.count, locale: locale)
        case .autorunLocalServers: return PreviewStrings.count(.findingAutorunLocalServers, finding.count, locale: locale)
        case .autorunInstallScripts: return PreviewStrings.count(.findingAutorunInstallScripts, finding.count, locale: locale)
        case .autorunRemoteServers: return PreviewStrings.count(.findingAutorunRemoteServers, finding.count, locale: locale)
        case .autorunServerEnvironment: return PreviewStrings.count(.findingAutorunServerEnvironment, finding.count, locale: locale)
        case .autorunContainerCommands: return PreviewStrings.count(.findingAutorunContainerCommands, finding.count, locale: locale)
        case .exportReadableLogins: return PreviewStrings.count(.findingExportReadableLogins, finding.count, locale: locale)
        case .exportReadableCodeSecrets: return PreviewStrings.count(.findingExportReadableCodeSecrets, finding.count, locale: locale)
        case .launchWatchPaths: return PreviewStrings.count(.findingLaunchWatchPaths, finding.count, locale: locale)
        case .certificateExpired: return PreviewStrings.count(.findingCertificateExpired, finding.count, locale: locale)
        case .certificateNotYetValid: return PreviewStrings.count(.findingCertificateNotYetValid, finding.count, locale: locale)
        case .certificateWeakKey: return PreviewStrings.count(.findingCertificateWeakKey, finding.count, locale: locale)
        case .launchHiddenLocation: return PreviewStrings.text(.findingLaunchHiddenLocation)
        case .launchInlineScript: return PreviewStrings.text(.findingLaunchInlineScript)
        case .launchAtLoad: return PreviewStrings.text(.findingLaunchAtLoad)
        case .launchKeepAlive: return PreviewStrings.text(.findingLaunchKeepAlive)
        case .launchJob: return PreviewStrings.text(.findingLaunchJob)
        case .launchSchedule: return PreviewStrings.text(.findingLaunchSchedule)
        case .profileExpired: return PreviewStrings.text(.findingProfileExpired)
        case .launchInterval:
            return PreviewStrings.format(.findingLaunchInterval, arguments: [interval(finding.detail, locale: locale)], locale: locale)
        case .certificateExpiresSoon:
            return PreviewStrings.count(.findingCertificateExpiresSoon, days(finding.detail), locale: locale)
        case .profileExpiresSoon:
            return PreviewStrings.count(.findingProfileExpiresSoon, days(finding.detail), locale: locale)
        }
    }

    /// Days left from a `.days` detail; a missing detail reads as one day, the smallest a producer reports.
    private static func days(_ detail: PreviewFindingDetail) -> Int {
        if case .days(let value) = detail { return max(1, value) }
        return 1
    }

    /// A declared repeat interval as a localized duration, for example "5 minutes" or "1 hour, 30 minutes".
    private static func interval(_ detail: PreviewFindingDetail, locale: Locale) -> String {
        guard case .seconds(let seconds) = detail, seconds > 0 else { return "" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide).locale(locale))
    }

    /// Secondary line: where the finding occurs, or the decoded hidden text. `nil` when there is nothing to add.
    static func detail(for finding: PreviewFinding, locale: Locale) -> String? {
        if case .decodedText(let text) = finding.detail, !text.isEmpty {
            return PreviewStrings.format(.findingDetailDecodedText, arguments: [text], locale: locale)
        }
        if case .cells(let cells) = finding.detail, !cells.isEmpty {
            let shown = list(cells.prefix(listedPositions), locale: locale)
            // The detail keeps at most 32 positions; for cell findings `count` is the true number of cells.
            let remaining = max(finding.count, cells.count) - min(cells.count, listedPositions)
            return remaining > 0
                ? PreviewStrings.format(.findingDetailCellsMore, arguments: [shown, Int64(remaining)], locale: locale)
                : PreviewStrings.format(.findingDetailCells, arguments: [shown], locale: locale)
        }
        guard !finding.lines.isEmpty else { return nil }
        let shown = list(finding.lines.prefix(listedPositions), locale: locale)
        // Lines beyond the kept positions are still occurrences; report what was kept, not the count.
        let remaining = finding.lines.count - min(finding.lines.count, listedPositions)
        return remaining > 0
            ? PreviewStrings.format(.findingDetailLinesMore, arguments: [shown, Int64(remaining)], locale: locale)
            : PreviewStrings.format(.findingDetailLines, arguments: [shown], locale: locale)
    }

    static func severityDescription(_ severity: PreviewFindingSeverity) -> String {
        switch severity {
        case .warning: PreviewStrings.text(.findingSeverityWarning)
        case .caution: PreviewStrings.text(.findingSeverityCaution)
        case .info: PreviewStrings.text(.findingSeverityInfo)
        }
    }

    static func providerName(_ provider: PreviewSyncProvider) -> String {
        switch provider {
        case .iCloudDrive: PreviewStrings.text(.findingProviderICloudDrive)
        case .dropbox: PreviewStrings.text(.findingProviderDropbox)
        case .googleDrive: PreviewStrings.text(.findingProviderGoogleDrive)
        case .oneDrive: PreviewStrings.text(.findingProviderOneDrive)
        case .box: PreviewStrings.text(.findingProviderBox)
        case .other: PreviewStrings.text(.findingProviderOther)
        }
    }

    private static func list<S: Sequence<Int>>(_ values: S, locale: Locale) -> String {
        values.map { Int64($0).formatted(.number.locale(locale)) }.formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// Execution numbers keep notebook order, which is the point of the finding; an arrow joins them.
    private static func sequence(_ detail: PreviewFindingDetail, locale: Locale) -> String {
        guard case .executionSequence(let values) = detail, !values.isEmpty else { return "" }
        return values.map { Int64($0).formatted(.number.locale(locale)) }.joined(separator: " → ")
    }
}

import Foundation
import PreviewContracts

/// Writes a scan as the file's summary and its findings (decision 030).
///
/// The summary says what was checked ("imports only; the file was never loaded") and nothing in it or in
/// the findings says a file is safe: a file with no findings has only had its imports looked at. Findings
/// carry counts of distinct import names per class and no lines; the names themselves appear only in the
/// summary, which is the file's content as far as the reader is concerned.
enum PickleSummary {
    /// Imports listed in the summary; further ones still count in the findings and mark the scan partial.
    static let maximumListedImports = 256

    /// - Parameter scanned: whether pickles were looked at. A file that turned out to be another kind of file
    ///   gets only its container and the mismatch.
    static func document(_ report: PickleScanReport, scanned: Bool = true, mismatch: Bool = false,
                         context: RequestContext) throws -> ParsedTextDocument {
        var fields = SummaryFields()
        fields.text("container", report.container)
        var findings: [PreviewFinding] = []
        if scanned {
            fields.number("pickleProtocol", report.protocolVersion)
            fields.number("pickles", report.pickles)
            fields.number("persistentIDs", report.persistentIDs)
            fields.number("storages", report.storages)
            if report.storages != nil { fields.number("storageBytes", report.storageBytes) }
            if report.checksumErrors > 0 { fields.number("checksumErrors", report.checksumErrors) }
            let sorted = report.tally.sorted
            if !sorted.isEmpty {
                fields.add("imports", .array(sorted.prefix(maximumListedImports).map { item in
                    .object([("name", .string(item.name)), ("count", .integer(item.entry.count)),
                             ("kind", .string(item.entry.kind.rawValue))])
                }))
            }
            fields.text("checked", "importsOnly")
            fields.flag("partial", report.isPartial || report.tally.overflowed || sorted.count > maximumListedImports)
            findings = Self.findings(report)
        }
        // Native code in an archive is a fact about the archive, whether or not it held pickles.
        if report.nativeMembers > 0 { findings.append(PreviewFinding(kind: .artifactNativeCode, count: report.nativeMembers)) }
        if mismatch { findings.append(PreviewFinding(kind: .artifactMismatchedContent, count: 1)) }
        return try PackageSummary.document(fields.value, context: context, findings: findings)
    }

    /// One finding per class that has imports, counting distinct names, and one for a stream that broke after naming
    /// imports.
    static func findings(_ report: PickleScanReport) -> [PreviewFinding] {
        var findings: [PreviewFinding] = []
        let classes: [(PickleImportKind, PreviewFindingKind)] = [
            (.code, .pickleRunsCode), (.networkOrFiles, .pickleNetworkOrFiles), (.uncommon, .pickleUncommonImports)
        ]
        for (importClass, kind) in classes where report.tally.distinctCount(importClass) > 0 {
            findings.append(PreviewFinding(kind: kind, count: report.tally.distinctCount(importClass)))
        }
        if report.isBroken { findings.append(PreviewFinding(kind: .pickleBrokenStream, count: 1)) }
        return findings
    }
}

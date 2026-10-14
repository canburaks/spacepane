import Foundation
import PreviewContracts

/// The findings of one presentation as plain text a reader can paste into a ticket (decision 029, Copy Findings
/// Report). It is built only from typed findings and the wording `FindingText` already owns, so it can never carry
/// the file's name, a path or any text from the file:
///
/// ```text
/// Findings: Plain Text
///
/// • Warning: <message> (Lines: 3, 7)
/// • Note: <message>
///
/// This list contains no text from the file.
/// ```
///
/// - The heading names the format with its localized catalog name, never the file.
/// - One line per finding, in the order the banner lists them, whatever the banner shows or hides: severity,
///   wording and, when the finding has positions, the same "Lines" or "Cells" list the banner prints.
/// - Text that was decoded from hidden characters (`PreviewFindingDetail.decodedText`) is left out. The finding is
///   still listed with its own wording and positions.
/// - The bullet, the colon after the severity and the parentheses are structure, not wording, so a report reads
///   the same in every language.
struct FindingsReport: Equatable, Sendable {
    let heading: String
    /// One bullet line per finding, in banner order.
    let lines: [String]
    let footer: String

    /// Heading, a blank line, the findings, a blank line and the footer. A part whose resource is empty is
    /// left out instead of leaving a blank paragraph.
    var text: String {
        [heading, lines.joined(separator: "\n"), footer].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// The two sentences around the list. Tests substitute fixed ones, because the localized strings arrive with
    /// the translations.
    struct Wording {
        var heading: (_ formatName: String) -> String
        var footer: String

        /// The presentation language's wording; numbers elsewhere in the report follow `locale`.
        static func localized(locale: Locale) -> Self {
            Self(heading: { PreviewStrings.format(.findingsReportHeading, arguments: [$0], locale: locale) },
                 footer: PreviewStrings.text(.findingsReportFooter))
        }
    }

    static func make(findings: [PreviewFinding], formatName: String, locale: Locale,
                     wording: Wording? = nil) -> FindingsReport {
        let wording = wording ?? .localized(locale: locale)
        return FindingsReport(heading: wording.heading(formatName),
                              lines: inBannerOrder(findings).map { line(for: $0, locale: locale) },
                              footer: wording.footer)
    }

    /// The format's localized name from the shared catalog, the same one the file-type settings list. A format
    /// the catalog does not know, or whose name resource is empty, falls back to its technical identifier, which
    /// is never localized and names no file.
    static func formatName(for format: FormatID, catalog: FormatCatalog = .standard) -> String {
        guard let descriptor = catalog.descriptor(for: format) else { return format.rawValue }
        let name = PreviewStrings.text(catalogKey: descriptor.nameKey)
        return name.isEmpty ? format.rawValue : name
    }

    /// The order the banner lists findings: a cloud-storage folder caution first, every other finding in the order
    /// the producers gave. The banner and the report share this one function, so they cannot disagree.
    static func inBannerOrder(_ findings: [PreviewFinding]) -> [PreviewFinding] {
        findings.filter { $0.kind == .secretSyncedFolder } + findings.filter { $0.kind != .secretSyncedFolder }
    }

    /// `• <severity>: <message>`, then the line or cell list in parentheses when the finding has one.
    static func line(for finding: PreviewFinding, locale: Locale) -> String {
        let severity = FindingText.severityDescription(finding.severity)
        var line = "• \(severity): \(FindingText.message(for: finding, locale: locale))"
        if let positions = positions(of: finding, locale: locale) { line += " (\(positions))" }
        return line
    }

    /// The banner's secondary line without the decoded text. `FindingText.detail` prefers decoded text to the
    /// positions, so a finding that carries it is described again without that detail, keeping its lines.
    private static func positions(of finding: PreviewFinding, locale: Locale) -> String? {
        guard case .decodedText = finding.detail else { return FindingText.detail(for: finding, locale: locale) }
        let withoutText = PreviewFinding(kind: finding.kind, severity: finding.severity, count: finding.count,
                                         lines: finding.lines)
        return FindingText.detail(for: withoutText, locale: locale)
    }
}

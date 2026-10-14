import AppKit
import Foundation
import PreviewContracts

/// The preview's half of Copy Findings Report (decision 029). The banner offers the action; the preview writes the
/// pasteboard and confirms, like every other copy: one chip and one announcement after a successful write, and
/// nothing when the write fails.
extension NativePreviewView {
    /// Copies the report of every finding the presentation carries, not only the rows the banner shows, to the
    /// preview's pasteboard. The report holds typed wording and positions only (see `FindingsReport`), so it passes
    /// no source text, file name or path to the clipboard. Returns whether anything was written.
    @discardableResult
    func copyFindingsReport() -> Bool {
        guard let presentation = safePresentation, !presentation.findings.isEmpty else { return false }
        let report = FindingsReport.make(findings: presentation.findings,
                                         formatName: FindingsReport.formatName(for: presentation.formatID),
                                         locale: presentationLocale)
        guard plainTextCopyWriter(report.text, pasteboard) else { return false }
        reportFindingsReportCopied()
        return true
    }

    /// The chip and the announcement of `reportCopy(_:)`, with the report's own wording. `PreviewCopyEvent` names
    /// its confirmation through its kind, so a `findingsReport` kind there would let this method be replaced by
    /// `reportCopy(.findingsReport)`.
    func reportFindingsReportCopied() {
        copyChipTimer?.cancel()
        let message = PreviewStrings.text(.findingsReportCopied)
        copyChipText = message
        refreshChip()
        announce(message)
        copyChipTimer = chromeScheduler.schedule(after: PreviewChrome.chipDuration) { [weak self] in
            self?.endCopyChip()
        }
    }
}

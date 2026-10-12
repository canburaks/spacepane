import Foundation
import PreviewContracts

/// One sentence about how the displayed text relates to the file, with the kind that decides where it is shown.
struct PresentationNotice: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Part of the file is not shown (a partial read, a page limit, protected text). Shown in the limits slot at
        /// the bottom of the preview, so it never pushes the content or the mode control around.
        case limit
        /// A plainer view stands in for a richer one (no structure could be built, a font was replaced).
        case fallback
        /// How the text was made or what was done to it (concealed, reformatted, shown as stored, approximated).
        /// Shown below the mode control, where the reader meets it before the content.
        case provenance
    }

    let kind: Kind
    let text: String
}

/// Status-line notices derived from an already-safe presentation, such as a partial read or a
/// formatted view. Each family appends its typed, localized notices below its own marker.
enum PresentationNotices {
    static func notices(for presentation: TextPresentation, locale: Locale) -> [PresentationNotice] {
        var notices: [PresentationNotice] = []
        // [diagrams]
        if presentation.syntax == .drawio, let pages = presentation.sourceRecordCount, pages > 1 {
            let text = PreviewStrings.format(.diagramDrawioPage, arguments: [Int64(pages)], locale: locale)
            notices.append(PresentationNotice(kind: .limit, text: text))
        }
        // [code]
        if let total = presentation.truncatedSourceBytes {
            // Byte counts follow the presentation locale; the order of the two counts is the translation's.
            let shown = Int64(presentation.byteCount).formatted(.byteCount(style: .file).locale(locale))
            let whole = Int64(total).formatted(.byteCount(style: .file).locale(locale))
            let text = PreviewStrings.format(.codeNoticeTruncated, arguments: [shown, whole], locale: locale)
            notices.append(PresentationNotice(kind: .limit, text: text))
        }
        if presentation.isReformatted {
            notices.append(PresentationNotice(kind: .provenance, text: PreviewStrings.text(.codeNoticeReformatted)))
        }
        // [markup]
        notices += NotebookPresentationNotices.notices(for: presentation, locale: locale)
        // [ebooks]
        // A protected or partial book, and the pages a comic shows of its total: what is not shown.
        notices += typed(DocumentPresentationNotices.lines(for: presentation, locale: locale), as: .limit)
        // [data]
        // [packages]
        // Signatures and certificates are shown as stored; nothing about their validity is claimed.
        if [FormatID.applicationBundle, .iosApp, .installerPackage, .provisioningProfile].contains(presentation.formatID) {
            notices.append(PresentationNotice(kind: .provenance, text: PreviewStrings.text(.packageNoticeSignature)))
        }
        if presentation.formatID == .certificate {
            notices.append(PresentationNotice(kind: .provenance, text: PreviewStrings.text(.packageNoticeCertificate)))
        }
        // [archives]
        // [mesh]
        return notices
    }

    /// The wording alone, for callers and tests that do not care where a notice is shown.
    static func lines(for presentation: TextPresentation, locale: Locale) -> [String] {
        notices(for: presentation, locale: locale).map(\.text)
    }

    /// Wraps already localized lines of one kind.
    static func typed(_ lines: [String], as kind: PresentationNotice.Kind) -> [PresentationNotice] {
        lines.map { PresentationNotice(kind: kind, text: $0) }
    }
}

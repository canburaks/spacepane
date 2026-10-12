import Foundation
import PreviewContracts

/// Summary schema written by the comic book adapter (`ComicBookAdapter`). Title, series, issue number and
/// writer come from the comic's own `ComicInfo.xml` and are shown verbatim; only the field names are
/// translated.
extension SummaryLabelSet {
    static let comicBook = SummaryLabelSet(
        formats: [.comicBook],
        fields: { parent in
            parent.isEmpty
                ? ["title", "series", "issueNumber", "writer", "pageCount", "declaredPageCount", "shownPages", "partial"] : nil
        },
        keys: [
            "title": .ebooksSummaryTitle, "series": .ebooksSummarySeries, "issueNumber": .ebooksSummaryIssueNumber,
            "writer": .ebooksSummaryWriter, "pageCount": .ebooksSummaryPageCount,
            "declaredPageCount": .ebooksSummaryDeclaredPageCount, "shownPages": .ebooksSummaryShownPages,
            "partial": .ebooksSummaryPartial
        ],
        verbatimFields: ["title", "series", "issueNumber", "writer"],
        booleanFields: ["partial"],
        countFields: ["pageCount", "declaredPageCount", "shownPages"])
}

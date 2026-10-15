import Foundation

/// The limits-strip notices of the Endpoints mode: the operations the row cap left out, and the path items this preview
/// cannot follow. Both say what is not shown, so both are limits. `ModePresentationNotices` asks for them in the
/// endpoints mode only, the same way it asks `DrawnModeNotices`.
enum OpenAPIEndpointNotices {
    static func notices(modes: SafePreviewModes, mode: NativePreviewMode, locale: Locale) -> [PresentationNotice] {
        guard mode == .endpoints, let list = modes.endpoints else { return [] }
        var notices: [PresentationNotice] = []
        if list.table.truncation.contains(.rows) {
            let total = list.totalOperations.formatted(.number.locale(locale))
            let text = PreviewStrings.count(.previewTableShownRowsOfTotal, list.table.rows.count,
                                            additionalArguments: [total], locale: locale)
            notices.append(PresentationNotice(kind: .limit, text: text))
        }
        if list.unresolvedReferences > 0 {
            let text = PreviewStrings.count(.openAPIUnresolvedReferences, list.unresolvedReferences, locale: locale)
            notices.append(PresentationNotice(kind: .limit, text: text))
        }
        return notices
    }
}

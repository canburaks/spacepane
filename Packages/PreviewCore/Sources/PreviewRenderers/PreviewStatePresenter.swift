import Foundation
import PreviewContracts

/// The one action a non-content state may offer.
enum StateAction: Equatable, Sendable {
    case openFile
    case enableFormat(FormatID)
    case showSource
}

/// What a non-content state says and offers. Titles and bodies come from `PreviewFailureCopy`, never from an
/// error's description or from the file, so a state shows no developer text and no file content.
struct NativeStateContent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case loading, empty, unavailable(PreviewFailure), disabled, settingsUnavailable, configurationUnavailable
    }

    let kind: Kind
    let title: String
    let body: String
    /// At most one. Always nil in the Finder extension, where nothing can open the companion.
    let action: StateAction?

    init(kind: Kind, title: String, body: String, action: StateAction? = nil) {
        self.kind = kind
        self.title = title
        self.body = body
        self.action = action
    }

    /// The words for `kind` in `locale`, from `PreviewFailureCopy`. Unknown limits retain the original wording.
    static func content(for kind: Kind, locale: Locale, action: StateAction? = nil,
                        limits: PreviewLimitsSummary? = nil) -> NativeStateContent {
        let copy = PreviewFailureCopy.content(forState: kind, locale: locale, limits: limits)
        return NativeStateContent(kind: kind, title: copy.title, body: copy.body, action: action)
    }

    /// A request that was cancelled shows nothing but the fact, with no body and no action.
    static func cancelled() -> NativeStateContent {
        NativeStateContent(kind: .empty, title: PreviewStrings.text(.cancelled), body: "")
    }

    /// Whether a ready presentation has nothing to show: a 0-byte file. The empty state replaces a blank pane.
    static func isEmpty(_ presentation: TextPresentation) -> Bool {
        presentation.text.isEmpty && presentation.images.isEmpty && presentation.midi == nil
    }
}

/// A state decision independent of views, loading timers and announcement delivery.
struct PreviewPresentedState: Equatable, Sendable {
    let content: NativeStateContent
    let announces: Bool
}

/// Composes state content and typed notices from safe values. It never owns a view, reads a file or constructs
/// a secondary presentation model; the facade supplies notices for the mode it has already selected.
enum PreviewStatePresenter {
    static func state(for outcome: PreviewOutcome, limits: PreviewBudget? = nil,
                      locale: Locale) -> PreviewPresentedState? {
        let summary = limits.flatMap { $0.isValid ? PreviewLimitsSummary(budget: $0) : nil }
        let kind: NativeStateContent.Kind
        switch outcome {
        case .disabledByUser:
            kind = .disabled
        case .unavailable(let failure):
            kind = .unavailable(failure)
        case .cancelled:
            return PreviewPresentedState(content: .cancelled(), announces: false)
        case .ready(let presentation) where NativeStateContent.isEmpty(presentation):
            kind = .empty
        case .ready, .geometryReady:
            return nil
        }
        return PreviewPresentedState(content: .content(for: kind, locale: locale, limits: summary), announces: true)
    }

    static func notices(for presentation: TextPresentation, mode: NativePreviewMode,
                        hasStructureFallback: Bool, markupNotices: [String], profileNotices: [String],
                        hasRecords: Bool, modeLimitNotices: [PresentationNotice] = [],
                        locale: Locale) -> [PresentationNotice] {
        var notices: [PresentationNotice] = []
        if hasStructureFallback {
            notices.append(PresentationNotice(kind: .fallback, text: PreviewStrings.text(.previewStructureFallback)))
        }
        notices += PresentationNotices.typed(markupNotices, as: .provenance)
        // The invisibles mode carries no note (owner, 2026-10-15).
        if mode == .profile {
            notices += PresentationNotices.typed(profileNotices, as: .provenance)
        }
        notices += PresentationNotices.notices(for: presentation, locale: locale)
        notices += modeLimitNotices
        if hasRecords, let line = presentation.invalidRecordLines.first {
            let invalid = PreviewStrings.format(.previewInvalidRecord, arguments: [Int64(line)], locale: locale)
            notices.append(PresentationNotice(kind: .fallback, text: invalid))
        }
        return notices
    }
}

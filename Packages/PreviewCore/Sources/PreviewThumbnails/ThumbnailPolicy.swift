import PreviewContracts

/// Why a request is answered with the content-free glyph. Hosts and tests read this; the glyph is
/// the same for every reason, so a reason never reveals anything about the file's content.
public enum ThumbnailFallbackReason: Equatable, Sendable {
    /// The shared settings snapshot is missing, corrupt, from a newer schema or in no App Group.
    case settingsUnavailable
    /// The user turned content thumbnails off.
    case contentThumbnailsOff
    case unsupportedType
    /// The user turned this file type off; no adapter is constructed.
    case disabledByUser
    /// The catalog keeps this format's thumbnail content-free (archives, folders, MIDI, CAD, environment files).
    case genericPolicy
    /// The pipeline declined or failed: unreadable, too large, malformed, binary or timed out.
    case unavailable
    case timedOut
    case cancelled
    /// The pipeline concealed values, so the document is withheld rather than summarized.
    case withheldConcealedContent
    /// The concealed text still looks credential-bearing (URL credentials, a private-key marker, a long
    /// token-like run) or the file name says it holds credentials, so nothing is drawn, not even a picture
    /// (decision 027, D14). The check is deliberately over-inclusive: a false positive costs only the glyph,
    /// while a miss would reach Finder's durable thumbnail cache. The file name decides and is never drawn.
    case withheldSecretShape
    /// The text is an app-made summary (an archive listing, a data or database description, package facts),
    /// not the document's own words, and no document picture could be drawn. Summary text is never drawn
    /// because it carries English schema keys that nothing localizes (decision 027, Q-10).
    case summaryText
    /// A readable document without anything worth drawing, or a presentation of an unexpected shape.
    case nothingToDraw
}

public enum ThumbnailDecision: Equatable, Sendable {
    case draw(FormatID)
    case fallback(ThumbnailFallbackReason)
}

/// The pure policy behind every thumbnail. It runs before an adapter exists, so a disabled or
/// content-free type never constructs a parser.
public enum ThumbnailPolicyEvaluator {
    /// Gate evaluated before the file is classified. `nil` means the request may continue.
    public static func preflight(preferences: PreviewPreferencesSnapshot?) -> ThumbnailFallbackReason? {
        guard let preferences else { return .settingsUnavailable }
        guard preferences.showsContentThumbnails else { return .contentThumbnailsOff }
        return nil
    }

    public static func resolve(_ inspection: PreviewInspection, catalog: FormatCatalog = .standard) -> ThumbnailDecision {
        switch inspection {
        case .unsupported:
            return .fallback(.unsupportedType)
        case .unavailable:
            return .fallback(.unavailable)
        case .disabledByUser:
            return .fallback(.disabledByUser)
        case .enabled(let format):
            guard let descriptor = catalog.descriptor(for: format), descriptor.thumbnail == .content,
                  descriptor.presentation == .text else { return .fallback(.genericPolicy) }
            return .draw(format)
        }
    }
}

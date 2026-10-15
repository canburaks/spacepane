import Foundation

/// App-owned provenance and command metadata only. The caller supplies the cached concealment count and the
/// already-localized provenance notes of the displayed content; source text, document values, file paths and parser
/// objects never enter this formatter.
@MainActor
enum PreviewInfoPanelCopy {
    static func lines(providerName: String?, concealedCount: Int, commands: [PreviewCommand], locale: Locale,
                      languagePreferences: [String]? = nil, provenance: [String] = []) -> [String] {
        var lines = [PreviewStrings.text(.readOnly, languagePreferences: languagePreferences),
            PreviewStrings.text(.previewInfoOnThisMac, languagePreferences: languagePreferences)]
        if let providerName, !providerName.isEmpty {
            lines.append(PreviewStrings.format(.interactionProviderBadge, arguments: [providerName], locale: locale,
                languagePreferences: languagePreferences))
        }
        if concealedCount >= 0 {
            lines.append(PreviewStrings.count(.previewInfoConcealedCount, concealedCount, locale: locale,
                languagePreferences: languagePreferences))
        }
        if !provenance.isEmpty {
            lines.append(PreviewStrings.text(.previewInfoNotesHeading, languagePreferences: languagePreferences))
            lines += provenance
        }
        if !commands.isEmpty {
            lines.append(PreviewStrings.text(.previewInfoCommandsHeading, languagePreferences: languagePreferences))
        }
        lines += commands.map { command in
            PreviewStrings.format(.previewInfoCommand, arguments: [command.localizedTitle(locale: locale,
                languagePreferences: languagePreferences), command.shortcutDescription], locale: locale,
                languagePreferences: languagePreferences)
        }
        return lines
    }
}

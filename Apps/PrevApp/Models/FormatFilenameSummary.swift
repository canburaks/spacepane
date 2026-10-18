import Foundation
import PreviewContracts
import PreviewRenderers

/// Catalog spellings are source identifiers; only the surrounding list punctuation
/// and conjunction follow the UI locale. A prefix is shown as a filename pattern.
struct FormatFilenameSummary {
    let patterns: [String]

    init(_ descriptor: FormatDescriptor) {
        let candidates = descriptor.suffixAliases.map { "." + $0 }
            + descriptor.filenameAliases
            + descriptor.filenamePrefixes.map { $0 + "*" }
        var seen: Set<String> = []
        patterns = candidates.filter { seen.insert($0).inserted }
    }

    /// How many patterns the short form names before it counts the rest.
    static let visiblePatterns = 4

    /// Every pattern, for places that must show the whole claim.
    func text(locale: Locale) -> String {
        patterns.formatted(.list(type: .and).locale(locale))
    }

    /// The first patterns and the count of the rest, for the caption, the tooltip and VoiceOver, so a type with
    /// hundreds of patterns cannot fill the row or a spoken label. Search still reads every pattern.
    func shortText(locale: Locale) -> String {
        let hidden = patterns.count - Self.visiblePatterns
        guard hidden > 0 else { return text(locale: locale) }
        let shown = Array(patterns.prefix(Self.visiblePatterns)).formatted(.list(type: .and).locale(locale))
        return PreviewStrings.format(.providersFormatsMore, arguments: [shown, hidden], locale: locale)
    }
}

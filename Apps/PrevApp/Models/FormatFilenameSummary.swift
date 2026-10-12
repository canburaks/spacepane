import Foundation
import PreviewContracts

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

    func text(locale: Locale) -> String {
        patterns.formatted(.list(type: .and).locale(locale))
    }
}

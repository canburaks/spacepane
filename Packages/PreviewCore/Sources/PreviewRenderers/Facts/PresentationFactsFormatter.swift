import Foundation
import PreviewContracts

/// Complete localized scalar templates, flattened before the regular/compact display budget is applied.
enum PresentationFactsFormatter {
    static func lines(for facts: PresentationFacts, compact: Bool, locale: Locale,
                      languagePreferences: [String]? = nil) -> [String] {
        var lines: [String] = []
        func lowerBound(_ value: String, _ isLowerBound: Bool) -> String {
            isLowerBound ? PreviewStrings.format(.previewFactsLowerBound, arguments: [value], locale: locale,
                languagePreferences: languagePreferences) : value
        }
        func count(_ value: Int, lower: Bool = false, template: (String) -> String) {
            guard value >= 0 else { return }
            lines.append(template(lowerBound(value.formatted(.number.locale(locale)), lower)))
        }
        func size(_ value: Int64) -> String { SafeListingFormatting.sizeText(value, locale: locale) }
        for fact in facts.facts {
            switch fact {
            case .encoding(let encoding): lines.append(encodingName(encoding))
            case .lines(let value):
                if value >= 0 {
                    lines.append(PreviewStrings.count(.previewCountLines, value, locale: locale,
                        languagePreferences: languagePreferences))
                }
            case .size(let bytes):
                if bytes >= 0 {
                    lines.append(PreviewStrings.format(.previewFactsSize, arguments: [size(bytes)], locale: locale,
                        languagePreferences: languagePreferences))
                }
            case .shownSize(let shown, let total):
                if shown >= 0, total >= shown {
                    lines.append(PreviewStrings.format(.previewFactsReadSize, arguments: [size(shown), size(total)],
                        locale: locale, languagePreferences: languagePreferences))
                }
            case .grid(let rows, let columns, let lower):
                count(rows, lower: lower) {
                    PreviewStrings.format(.previewFactsRows, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
                count(columns) {
                    PreviewStrings.format(.previewFactsColumns, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
            case .records(let value, let kind, let lower):
                count(value, lower: lower) { recordLine(kind, value: $0, locale: locale,
                    languagePreferences: languagePreferences) }
            case .nodes(let value, let lower):
                count(value, lower: lower) {
                    PreviewStrings.format(.previewFactsNodes, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
            case .listing(let files, let folders, let lower, let bytes):
                count(files, lower: lower) {
                    PreviewStrings.format(.previewFactsListedFiles, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
                count(folders, lower: lower) {
                    PreviewStrings.format(.previewFactsListedFolders, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
                if let bytes, bytes >= 0 {
                    lines.append(PreviewStrings.format(.previewFactsListedSize, arguments: [lowerBound(size(bytes), lower)],
                        locale: locale, languagePreferences: languagePreferences))
                }
            case .geometry(let faces, let bodies, let extent, let unit, let lower):
                count(faces, lower: lower) {
                    PreviewStrings.format(.previewFactsFaces, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
                if extent.x.isFinite, extent.y.isFinite, extent.z.isFinite,
                   extent.x >= 0, extent.y >= 0, extent.z >= 0 {
                    let units = GeometrySummaryUnits(unit)
                    let scale = units?.millimetresPerUnit ?? 1
                    let converted = [extent.x, extent.y, extent.z].map { $0 / scale }
                    if converted.allSatisfy({ $0.isFinite && $0 >= 0 }) {
                        let dimensions = converted.map {
                            $0.formatted(.number.locale(locale).precision(.fractionLength(0...3)))
                        }
                        switch unit {
                        case .undeclared:
                            lines.append(PreviewStrings.format(.previewFactsDimensionsUnitless, arguments: dimensions,
                                locale: locale, languagePreferences: languagePreferences))
                        case .declared:
                            if let units {
                                lines.append(PreviewStrings.format(.previewFactsDimensions,
                                    arguments: dimensions + [units.lengthSymbol(locale: locale)], locale: locale,
                                    languagePreferences: languagePreferences))
                            }
                        case .assumedMillimetres:
                            if let units {
                                lines.append(PreviewStrings.format(.previewFactsDimensionsAssumed,
                                    arguments: dimensions + [units.lengthSymbol(locale: locale)], locale: locale,
                                    languagePreferences: languagePreferences))
                            }
                        }
                    }
                }
                if let bodies {
                    count(bodies) {
                        PreviewStrings.format(.previewFactsBodies, arguments: [$0], locale: locale,
                            languagePreferences: languagePreferences)
                    }
                }
            case .playback(let tracks, let seconds):
                count(tracks) {
                    PreviewStrings.format(.previewFactsTracks, arguments: [$0], locale: locale,
                        languagePreferences: languagePreferences)
                }
                if let duration = FactsDurationFormatting.text(seconds, locale: locale) {
                    lines.append(PreviewStrings.format(.previewFactsDuration, arguments: [duration], locale: locale,
                        languagePreferences: languagePreferences))
                }
            case .pixels(let width, let height):
                if width > 0, height > 0 {
                    lines.append(PreviewStrings.format(.previewFactsPixels,
                        arguments: [width.formatted(.number.locale(locale)), height.formatted(.number.locale(locale))],
                        locale: locale, languagePreferences: languagePreferences))
                }
            }
        }
        return Array(lines.prefix(compact ? PresentationFacts.compactCount : PresentationFacts.regularCount))
    }

    private static func encodingName(_ encoding: TextEncoding) -> String {
        switch encoding {
        case .utf8: "UTF-8"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .codePage437: "CP437"
        }
    }

    private static func recordLine(_ kind: PresentationFacts.RecordKind, value: String, locale: Locale,
                                   languagePreferences: [String]?) -> String {
        switch kind {
        case .records:
            PreviewStrings.format(.previewFactsRecords, arguments: [value], locale: locale,
                languagePreferences: languagePreferences)
        case .cues:
            PreviewStrings.format(.previewFactsCues, arguments: [value], locale: locale,
                languagePreferences: languagePreferences)
        case .pages:
            PreviewStrings.format(.previewFactsPages, arguments: [value], locale: locale,
                languagePreferences: languagePreferences)
        case .cells:
            PreviewStrings.format(.previewFactsCells, arguments: [value], locale: locale,
                languagePreferences: languagePreferences)
        case .events:
            PreviewStrings.format(.previewFactsEvents, arguments: [value], locale: locale,
                languagePreferences: languagePreferences)
        case .images:
            PreviewStrings.format(.previewFactsEmbeddedImages, arguments: [value], locale: locale,
                languagePreferences: languagePreferences)
        }
    }
}

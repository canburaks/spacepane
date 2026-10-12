import Foundation
import PreviewContracts

/// Lists the cues of the code family's caption dialects from concealed text, using the same
/// `CaptionParser` the adapter validated with. Rows follow the SubRip/WebVTT shape: `name` is an optional
/// label (SubStation style and actor), the start, and for ranges an arrow and the end; `value` is the cue
/// text lines joined by " / ". Lyrics tags (`ti`, `ar`, `al`, ...) come first as `key`/`value` rows. Times,
/// labels and text are source content and are never localized, so the locale does not affect the rows.
///
/// Returns `nil` (structure fallback with safe source) when the text no longer parses, has no cue, exceeds
/// the display limits, or its cue count differs from the adapter's `expectedCueCount`, which is how a
/// secret that concealment swallowed along with following cues is detected.
enum CaptionCueNodes {
    static let maximumUTF16Units = 1_048_576
    private static let identifierSeparator = ": "
    private static let timingJoiner = " \u{2192} "
    private static let lineJoiner = " / "

    static func dialect(for syntax: TextSyntax) -> CaptionDialect? {
        switch syntax {
        case .subStationAlpha: .subStationAlpha
        case .timedText: .timedText
        case .subViewer: .subViewer
        case .lyrics: .lyrics
        case .microDVD: .microDVD
        default: nil
        }
    }

    static func nodes(_ safeText: String, dialect: CaptionDialect, expectedCueCount: Int?) -> [SafeOutlineNode]? {
        guard safeText.utf16.prefix(maximumUTF16Units + 1).count <= maximumUTF16Units,
              let document = try? CaptionParser.parse(Array(safeText.utf8), dialect: dialect),
              !document.cues.isEmpty, expectedCueCount == nil || expectedCueCount == document.cues.count else { return nil }
        var rows: [SafeOutlineNode] = []
        for item in document.metadata {
            rows.append(SafeOutlineNode(id: rows.count, name: item.key, value: item.value))
        }
        for cue in document.cues {
            let prefix = cue.label.map { $0 + identifierSeparator } ?? ""
            let range = cue.end.map { cue.start + timingJoiner + $0 } ?? cue.start
            rows.append(SafeOutlineNode(id: rows.count, name: prefix + range, value: cue.lines.joined(separator: lineJoiner)))
        }
        return rows
    }
}

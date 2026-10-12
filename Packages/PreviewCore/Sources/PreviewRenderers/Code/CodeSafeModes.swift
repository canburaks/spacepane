import Foundation
import PreviewContracts

/// The derived modes of the code family: an INI outline, a JSON-with-comments outline, the cue lists of
/// the caption dialects and the keys-by-languages table of a String Catalog. Every model is derived from the already-concealed presentation text, never from
/// source bytes. `SafePreviewModes` calls this once per presentation, below its `[code]` marker.
enum CodeSafeModes {
    struct Derived {
        var outline: [SafeOutlineNode]?
        var cues: [SafeOutlineNode]?
        var table: SafeTable?
        /// A structured view was expected but could not be built, so the safe source stands in for it.
        var hasStructureFallback: Bool
        /// `false` when the base derivations still own the outline and fallback (an extra view over JSON).
        var replacesStructure = true
    }

    static func derive(_ presentation: TextPresentation, locale: Locale) -> Derived? {
        switch presentation.syntax {
        case .json:
            // String Catalogs add a keys-by-languages table next to the ordinary JSON modes.
            guard presentation.formatID == .json, let table = SafeStringCatalogTable.table(presentation.text, locale: locale) else { return nil }
            return Derived(outline: nil, cues: nil, table: table, hasStructureFallback: false, replacesStructure: false)
        case .ini:
            let outline = SafeINIDocument.nodes(presentation.text)
            return Derived(outline: outline, cues: nil, table: nil, hasStructureFallback: outline == nil)
        case .jsonWithComments:
            let outline = SafeJSONCOutline.nodes(presentation.text)
            return Derived(outline: outline, cues: nil, table: nil, hasStructureFallback: outline == nil)
        case .subStationAlpha, .timedText, .subViewer, .lyrics, .microDVD:
            guard let dialect = CaptionCueNodes.dialect(for: presentation.syntax) else { return nil }
            let cues = CaptionCueNodes.nodes(presentation.text, dialect: dialect, expectedCueCount: presentation.sourceRecordCount)
            return Derived(outline: nil, cues: cues, table: nil, hasStructureFallback: cues == nil)
        default:
            return nil
        }
    }
}

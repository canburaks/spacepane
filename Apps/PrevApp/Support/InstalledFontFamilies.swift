import AppKit

/// Font discovery is the only AppKit capability needed by the settings controls.
/// The persisted choice remains a family name, independent of AppKit font objects.
@MainActor enum InstalledFontFamilies {
    static func available() -> FontFamilyList {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        // A family counts as fixed width when one of its fonts carries the fixed-pitch trait.
        var fixedWidthFamilies: Set<String> = []
        for fontName in manager.availableFontNames(with: .fixedPitchFontMask) ?? [] {
            if let family = NSFont(name: fontName, size: 12)?.familyName { fixedWidthFamilies.insert(family) }
        }
        return FontFamilyList(families: families, fixedWidthFamilies: fixedWidthFamilies)
    }
}

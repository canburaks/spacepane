import Foundation

/// Installed font families for the Typography picker: the fixed-width families first, because that is what
/// source text wants, then every other family. Each list keeps the order the caller supplied.
struct FontFamilyList: Equatable, Sendable {
    let fixedWidth: [String]
    let others: [String]

    static let empty = FontFamilyList(fixedWidth: [], others: [])

    init(fixedWidth: [String], others: [String]) {
        self.fixedWidth = fixedWidth
        self.others = others
    }

    /// Splits `families` by membership in `fixedWidthFamilies`; no family is dropped or listed twice.
    init(families: [String], fixedWidthFamilies: Set<String>) {
        fixedWidth = families.filter { fixedWidthFamilies.contains($0) }
        others = families.filter { !fixedWidthFamilies.contains($0) }
    }

    var isEmpty: Bool { fixedWidth.isEmpty && others.isEmpty }

    func contains(_ family: String) -> Bool {
        fixedWidth.contains(family) || others.contains(family)
    }
}

import AppKit
import PreviewContracts

/// One appearance pass prepares a bounded dictionary per semantic role. Token and
/// cell lookups reuse resolved fonts and the typography's immutable paragraph style.
/// This contains no source text and is replaced when typography, palette or traits change.
@MainActor
struct NativeTextStylePass {
    let baseAttributes: [NSAttributedString.Key: Any]
    private let roleAttributes: [PreviewSyntaxRole: [NSAttributedString.Key: Any]]

    init(typography: NativeTextTypography, palette: NativeTextPalette, syntaxStyle: PreviewSyntaxStyle) {
        baseAttributes = typography.attributes(foreground: palette.foreground)
        roleAttributes = Dictionary(uniqueKeysWithValues: PreviewSyntaxRole.allCases.map { role in
            (role, typography.attributes(foreground: palette.color(for: role, style: syntaxStyle),
                                         role: role, style: syntaxStyle))
        })
    }

    func attributes(for role: PreviewSyntaxRole) -> [NSAttributedString.Key: Any] {
        roleAttributes[role] ?? baseAttributes
    }
}

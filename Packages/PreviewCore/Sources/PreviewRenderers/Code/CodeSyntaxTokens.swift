import Foundation
import PreviewContracts

/// Chooses the decoration for the code family's syntaxes: language profiles for source code, and
/// dedicated line tokenizers for INI files, logs and captions. `nil` means the syntax is not one of
/// theirs and the caller keeps its generic rules. All of them read only already-concealed text, color
/// the first `maximumUTF16Units` code units and return at most `maximumTokens` tokens.
enum CodeSyntaxTokens {
    static func tokens(in source: String, syntax: TextSyntax, language: SourceLanguageID?,
                       maximumUTF16Units: Int, maximumTokens: Int) -> [JSONSyntaxToken]? {
        switch syntax {
        case .sourceCode:
            guard let language, let profile = SourceLanguageProfiles.profile(for: language) else { return nil }
            return ProfiledSourceTokenizer.tokens(in: units(source, maximumUTF16Units), profile: profile, maximumTokens: maximumTokens)
        case .jsonWithComments:
            return ProfiledSourceTokenizer.tokens(in: units(source, maximumUTF16Units), profile: jsonWithComments, maximumTokens: maximumTokens)
        case .timedText:
            return ProfiledSourceTokenizer.tokens(in: units(source, maximumUTF16Units), profile: SourceLanguageProfile(markup: .html),
                                                  maximumTokens: maximumTokens)
        case .ini:
            return LineSyntaxTokens.ini(units(source, maximumUTF16Units), maximumTokens: maximumTokens)
        case .log:
            return LineSyntaxTokens.log(units(source, maximumUTF16Units), maximumTokens: maximumTokens)
        case .subStationAlpha, .subViewer, .lyrics, .microDVD:
            return CaptionSyntaxTokens.tokens(units(source, maximumUTF16Units), syntax: syntax, maximumTokens: maximumTokens)
        default:
            return nil
        }
    }

    /// The leading code units, never ending inside a surrogate pair.
    static func units(_ source: String, _ maximum: Int) -> [UInt16] {
        var units = Array(source.utf16.prefix(maximum))
        if let last = units.last, (0xD800...0xDBFF).contains(last) { units.removeLast() }
        return units
    }

    /// JSONC and JSON5: comments, single-quoted strings, unquoted keys, hexadecimal and signed numbers.
    private static let jsonWithComments = SourceLanguageProfile(
        lineComments: [LineComment("//")], blockComments: [BlockComment("/*", "*/")],
        strings: [StringForm("\""), StringForm("'")],
        literals: "true false null Infinity NaN", identifierExtras: "$", keyStyle: .anyColon, operators: "",
        allowsUnderscoreInNumbers: false, allowsLeadingDotNumbers: true, stringKeys: true)
}

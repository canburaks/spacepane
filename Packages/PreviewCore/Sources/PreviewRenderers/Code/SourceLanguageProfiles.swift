import Foundation
import PreviewContracts

/// The table of lexical profiles, one per `SourceLanguageID` the detector can produce. Each family of
/// languages lives in its own file (`SourceLanguageProfiles+*.swift`); this file only assembles them.
/// Adding a language is a new entry in a family file plus its identifier in `SourceLanguageID.all`;
/// the tokenizer and the renderer are untouched.
enum SourceLanguageProfiles {
    static func profile(for language: SourceLanguageID) -> SourceLanguageProfile? { table[language] }

    /// Built once, on first use. Languages that share a lexical shape share a profile value.
    static let table: [SourceLanguageID: SourceLanguageProfile] = {
        var result: [SourceLanguageID: SourceLanguageProfile] = [:]
        for family in [compiledLanguages, scriptingLanguages, shellLanguages, hardwareLanguages, queryLanguages,
                       buildLanguages, webLanguages, shaderLanguages] {
            result.merge(family()) { current, _ in current }
        }
        return result
    }()
}

typealias LineComment = SourceLanguageProfile.LineCommentSpec
typealias BlockComment = SourceLanguageProfile.BlockCommentSpec
typealias StringForm = SourceLanguageProfile.StringSpec

/// Shared pieces of the C-family syntax.
enum CFamilySyntax {
    static let lineAndBlock: (lines: [LineComment], blocks: [BlockComment]) =
        ([LineComment("//")], [BlockComment("/*", "*/")])
    static let plainStrings: [StringForm] = [StringForm("\""), StringForm("'", character: true)]
}

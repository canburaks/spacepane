import Foundation
import PreviewContracts

/// The lexical shape of one source language, as data. The tokenizer (`ProfiledSourceTokenizer`) is the
/// only code that interprets it, so adding a language is a table entry, not a parser. Profiles describe
/// comments, string and character forms, numeric literals, keyword sets, preprocessor lines and a few
/// naming conventions. They are deliberately lexical: no grammar, no scoping, no semantic promises.
struct SourceLanguageProfile: Sendable {
    /// How string-like text ends. `role` lets quoted identifiers (SQL `"name"`) use another color.
    struct StringSpec: Sendable {
        let open: [UInt16]
        let close: [UInt16]
        /// Unit that escapes the next unit (backslash, or backtick in PowerShell); `nil` for none.
        let escape: UInt16?
        /// A doubled closing quote stands for itself (`''` in SQL, Pascal and Fortran).
        let doubledQuote: Bool
        let multiline: Bool
        /// A character literal: only a single (possibly escaped) character may sit between the quotes,
        /// so the same `'` is left alone where it is an apostrophe, a lifetime or a type variable.
        let isCharacter: Bool
        let role: PreviewSyntaxRole

        init(_ open: String, close: String? = nil, escape: Character? = "\\", doubledQuote: Bool = false,
             multiline: Bool = false, character: Bool = false, role: PreviewSyntaxRole = .string) {
            self.open = Array(open.utf16)
            self.close = Array((close ?? open).utf16)
            self.escape = escape.flatMap { $0.utf16.first }
            self.doubledQuote = doubledQuote
            self.multiline = multiline
            self.isCharacter = character
            self.role = role
        }
    }

    struct BlockCommentSpec: Sendable {
        let open: [UInt16]
        let close: [UInt16]
        let nests: Bool
        /// Only recognized as the first thing on a line (Ruby `=begin`, Perl `=pod`).
        let lineStartOnly: Bool
        init(_ open: String, _ close: String, nests: Bool = false, lineStartOnly: Bool = false) {
            self.open = Array(open.utf16)
            self.close = Array(close.utf16)
            self.nests = nests
            self.lineStartOnly = lineStartOnly
        }
    }

    struct LineCommentSpec: Sendable {
        let marker: [UInt16]
        /// Only a comment at the start of a word (shell `#`, so `$#` and `${#x}` are not comments).
        let atWordStart: Bool
        /// Only a comment as the first thing on a line (`.gitignore`, Dockerfile `#`).
        let lineStartOnly: Bool
        /// Not a comment when directly followed by a symbol character (Haskell `-->` is an operator).
        let notBeforeSymbol: Bool
        init(_ marker: String, atWordStart: Bool = false, lineStartOnly: Bool = false, notBeforeSymbol: Bool = false) {
            self.marker = Array(marker.utf16)
            self.atWordStart = atWordStart
            self.lineStartOnly = lineStartOnly
            self.notBeforeSymbol = notBeforeSymbol
        }
    }

    enum Preprocessor: Sendable {
        case none
        /// `#directive` as the first token of a line (C family, GLSL, Objective-C).
        case hashAtLineStart
        /// `#word` anywhere (Swift `#if`, `#available`, `#selector`).
        case hashAnywhere
        /// A backtick directive at the start of a line (Verilog `` `define ``).
        case backtickAtLineStart
    }

    /// Which identifiers are colored as keys: those followed by `=` or `:`.
    enum KeyStyle: Sendable {
        case none
        /// `name=value` with no blanks, as in shell assignments.
        case immediateEquals
        /// `name = value` with optional blanks (HCL, Nix, Makefile variables).
        case spacedEquals
        /// `name: value` where a blank follows the colon (CSS declarations, so `a:hover` is untouched).
        case declarationColon
        /// `name:` with nothing required after the colon (unquoted JSON5 keys).
        case anyColon
    }

    enum MarkupStyle: Sendable {
        case html
        /// HTML plus `{{ }}`, `{% %}`, `{# #}`, `<% %>` and `{ }` template delimiters.
        case template
    }

    let lineComments: [LineCommentSpec]
    let blockComments: [BlockCommentSpec]
    let strings: [StringSpec]
    let keywords: Set<String>
    let types: Set<String>
    let literals: Set<String>
    let caseInsensitive: Bool
    /// Identifiers that start with a capital and contain a lowercase letter are type names.
    let capitalizedTypes: Bool
    let preprocessor: Preprocessor
    /// `@name` annotations and decorators.
    let decorators: Bool
    /// Rust `#[...]` and `#![...]` attributes.
    let rustAttributes: Bool
    /// Extra characters allowed inside identifiers (`-` in Lisp and CSS, `?!` in Ruby).
    let identifierExtras: Set<UInt16>
    /// Characters that start a variable, which is never a keyword (`$name`, `@name`, `%name`).
    let variableSigils: Set<UInt16>
    let keyStyle: KeyStyle
    /// Operator characters; consecutive ones become one token.
    let operators: Set<UInt16>
    let markup: MarkupStyle?
    /// Letters that may prefix a quoted string (`r"..."`, `b'...'`, `f"..."`), compared lowercased.
    let stringPrefixes: Set<String>
    /// Rust raw strings `r#"..."#` and Swift extended delimiters `#"..."#`.
    let hashDelimitedStrings: Bool
    /// Lua long brackets `[[ ]]`, `[==[ ]==]` for strings and `--[[ ]]` for comments.
    let longBrackets: Bool
    /// Numeric literal conventions.
    let allowsUnderscoreInNumbers: Bool
    let allowsLeadingDotNumbers: Bool
    /// A quoted string followed by `:` is a key (JSON-like documents).
    let stringKeys: Bool
    /// Verilog sized and based literals such as `4'b1010` and `'hFF`.
    let basedNumbers: Bool
    /// `$` and `0x`-less hexadecimal as in assembler (`$FF`).
    let dollarHexNumbers: Bool

    init(lineComments: [LineCommentSpec] = [], blockComments: [BlockCommentSpec] = [], strings: [StringSpec] = [],
         keywords: String = "", types: String = "", literals: String = "true false null",
         caseInsensitive: Bool = false, capitalizedTypes: Bool = false, preprocessor: Preprocessor = .none,
         decorators: Bool = false, rustAttributes: Bool = false, identifierExtras: String = "", variableSigils: String = "",
         keyStyle: KeyStyle = .none, operators: String = "+-*/%=<>!&|^~", markup: MarkupStyle? = nil,
         stringPrefixes: String = "", hashDelimitedStrings: Bool = false, longBrackets: Bool = false,
         allowsUnderscoreInNumbers: Bool = true, allowsLeadingDotNumbers: Bool = false,
         stringKeys: Bool = false, basedNumbers: Bool = false, dollarHexNumbers: Bool = false) {
        func words(_ text: String) -> Set<String> {
            Set(text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { caseInsensitive ? $0.lowercased() : String($0) })
        }
        self.lineComments = lineComments
        self.blockComments = blockComments
        self.strings = strings
        self.keywords = words(keywords)
        self.types = words(types)
        self.literals = words(literals)
        self.caseInsensitive = caseInsensitive
        self.capitalizedTypes = capitalizedTypes
        self.preprocessor = preprocessor
        self.decorators = decorators
        self.rustAttributes = rustAttributes
        self.identifierExtras = Set(identifierExtras.utf16)
        self.variableSigils = Set(variableSigils.utf16)
        self.keyStyle = keyStyle
        self.operators = Set(operators.utf16)
        self.markup = markup
        self.stringPrefixes = Set(stringPrefixes.split(separator: " ").map { String($0).lowercased() })
        self.hashDelimitedStrings = hashDelimitedStrings
        self.longBrackets = longBrackets
        self.allowsUnderscoreInNumbers = allowsUnderscoreInNumbers
        self.allowsLeadingDotNumbers = allowsLeadingDotNumbers
        self.stringKeys = stringKeys
        self.basedNumbers = basedNumbers
        self.dollarHexNumbers = dollarHexNumbers
        // Longest openers first, so `"""` is tried before `"` and `///` before `//`.
        var table: [UInt16: [Starter]] = [:]
        for comment in lineComments { table[comment.marker[0], default: []].append(.lineComment(comment)) }
        for comment in blockComments { table[comment.open[0], default: []].append(.blockComment(comment)) }
        for string in strings { table[string.open[0], default: []].append(.string(string)) }
        self.starters = table.mapValues { $0.sorted { $0.length > $1.length } }
    }

    /// Candidates for the unit at a position, longest opener first.
    enum Starter: Sendable {
        case lineComment(LineCommentSpec)
        case blockComment(BlockCommentSpec)
        case string(StringSpec)
        var length: Int {
            switch self {
            case .lineComment(let spec): spec.marker.count
            case .blockComment(let spec): spec.open.count
            case .string(let spec): spec.open.count
            }
        }
    }
    let starters: [UInt16: [Starter]]
}

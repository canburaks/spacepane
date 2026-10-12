import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

struct Piece: Equatable, CustomStringConvertible {
    let text: String
    let role: PreviewSyntaxRole
    init(_ text: String, _ role: PreviewSyntaxRole) { self.text = text; self.role = role }
    var description: String { "\(role):\(text)" }
}

/// The decorated substrings of `source` for a language, in order.
func pieces(_ source: String, _ language: SourceLanguageID, units: Int = 262_144, tokens: Int = 20_000) -> [Piece] {
    let text = source as NSString
    return SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: language, maximumUTF16Units: units, maximumTokens: tokens)
        .map { Piece(text.substring(with: $0.range), $0.role) }
}

/// Invariants every tokenization must keep: in bounds, ordered, non-overlapping, never empty.
func expectWellFormed(_ source: String, _ language: SourceLanguageID, sourceLocation: SourceLocation = #_sourceLocation) {
    let length = source.utf16.count
    let result = SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: language)
    var previousEnd = 0
    for token in result {
        #expect(token.range.length > 0 && token.range.location >= previousEnd && NSMaxRange(token.range) <= length,
                "\(language.rawValue): \(token.range) after \(previousEnd) of \(length)", sourceLocation: sourceLocation)
        previousEnd = NSMaxRange(token.range)
    }
}

@Suite("Language-aware source decoration")
struct ProfiledSourceTokenizerTests {
    @Test func everyLanguageHasAProfileAndOnlyThose() {
        for language in SourceLanguageID.all { #expect(SourceLanguageProfiles.profile(for: language) != nil, "\(language.rawValue)") }
        #expect(Set(SourceLanguageProfiles.table.keys) == Set(SourceLanguageID.all))
        #expect(SourceLanguageProfiles.table.count >= 60)
    }

    @Test func cFamilyCommentsStringsCharactersNumbersAndDirectives() {
        let source = "#include <stdio.h>\nint main(void) { // entry\n  char c = '\\n'; /* block */ double d = 0x1F + 1.5e-3 + 10UL;\n  return printf(\"hi\\\"there\"); }\n"
        let result = pieces(source, .c)
        #expect(result.contains(Piece("#include", .keyword)))
        #expect(result.contains(Piece("int", .type)) && result.contains(Piece("return", .keyword)) && result.contains(Piece("void", .type)))
        #expect(result.contains(Piece("// entry", .comment)) && result.contains(Piece("/* block */", .comment)))
        #expect(result.contains(Piece("'\\n'", .string)) && result.contains(Piece("\"hi\\\"there\"", .string)))
        #expect(result.contains(Piece("0x1F", .number)) && result.contains(Piece("1.5e-3", .number)) && result.contains(Piece("10UL", .number)))
        expectWellFormed(source, .c)
    }

    @Test func preprocessorLinesOnlyCountAtTheStartOfALine() {
        #expect(pieces("x = 1 # not a directive\n", .c).allSatisfy { $0.role != .keyword })
        #expect(pieces("  #  define X 1\n", .c).contains(Piece("#  define", .keyword)))
    }

    @Test func unterminatedConstructsEndAtTheLineOrTheText() {
        #expect(pieces("let a = \"open\nlet b = 1\n", .swift).contains(Piece("\"open", .string)))
        let block = pieces("x /* never closed\nstill comment", .c)
        #expect(block.last == Piece("/* never closed\nstill comment", .comment))
        let multiline = pieces("let s = \"\"\"\nline\nnever closed", .swift)
        #expect(multiline.last == Piece("\"\"\"\nline\nnever closed", .string))
    }

    @Test func swiftNestsBlockCommentsAndKnowsRawStringsDirectivesAndAttributes() {
        let source = "/* a /* nested */ still */ @MainActor struct Box<Item>: Equatable { let raw = #\"a \\n \"quoted\"\"#; #if DEBUG\n var count: Int = 1_000\n #endif }"
        let result = pieces(source, .swift)
        #expect(result.contains(Piece("/* a /* nested */ still */", .comment)))
        #expect(result.contains(Piece("@MainActor", .tag)) && result.contains(Piece("struct", .keyword)))
        #expect(result.contains(Piece("Box", .type)) && result.contains(Piece("Item", .type)) && result.contains(Piece("Int", .type)))
        #expect(result.contains(Piece("#\"a \\n \"quoted\"\"#", .string)))
        #expect(result.contains(Piece("#if", .keyword)) && result.contains(Piece("#endif", .keyword)))
        #expect(result.contains(Piece("1_000", .number)))
        expectWellFormed(source, .swift)
    }

    @Test func rustLifetimesAreNotCharactersAndRawStringsAndAttributesAreRecognized() {
        let source = "#[derive(Debug)]\nfn first<'a>(s: &'a str) -> &'a str { let c = 'x'; let r = r#\"raw \"q\" \"#; let n = 0xff_u8; s }\n"
        let result = pieces(source, .rust)
        #expect(result.contains(Piece("#[derive(Debug)]", .tag)))
        #expect(result.contains(Piece("'x'", .string)) && result.contains(Piece("r#\"raw \"q\" \"#", .string)))
        #expect(!result.contains { $0.text.hasPrefix("'a") })
        #expect(result.contains(Piece("fn", .keyword)) && result.contains(Piece("str", .type)) && result.contains(Piece("0xff_u8", .number)))
        expectWellFormed(source, .rust)
    }

    @Test func pythonPrefixesTripleQuotesDecoratorsAndNumbers() {
        let source = "@decorator\ndef f(x):  # note\n    s = f\"value {x}\" + r'raw\\d' + \"\"\"doc\nstring\"\"\"\n    return 0b101 + 1_000 + 2.5e3 if x is None else True\n"
        let result = pieces(source, .python)
        #expect(result.contains(Piece("@decorator", .tag)) && result.contains(Piece("def", .keyword)) && result.contains(Piece("# note", .comment)))
        #expect(result.contains(Piece("f\"value {x}\"", .string)) && result.contains(Piece("r'raw\\d'", .string)))
        #expect(result.contains(Piece("\"\"\"doc\nstring\"\"\"", .string)))
        #expect(result.contains(Piece("0b101", .number)) && result.contains(Piece("1_000", .number)) && result.contains(Piece("2.5e3", .number)))
        #expect(result.contains(Piece("None", .literal)) && result.contains(Piece("True", .literal)))
        expectWellFormed(source, .python)
    }

    @Test func javaScriptTemplateLiteralsAndOperators() {
        let source = "const f = async (x) => `a ${x}\nb`; // tail\nlet big = 10n + 0xFF;"
        let result = pieces(source, .javascript)
        #expect(result.contains(Piece("const", .keyword)) && result.contains(Piece("async", .keyword)))
        #expect(result.contains(Piece("`a ${x}\nb`", .string)) && result.contains(Piece("=>", .operator)))
        #expect(result.contains(Piece("10n", .number)) && result.contains(Piece("// tail", .comment)))
    }

    @Test func sqlIsCaseInsensitiveWithDoubledQuotesAndQuotedIdentifiers() {
        let result = pieces("SELECT \"Name\", 'it''s' FROM users -- note\nwhere id = 1 AND flag IS NULL; /* c */", .sql)
        #expect(result.contains(Piece("SELECT", .keyword)) && result.contains(Piece("FROM", .keyword)) && result.contains(Piece("where", .keyword)))
        #expect(result.contains(Piece("\"Name\"", .key)) && result.contains(Piece("'it''s'", .string)))
        #expect(result.contains(Piece("-- note", .comment)) && result.contains(Piece("NULL", .literal)) && result.contains(Piece("/* c */", .comment)))
    }

    @Test func shellCommentsStartAtWordsAndAssignmentsAreKeys() {
        let source = "# top\nNAME=value echo $# ${#x} 'it\\' # kept\necho \"a # b\" # real\nif [ -f x ]; then :; fi\n"
        let result = pieces(source, .shell)
        #expect(result.first == Piece("# top", .comment))
        #expect(result.contains(Piece("NAME", .key)) && result.contains(Piece("'it\\'", .string)))
        #expect(result.contains(Piece("# kept", .comment)) && result.contains(Piece("# real", .comment)))
        #expect(!result.contains { $0.role == .comment && $0.text.contains("{#x}") || $0.text == "#" })
        #expect(result.contains(Piece("\"a # b\"", .string)) && result.contains(Piece("if", .keyword)) && result.contains(Piece("fi", .keyword)))
    }

    @Test func luaLongBracketsAndComments() {
        let source = "--[==[ long\ncomment ]==] local s = [[multi\nline]] -- line\nlocal t = [=[x]=]\n"
        let result = pieces(source, .lua)
        #expect(result.first == Piece("--[==[ long\ncomment ]==]", .comment))
        #expect(result.contains(Piece("[[multi\nline]]", .string)) && result.contains(Piece("[=[x]=]", .string)))
        #expect(result.contains(Piece("-- line", .comment)) && result.contains(Piece("local", .keyword)))
    }

    @Test func haskellDoubleDashOperatorsAndNestedComments() {
        let result = pieces("x --> y -- real comment\n{- a {- b -} c -} f' = 'c'", .haskell)
        #expect(result.contains(Piece("-->", .operator)) && result.contains(Piece("-- real comment", .comment)))
        #expect(result.contains(Piece("{- a {- b -} c -}", .comment)) && result.contains(Piece("'c'", .string)))
    }

    @Test func lispFamilyKeepsHyphenatedNamesTogetherAndNestsBlockComments() {
        let result = pieces("(defn my-fn [x] ; comment\n  (if-let [y x] y nil))\n#| a #| b |# c |#", .clojure)
        #expect(result.contains(Piece("defn", .keyword)) && result.contains(Piece("if-let", .keyword)) && result.contains(Piece("nil", .literal)))
        #expect(result.contains(Piece("; comment", .comment)))
        #expect(!result.contains { $0.role == .operator })
        #expect(pieces("#| a #| b |# c |#", .lisp) == [Piece("#| a #| b |# c |#", .comment)])
    }

    @Test func cssDeclarationsAreKeysAndSelectorsAreNot() {
        let result = pieces("@media (min-width: 1px) { a:hover { color: red; margin: 10px } } /* c */", .css)
        #expect(result.contains(Piece("@media", .tag)) && result.contains(Piece("color", .key)) && result.contains(Piece("margin", .key)))
        #expect(!result.contains(Piece("a", .key)) && result.contains(Piece("10px", .number)) && result.contains(Piece("/* c */", .comment)))
    }

    @Test func infrastructureLanguagesColorKeysAndLineStartComments() {
        #expect(pieces("# real\nFROM x # not a comment here\nENV KEY=value\n", .dockerfile).contains(Piece("# real", .comment)))
        #expect(!pieces("FROM x # not a comment here\n", .dockerfile).contains { $0.role == .comment })
        let hcl = pieces("resource \"a\" \"b\" {\n  name = \"x\" # c\n  count == 1\n}\n", .hcl)
        #expect(hcl.contains(Piece("name", .key)) && !hcl.contains(Piece("count", .key)) && hcl.contains(Piece("# c", .comment)))
        #expect(pieces("CC := gcc\nOBJ = a.o\n", .makefile).filter { $0.role == .key }.map(\.text) == ["CC", "OBJ"])
        #expect(pieces("# c\n!keep\nfoo # literal hash\n", .ignoreList) == [Piece("# c", .comment), Piece("!", .operator)])
        #expect(pieces("add_executable(app main.c) # c\n#[[ block ]]", .cmake).contains(Piece("#[[ block ]]", .comment)))
    }

    @Test func hardwareLanguagesRecognizeBasedLiteralsAndDirectives() {
        let verilog = pieces("`define W 8\nwire [7:0] a = 4'b1010 + 8'hFF; // c\n", .verilog)
        #expect(verilog.contains(Piece("`define", .keyword)) && verilog.contains(Piece("4'b1010", .number)) && verilog.contains(Piece("8'hFF", .number)))
        #expect(pieces("signal s : std_logic := '1'; -- c", .vhdl).contains(Piece("'1'", .string)))
    }

    @Test func markupLanguagesColorTagsAttributesStringsAndTemplateDelimiters() {
        let result = pieces("<!-- c --><div class=\"a\" @click=go>{{ name }}</div><br/>", .vue)
        #expect(result.contains(Piece("<!-- c -->", .comment)) && result.contains(Piece("<div", .tag)) && result.contains(Piece("class", .key)))
        #expect(result.contains(Piece("\"a\"", .string)) && result.contains(Piece("@click", .key)) && result.contains(Piece("{{ name }}", .keyword)))
        #expect(result.contains(Piece("</div", .tag)) && result.contains(Piece("/>", .tag)))
        #expect(!pieces("{{ not template }}", .html).contains { $0.role == .keyword })
    }

    @Test func unicodeRangesAreExactUTF16Offsets() {
        let source = "let s = \"😀 café\" // 日本語 🙂\nlet n = 42\n"
        let ns = source as NSString
        for token in SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: .swift) {
            #expect(NSMaxRange(token.range) <= ns.length)
        }
        let result = pieces(source, .swift)
        #expect(result.contains(Piece("\"😀 café\"", .string)) && result.contains(Piece("// 日本語 🙂", .comment)) && result.contains(Piece("42", .number)))
        expectWellFormed(source, .swift)
    }

    @Test func budgetsKeepAPrefixAndNeverSplitASurrogatePair() {
        let source = "let a = 1\nlet b = 2\nlet c = 3\n"
        // The token cap keeps the earliest tokens.
        let full = pieces(source, .swift)
        #expect(pieces(source, .swift, tokens: 2) == Array(full.prefix(2)))
        // The unit cap decorates only the leading units.
        let limited = pieces(source, .swift, units: 11)
        #expect(limited.allSatisfy { $0.text != "c" } && limited.contains(Piece("let", .keyword)))
        // A cap that ends in the middle of a pair drops the dangling half.
        let emoji = "a = \"😀\""
        let cut = SourceSyntaxTokens.tokens(in: emoji, syntax: .sourceCode, language: .python, maximumUTF16Units: 6, maximumTokens: 100)
        #expect(cut.allSatisfy { NSMaxRange($0.range) <= 5 })
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: .swift, maximumUTF16Units: 0).isEmpty)
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: .swift, maximumTokens: 0).isEmpty)
    }

    @Test func aNilOrUnknownLanguageKeepsTheGenericBehaviorAndPlainStaysPlain() {
        let source = "let value = 42 // note\n"
        let generic = SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode)
        #expect(!generic.isEmpty)
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: SourceLanguageID(rawValue: "klingon")) == generic)
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .plain, language: .swift).isEmpty)
        // The language only applies to source code: other syntaxes ignore it.
        #expect(SourceSyntaxTokens.tokens(in: "{\"a\": 1}", syntax: .json, language: .swift) == JSONSyntaxTokens.tokens(in: "{\"a\": 1}"))
    }

    @Test func tokenizationIsWellFormedForEveryLanguageOnHostileInput() {
        let samples = [
            "", "\"", "'", "`", "/*", "//", "#", "\"\"\"", "'''", "\\", "\\\"", "(*", "{-", "--[[", "[==[", "r#\"", "#\"", "<!--", "<",
            "<a href=\"", "{{", "<%", "0x", "1e", "1e+", ".5.", "$", "@", "@@", "#[", "#![x", "'\\", "'\\u{", "\u{FFFD}", "😀", "a\u{0}b",
            String(repeating: "(", count: 500), String(repeating: "/*", count: 300), String(repeating: "\"", count: 301), "x = \"😀\\\n"
        ]
        for language in SourceLanguageID.all {
            for sample in samples {
                expectWellFormed(sample, language)
                expectWellFormed(sample + "\n" + sample, language)
            }
        }
    }

    @Test func largeInputsStayLinear() {
        let line = "let value = foo(\"text\", 42) // trailing comment\n"
        let source = String(repeating: line, count: 4_000)             // ~190 KB, within the unit cap
        let start = ContinuousClock.now
        let result = SourceSyntaxTokens.tokens(in: source, syntax: .sourceCode, language: .swift)
        let elapsed = ContinuousClock.now - start
        #expect(result.count > 10_000 && elapsed < .seconds(5))
        let nested = String(repeating: "/*", count: 100_000)
        #expect(SourceSyntaxTokens.tokens(in: nested, syntax: .sourceCode, language: .swift).count == 1)
    }
}

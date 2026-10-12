import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private let english = Locale(identifier: "en")

private func presentation(_ format: FormatID, _ text: String, _ syntax: TextSyntax, records: Int? = nil,
                          language: SourceLanguageID? = nil, truncated: Int? = nil, reformatted: Bool = false) -> TextPresentation {
    TextPresentation(formatID: format, text: text, lineCount: text.components(separatedBy: "\n").count, byteCount: text.utf8.count,
                     encoding: .utf8, redactionCount: 0, syntax: syntax, sourceRecordCount: records, sourceLanguage: language,
                     truncatedSourceBytes: truncated, isReformatted: reformatted)
}

private func flatten(_ nodes: [SafeOutlineNode]) -> [String] {
    nodes.flatMap { [$0.name + "=" + $0.value] + flatten($0.children).map { "  " + $0 } }
}

@Suite("INI outline")
struct INIOutlineTests {
    @Test func sectionsContainTheirSettingsAndGlobalKeysComeFirst() throws {
        let source = "global = 1\n; comment\n[server]\nhost = localhost\nport: 8080\nlist = a, \\\n  b\n\n[empty]\n[server]\nhost = other\n"
        let nodes = try #require(SafeINIDocument.nodes(source))
        #expect(flatten(nodes) == ["global=1", "server=", "  host=localhost", "  port=8080", "  list=a, b", "empty=", "server=", "  host=other"])
        // A section name used twice is flagged, as are repeated keys inside a section.
        #expect(nodes[1].isDuplicateKey && nodes[3].isDuplicateKey && !nodes[2].isDuplicateKey)
        let repeated = try #require(SafeINIDocument.nodes("[a]\nk=1\nk=2\n"))
        #expect(repeated[0].children.allSatisfy { $0.isDuplicateKey })
    }

    @Test func concealedValuesAreScalars() throws {
        let nodes = try #require(SafeINIDocument.nodes("[auth]\npassword = ••••\n//registry.example/:_authToken=••••\nrequirepass ••••\n"))
        #expect(flatten(nodes) == ["auth=", "  password=••••", "  //registry.example/:_authToken=••••", "  requirepass=••••"])
    }

    @Test(arguments: ["server {\n  listen 80;\n}\n", "[unclosed\nk=v\n", "[]\n", "= no name\n", "}\n", "bind {\n", "a=b\n[x[y]]\n"])
    func linesThatCannotBeSettingsDeclineTheOutline(source: String) {
        #expect(SafeINIDocument.nodes(source) == nil)
    }

    @Test func limitsDeclineTheViewInsteadOfTruncating() {
        #expect(SafeINIDocument.nodes(String(repeating: "x", count: 262_145)) == nil)
        let many = (0..<20_001).map { "k\($0)=v" }.joined(separator: "\n")
        #expect(SafeINIDocument.nodes(many) == nil)
    }
}

@Suite("JSON with comments outline")
struct JSONCOutlineTests {
    @Test func theLenientGrammarBuildsTheSameShapeAsStrictJSON() throws {
        let source = "{ // c\n  a: 1, 'b': [true, null, 0xFF,], \"c\": {x: 'y'}, /* n */ d: \"é\\u00e9\\x41\" }"
        let nodes = try #require(SafeJSONCOutline.nodes(source))
        #expect(flatten(nodes) == ["$={…}", "  a=1", "  b=[…]", "    [0]=true", "    [1]=null", "    [2]=0xFF", "  c={…}", "    x=y", "  d=ééA"])
    }

    @Test func concealedValuesAndDuplicateKeys() throws {
        let nodes = try #require(SafeJSONCOutline.nodes("{password: ••••, \"k\": 1, 'k': 2, // note\n}"))
        let root = nodes[0]
        #expect(root.children.map(\.value) == ["••••", "1", "2"])
        #expect(root.children.map(\.isDuplicateKey) == [false, true, true])
    }

    @Test(arguments: ["", "{", "{a}", "{a: }", "[1 2]", "{a: 1} x", "'unterminated", "/* open", "{a: undefined}", "{\"a\": \"\\q\u{0}\"}x", "[,]"])
    func malformedConcealedTextDeclinesTheOutline(source: String) {
        #expect(SafeJSONCOutline.nodes(source) == nil)
    }

    @Test func boundsDeclineTheViewInsteadOfOverflowing() {
        #expect(SafeJSONCOutline.nodes(String(repeating: "[", count: 70) + String(repeating: "]", count: 70)) == nil)
        #expect(SafeJSONCOutline.nodes("[1,2,3]", maximumNodes: 3) == nil)
        #expect(SafeJSONCOutline.nodes(String(repeating: " ", count: 100), maximumUTF16Units: 10) == nil)
    }
}

@Suite("Derived modes of the code family")
struct CodeSafeModesTests {
    @Test func iniAndJSONCOfferOutlineWithSourceFirst() throws {
        let ini = SafePreviewModes(presentation(.iniConfiguration, "[a]\nb = 1\n", .ini), locale: english)
        #expect(ini.available == [.source, .outline] && ini.initialMode(for: .iniConfiguration) == .source && !ini.hasStructureFallback)
        let jsonc = SafePreviewModes(presentation(.jsonWithComments, "{a: 1, // c\n}", .jsonWithComments), locale: english)
        #expect(jsonc.available == [.source, .outline] && jsonc.initialMode(for: .jsonWithComments) == .source)
        let outline = try #require(jsonc.nodes(for: .outline))
        #expect(outline.first?.children.first?.value == "1")
    }

    @Test func aStructureThatCannotBeDerivedFallsBackToSource() {
        let nginx = SafePreviewModes(presentation(.iniConfiguration, "server {\n}\n", .ini), locale: english)
        #expect(nginx.available == [.source] && nginx.hasStructureFallback)
        let damaged = SafePreviewModes(presentation(.jsonWithComments, "{a: ••••", .jsonWithComments), locale: english)
        #expect(damaged.available == [.source] && damaged.hasStructureFallback)
    }

    @Test(arguments: [
        (FormatID.subStationAlpha, TextSyntax.subStationAlpha, "[Script Info]\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:04.00,Default,Ann,0,0,0,,Hi{\\i1}!\\Nthere\n", "Default / Ann: 0:00:01.00 → 0:00:04.00", "Hi! / there"),
        (.timedText, .timedText, "<tt><body><p begin=\"1s\" end=\"2s\">Hi<br/>there</p></body></tt>", "1s → 2s", "Hi / there"),
        (.subViewer, .subViewer, "0:00:01.000,0:00:04.000\nHi\nthere\n", "0:00:01.000 → 0:00:04.000", "Hi / there"),
        (.lyrics, .lyrics, "[00:12.00]Hi there\n", "00:12.00", "Hi there"),
        (.microDVD, .microDVD, "{25}{100}Hi|there\n", "0:00:01.000 → 0:00:04.000", "Hi / there")
    ]) func captionDialectsListCuesAsTimedRows(format: FormatID, syntax: TextSyntax, text: String, name: String, value: String) throws {
        let modes = SafePreviewModes(presentation(format, text, syntax, records: 1), locale: english)
        #expect(modes.available == [.source, .cues] && modes.initialMode(for: format) == .source)
        let row = try #require(modes.nodes(for: .cues)?.last)
        #expect(row.name == name && row.value == value)
    }

    @Test func lyricsTagsComeFirstAsKeyValueRows() throws {
        let modes = SafePreviewModes(presentation(.lyrics, "[ti:Song]\n[ar:Artist]\n[00:12.00]Hi\n", .lyrics, records: 1), locale: english)
        let rows = try #require(modes.nodes(for: .cues))
        #expect(rows.map(\.name) == ["ti", "ar", "00:12.00"] && rows.map(\.value) == ["Song", "Artist", "Hi"])
    }

    @Test func aCueCountThatConcealmentCollapsedFallsBackToSource() {
        let collapsed = SafePreviewModes(presentation(.subViewer, "0:00:01.000,0:00:04.000\nHi\n", .subViewer, records: 2), locale: english)
        #expect(collapsed.available == [.source] && collapsed.hasStructureFallback)
        let broken = SafePreviewModes(presentation(.lyrics, "plain text", .lyrics, records: 1), locale: english)
        #expect(broken.available == [.source] && broken.hasStructureFallback)
        let empty = SafePreviewModes(presentation(.subStationAlpha, "[Script Info]\n", .subStationAlpha, records: 0), locale: english)
        #expect(empty.cues == nil && empty.hasStructureFallback)
    }

    @Test func logsAndSourceKeepOnlySourceAndOtherFamiliesAreUntouched() {
        #expect(SafePreviewModes(presentation(.log, "2026 INFO x\n", .log), locale: english).available == [.source])
        #expect(SafePreviewModes(presentation(.sourceCode, "let x = 1\n", .sourceCode, language: .swift), locale: english).available == [.source])
        #expect(SafePreviewModes(presentation(.subRip, "1\n00:00:01,000 --> 00:00:02,000\nHi\n", .subRip, records: 1), locale: english).available == [.source, .cues])
        #expect(SafePreviewModes(presentation(.json, "{\"a\": 1}", .json), locale: english).available == [.source, .outline])
    }
}

@Suite("Presentation notices of the code family")
struct CodeNoticeTests {
    @Test func aPartialPresentationNamesBothSizesInTheLocaleOfTheNotice() {
        let partial = presentation(.plainText, "line\n", .plain, truncated: 2_500_000)
        let lines = PresentationNotices.lines(for: partial, locale: Locale(identifier: "en_US"))
        #expect(lines.count == 1)
        // "Showing the first 5 bytes of 2.5 MB" with locale-formatted counts.
        #expect(lines[0].contains("5") && lines[0].contains("2.5") && lines[0].lowercased().contains("first"))
        let german = PresentationNotices.lines(for: partial, locale: Locale(identifier: "de_DE"))
        #expect(german[0].contains("2,5"))
    }

    @Test func aReformattedPresentationSaysSo() {
        let lines = PresentationNotices.lines(for: presentation(.json, "{}", .json, reformatted: true), locale: english)
        #expect(lines == [PreviewStrings.text(.codeNoticeReformatted)])
        #expect(lines[0] == "Formatted for display")
    }

    @Test func ordinaryPresentationsHaveNoNotice() {
        #expect(PresentationNotices.lines(for: presentation(.plainText, "x", .plain), locale: english).isEmpty)
    }

    @Test func bothNoticesCanAppearTogetherAndEveryLanguageHasThem() {
        let both = presentation(.json, "{}", .json, truncated: 10, reformatted: true)
        #expect(PresentationNotices.lines(for: both, locale: english).count == 2)
        for language in ["en", "tr", "de", "fr", "zh-Hans", "ja", "hi", "ku-Latn", "ru", "id", "bn", "ha", "pt", "es"] {
            let reformatted = PreviewStrings.text(.codeNoticeReformatted, languagePreferences: [language])
            let template = PreviewStrings.text(.codeNoticeTruncated, languagePreferences: [language])
            #expect(!reformatted.isEmpty && !reformatted.contains("preview.code"), "\(language)")
            #expect(template.contains("%1$@") && template.contains("%2$@"), "\(language)")
        }
    }
}

@MainActor
@Suite("Native view with a language hint", .serialized)
struct LanguageAwareNativeViewTests {
    @Test func theViewColorsKeywordsAndCommentsOfTheNamedLanguageAndNotOfTheGenericRules() throws {
        let source = "fn main() { let x = 1; } // tail\n"
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        let outcome = PreviewOutcome.ready(presentation(.sourceCode, source, .sourceCode, language: .rust))
        view.display(outcome, typography: PreviewTypography(), theme: .light, resetsContentState: true)
        let scroll = view.scrollView
        let storage = try #require((scroll.documentView as? NSTextView)?.textStorage)
        let base = try #require(storage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor)       // "(" has no role
        let keyword = try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)    // "fn" is a Rust keyword
        let comment = try #require(storage.attribute(.foregroundColor, at: source.utf16.count - 8, effectiveRange: nil) as? NSColor)
        #expect(keyword != base && comment != base && keyword != comment)
        #expect(storage.string == source)
    }

    @Test func differentLanguagesDecorateTheSameCharactersDifferently() throws {
        let source = "fn main() { let x = 1; } // tail\n"
        func keywordColor(_ language: SourceLanguageID?) throws -> NSColor {
            let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
            view.display(.ready(presentation(.sourceCode, source, .sourceCode, language: language)), typography: PreviewTypography(),
                         theme: .light, resetsContentState: true)
            let scroll = view.scrollView
            let storage = try #require((scroll.documentView as? NSTextView)?.textStorage)
            return try #require(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        }
        let rust = try keywordColor(.rust)
        let python = try keywordColor(.python)       // `fn` is not a Python keyword
        #expect(rust != python)
    }
}

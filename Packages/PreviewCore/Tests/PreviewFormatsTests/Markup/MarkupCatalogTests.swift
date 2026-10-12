import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewFormats

private let markupFormats: [(id: FormatID, suffixes: [String], syntax: TextSyntax)] = [
    (.latex, ["tex", "ltx", "sty", "cls"], .latex),
    (.bibtex, ["bib"], .bibtex),
    (.asciidoc, ["adoc", "asciidoc"], .asciidoc),
    (.restructuredText, ["rst", "rest"], .restructuredText),
    (.org, ["org"], .orgMode),
    (.fountain, ["fountain", "spmd"], .fountain)
]

@Suite("Markup catalog entries")
struct MarkupCatalogTests {
    @Test func stableIdentifiersAreExactlyThePublishedOnes() {
        #expect(FormatID.latex.rawValue == "text.latex")
        #expect(FormatID.bibtex.rawValue == "text.bibtex")
        #expect(FormatID.asciidoc.rawValue == "text.asciidoc")
        #expect(FormatID.restructuredText.rawValue == "text.restructuredtext")
        #expect(FormatID.org.rawValue == "text.org")
        #expect(FormatID.fountain.rawValue == "text.fountain")
    }

    @Test func newEntriesFollowMarkdownAndKeepTheirSuffixesGroupAndContentThumbnails() throws {
        let catalog = FormatCatalog.standard
        let order = catalog.descriptors.map(\.id)
        let markdownIndex = try #require(order.firstIndex(of: .markdown))
        #expect(Array(order[(markdownIndex + 1)...(markdownIndex + 6)]) == markupFormats.map(\.id))
        for (id, suffixes, _) in markupFormats {
            let descriptor = try #require(catalog.descriptor(for: id))
            #expect(descriptor.suffixAliases == suffixes)
            #expect(descriptor.group == .text)
            #expect(descriptor.presentation == .text)
            #expect(descriptor.thumbnail == .content)
            #expect(descriptor.defaultEnabled)
            // None of these has a first-party system type, so the canonical one is an app-selected imported identifier.
            #expect(descriptor.canonicalContentType.identifier.hasPrefix("org.webmeister.spacepane.type."))
        }
    }

    @Test func markdownGainsEightSuffixesAndKeepsItsOwnThumbnailPolicy() throws {
        let descriptor = try #require(FormatCatalog.standard.descriptor(for: .markdown))
        for suffix in ["md", "markdown", "mdown", "mkd", "mdx", "rmd", "qmd", "mkdn", "mdwn", "mdtxt", "mdtext", "markdn"] {
            #expect(descriptor.suffixAliases.contains(suffix), "\(suffix)")
            #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/file.\(suffix)")) == .markdown, "\(suffix)")
        }
        // The thumbnails workstream owns this value and draws Markdown content (decision 022).
        #expect(descriptor.thumbnail == .content)
    }

    @Test func suffixesClassifyCaseInsensitivelyWithoutReadingTheFile() {
        let catalog = FormatCatalog.standard
        for (id, suffixes, _) in markupFormats {
            for suffix in suffixes {
                #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/Report.\(suffix)")) == id)
                #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/REPORT.\(suffix.uppercased())")) == id)
            }
        }
    }

    @Test func armoredPGPSuffixIsNotClaimedByAsciiDoc() {
        let catalog = FormatCatalog.standard
        #expect(catalog.classify(url: URL(fileURLWithPath: "/unused/key.asc")) == nil)
        #expect(catalog.descriptor(for: .asciidoc)?.suffixAliases.contains("asc") == false)
    }

    @Test func eachMarkupTypeIsOwnedByOneFormatAndNeverARootType() {
        let descriptors = FormatCatalog.standard.descriptors
        let family = Set(markupFormats.map(\.id)).union([.markdown])
        for descriptor in descriptors where family.contains(descriptor.id) {
            for type in descriptor.contentTypes {
                #expect(descriptors.filter { $0.contentTypes.contains(type) }.count == 1, "\(type.identifier) shared")
                #expect(type != .data && type != .item && type != .content)
            }
        }
    }

    @Test func importedTypeConstructionWorksWithoutARegisteredHost() throws {
        for (id, _, _) in markupFormats {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: id))
            // The canonical imported type loads in an unregistered process and classifies by exact match.
            #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/unused/noaliasfile"), contentType: descriptor.canonicalContentType) == id)
        }
    }

    @Test func registrationsExistForEveryMarkupFormatAndAreIndependentOfPlainText() {
        let registered = Set(StandardFormatAdapters.registrations.map(\.formatID))
        for (id, _, _) in markupFormats { #expect(registered.contains(id)) }
        #expect(Set(MarkupFormatAdapters.registrations.map(\.formatID)) == Set(markupFormats.map(\.id)))
        #expect(registered.count == StandardFormatAdapters.registrations.count)
    }

    @Test func eachAdapterSuppliesItsSyntaxHint() throws {
        let context = RequestContext(budget: .standard)
        let input = DecodedText(text: "x", encoding: .utf8, byteCount: 1)
        for registration in MarkupFormatAdapters.registrations {
            guard case .text(let factory) = registration.inputPath else { Issue.record("Expected text adapters"); continue }
            let expected = try #require(markupFormats.first { $0.id == registration.formatID }).syntax
            #expect(try factory().parse(input, context: context).syntax == expected)
        }
        #expect(try MarkdownSourceAdapter().parse(input, context: context).syntax == .markdown)
    }
}

@Suite("Markup adapter budgets")
struct MarkupAdapterBudgetTests {
    private let adapters: [(String, any FormatAdapter)] = [
        ("markdown", MarkdownSourceAdapter()), ("latex", LaTeXSourceAdapter()), ("bibtex", BibTeXSourceAdapter()),
        ("asciidoc", AsciiDocSourceAdapter()), ("rst", ReStructuredTextSourceAdapter()), ("org", OrgSourceAdapter()),
        ("fountain", FountainSourceAdapter())
    ]

    @Test func inputLineAndLengthBudgetsFailTyped() {
        for (name, adapter) in adapters {
            let big = DecodedText(text: String(repeating: "a", count: 65), encoding: .utf8, byteCount: 65)
            #expect(throws: PreviewFailure.inputTooLarge, "\(name)") { try adapter.parse(big, context: .init(budget: .init(maxInputBytes: 64))) }
            #expect(throws: PreviewFailure.lineTooLong, "\(name)") { try adapter.parse(big, context: .init(budget: .init(maxLineUTF8Bytes: 64))) }
            let lines = DecodedText(text: "a\nb\nc", encoding: .utf8, byteCount: 5)
            #expect(throws: PreviewFailure.tooManyLines, "\(name)") { try adapter.parse(lines, context: .init(budget: .init(maxTextLines: 2))) }
            let wide = DecodedText(text: "ab", encoding: .utf8, byteCount: 2)
            #expect(throws: PreviewFailure.outputTooLarge, "\(name)") { try adapter.parse(wide, context: .init(budget: .init(maxOutputUTF8Bytes: 1))) }
        }
    }

    @Test func cancellationAndExpiredDeadlinesAreCheckedBeforeAnyInputWork() async {
        let input = DecodedText(text: "# t\n---\nkey: value\n---\n", encoding: .utf8, byteCount: 24)
        for (name, adapter) in adapters {
            #expect(throws: PreviewFailure.deadlineExceeded, "\(name)") { try adapter.parse(input, context: .init(budget: .init(maxMilliseconds: 0))) }
        }
        let task = Task.detached { [adapters] in
            withUnsafeCurrentTask { $0?.cancel() }
            for (name, adapter) in adapters {
                #expect(throws: CancellationError.self, "\(name)") { try adapter.parse(input, context: .init(budget: .standard)) }
            }
        }
        await task.value
    }

    @Test func adaptersNeverChangeTheDecodedText() throws {
        let text = "\u{FEFF}Line 😀 mixed\r\nsecond\tline\u{2028}end"
        let input = DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count)
        for (name, adapter) in adapters {
            let result = try adapter.parse(input, context: .init(budget: .standard))
            #expect(result.text.utf8.elementsEqual(text.utf8), "\(name)")
        }
    }

    @Test func privacyPlannersAreBoundedOnAdversarialInput() throws {
        let hostile = [
            String(repeating: "\\password{", count: 400), String(repeating: "%", count: 100_000),
            "---\n" + String(repeating: "a: |\n  ", count: 500) + "---\n",
            "#+PROPERTY: " + String(repeating: "password ", count: 5_000),
            String(repeating: ".. |token| replace:: ", count: 1_000)
        ]
        let started = ContinuousClock.now
        for text in hostile {
            let input = DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count)
            for (_, adapter) in adapters { _ = try? adapter.parse(input, context: .init(budget: .standard)) }
        }
        #expect(ContinuousClock.now - started < .seconds(20))
    }
}

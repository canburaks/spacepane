import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private struct Converted {
    let text: String
    let outcome: HTMLMarkdownConverter.Outcome
    let writer: MarkdownWriter
}

private func convert(_ html: String, fallbackHeading: String? = nil,
                     budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> Converted {
    let context = documentContext(budget)
    var writer = MarkdownWriter(context: context)
    var nodes = budget.maxJSONNodes * 4
    let outcome = try HTMLMarkdownConverter.convert(html, into: &writer, fallbackHeading: fallbackHeading,
                                                    nodeBudget: &nodes, context: context)
    return Converted(text: writer.text, outcome: outcome, writer: writer)
}

private func markdown(_ html: String, fallbackHeading: String? = nil) throws -> String {
    try convert(html, fallbackHeading: fallbackHeading).text
}

@Suite("HTML to Markdown converter")
struct HTMLMarkdownConverterTests {
    // MARK: Structure

    @Test func headingsParagraphsAndInlineEmphasis() throws {
        #expect(try markdown("<h1>Title</h1><p>Hello <em>world</em> and <strong>bold</strong>.</p>")
                == "# Title\n\nHello *world* and **bold**.\n")
        #expect(try markdown("<h3>Third</h3><h6>Sixth</h6>") == "### Third\n\n###### Sixth\n")
    }

    @Test func nestedListsKeepTheirIndentation() throws {
        #expect(try markdown("<ul><li>One<ul><li>Nested</li></ul></li><li>Two</li></ul>") == "- One\n  - Nested\n- Two\n")
        #expect(try markdown(#"<ol start="3"><li>a</li><li>b</li></ol>"#) == "3. a\n4. b\n")
    }

    @Test func blockQuotesNestAndPrefixEveryLine() throws {
        #expect(try markdown("<blockquote><p>Quoted <b>text</b></p></blockquote>") == "> Quoted **text**\n")
        #expect(try markdown("<blockquote><blockquote><p>Deep</p></blockquote></blockquote>") == "> > Deep\n")
    }

    @Test func preformattedTextBecomesAFenceThatCannotBeClosedByItsContent() throws {
        #expect(try markdown("<pre><code>let x = 1;\n  y</code></pre>") == "```\nlet x = 1;\n  y\n```\n")
        #expect(try markdown("<pre>```\nx</pre>") == "~~~\n```\nx\n~~~\n")
        let both = try markdown("<pre>```\n~~~\nx</pre>")
        #expect(both.hasPrefix("```\n"))
        #expect(both.contains("\u{200B}```"))
    }

    @Test func inlineCodeEscapesBackticksAndIgnoresMarkdownCharacters() throws {
        #expect(try markdown("<p>Run <code>a*b_c`d</code> now</p>") == "Run `a*b_c'd` now\n")
    }

    @Test func tablesBecomePipeRowsWithPipesReplaced() throws {
        let table = "<table><tr><th>Name</th><th>Qty</th></tr><tr><td>Pen</td><td>2 | 3</td></tr></table>"
        #expect(try markdown(table) == "| Name | Qty |\n| --- | --- |\n| Pen | 2 ¦ 3 |\n")
    }

    @Test func imagesBecomeInertMarkdownImagesWithEscapedAltTextAndNeverKeepTheirSource() throws {
        // `![alt]()` carries the description only; the renderer draws one localized marker for it (decision 027, Q-07).
        let result = try markdown(#"<p><img src="https://example.com/pixel.png?token=abc" alt="A *cat*"/></p>"#)
        #expect(result == #"![A \*cat\*]()"# + "\n")
        #expect(!result.contains("pixel.png") && !result.contains("token"))
        #expect(try markdown(#"<img src="x.png">"#).isEmpty)
    }

    @Test func linksKeepOnlyTheirReadableText() throws {
        let result = try markdown(#"<p>See <a href="https://example.com/?api_key=abc">the guide</a>.</p>"#)
        #expect(result == "See the guide.\n")
    }

    @Test func lineBreaksStartNewLinesInTheSameParagraph() throws {
        #expect(try markdown("<DIV><P>One<BR>Two</div></p>") == "One\nTwo\n")
        #expect(try markdown("<p><em>one<br>two</em></p>") == "*one*\n*two*\n")
    }

    // MARK: Entities, tolerance, dropped content

    @Test func entitiesDecodeButNeverExpandDeclarations() throws {
        #expect(try markdown("<p>Caf&eacute; &amp; &#x41;&#66; &mdash; &bogus;&nbsp;x</p>") == "Café & AB — &bogus;\u{A0}x\n")
        #expect(try markdown(#"<!DOCTYPE x [<!ENTITY a "expanded">]><p>&a;&a;</p>"#) == "&a;&a;\n")
    }

    @Test func scriptsStylesFramesFormsAndSVGAreDroppedWithTheirContent() throws {
        let html = "<p>a</p><script>alert(1)</script><style>p{}</style><iframe src=x>frame text</iframe>"
            + "<form><input value=x>form text</form><svg><text>svg text</text></svg><object>obj</object>"
            + "<math><mi>m</mi></math><audio>sound</audio><noscript>no script</noscript><p>b</p>"
        #expect(try markdown(html) == "a\n\nb\n")
    }

    @Test func malformedXHTMLIsTolerated() throws {
        // Unclosed tags, stray end tags, mixed case, unquoted attributes and unterminated markup at the end.
        let html = "<DIV class=x><P>One<P>Two</div></span></li><b>bold <i>both</b> italic</i><p>end<p class=\"never"
        let result = try markdown(html)
        #expect(result.contains("One"))
        #expect(result.contains("Two"))
        #expect(result.contains("**bold *both***"))
        #expect(result.contains("end"))
        #expect(!result.contains("never"))
    }

    @Test func emptyEmphasisLeavesNoStrayMarkers() throws {
        #expect(try markdown("<p>a<em></em>b</p>") == "ab\n")
        #expect(try markdown("<p>a<code></code>b</p>") == "ab\n")
    }

    @Test func controlCharactersAreRemovedAndUnicodeIsPreserved() throws {
        #expect(try markdown("<p>a\u{0}b\u{7}c \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB} 日本語</p>") == "abc \u{1F469}\u{1F3FD}\u{200D}\u{1F4BB} 日本語\n")
    }

    @Test func titleIsCapturedAndNotWrittenAsText() throws {
        let converted = try convert("<html><head><title>My  Title</title></head><body><p>Body</p></body></html>")
        #expect(converted.outcome.title == "My Title")
        #expect(converted.text == "Body\n")
    }

    // MARK: Markdown safety

    @Test func textThatLooksLikeMarkdownIsEscaped() throws {
        let result = try markdown("<p>- not a list</p><p># not heading</p><p>1. not ordered</p><p>*stars* and _under_ [x](y) `tick`</p>")
        #expect(result == "\\- not a list\n\n\\# not heading\n\n1\\. not ordered\n\n\\*stars\\* and \\_under_ \\[x](y) \\`tick\\`\n")
    }

    @Test func underscoresInsideWordsStayLiteralSoSecretNamesRemainDetectable() throws {
        // A backslash inside `api_key` would hide the name from the shared privacy filter.
        #expect(try markdown("<p>api_key = abc and AWS_SECRET_ACCESS_KEY: def, ghp_abcdefghijklmnopqrstuvwx</p>")
                == "api_key = abc and AWS_SECRET_ACCESS_KEY: def, ghp_abcdefghijklmnopqrstuvwx\n")
        #expect(try markdown("<p>_leading and trailing_ and 9_digit</p>") == "\\_leading and trailing_ and 9_digit\n")
        #expect(MarkdownEscaping.prose("a_b _c d_ *e*") == "a_b \\_c d_ \\*e\\*")
    }

    @Test func fallbackHeadingPrecedesTheFirstBlockOnlyWhenItIsNotAHeading() throws {
        #expect(try markdown("<p>No heading here.</p>", fallbackHeading: "Chapter One") == "# Chapter One\n\nNo heading here.\n")
        #expect(try markdown("<h2>Own</h2><p>x</p>", fallbackHeading: "Chapter One") == "## Own\n\nx\n")
        #expect(try markdown("<script>x</script>", fallbackHeading: "Chapter One").isEmpty)
    }

    // MARK: Budgets

    @Test func outputCeilingStopsConversionAndReportsTruncation() throws {
        let html = String(repeating: "<p>A reasonably sized paragraph of text.</p>", count: 200)
        let budget = PreviewBudget(maxOutputUTF8Bytes: 400, maxMilliseconds: 30_000)
        let converted = try convert(html, budget: budget)
        #expect(converted.outcome.truncated)
        #expect(converted.writer.isFull)
        #expect(converted.text.utf8.count <= 300)
        #expect(converted.text.hasPrefix("A reasonably sized paragraph of text.\n"))
    }

    @Test func lineCeilingStopsConversion() throws {
        let html = String(repeating: "<p>x</p>", count: 500)
        let converted = try convert(html, budget: PreviewBudget(maxTextLines: 40, maxMilliseconds: 30_000))
        #expect(converted.outcome.truncated)
        #expect(converted.text.components(separatedBy: "\n").count <= 41)
    }

    @Test func elementBudgetStopsConversion() throws {
        let html = String(repeating: "<p>x</p>", count: 500)
        let converted = try convert(html, budget: PreviewBudget(maxJSONNodes: 10, maxMilliseconds: 30_000))
        #expect(converted.outcome.truncated)
    }

    @Test func nestingIsBoundedWithoutRecursion() throws {
        let lists = String(repeating: "<ul><li>", count: 60) + "deep" + String(repeating: "</li></ul>", count: 60)
        let result = try markdown(lists)
        let indent = result.components(separatedBy: "\n").map { line in line.prefix(while: { $0 == " " }).count }.max() ?? 0
        #expect(indent <= 2 * 7)
        let divs = String(repeating: "<div>", count: 50_000) + "text"
        #expect(try markdown(divs) == "text\n")
        let quotes = String(repeating: "<blockquote>", count: 100) + "<p>q</p>"
        #expect(try markdown(quotes).hasPrefix(String(repeating: "> ", count: 8) + "q"))
    }

    @Test func longParagraphsWrapBelowTheLineLimit() throws {
        let words = Array(repeating: "word", count: 5_000).joined(separator: " ")
        let result = try markdown("<p>\(words)</p>")
        let lines = result.split(separator: "\n")
        #expect(lines.count > 1)
        #expect(lines.allSatisfy { $0.utf8.count <= 8_192 })
        #expect(result.split(whereSeparator: \.isWhitespace).count == 5_000)
        // One unbroken token longer than the limit is split rather than exceeding it.
        let token = try markdown("<p>\(String(repeating: "x", count: 20_000))</p>")
        #expect(token.split(separator: "\n").allSatisfy { $0.utf8.count <= 8_192 })
    }

    @Test func cancellationStopsConversion() async {
        let html = String(repeating: "<p>x</p>", count: 20_000)
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try convert(html); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
    }

    @Test func generatedFrontMatterQuotesValuesThatYAMLCouldMisread() {
        #expect(MarkdownWriter.scalar("Plain title") == "Plain title")
        #expect(MarkdownWriter.scalar("Title: subtitle") == "\"Title: subtitle\"")
        #expect(MarkdownWriter.scalar("- dash") == "\"- dash\"")
        #expect(MarkdownWriter.scalar("Yes") == "\"Yes\"")
        #expect(MarkdownWriter.scalar("say \"hi\"") == "say \"hi\"")
        #expect(MarkdownWriter.scalar("  a \n b ") == "a b")
        #expect(MarkdownWriter.scalar("") == "")
        var writer = MarkdownWriter(context: documentContext())
        writer.frontMatter([("title", "Book"), ("author", ""), ("language", "en")], flags: ["drm"])
        #expect(writer.text == "---\ntitle: Book\nlanguage: en\ndrm: true\n---\n\n")
    }
}

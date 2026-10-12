import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func events(_ text: String, rawText: Set<String> = ["script", "style"], voids: Set<String> = HTMLVoidElements.names,
                    budget: PreviewBudget = PreviewBudget(maxMilliseconds: 30_000)) throws -> [MarkupEvent] {
    var tokenizer = MarkupTokenizer(text, rawTextElements: rawText, voidElements: voids, context: documentContext(budget))
    var result: [MarkupEvent] = []
    while let event = try tokenizer.next() { result.append(event) }
    return result
}

@Suite("Markup tokenizer")
struct MarkupTokenizerTests {
    @Test func startEndAndTextEventsLowercaseNamesAndDecodeReferences() throws {
        let result = try events(#"<P Class=a ID='b' hidden>Fish &amp; chips &lt;3 &#x263A;</P>"#)
        #expect(result == [
            .start(name: "p", attributes: [.init(name: "class", qualifiedName: "class", value: "a"),
                                           .init(name: "id", qualifiedName: "id", value: "b"),
                                           .init(name: "hidden", qualifiedName: "hidden", value: "")], selfClosing: false),
            .text("Fish & chips <3 \u{263A}"), .end(name: "p")
        ])
    }

    @Test func namespacePrefixesAreRemovedButQualifiedNamesAreKept() throws {
        let result = try events(#"<dc:title xml:lang="en" epub:type="toc">T</dc:title>"#, voids: [])
        guard case .start(let name, let attributes, _) = result.first else { Issue.record("no start"); return }
        #expect(name == "title")
        #expect(attributes.map(\.name) == ["lang", "type"])
        #expect(attributes.map(\.qualifiedName) == ["xml:lang", "epub:type"])
    }

    @Test func voidAndSelfClosingElementsHaveNoEndEvent() throws {
        let result = try events("<br><img src=a.png><p/>")
        #expect(result.count == 3)
        for event in result {
            guard case .start(_, _, let selfClosing) = event else { Issue.record("unexpected \(event)"); return }
            #expect(selfClosing)
        }
        // An XML document passes no void names, so only the explicit slash closes an element.
        let xml = try events("<link>text</link>", voids: [])
        #expect(xml.count == 3)
    }

    @Test func scriptAndStyleContentIsDiscardedUpToTheirEndTag() throws {
        let result = try events("<p>a</p><SCRIPT>if (a < b) { x = '</p>' }</SCRIPT><style>p > b {}</style>z")
        let text = result.compactMap { event -> String? in if case .text(let value) = event { value } else { nil } }
        #expect(text == ["a", "z"])
        #expect(result.contains(.end(name: "script")))
    }

    @Test func rawTextElementsAreConfigurable() throws {
        let result = try events("<binary id='a'>QUJD</binary>", rawText: ["binary"], voids: [])
        #expect(result.count == 2)
        #expect(!result.contains(.text("QUJD")))
    }

    @Test func commentsProcessingInstructionsAndDoctypeAreSkippedAndNeverExpanded() throws {
        let source = #"<?xml version="1.0"?><!DOCTYPE x [<!ENTITY a "expanded">]><!-- hidden --><p>&a; visible</p>"#
        let result = try events(source)
        let text = result.compactMap { event -> String? in if case .text(let value) = event { value } else { nil } }
        #expect(text == ["&a; visible"])
    }

    @Test func cdataBecomesLiteralText() throws {
        let result = try events("<p><![CDATA[1 < 2 & <b>]]></p>")
        #expect(result.contains(.text("1 < 2 & <b>")))
    }

    @Test func unknownAndOverlongReferencesStayLiteral() throws {
        let result = try events("<p>&unknown; &#xZZ; &#99999999999; &averyveryverylongname; & alone</p>")
        guard case .text(let value)? = result.dropFirst().first else { Issue.record("no text"); return }
        #expect(value == "&unknown; &#xZZ; &#99999999999; &averyveryverylongname; & alone")
    }

    @Test func malformedMarkupNeverThrowsAndLosesOnlyTheBrokenTag() throws {
        let broken = ["<", "<p", "<p class=\"x", "a < b", "<<p>>", "</>", "<p/ >x", "<a href=x/y>t</a", "<!--", "<![CDATA[x", "<?pi"]
        for source in broken { _ = try events(source) }
        let result = try events("one < two <b>bold</b> and <p unterminated")
        let text = result.compactMap { event -> String? in if case .text(let value) = event { value } else { nil } }.joined()
        #expect(text.contains("one "))
        #expect(text.contains("bold"))
    }

    @Test func aRunOfUnterminatedTagsStaysLinear() throws {
        // Each `<a` would otherwise rescan the rest of the input; a 64 KiB tag bound plus dropping the scanned
        // span keeps this fast. The test fails by timing out the context rather than by wall-clock assertion.
        let source = String(repeating: "<a ", count: 100_000)
        _ = try events(source, budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
    }

    @Test func attributeCountAndValueSizeAreBounded() throws {
        let attributes = (0..<200).map { "a\($0)=1" }.joined(separator: " ")
        let long = String(repeating: "x", count: 10_000)
        let result = try events("<p \(attributes) title=\"\(long)\">")
        guard case .start(_, let kept, _) = result.first else { Issue.record("no start"); return }
        #expect(kept.count == MarkupTokenizer.maximumAttributes)
        let result2 = try events("<p title=\"\(long)\">")
        guard case .start(_, let one, _) = result2.first else { Issue.record("no start"); return }
        #expect(one.first?.value.utf8.count == MarkupTokenizer.maximumAttributeValueBytes)
    }

    @Test func cancellationAndDeadlineStopTokenizing() async {
        let source = String(repeating: "<p>x</p>", count: 20_000)
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try events(source); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            _ = try events(source, budget: PreviewBudget(maxMilliseconds: 0))
        }
    }

    @Test func namedReferenceTableCoversLatinOneAndTypography() {
        func decode(_ text: String) -> String { HTMLEntities.decode(Array(text.utf8)[...]) }
        #expect(decode("&nbsp;") == "\u{A0}")
        #expect(decode("&copy;&eacute;&yuml;&szlig;&frac12;") == "\u{A9}\u{E9}\u{FF}\u{DF}\u{BD}")
        #expect(decode("&ndash;&mdash;&hellip;&ldquo;&rdquo;&euro;") == "\u{2013}\u{2014}\u{2026}\u{201C}\u{201D}\u{20AC}")
        #expect(decode("&amp;&lt;&gt;&quot;&apos;") == "&<>\"'")
    }

    @Test func treeBuilderIgnoresUnmatchedEndTagsAndClosesOpenElements() throws {
        let tree = try MarkupTreeBuilder.parse("<a><b>text</c></b><d>open", context: documentContext())
        let a = try #require(tree.firstDescendant(named: "a"))
        #expect(a.firstChild(named: "b")?.textContent == "text")
        #expect(a.firstChild(named: "d")?.textContent == "open")
    }

    @Test func treeBuilderEnforcesDepthAndNodeBudgets() {
        let deep = String(repeating: "<a>", count: 200)
        #expect(throws: PreviewFailure.structureTooDeep) { _ = try MarkupTreeBuilder.parse(deep, context: documentContext()) }
        let wide = String(repeating: "<a/>", count: 100)
        #expect(throws: PreviewFailure.tooManyNodes) {
            _ = try MarkupTreeBuilder.parse(wide, context: documentContext(PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)))
        }
    }

    @Test func decoderHonorsBOMsDeclaredEncodingsAndTolerantFallback() throws {
        let context = documentContext()
        #expect(try MarkupDecoder.decode(Data([0xEF, 0xBB, 0xBF] + Array("é".utf8)), context: context) == "é")
        #expect(try MarkupDecoder.decode(Data([0xFF, 0xFE, 0x41, 0x00]), context: context) == "A")
        let cyrillic = try #require("Привет".data(using: .windowsCP1251))
        let declared = Data(#"<?xml version="1.0" encoding="windows-1251"?><p>"#.utf8) + cyrillic
        #expect(try MarkupDecoder.decode(declared, context: context).hasSuffix("Привет"))
        #expect(try MarkupDecoder.decode(cyrillic, declaredCharset: "windows-1251", context: context) == "Привет")
        #expect(try MarkupDecoder.decode(Data([0x61, 0xFF, 0x62]), context: context) == "a\u{FFFD}b")
        #expect(MarkupDecoder.encoding(named: "no-such-charset") == nil)
    }
}

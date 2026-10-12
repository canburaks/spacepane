import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("draw.io source adapter")
struct DrawioSourceAdapterTests {
    private func parse(_ source: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
        try DrawioSourceAdapter().parse(FileBytes(data: Data(source.utf8)), context: RequestContext(budget: budget))
    }

    /// The text with every recorded range replaced the way the shared privacy filter does.
    private func concealed(_ document: ParsedTextDocument) -> String {
        var bytes = Array(document.text.utf8)
        for range in document.sensitiveRanges.sorted(by: { $0.utf8Range.lowerBound > $1.utf8Range.lowerBound }) {
            bytes.replaceSubrange(range.utf8Range, with: Array("••••".utf8))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func isWellFormed(_ text: String) -> Bool {
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        return parser.parse()
    }

    // MARK: Reading pages

    @Test func aPlainPageIsWrittenAsNormalizedXML() throws {
        let document = try parse(DrawioFixtures.file(inlinePages: [DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"2\" value=\"A &amp; B\" style=\"ellipse;\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"1\" y=\"2\" width=\"3\" height=\"4\" as=\"geometry\"/></mxCell>")]))
        #expect(document.text == """
        <mxGraphModel dx="800" dy="400">
          <root>
            <mxCell id="0"/>
            <mxCell id="1" parent="0"/>
            <mxCell id="2" value="A &amp; B" style="ellipse;" vertex="1" parent="1">
              <mxGeometry as="geometry" x="1" y="2" width="3" height="4"/>
            </mxCell>
          </root>
        </mxGraphModel>

        """)
        #expect(document.syntax == .drawio)
        #expect(document.usesStructuredPrivacy)
        #expect(document.sourceRecordCount == 1)
        #expect(document.decodedEncoding == .utf8)
    }

    @Test func compressedAndPlainPagesProduceTheSameText() throws {
        let plain = try parse(DrawioFixtures.file(inlinePages: [DrawioFixtures.model()]))
        let compressed = try parse(DrawioFixtures.file(compressedPages: [DrawioFixtures.model()]))
        #expect(plain.text == compressed.text)
        #expect(compressed.sourceRecordCount == 1)
        #expect(compressed.text.contains("<Array as=\"points\">"))
        #expect(isWellFormed(compressed.text))
    }

    @Test func theCompressionFixtureMatchesTheSharedInflater() throws {
        let data = DrawioFixtures.rawDeflate(Data("round trip".utf8))
        let inflated = try BoundedDecompression.rawDeflate(data, context: RequestContext(budget: .standard), maximum: 1_000)
        #expect(String(decoding: inflated, as: UTF8.self) == "round trip")
    }

    @Test func onlyTheFirstPageIsShownAndAllPagesAreCounted() throws {
        let second = DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"9\" value=\"SecondPageOnly\" vertex=\"1\" parent=\"1\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell>")
        for source in [DrawioFixtures.file(compressedPages: [DrawioFixtures.model(), second, second]),
                       DrawioFixtures.file(inlinePages: [DrawioFixtures.model(), second, second])] {
            let document = try parse(source)
            #expect(document.sourceRecordCount == 3)
            #expect(document.text.contains("Start") && !document.text.contains("SecondPageOnly"))
        }
    }

    @Test func aBareModelRootIsOnePage() throws {
        let document = try parse(DrawioFixtures.model())
        #expect(document.sourceRecordCount == 1)
        #expect(document.text.hasPrefix("<mxGraphModel dx=\"800\" dy=\"400\">\n"))
    }

    @Test func percentEncodedAndCDATAPagesAreRead() throws {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        let encoded = try #require(DrawioFixtures.model().addingPercentEncoding(withAllowedCharacters: allowed))
        let percent = try parse("<mxfile><diagram>\(encoded)</diagram></mxfile>")
        let cdata = try parse("<mxfile><diagram><![CDATA[\(DrawioFixtures.compressedPage(DrawioFixtures.model()))]]></diagram></mxfile>")
        let plain = try parse(DrawioFixtures.model())
        #expect(percent.text == plain.text && cdata.text == plain.text)
    }

    @Test func attributeOrderAndEscapingAreDeterministic() throws {
        let cells = "<mxCell parent=\"1\" vertex=\"1\" style=\"a=1;\" value=\"&lt;b&gt;&quot;x&quot; &amp; y&#10;line&lt;/b&gt;\" id=\"2\"><mxGeometry height=\"4\" width=\"3\" y=\"2\" x=\"1\" as=\"geometry\"/></mxCell>"
        let document = try parse(DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>" + cells))
        #expect(document.text.contains("<mxCell id=\"2\" value=\"&lt;b&gt;&quot;x&quot; &amp; y&#10;line&lt;/b&gt;\" style=\"a=1;\" vertex=\"1\" parent=\"1\">"))
        #expect(document.text.contains("<mxGeometry as=\"geometry\" x=\"1\" y=\"2\" width=\"3\" height=\"4\"/>"))
        #expect(isWellFormed(document.text))
    }

    // MARK: Corrupt and hostile input

    @Test func corruptBase64OrDeflateOrEncodingFailsClosed() throws {
        let valid = DrawioFixtures.compressedPage(DrawioFixtures.model())
        func page(_ text: String) -> String { "<mxfile><diagram>\(text)</diagram></mxfile>" }
        let truncated = String(valid.prefix(valid.count / 2 - valid.count / 2 % 4))
        let randomBytes = Data((0..<200).map { UInt8(($0 * 37 + 11) % 256) }).base64EncodedString()
        let badPercent = DrawioFixtures.rawDeflate(Data("%E0%A4%A".utf8)).base64EncodedString()
        let badUTF8 = DrawioFixtures.rawDeflate(Data([0xFF, 0xFE, 0xFD, 0x41])).base64EncodedString()
        let notXML = DrawioFixtures.compressedPage("this is not xml")
        let wrongRoot = DrawioFixtures.compressedPage("<foo><bar/></foo>")
        for text in ["!!!!", "====", "AAAA", truncated, randomBytes, badPercent, badUTF8, notXML, wrongRoot, "   "] {
            #expect(throws: PreviewFailure.malformedDocument, "page text: \(text.prefix(24))") { try parse(page(text)) }
        }
    }

    @Test func missingOrEmptyPagesAreMalformed() {
        for source in ["<mxfile/>", "<mxfile><diagram/></mxfile>", "<mxfile><other/></mxfile>", "<root/>", "not xml", "", "<mxGraphModel>",
                       "<mxfile><diagram><mxGraphModel></diagram></mxfile>"] {
            #expect(throws: PreviewFailure.malformedDocument, "source: \(source)") { try parse(source) }
        }
    }

    @Test(arguments: [
        "<?xml version=\"1.0\"?><!DOCTYPE mxfile [<!ENTITY xxe SYSTEM \"file:///etc/hosts\">]><mxfile><diagram>&xxe;</diagram></mxfile>",
        "<!DOCTYPE mxfile><mxfile><diagram/></mxfile>",
        "<!DOCTYPE lolz [<!ENTITY lol \"lol\"><!ENTITY lol2 \"&lol;&lol;&lol;&lol;\">]><mxfile><diagram>&lol2;</diagram></mxfile>",
        "<mxfile><!ENTITY a \"b\"><diagram/></mxfile>",
        "<mxfile><diagram>&undefined;</diagram></mxfile>"
    ])
    func entityDeclarationsAndUndefinedEntitiesAreRefused(source: String) {
        #expect(throws: PreviewFailure.malformedDocument) { try parse(source) }
    }

    @Test func declarationsInsideACompressedPageAreRefusedToo() {
        let inner = "<!DOCTYPE mxGraphModel [<!ENTITY xxe SYSTEM \"file:///etc/hosts\">]><mxGraphModel><root><mxCell id=\"0\" value=\"&xxe;\"/></root></mxGraphModel>"
        #expect(throws: PreviewFailure.malformedDocument) { try parse(DrawioFixtures.file(compressedPages: [inner])) }
    }

    @Test func commentsAndCDATAAreNotMistakenForDeclarations() throws {
        let document = try parse("<!-- a comment --><mxfile><!-- another --><diagram>\(DrawioFixtures.model())</diagram></mxfile>")
        #expect(document.sourceRecordCount == 1)
    }

    @Test func aDecompressionBombStopsAtTheOutputBudget() {
        let bomb = DrawioFixtures.rawDeflate(Data(repeating: UInt8(ascii: "A"), count: 40_000_000)).base64EncodedString()
        #expect(bomb.utf8.count < 100_000)
        let started = ContinuousClock.now
        #expect(throws: PreviewFailure.outputTooLarge) { try parse("<mxfile><diagram>\(bomb)</diagram></mxfile>") }
        #expect(started.duration(to: .now) < .seconds(5))
    }

    @Test func utf16AndByteOrderMarkedFilesAreDecoded() throws {
        let xml = DrawioFixtures.file(compressedPages: [DrawioFixtures.model()])
        let reference = try parse(xml).text
        let utf16 = Data([0xFF, 0xFE]) + (xml.data(using: .utf16LittleEndian) ?? Data())
        let bigEndian = Data([0xFE, 0xFF]) + (xml.data(using: .utf16BigEndian) ?? Data())
        let utf8WithMark = Data([0xEF, 0xBB, 0xBF]) + Data(xml.utf8)
        for data in [utf16, bigEndian, utf8WithMark] {
            let document = try DrawioSourceAdapter().parse(FileBytes(data: data), context: RequestContext(budget: .standard))
            #expect(document.text == reference)
        }
        #expect(throws: PreviewFailure.unsupportedEncoding) {
            try DrawioSourceAdapter().parse(FileBytes(data: Data([0x3C, 0xFF, 0xFE, 0x3E])), context: RequestContext(budget: .standard))
        }
    }

    @Test func aCompressedPageLongerThanTheTextLineLimitIsAccepted() throws {
        // Incompressible labels make the base64 page longer than the 32 KiB per-line text limit.
        var state: UInt64 = 0x9E3779B97F4A7C15
        func token() -> String {
            (0..<60).map { _ -> String in
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return String(Int(state >> 40) % 36, radix: 36)
            }.joined()
        }
        let cells = (0..<700).map { "<mxCell id=\"c\($0)\" value=\"\(token())\" vertex=\"1\" parent=\"1\"><mxGeometry x=\"\($0 * 3)\" width=\"10\" height=\"10\" as=\"geometry\"/></mxCell>" }.joined()
        let file = DrawioFixtures.file(compressedPages: [DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>" + cells)])
        #expect(file.utf8.count > PreviewBudget.standard.maxLineUTF8Bytes)
        let document = try parse(file)
        #expect(document.text.components(separatedBy: "\n").count > 1_000)
        #expect(document.text.components(separatedBy: "\n").allSatisfy { $0.utf8.count <= PreviewBudget.standard.maxLineUTF8Bytes })
    }

    // MARK: Budgets

    @Test func elementDepthAndOutputBudgetsAreEnforced() throws {
        let many = DrawioFixtures.model((0..<60).map { "<mxCell id=\"c\($0)\" parent=\"1\"/>" }.joined())
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(many, budget: PreviewBudget(maxJSONNodes: 20)) }
        #expect(throws: PreviewFailure.tooManyNodes) { try parse(DrawioFixtures.file(compressedPages: [many]), budget: PreviewBudget(maxJSONNodes: 20)) }
        let deep = "<mxGraphModel>" + String(repeating: "<a>", count: 30) + String(repeating: "</a>", count: 30) + "</mxGraphModel>"
        #expect(throws: PreviewFailure.structureTooDeep) { try parse(deep, budget: PreviewBudget(maxJSONDepth: 10)) }
        let big = DrawioFixtures.model((0..<400).map { "<mxCell id=\"c\($0)\" value=\"label number \($0)\" parent=\"1\"/>" }.joined())
        let compressed = DrawioFixtures.file(compressedPages: [big])
        #expect(compressed.utf8.count < 6_000)
        #expect(throws: PreviewFailure.self) { try parse(compressed, budget: PreviewBudget(maxOutputUTF8Bytes: 6_000)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(big, budget: PreviewBudget(maxInputBytes: 100)) }
    }

    @Test func oversizedValuesAndEmbeddedImagesAreShortened() throws {
        let hugeLabel = String(repeating: "x", count: 20_000)
        let image = "image=data:image/png," + String(repeating: "A", count: 3_000)
        let cell = "<mxCell id=\"2\" value=\"\(hugeLabel)\" style=\"shape=image;\(image);fillColor=#fff\" vertex=\"1\" parent=\"1\"/>"
        let document = try parse(DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>" + cell))
        #expect(document.text.utf8.count < 10_000)
        #expect(document.text.contains("…"))
        #expect(document.text.contains("style=\"shape=image;fillColor=#fff\""))
        #expect(!document.text.contains("data:image"))
    }

    @Test func cancellationAndDeadlinesComeBeforeAnyWork() async {
        let source = DrawioFixtures.file(compressedPages: [DrawioFixtures.model()])
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try DrawioSourceAdapter().parse(FileBytes(data: Data(source.utf8)), context: RequestContext(budget: .standard))
            }
        }
        await task.value
        #expect(throws: PreviewFailure.deadlineExceeded) { try parse(source, budget: PreviewBudget(maxMilliseconds: 0)) }
    }

    // MARK: Privacy

    @Test func secretLikeLabelsAreRecordedAndTheModelStaysWellFormed() throws {
        let secret = "synthetic-secret-value"
        let cells = """
        <mxCell id="0"/><mxCell id="1" parent="0"/>\
        <mxCell id="2" value="password: \(secret)" vertex="1" parent="1"><mxGeometry width="9" height="9" as="geometry"/></mxCell>\
        <mxCell id="3" value="&lt;b&gt;Client Secret&lt;/b&gt; = \(secret)&lt;br&gt;visible line" vertex="1" parent="1"><mxGeometry width="9" height="9" as="geometry"/></mxCell>\
        <mxCell id="4" value="Token count is high" vertex="1" parent="1"><mxGeometry width="9" height="9" as="geometry"/></mxCell>\
        <mxCell id="5" value="Status: ok" style="secret=\(secret);fillColor=#fff" vertex="1" parent="1"><mxGeometry width="9" height="9" as="geometry"/></mxCell>
        """
        let document = try parse(DrawioFixtures.file(compressedPages: [DrawioFixtures.model(cells)]))
        let safe = concealed(document)
        #expect(!safe.contains(secret))
        #expect(safe.contains("value=\"password: ••••\""))
        #expect(safe.contains("visible line") && safe.contains("Token count is high") && safe.contains("Status: ok"))
        #expect(isWellFormed(safe))
        #expect(document.sensitiveRanges.count == 3)
    }

    @Test func secretNamedAttributesAndObjectPropertiesAreConcealedWhole() throws {
        let secret = "synthetic-secret-value"
        let wrapped = "<object label=\"Service\" id=\"9\" apiKey=\"\(secret)\" owner=\"team\" Authorization=\"Bearer \(secret)\"><mxCell vertex=\"1\" parent=\"1\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell></object>"
        let document = try parse(DrawioFixtures.model("<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>" + wrapped))
        let safe = concealed(document)
        #expect(!safe.contains(secret))
        #expect(safe.contains("label=\"Service\"") && safe.contains("owner=\"team\""))
        #expect(isWellFormed(safe))
    }

    @Test func unicodeValuesAreConcealedAtScalarBoundaries() throws {
        let cells = "<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"2\" value=\"Token: 日本語-значение-😀-end\" vertex=\"1\" parent=\"1\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell><mxCell id=\"3\" value=\"Ünïcode 😀 label\" vertex=\"1\" parent=\"1\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell>"
        let document = try parse(DrawioFixtures.model(cells))
        let safe = concealed(document)
        #expect(!safe.contains("日本語") && !safe.contains("значение") && !safe.contains("😀-end"))
        #expect(safe.contains("Ünïcode 😀 label"))
        #expect(isWellFormed(safe))
        for range in document.sensitiveRanges {
            let bytes = Array(document.text.utf8)
            #expect(String(data: Data(bytes[range.utf8Range]), encoding: .utf8) != nil)
        }
    }

    @Test func parsingNeverReadsOrWritesFilesOrTheNetwork() throws {
        // The adapter takes text only; this documents that a file reference in the model is just text.
        let cells = "<mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/><mxCell id=\"2\" value=\"x\" style=\"image=file:///etc/passwd;shape=image;\" link=\"https://example.invalid/x\" vertex=\"1\" parent=\"1\"><mxGeometry width=\"5\" height=\"5\" as=\"geometry\"/></mxCell>"
        let document = try parse(DrawioFixtures.model(cells))
        #expect(document.text.contains("link=\"https://example.invalid/x\""))
        #expect(document.images.isEmpty)
    }
}

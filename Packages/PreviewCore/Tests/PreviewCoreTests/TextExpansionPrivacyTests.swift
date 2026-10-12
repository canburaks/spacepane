import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

@Suite("Expanded format privacy")
struct TextExpansionPrivacyTests {
    private func safe(_ text: String, adapter: any FormatAdapter) throws -> SafeText {
        let context = RequestContext(budget: .standard)
        let input = DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count)
        return try DefaultPrivacyFilter().filter(adapter.parse(input, context: context), context: context)
    }

    @Test(arguments: [
        #""pass\u0077ord": "synthetic-escaped-value""#,
        "password: !vault |\n  synthetic-block-value\n  continuation",
        "base: &base synthetic-anchor-value\npassword: *base",
        #""\x70assword": synthetic-uncertain-value"#,
        #"db: {"pass\u0077ord": "synthetic-flow-value"}"#
    ])
    func YAMLQuotedKeysTagsAliasesAndBlockValuesRemainConcealed(source: String) throws {
        let result = try safe(source, adapter: YAMLSourceAdapter())
        #expect(!result.text.contains("synthetic-"))
        #expect(result.redactionCount > 0)
    }

    @Test(arguments: [
        #"database."pass\u0077ord" = "synthetic-escaped-value""#,
        "[database]\npassword = '''\nsynthetic-multiline-value\n'''",
        #""api\u005fkey" = "synthetic-api-value""#,
        #"db = {"pass\u0077ord" = "synthetic-inline-value"}"#,
        #"["pass\u0077ord"]"# + "\n" + #"value = "synthetic-table-value""#
    ])
    func TOMLQuotedDottedAndMultilineSecretValuesRemainConcealed(source: String) throws {
        let result = try safe(source, adapter: TOMLSourceAdapter())
        #expect(!result.text.contains("synthetic-"))
        #expect(result.redactionCount > 0)
    }

    @Test func environmentNeverEvaluatesSubstitutionsAndConcealsSecretValues() throws {
        let source = "SAFE=$(printf inert)\nPASSWORD=synthetic-env-value"
        let result = try safe(source, adapter: EnvironmentSourceAdapter())
        #expect(result.text.contains("$(printf inert)"))
        #expect(!result.text.contains("synthetic-env-value"))
    }

    @Test func stringsEscapedSecretKeysAreConcealed() throws {
        let result = try safe(#""\U0070assword" = "synthetic-strings-value"; "safe" = "😀";"#, adapter: StringsSourceAdapter())
        #expect(!result.text.contains("synthetic-strings-value"))
        #expect(result.text.contains("😀"))
    }

    @Test func XMLSecretAttributesAndNestedElementsRemainConcealed() throws {
        let source = #"<root password="synthetic-attr-value"><password><child>synthetic-child-value</child></password><safe>visible</safe></root>"#
        let result = try safe(source, adapter: XMLSourceAdapter())
        #expect(!result.text.contains("synthetic-"))
        #expect(result.text.contains("<safe>visible</safe>"))
    }

    @Test(arguments: [
        "<!-- password=synthetic-comment-value --><root><safe>visible</safe></root>",
        "<root><!-- 😀 \"api_key\" : synthetic-comment-value\ncontinued --><safe>visible</safe></root>"
    ])
    func XMLCommentAssignmentsAreConcealedWithoutRemovingMarkup(source: String) throws {
        let result = try safe(source, adapter: XMLSourceAdapter())
        #expect(!result.text.contains("synthetic-comment-value"))
        #expect(result.text.contains("<!--••••-->"))
        #expect(result.text.contains("<safe>visible</safe>"))
    }

    @Test(arguments: [
        "// password=synthetic-comment-value\n\"safe\" = \"visible\";",
        "/* 😀 \"api_key\" : synthetic-comment-value\ncontinued */ \"safe\" = \"visible\";"
    ])
    func stringsCommentAssignmentsAreConcealedWithoutRemovingPairs(source: String) throws {
        let result = try safe(source, adapter: StringsSourceAdapter())
        #expect(!result.text.contains("synthetic-comment-value"))
        #expect(result.text.contains("••••"))
        #expect(result.text.contains("\"safe\" = \"visible\";"))
    }

    @Test func recoverableJSONLConcealsWholeMalformedRecordsAndKeepsValidRecords() throws {
        let source = "{\"safe\":1}\n{\"pass\\u0077ord\":\"synthetic-bad-record\"\n{\"password\":\"synthetic-valid-record\",\"safe\":2}\n"
        let context = RequestContext(budget: .standard)
        let document = try JSONLinesAdapter(allowsMalformedRecords: true).parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        #expect(document.invalidRecordLines == [2])
        #expect(document.usesStructuredPrivacy)
        let result = try DefaultPrivacyFilter().filter(document, context: context)
        #expect(!result.text.contains("synthetic-"))
        #expect(result.text.contains("\"safe\":2"))
        #expect(result.text.components(separatedBy: "\n").count == 4)
    }

    @Test func recognizableSecretSpanningRecordsKeepsOriginalCountProvenance() throws {
        let source = "{\"value\":\"-----BEGIN PRIVATE KEY-----\"}\n{\"password\":\"synthetic-middle-record\"}\n{\"value\":\"-----END PRIVATE KEY-----\"}\n"
        let context = RequestContext(budget: .standard)
        let document = try JSONLinesAdapter(allowsMalformedRecords: true).parse(.init(text: source, encoding: .utf8, byteCount: source.utf8.count), context: context)
        let result = try DefaultPrivacyFilter().filter(document, context: context)
        #expect(document.sourceRecordCount == 3)
        #expect(!result.text.contains("synthetic-"))
        #expect(result.text.components(separatedBy: "\n").count == 2)
    }

    @Test func expandedAdaptersRespectCancellationBeforeParsing() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let input = DecodedText(text: "safe", encoding: .utf8, byteCount: 4)
            #expect(throws: CancellationError.self) { try SourceCodeAdapter().parse(input, context: .init(budget: .standard)) }
            #expect(throws: CancellationError.self) { try YAMLSourceAdapter().parse(input, context: .init(budget: .standard)) }
            #expect(throws: CancellationError.self) { try XMLSourceAdapter().parse(input, context: .init(budget: .standard)) }
            #expect(throws: CancellationError.self) { try PropertyListSourceAdapter().parse(FileBytes(data: Data()), context: .init(budget: .standard)) }
        }
        await task.value
    }

    @Test func expandedPipelinePreviewsNeverMutateTheirSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sources = [("code.swift", "let safe = 1"), ("notes.md", "# Safe"), ("config.yaml", "safe: visible"),
                       ("config.toml", "safe = 1"), (".env", "SAFE=visible"), ("change.patch", "+safe"),
                       ("data.xml", "<root>safe</root>"), ("Localizable.strings", "\"safe\" = \"visible\";"),
                       ("feeds.opml", "<opml><body><outline text=\"safe\"/></body></opml>"), ("package.json", "{\"name\":\"safe\"}")]
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        for (name, source) in sources {
            let url = directory.appendingPathComponent(name)
            let data = Data(source.utf8)
            try data.write(to: url)
            let outcome = await pipeline.preview(url: url)
            guard case .ready = outcome else { Issue.record("Expected preview for \(name), got \(outcome)"); continue }
            #expect(try Data(contentsOf: url) == data)
        }
    }

    @Test(arguments: [PropertyListSerialization.PropertyListFormat.xml, .binary])
    func propertyListsNormalizeAndConcealBeforeAnyPresentation(format: PropertyListSerialization.PropertyListFormat) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["password": "synthetic-plist-value", "safe": [1, 2, 3], "blob": Data("synthetic-data-payload".utf8)], format: format, options: 0)
        let context = RequestContext(budget: .standard)
        let document = try PropertyListSourceAdapter().parse(FileBytes(data: data), context: context)
        let result = try DefaultPrivacyFilter().filter(document, context: context)
        #expect(!result.text.contains("synthetic-"))
        #expect(result.text.contains("$dataBytes"))
        #expect(result.text.contains("\"safe\""))
    }

    @Test func XMLExternalEntitiesAreRejectedBeforeNativeParsing() {
        let source = #"<!DOCTYPE root [<!ENTITY private SYSTEM "file:///tmp/never-read">]><root>&private;</root>"#
        #expect(throws: PreviewFailure.malformedDocument) { try safe(source, adapter: XMLSourceAdapter()) }
    }

    @Test func newAdaptersEnforceStructureBudgetsBeforeNativeGraphs() throws {
        let source = "<root><one><two/></one></root>"
        let input = DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count)
        #expect(throws: PreviewFailure.structureTooDeep) { try XMLSourceAdapter().parse(input, context: .init(budget: .init(maxJSONDepth: 2))) }
        let plist = try PropertyListSerialization.data(fromPropertyList: [[[[1]]]], format: .binary, options: 0)
        #expect(throws: PreviewFailure.structureTooDeep) { try PropertyListSourceAdapter().parse(FileBytes(data: plist), context: .init(budget: .init(maxJSONDepth: 3))) }
    }
}

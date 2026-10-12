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

    // MARK: A sensitive YAML key with an empty or continuing value conceals to the end of the text

    /// The displayed text after each privacy stage alone and after both: the adapter's own ranges (the shared
    /// heuristic switched off), the shared filter's heuristic with no adapter ranges, and the real combination.
    private func stages(_ text: String) throws -> [(name: String, text: String)] {
        let context = RequestContext(budget: .standard)
        let parsed = try YAMLSourceAdapter().parse(DecodedText(text: text, encoding: .utf8, byteCount: text.utf8.count), context: context)
        let filter = DefaultPrivacyFilter()
        let adapterOnly = ParsedTextDocument(text: text, sensitiveRanges: parsed.sensitiveRanges, usesStructuredPrivacy: true, syntax: .yaml)
        return [("adapter", try filter.filter(adapterOnly, context: context).text),
                ("filter", try filter.filter(ParsedTextDocument(text: text, syntax: .yaml), context: context).text),
                ("combined", try filter.filter(parsed, context: context).text)]
    }

    struct Concealment: Sendable, CustomStringConvertible {
        let name: String
        let source: String
        let secrets: [String]
        let stages: Set<String>
        var description: String { name }
        static let all: Set<String> = ["adapter", "filter", "combined"]
    }

    /// Nothing the key owns may stay visible, however its block is spelled. The conservative rule conceals from the
    /// key to the end of the text; these documents are the ones a shorter, indentation-bounded range leaked.
    @Test(arguments: [
        Concealment(name: "hash line inside a block scalar", source: "password: |\n  abc-synthetic\n  #synthetic-tail\nnext: visible\n",
                    secrets: ["abc-synthetic", "synthetic-tail"], stages: ["adapter", "combined"]),
        Concealment(name: "tab-indented line", source: "a:\n  password:\n\tsynthetic-tab\n  next: visible\n",
                    secrets: ["synthetic-tab"], stages: Concealment.all),
        Concealment(name: "flow collection after a bare tag", source: "secret: ! [synthetic-a,\nsynthetic-b]\nnext: visible\n",
                    secrets: ["synthetic-a", "synthetic-b"], stages: ["adapter", "combined"]),
        Concealment(name: "multi-line flow context", source: "config: {\npassword:\n\"synthetic-s3cret\", other: 1}\nnext: visible\n",
                    secrets: ["synthetic-s3cret"], stages: Concealment.all),
        Concealment(name: "quoted scalar running past the block", source: "password:\n  \"synthetic-abc\ndef-synthetic\"\nnext: visible\n",
                    secrets: ["synthetic-abc", "def-synthetic"], stages: Concealment.all),
        Concealment(name: "unbalanced bracket in the block", source: "password:\n  [synthetic-abc\ndef-synthetic]\nnext: visible\n",
                    secrets: ["synthetic-abc", "def-synthetic"], stages: Concealment.all),
        Concealment(name: "plain scalar on the next line", source: "password:\nhunter2-synthetic\nnext: visible\n",
                    secrets: ["hunter2-synthetic"], stages: Concealment.all),
        Concealment(name: "no-break space indentation", source: "password:\n\u{00A0}\u{00A0}synthetic-nbsp\nnext: visible\n",
                    secrets: ["synthetic-nbsp"], stages: Concealment.all),
        Concealment(name: "zero-width space indentation", source: "password: |\n\u{200B}synthetic-zwsp\nnext: visible\n",
                    secrets: ["synthetic-zwsp"], stages: ["adapter", "combined"]),
        Concealment(name: "flow opener with a trailing comment", source: "password: [ # c\n  synthetic-a,\n  synthetic-b ]\nnext: visible\n",
                    secrets: ["synthetic-a", "synthetic-b"], stages: Concealment.all),
        Concealment(name: "flow opener with a trailing comment on a mapping", source: "x: { # c\n  password: synthetic-m,\n  other: synthetic-n }\nnext: visible\n",
                    secrets: ["synthetic-m"], stages: Concealment.all),
        Concealment(name: "quote opened before the key", source: "note: \"first line\npassword:\n  synthetic-q\"\nnext: visible\n",
                    secrets: ["synthetic-q"], stages: Concealment.all),
        Concealment(name: "line separator after the key", source: "password:\u{2028}  synthetic-ls\nnext: visible\n",
                    secrets: ["synthetic-ls"], stages: Concealment.all),
        Concealment(name: "next line character after the key", source: "password:\u{0085}  synthetic-nel\nnext: visible\n",
                    secrets: ["synthetic-nel"], stages: Concealment.all),
        Concealment(name: "next line character inside the block", source: "password:\n  synthetic-a\u{0085}synthetic-b\nnext: visible\n",
                    secrets: ["synthetic-a", "synthetic-b"], stages: Concealment.all),
        Concealment(name: "nested mapping under a comment-only value", source: "auth: # c\n  user: synthetic-user\nkept: visible\n",
                    secrets: ["synthetic-user"], stages: Concealment.all)
    ])
    func aSensitiveKeyStillConcealsEverythingItCouldOwn(case concealment: Concealment) throws {
        for stage in try stages(concealment.source) where concealment.stages.contains(stage.name) {
            for secret in concealment.secrets {
                #expect(!stage.text.contains(secret), Comment(rawValue: "\(stage.name) stage leaked \(secret):\n\(stage.text)"))
            }
        }
    }

    /// A real value followed by a comment is concealed as a value: the comment is not an empty value, so the rest
    /// of the file is not swallowed.
    @Test func aValueFollowedByACommentConcealsTheValueAndNotTheFile() throws {
        for stage in try stages("password: abc-synthetic # note\nnext: visible\n") {
            #expect(!stage.text.contains("abc-synthetic"), Comment(rawValue: "\(stage.name): \(stage.text)"))
            #expect(stage.text.contains("next: visible"), Comment(rawValue: "\(stage.name) concealed the file: \(stage.text)"))
        }
    }

    /// Everything the key could own, in several shapes, is concealed in every stage.
    @Test(arguments: [
        "auth:\n  a: synthetic-1\n  b:\n    c: synthetic-2\n  # synthetic-3\n  d: [synthetic-4]\nafter: visible\n",
        "x:\n  password:\n    synthetic-1: 1\n    - synthetic-2\n\n    # synthetic-3\n  after: visible\nlast: visible\n",
        "password:\n- synthetic-1\n- k: synthetic-2\n  j: synthetic-3\nafter: visible\n",
        "- password:\n    u: synthetic-1\n    v: synthetic-2\n  after: visible\n- other: visible\n",
        "token: |\n  synthetic-1\n\n  synthetic-2\n    synthetic-3\nafter: visible\n",
        "secret: >-\n  synthetic-1\n  # synthetic-2\n  synthetic-3 # synthetic-4\nafter: visible\n"
    ])
    func everythingTheKeyOwnsIsStillConcealed(source: String) throws {
        // A block scalar header is the adapter's to conceal; the shared heuristic follows an empty value.
        let blockScalar = source.contains(": |") || source.contains(": >")
        for stage in try stages(source) where !(blockScalar && stage.name == "filter") {
            for number in 1...4 where source.contains("synthetic-\(number)") {
                #expect(!stage.text.contains("synthetic-\(number)"), Comment(rawValue: "\(stage.name) leaked synthetic-\(number):\n\(stage.text)"))
            }
        }
    }

    @Test(arguments: [
        "auth: {user: synthetic-flow,\n  more: synthetic-flow-two}\nafter: synthetic-rest",
        "auth: [synthetic-flow,\nsynthetic-flow-two]\nafter: synthetic-rest",
        "auth: 'synthetic-quote\nsynthetic-quote-two'\nafter: synthetic-rest",
        "auth: synthetic-slash \\\nafter: synthetic-rest"
    ])
    func uncertainSensitiveYAMLContinuationsStillConcealTheRestOfTheFile(source: String) throws {
        let result = try safe(source, adapter: YAMLSourceAdapter())
        #expect(!result.text.contains("synthetic-"), Comment(rawValue: result.text))
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

import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

@Suite("Q16 adapter credential grammars")
struct Q16AdapterCredentialPrivacyTests {
    enum Family: Equatable, Sendable { case json, jsonc, yaml, toml, xml, source, unnamed }
    struct Sample: Sendable, CustomTestStringConvertible {
        let id: String
        let family: Family
        let filename: String
        let text: String
        let concealed: String
        var testDescription: String { id }
    }
    private static let marker = "synthetic-q16-binding-value"
    private static let ordinary = "ordinary-next-record-value"
    private static let tokenBody = "Q16SyntheticEscapeValueAa1Bb2Cc3Dd4Ee5Ff6"

    static let positives: [Sample] = [
        .init(id: "json-name-first", family: .json, filename: "config.json", text: "{\"name\":\"api_key\",\"value\":\"\(marker)\"}", concealed: marker),
        .init(id: "json-value-first", family: .json, filename: "config.json", text: "{\"value\":\"\(marker)\",\"name\":\"password\"}", concealed: marker),
        .init(id: "json-key-member", family: .json, filename: "config.json", text: "{\"key\":\"clientSecret\",\"value\":\"\(marker)\"}", concealed: marker),
        .init(id: "json-case-member", family: .json, filename: "config.json", text: "{\"Name\":\"AUTH\",\"Value\":\"\(marker)\"}", concealed: marker),
        .init(id: "json-escaped-name", family: .json, filename: "config.json", text: "{\"name\":\"api\\u005fkey\",\"value\":\"\(marker)\"}", concealed: marker),
        .init(id: "jsonc-name", family: .jsonc, filename: "config.jsonc", text: "{/* inert */\"name\":\"api_key\",\"value\":\"\(marker)\"}", concealed: marker),
        .init(id: "json5-value-first", family: .jsonc, filename: "config.json5", text: "{value:'\(marker)',name:'passphrase',}", concealed: marker),
        .init(id: "yaml-sequence-name", family: .yaml, filename: "config.yaml", text: "settings:\n  - name: API_KEY\n    value: \(marker)\n  - name: title\n    value: \(ordinary)\n", concealed: marker),
        .init(id: "yaml-sequence-value-first", family: .yaml, filename: "config.yaml", text: "settings:\n  - value: \(marker)\n    name: password\n  - name: title\n    value: \(ordinary)\n", concealed: marker),
        .init(id: "yaml-map-key", family: .yaml, filename: "config.yaml", text: "entry:\n  key: client_secret\n  value: \(marker)\nnext: \(ordinary)\n", concealed: marker),
        .init(id: "xml-name-text", family: .xml, filename: "config.xml", text: "<settings><entry name=\"api_key\">\(marker)</entry><entry name=\"title\">\(ordinary)</entry></settings>", concealed: marker),
        .init(id: "xml-value-first", family: .xml, filename: "config.xml", text: "<settings><entry value=\"\(marker)\" name=\"password\"/><entry name=\"title\" value=\"\(ordinary)\"/></settings>", concealed: marker),
        .init(id: "xml-key-attribute", family: .xml, filename: "config.xml", text: "<settings><entry key=\"api_key\" value=\"\(marker)\"/></settings>", concealed: marker),
        .init(id: "xml-escaped-name", family: .xml, filename: "config.xml", text: "<settings><entry name=\"api&#x5f;key\" value=\"\(marker)\"/></settings>", concealed: marker),
        .init(id: "php-define", family: .source, filename: "config.php", text: "<?php define('API_KEY', '\(marker)');\n$title = '\(ordinary)';", concealed: marker),
        .init(id: "java-set-property", family: .source, filename: "Config.java", text: "System.setProperty(\"db.password\", \"\(marker)\");", concealed: marker),
        .init(id: "python-environ", family: .source, filename: "config.py", text: "os.environ[\"API_KEY\"] = \"\(marker)\"", concealed: marker),
        .init(id: "netrc-inline", family: .unnamed, filename: ".netrc", text: "machine example.test login demo password \(marker)\n", concealed: marker),
        .init(id: "netrc-multiline", family: .unnamed, filename: ".netrc", text: "machine example.test\nlogin demo\npassword\n\(marker)\n", concealed: marker),
        .init(id: "netrc-quoted", family: .unnamed, filename: ".netrc", text: "default login demo password \"\(marker) with spaces\"\n", concealed: marker),
        .init(id: "netrc-account", family: .unnamed, filename: ".netrc", text: "machine example.test login demo account \(marker)\n", concealed: marker),
        .init(id: "pgpass", family: .unnamed, filename: ".pgpass", text: "example.test:5432:sample:demo:\(marker)\n", concealed: marker),
        .init(id: "pgpass-escaped-colon", family: .unnamed, filename: ".pgpass", text: "host\\:name:5432:sample:demo:\(marker)\\:tail\n", concealed: marker),
        .init(id: "escaped-json-value", family: .json, filename: "config.json", text: "{\"note\":\"\\u0073k_test_\(tokenBody)\"}", concealed: tokenBody),
        .init(id: "escaped-json5-value", family: .jsonc, filename: "config.json5", text: "{note:'\\x73k_test_\(tokenBody)'}", concealed: tokenBody),
        .init(id: "escaped-yaml-value", family: .yaml, filename: "config.yaml", text: "note: \"\\u0073k_test_\(tokenBody)\"\n", concealed: tokenBody),
        .init(id: "escaped-toml-value", family: .toml, filename: "config.toml", text: "note = \"\\u0073k_test_\(tokenBody)\"\n", concealed: tokenBody),
        .init(id: "escaped-xml-attribute", family: .xml, filename: "config.xml", text: "<entry value=\"&#x73;k_test_\(tokenBody)\"/>", concealed: tokenBody),
        .init(id: "escaped-xml-text", family: .xml, filename: "config.xml", text: "<entry>&#115;k_test_\(tokenBody)</entry>", concealed: tokenBody)
    ]

    static let negatives: [Sample] = [
        .init(id: "json-other-record", family: .json, filename: "config.json", text: "[{\"name\":\"api_key\"},{\"value\":\"\(ordinary)\"}]", concealed: ordinary),
        .init(id: "json-id-is-not-name", family: .json, filename: "config.json", text: "{\"id\":\"api_key\",\"value\":\"\(ordinary)\"}", concealed: ordinary),
        .init(id: "json-public-name", family: .json, filename: "config.json", text: "{\"name\":\"public_key\",\"value\":\"\(ordinary)\"}", concealed: ordinary),
        .init(id: "jsonc-other-record", family: .jsonc, filename: "config.jsonc", text: "[{name:'password'},{value:'\(ordinary)'}]", concealed: ordinary),
        .init(id: "yaml-other-record", family: .yaml, filename: "config.yaml", text: "settings:\n  - name: api_key\n  - value: \(ordinary)\n", concealed: ordinary),
        .init(id: "yaml-public-name", family: .yaml, filename: "config.yaml", text: "entry:\n  name: public_key\n  value: \(ordinary)\n", concealed: ordinary),
        .init(id: "xml-other-element", family: .xml, filename: "config.xml", text: "<settings><entry name=\"api_key\"/><entry value=\"\(ordinary)\"/></settings>", concealed: ordinary),
        .init(id: "xml-public-name", family: .xml, filename: "config.xml", text: "<entry name=\"public_key\" value=\"\(ordinary)\"/>", concealed: ordinary),
        .init(id: "source-public-definition", family: .source, filename: "config.php", text: "<?php define('PUBLIC_KEY', '\(ordinary)');", concealed: ordinary),
        .init(id: "source-ordinary-property", family: .source, filename: "Config.java", text: "System.setProperty(\"title\", \"\(ordinary)\");", concealed: ordinary),
        .init(id: "netrc-comment", family: .unnamed, filename: ".netrc", text: "# password \(ordinary)\nmachine example.test login demo\n", concealed: ordinary),
        .init(id: "netrc-name-gate", family: .unnamed, filename: "notes", text: "machine example.test login demo password \(ordinary)\n", concealed: ordinary),
        .init(id: "pgpass-comment", family: .unnamed, filename: ".pgpass", text: "# example.test:5432:sample:demo:\(ordinary)\n", concealed: ordinary),
        .init(id: "pgpass-name-gate", family: .unnamed, filename: "notes", text: "example.test:5432:sample:demo:\(ordinary)\n", concealed: ordinary)
    ]

    static let finalGrammarPositives: [Sample] = [
        .init(id: "escaped-java-literal", family: .source, filename: "Config.java", text: "String note = \"\\u0073k_test_\(tokenBody)\";", concealed: tokenBody),
        .init(id: "escaped-javascript-literal", family: .source, filename: "config.js", text: "// It's an ordinary comment.\nconst note = '\\x73k_test_\(tokenBody)';", concealed: tokenBody),
        .init(id: "escaped-python-literal", family: .source, filename: "config.py", text: "note = '\\u0073k_test_\(tokenBody)'", concealed: tokenBody),
        .init(id: "escaped-java-text-block", family: .source, filename: "Config.java", text: "String note = \"\"\"\n\\u0073k_test_\(tokenBody)\n\"\"\";", concealed: tokenBody),
        .init(id: "java-name-trivia", family: .source, filename: "Config.java", text: "System.setProperty(\"password\" /* inert */, \"\(marker)\");", concealed: marker),
        .init(id: "php-opening-trivia", family: .source, filename: "config.php", text: "<?php define(/* inert */ 'API_KEY', '\(marker)');", concealed: marker),
        .init(id: "java-call-trivia", family: .source, filename: "Config.java", text: "System.setProperty /* inert */ (\"password\", \"\(marker)\");", concealed: marker),
        .init(id: "python-index-trivia", family: .source, filename: "config.py", text: "os.environ[\"API_KEY\" # inert\n] = \"\(marker)\"", concealed: marker),
        .init(id: "yaml-flow-name-first", family: .yaml, filename: "config.yaml", text: "entry: {name: api_key, value: \(marker)}\n", concealed: marker),
        .init(id: "yaml-flow-value-first", family: .yaml, filename: "config.yaml", text: "entry: {value: \(marker), name: password}\n", concealed: marker),
        .init(id: "yaml-flow-neighbor", family: .yaml, filename: "config.yaml", text: "items: [{name: password, value: \(marker)}, {name: title, value: \(ordinary)}]\n", concealed: marker),
        .init(id: "yaml-flow-key-member", family: .yaml, filename: "config.yaml", text: "entry: {key: 'client_secret', value: '\(marker)'}\n", concealed: marker),
        .init(id: "yaml-flow-escaped-member", family: .yaml, filename: "config.yaml", text: "entry: {\"\\u006eame\": api_key, value: \(marker)}\n", concealed: marker),
        .init(id: "yaml-flow-nested-value", family: .yaml, filename: "config.yaml", text: "entry: {name: password, value: {text: \(marker)}}\n", concealed: marker)
    ]

    static let finalGrammarNegatives: [Sample] = [
        .init(id: "source-ordinary-escape", family: .source, filename: "config.js", text: "const shape = '\\x73hape';\nconst title = '\(ordinary)';", concealed: ordinary),
        .init(id: "source-public-escape", family: .source, filename: "Config.java", text: "String note = \"public\\u005fkey\";\nString title = \"\(ordinary)\";", concealed: ordinary),
        .init(id: "source-backslash-path", family: .source, filename: "config.py", text: "path = 'C:\\Temp\\notes.txt'\ntitle = '\(ordinary)'", concealed: ordinary),
        .init(id: "source-public-trivia", family: .source, filename: "config.php", text: "<?php define(/* inert */ 'PUBLIC_KEY' /* inert */, '\(ordinary)');", concealed: ordinary),
        .init(id: "yaml-flow-other-record", family: .yaml, filename: "config.yaml", text: "items: [{name: password}, {value: \(ordinary)}]\n", concealed: ordinary),
        .init(id: "yaml-flow-public-name", family: .yaml, filename: "config.yaml", text: "entry: {name: public_key, value: \(ordinary)}\n", concealed: ordinary),
        .init(id: "yaml-flow-nested-locality", family: .yaml, filename: "config.yaml", text: "entry: {name: password, child: {value: \(ordinary)}}\n", concealed: ordinary),
        .init(id: "yaml-flow-quoted-delimiters", family: .yaml, filename: "config.yaml", text: "entry: {name: title, value: '\(ordinary), {name: password}'}\n", concealed: ordinary)
    ]

    @Test(arguments: finalGrammarPositives)
    func finalSourceAndFlowGrammarsConcealOriginalSpans(sample: Sample) throws {
        let result = try safe(sample)
        let leaked = result.text.contains(sample.concealed)
        #expect(!leaked, "Final grammar \(sample.id)")
        #expect(result.redactionCount > 0, "Final grammar \(sample.id)")
        if sample.text.contains(Self.ordinary) {
            let preserved = result.text.contains(Self.ordinary)
            #expect(preserved, "Final neighboring record \(sample.id)")
        }
    }

    @Test(arguments: finalGrammarNegatives)
    func finalSourceAndFlowControlsRemainReadable(sample: Sample) throws {
        let result = try safe(sample)
        let preserved = result.text.contains(sample.concealed)
        #expect(preserved, "Final ordinary grammar \(sample.id)")
        #expect(result.redactionCount == 0, "Final ordinary grammar \(sample.id)")
    }

    @Test func rawSourceLiteralsKeepInertEscapesAndVisibleURLHostsStayReadable() throws {
        let raw = Sample(id: "python-raw-escape", family: .source, filename: "config.py",
                         text: "note = r'\\x73k_test_\(Self.tokenBody)'\n", concealed: Self.tokenBody)
        let rawResult = try safe(raw)
        #expect(rawResult.text == raw.text)
        #expect(rawResult.redactionCount == 0)
        let incompleteRaw = Sample(id: "python-raw-prefix", family: .source, filename: "config.py",
                                   text: "note = r'\\x73k_test_\(Self.tokenBody)", concealed: Self.tokenBody)
        let incompleteRawResult = try safe(incompleteRaw)
        #expect(incompleteRawResult.text == incompleteRaw.text)
        #expect(incompleteRawResult.redactionCount == 0)
        let incompleteURL = Sample(id: "source-url-prefix", family: .source, filename: "config.py",
                                   text: "note = \"postgres://app:\(Self.marker)@db.example.test/main\\n", concealed: Self.marker)
        let incompleteURLResult = try safe(incompleteURL)
        // The existing uncertain escaped-double-quote fallback conceals this malformed source
        // whole. URL host compatibility is required for valid literals, not this uncertain extent.
        #expect(incompleteURLResult.text == SecretFieldPolicy.concealmentToken)
        #expect(incompleteURLResult.redactionCount == 1)
        let singleQuotedURL = Sample(id: "source-single-quoted-url-prefix", family: .source, filename: "config.py",
                                     text: "note = 'postgres://app:\(Self.marker)@db.example.test/main\\n", concealed: Self.marker)
        let singleQuotedURLResult = try safe(singleQuotedURL)
        #expect(singleQuotedURLResult.text.contains("postgres://••••@db.example.test/main"))
        #expect(singleQuotedURLResult.redactionCount == 1)
        for family in [Family.source, .yaml] {
            let sample = Sample(id: "visible-url-escape", family: family,
                                filename: family == .source ? "config.py" : "config.yaml",
                                text: family == .source
                                    ? "note = \"postgres://app:\(Self.marker)@db.example.test/main\\n\"\n"
                                    : "entry: {note: \"postgres://app:\(Self.marker)@db.example.test/main\\n\"}\n",
                                concealed: Self.marker)
            let result = try safe(sample)
            let leaked = result.text.contains(Self.marker)
            #expect(!leaked)
            #expect(result.text.contains("postgres://••••@db.example.test/main"))
            #expect(result.redactionCount == 1)
        }
    }

    @Test func flowCollectionsHaveTypedNodeAndDepthLimitsAndConcealUncertainSensitiveRecords() throws {
        let nodeSample = Sample(id: "flow-node-limit", family: .yaml, filename: "config.yaml",
                                text: "entry: {name: password, value: \(Self.marker)}\n", concealed: Self.marker)
        #expect(throws: PreviewFailure.tooManyNodes) {
            try Self.parse(nodeSample, budget: PreviewBudget(maxJSONNodes: 1))
        }
        let deep = Sample(id: "flow-depth-limit", family: .yaml, filename: "config.yaml",
                          text: "entry: [{child: {value: \(Self.marker)}}]\n", concealed: Self.marker)
        #expect(throws: PreviewFailure.structureTooDeep) {
            try Self.parse(deep, budget: PreviewBudget(maxJSONDepth: 2))
        }
        let malformed = [
            Sample(id: "flow-missing-close", family: .yaml, filename: "config.yaml",
                   text: "entry: {value: \(Self.marker), name: password", concealed: Self.marker),
            Sample(id: "flow-uncertain-sensitive", family: .yaml, filename: "config.yaml",
                   text: "entry: {name: password, value: \(Self.marker), malformed}\n", concealed: Self.marker),
            Sample(id: "flow-alias-fallback", family: .yaml, filename: "config.yaml",
                   text: "shared: &fixture \(Self.marker)\nentry: {name: password, value: *fixture}\n", concealed: Self.marker)
        ]
        for sample in malformed {
            let result = try safe(sample)
            let leaked = result.text.contains(Self.marker)
            #expect(!leaked, "Uncertain flow record \(sample.id)")
            #expect(result.redactionCount > 0)
        }
    }

    @Test func finalLexicalPassesKeepCancellationCheckpointsAcrossEscapedRuns() async throws {
        let escaped = String(repeating: "\\t", count: 8_192)
        let samples = [
            Sample(id: "source-escaped-progress", family: .source, filename: "config.js",
                   text: "const note = '\(escaped)\\x73k_test_\(Self.tokenBody)';", concealed: Self.tokenBody),
            Sample(id: "flow-escaped-progress", family: .yaml, filename: "config.yaml",
                   text: "entry: {name: password, value: \"\(escaped)\(Self.marker)\"}\n", concealed: Self.marker)
        ]
        for sample in samples {
            let count = Mutex(0)
            var baseline = RequestContext(budget: .standard)
            baseline.checkpointObserver = { count.withLock { $0 += 1 } }
            let document = try Self.parse(sample, context: baseline)
            #expect(!document.sensitiveRanges.isEmpty)
            let cancelAt = max(2, count.withLock { $0 } / 2)
            let observed = Mutex(0)
            let stopped = await Task.detached {
                var context = RequestContext(budget: .standard)
                context.checkpointObserver = {
                    let current = observed.withLock { $0 += 1; return $0 }
                    if current == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
                }
                do { _ = try Self.parse(sample, context: context); return false }
                catch is CancellationError { return true }
                catch { return false }
            }.value
            #expect(stopped, "Final lexical cancellation \(sample.id)")
            #expect(observed.withLock { $0 } == cancelAt)
        }
    }

    @Test(arguments: [
        Sample(id: "javascript-private-field", family: .source, filename: "config.js",
               text: "class Config { #note = '\\x73k_test_\(Self.tokenBody)'; }", concealed: Self.tokenBody),
        Sample(id: "typescript-private-field", family: .source, filename: "config.ts",
               text: "class Config { #note = '\\u0073k_test_\(Self.tokenBody)'; }", concealed: Self.tokenBody),
        Sample(id: "yaml-flow-array-value", family: .yaml, filename: "config.yaml",
               text: "entry: [\"\\u0073k_test_\(Self.tokenBody)\"]\n", concealed: Self.tokenBody),
        Sample(id: "yaml-flow-nested-array", family: .yaml, filename: "config.yaml",
               text: "entry: [[\"\\u0073k_test_\(Self.tokenBody)\"]]\n", concealed: Self.tokenBody),
        Sample(id: "yaml-flow-object-array", family: .yaml, filename: "config.yaml",
               text: "entry: {notes: [\"\\u0073k_test_\(Self.tokenBody)\"]}\n", concealed: Self.tokenBody),
        Sample(id: "yaml-sequence-member-flow", family: .yaml, filename: "config.yaml",
               text: "- name: title\n  child: {name: password, value: \(Self.marker)}\n", concealed: Self.marker),
        Sample(id: "yaml-inert-anchor-flow", family: .yaml, filename: "config.yaml",
               text: "entry: &fixture {name: password, value: \(Self.marker)}\n", concealed: Self.marker),
        Sample(id: "yaml-inert-tag-flow", family: .yaml, filename: "config.yaml",
               text: "!<tag:example.test,2026:map> {name: password, value: \(Self.marker)}\n", concealed: Self.marker)
    ])
    func reviewedPrivateFieldsAndFlowArrayScalarsUseDecodedRecognition(sample: Sample) throws {
        let result = try safe(sample)
        let leaked = result.text.contains(sample.concealed)
        #expect(!leaked, "Reviewed lexical boundary \(sample.id)")
        #expect(result.redactionCount > 0)
    }

    @Test(arguments: [
        Sample(id: "javascript-unterminated-escaped-literal", family: .source, filename: "config.js",
               text: "const note = '\\x73k_test_\(Self.tokenBody)", concealed: Self.tokenBody),
        Sample(id: "python-leading-record-escaped-prefix", family: .source, filename: "config.py",
               text: "note = \"\\u0073k_test_\(Self.tokenBody)\n", concealed: Self.tokenBody)
    ])
    func recognizableDecodedContentConcealsAnEntireUnterminatedLiteral(sample: Sample) throws {
        let document = try Self.parse(sample)
        let result = try DefaultPrivacyFilter().filter(document, context: RequestContext(budget: .standard))
        let leaked = result.text.contains(sample.concealed)
        #expect(!leaked, "Unterminated decoded credential \(sample.id)")
        #expect(result.redactionCount > 0)
    }

    @Test(arguments: ["|", ">-", "|2-"])
    func bracketsInsideYAMLBlockScalarsAreProseRatherThanCollections(indicator: String) throws {
        let brackets = String(repeating: "[", count: 129) + String(repeating: "]", count: 129)
        let source = "note: \(indicator)\n  \(brackets)\nnext: \(Self.ordinary)\n"
        let sample = Sample(id: "yaml-block-prose", family: .yaml, filename: "config.yaml", text: source, concealed: Self.ordinary)
        let document = try Self.parse(sample, budget: PreviewBudget(maxJSONDepth: 2))
        let result = try DefaultPrivacyFilter().filter(document, context: RequestContext(budget: .standard))
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
    }

    @Test(arguments: ["note: |\n  [a,b,c]\n", "note: prose [a,b,c] remains text\n"])
    func proseBracketsDoNotSpendTheFlowCollectionNodeBudget(source: String) throws {
        let sample = Sample(id: "yaml-prose-node-budget", family: .yaml, filename: "config.yaml", text: source, concealed: "a,b,c")
        let document = try Self.parse(sample, budget: PreviewBudget(maxJSONNodes: 1))
        let result = try DefaultPrivacyFilter().filter(document, context: RequestContext(budget: PreviewBudget(maxJSONNodes: 1)))
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
    }

    @Test(arguments: ["note:[a,b,c]\n", "scheme:[a,b,c]\n"])
    func unseparatedColonsRemainPlainScalarsWithoutFlowNodes(source: String) throws {
        let sample = Sample(id: "yaml-unseparated-colon", family: .yaml, filename: "config.yaml",
                            text: source, concealed: "a,b,c")
        let budget = PreviewBudget(maxJSONNodes: 1)
        let document = try Self.parse(sample, budget: budget)
        let result = try DefaultPrivacyFilter().filter(document, context: RequestContext(budget: budget))
        #expect(result.text == source)
        #expect(result.redactionCount == 0)
        let mapping = Sample(id: "yaml-separated-colon", family: .yaml, filename: "config.yaml",
                             text: "note: [a,b,c]\n", concealed: "a,b,c")
        #expect(throws: PreviewFailure.tooManyNodes) { try Self.parse(mapping, budget: budget) }
    }

    private static func parse(_ sample: Sample, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
        try Self.parse(sample, context: RequestContext(budget: budget))
    }

    private static func parse(_ sample: Sample, context supplied: RequestContext) throws -> ParsedTextDocument {
        var context = supplied
        context.nameHint = PreviewNameHint(filename: sample.filename, suffix: (sample.filename as NSString).pathExtension)
        let input = DecodedText(text: sample.text, encoding: .utf8, byteCount: sample.text.utf8.count)
        switch sample.family {
        case .json: return try JSONSourceAdapter().parse(input, context: context)
        case .jsonc: return try JSONCAdapter().parse(input, context: context)
        case .yaml: return try YAMLSourceAdapter().parse(input, context: context)
        case .toml: return try TOMLSourceAdapter().parse(input, context: context)
        case .xml: return try XMLSourceAdapter().parse(input, context: context)
        case .source: return try SourceCodeAdapter().parse(input, context: context)
        case .unnamed: return try ExtensionlessTextAdapter().parse(FileBytes(data: Data(sample.text.utf8)), context: context)
        }
    }

    private func safe(_ sample: Sample) throws -> SafeText {
        try DefaultPrivacyFilter().filter(Self.parse(sample), context: RequestContext(budget: .standard))
    }

    @Test(arguments: positives)
    func newlyRecognizedBindingsAndDecodedValuesAreConcealed(sample: Sample) throws {
        let result = try safe(sample)
        let leaked = result.text.contains(sample.concealed)
        #expect(!leaked, "Adapter grammar \(sample.id)")
        #expect(result.redactionCount > 0, "Adapter grammar \(sample.id)")
        #expect(result.findings.contains { $0.kind == .secretSensitiveField })
        if sample.text.contains(Self.ordinary) {
            let neighborPreserved = result.text.contains(Self.ordinary)
            #expect(neighborPreserved, "Adjacent ordinary record \(sample.id)")
        }
    }

    @Test(arguments: negatives)
    func scopeBoundariesAndOrdinaryBindingsStayReadable(sample: Sample) throws {
        let result = try safe(sample)
        let preserved = result.text.contains(sample.concealed)
        #expect(preserved, "Ordinary adapter grammar \(sample.id)")
        #expect(result.redactionCount == 0, "Ordinary adapter grammar \(sample.id)")
    }

    @Test func duplicateValueMembersAreAllConcealedWithinTheSameObject() throws {
        let text = "{\"value\":\"\(Self.marker)-first\",\"name\":\"api_key\",\"value\":\"\(Self.marker)-second\"}"
        let result = try safe(Sample(id: "duplicates", family: .json, filename: "config.json", text: text, concealed: Self.marker))
        let leaked = result.text.contains(Self.marker)
        #expect(!leaked)
        #expect(result.redactionCount == 2)
    }

    @Test func nestedObjectsDoNotInheritAnOuterSiblingBinding() throws {
        let text = "{\"name\":\"api_key\",\"child\":{\"value\":\"\(Self.ordinary)\"},\"value\":\"\(Self.marker)\"}"
        let result = try safe(Sample(id: "nested", family: .json, filename: "config.json", text: text, concealed: Self.marker))
        let leaked = result.text.contains(Self.marker)
        let neighborPreserved = result.text.contains(Self.ordinary)
        #expect(!leaked && neighborPreserved)
        #expect(result.redactionCount == 1)
    }

    @Test func multilineSensitiveBindingsConcealTheCompleteValue() throws {
        let samples = [
            Sample(id: "java-text-block", family: .source, filename: "Config.java", text: "System.setProperty(\"password\", \"\"\"\n\(Self.marker)\n\"\"\");\nString title = \"\(Self.ordinary)\";", concealed: Self.marker),
            Sample(id: "yaml-literal-binding", family: .yaml, filename: "config.yaml", text: "settings:\n  - name: password\n    value: |\n      \(Self.marker)\n  - name: title\n    value: \(Self.ordinary)\n", concealed: Self.marker),
            Sample(id: "yaml-folded-value-first", family: .yaml, filename: "config.yaml", text: "settings:\n  - value: >-\n      \(Self.marker)\n    name: api_key\n  - name: title\n    value: \(Self.ordinary)\n", concealed: Self.marker),
            Sample(id: "yaml-nested-value", family: .yaml, filename: "config.yaml", text: "entry:\n  name: api_key\n  value:\n    text: \(Self.marker)\nnext: \(Self.ordinary)\n", concealed: Self.marker)
        ]
        for sample in samples {
            let result = try safe(sample)
            let leaked = result.text.contains(sample.concealed)
            let neighborPreserved = result.text.contains(Self.ordinary)
            #expect(!leaked, "Complete multiline binding \(sample.id)")
            #expect(neighborPreserved, "Adjacent ordinary binding \(sample.id)")
        }
    }

    @Test func malformedCredentialFilesAndInertMacrosAreConcealed() throws {
        let samples = [
            Sample(id: "netrc-unclosed-value", family: .unnamed, filename: ".netrc", text: "default login demo password \"\(Self.marker)\ncontinuation\n", concealed: Self.marker),
            Sample(id: "netrc-inert-macro", family: .unnamed, filename: ".netrc", text: "machine example.test login demo\nmacdef init\nuser demo \(Self.marker)\n\nmachine next.test login \(Self.ordinary)\n", concealed: Self.marker),
            Sample(id: "pgpass-missing-delimiters", family: .unnamed, filename: ".pgpass", text: "sample:demo:\(Self.marker)\n# \(Self.ordinary)\n", concealed: Self.marker)
        ]
        for sample in samples {
            let result = try safe(sample)
            let leaked = result.text.contains(sample.concealed)
            #expect(!leaked, "Malformed or macro grammar \(sample.id)")
            #expect(result.redactionCount > 0)
            if sample.text.contains(Self.ordinary) {
                let neighborPreserved = result.text.contains(Self.ordinary)
                #expect(neighborPreserved, "Macro boundary \(sample.id)")
            }
        }
    }

    @Test func sensitiveLiteralNamesConcealCompleteInertValueExpressions() throws {
        let samples = [
            Sample(id: "java-concatenation", family: .source, filename: "Config.java", text: "System.setProperty(\"password\", \"prefix\" + \"\(Self.marker)\");\nString title = \"\(Self.ordinary)\";", concealed: Self.marker),
            Sample(id: "php-concatenation", family: .source, filename: "config.php", text: "<?php define('API_KEY', 'prefix' . '\(Self.marker)');\n$title = '\(Self.ordinary)';", concealed: Self.marker),
            Sample(id: "java-nested-expression", family: .source, filename: "Config.java", text: "System.setProperty(\"password\", choose(\"prefix\", \"\(Self.marker)\"));\nString title = \"\(Self.ordinary)\";", concealed: Self.marker),
            Sample(id: "java-comment-expression", family: .source, filename: "Config.java", text: "System.setProperty(\"password\", /* ) not a delimiter */ \"prefix\" +\n \"\(Self.marker)\");\nString title = \"\(Self.ordinary)\";", concealed: Self.marker),
            Sample(id: "python-parenthesized-expression", family: .source, filename: "config.py", text: "os.environ[\"API_KEY\"] = (\n \"prefix\" +\n \"\(Self.marker)\"\n)\ntitle = \"\(Self.ordinary)\"", concealed: Self.marker)
        ]
        for sample in samples {
            let result = try safe(sample)
            let leaked = result.text.contains(sample.concealed)
            let neighborPreserved = result.text.contains(Self.ordinary)
            #expect(!leaked, "Inert sensitive expression \(sample.id)")
            #expect(neighborPreserved, "Expression boundary \(sample.id)")
        }
    }

    @Test func sensitiveNamedYAMLAliasesUseTheExistingConservativeFallback() throws {
        let sample = Sample(id: "yaml-named-alias", family: .yaml, filename: "config.yaml", text: "shared: &fixture \(Self.marker)\nentry:\n  name: password\n  value: *fixture\n", concealed: Self.marker)
        let result = try safe(sample)
        #expect(result.text == SecretFieldPolicy.concealmentToken)
        #expect(result.redactionCount == 1)
    }

    @Test func credentialAnnotationsSurviveMinifiedJSONReformatting() throws {
        let sample = Sample(id: "formatted-binding", family: .json, filename: "config.json", text: "{\"name\":\"password\",\"value\":\"\(Self.marker)\",\"title\":\"\(Self.ordinary)\"}", concealed: Self.marker)
        let context = RequestContext(budget: PreviewBudget(maxLineUTF8Bytes: 48))
        let document = try Self.parse(sample, context: context)
        let result = try DefaultPrivacyFilter().filter(document, context: context)
        #expect(document.isReformatted)
        let leaked = result.text.contains(Self.marker)
        let preserved = result.text.contains(Self.ordinary)
        #expect(!leaked && preserved)
        #expect(result.redactionCount == 1)
    }

    @Test func newGrammarsRespectInputDeadlinesAndAnnotationStorageBounds() throws {
        for family in [Family.json, .jsonc, .xml] {
            let sample = try #require(Self.positives.first { $0.family == family })
            #expect(throws: PreviewFailure.tooManyNodes) {
                try Self.parse(sample, budget: PreviewBudget(maxJSONNodes: 1))
            }
        }
        let capped = [
            Sample(id: "yaml-cap", family: .yaml, filename: "config.yaml", text: "name: password\nvalue: \(Self.marker)\nnext:\n  name: api_key\n  value: \(Self.marker)\n", concealed: Self.marker),
            Sample(id: "source-cap", family: .source, filename: "Config.java", text: "System.setProperty(\"password\", \"\(Self.marker)\");\nSystem.setProperty(\"api_key\", \"\(Self.marker)\");", concealed: Self.marker),
            Sample(id: "netrc-cap", family: .unnamed, filename: ".netrc", text: "password \(Self.marker)\npassword \(Self.marker)\n", concealed: Self.marker),
            Sample(id: "pgpass-cap", family: .unnamed, filename: ".pgpass", text: "host:5432:db:user:\(Self.marker)\nhost:5432:db:user:\(Self.marker)\n", concealed: Self.marker)
        ]
        for sample in capped {
            let context = RequestContext(budget: PreviewBudget(maxJSONNodes: 1))
            let document = try Self.parse(sample, context: context)
            #expect(document.sensitiveRanges.count == 1, "Bounded grammar \(sample.id)")
            #expect(document.sensitiveRanges.first?.utf8Range == 0..<document.text.utf8.count)
            let result = try DefaultPrivacyFilter().filter(document, context: context)
            #expect(result.text == SecretFieldPolicy.concealmentToken)
        }
        for sample in Self.positives {
            #expect(throws: PreviewFailure.deadlineExceeded) {
                try Self.parse(sample, budget: PreviewBudget(maxMilliseconds: 0))
            }
            #expect(throws: PreviewFailure.inputTooLarge) {
                try Self.parse(sample, budget: PreviewBudget(maxInputBytes: 8))
            }
        }
    }

    @Test func activeCredentialParsersStopAtADeterministicCancellationCheckpoint() async throws {
        for family in [Family.json, .jsonc, .yaml, .xml, .source, .unnamed] {
            let sample = try #require(Self.positives.first { $0.family == family })
            let completedCheckpoints = Mutex(0)
            var baseline = RequestContext(budget: .standard)
            baseline.checkpointObserver = { completedCheckpoints.withLock { $0 += 1 } }
            _ = try Self.parse(sample, context: baseline)
            let cancelAt = max(2, completedCheckpoints.withLock { $0 } / 2)
            let observed = Mutex(0)
            let outcome = await Task.detached {
                var context = RequestContext(budget: .standard)
                context.checkpointObserver = {
                    let count = observed.withLock { $0 += 1; return $0 }
                    if count == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
                }
                do { _ = try Self.parse(sample, context: context); return false }
                catch is CancellationError { return true }
                catch { return false }
            }.value
            #expect(outcome, "Active grammar family \(family)")
            #expect(observed.withLock { $0 } == cancelAt)
        }
    }

    @Test func realCredentialFilePreviewsNeverChangeTheirIsolatedSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        for sample in Self.positives {
            let url = directory.appendingPathComponent(sample.filename)
            let original = Data(sample.text.utf8)
            try original.write(to: url)
            let before = try FileManager.default.attributesOfItem(atPath: url.path)
            let outcome = await pipeline.preview(url: url)
            guard case .ready(let presentation) = outcome else {
                Issue.record("Expected isolated synthetic preview for \(sample.id)"); continue
            }
            let leaked = presentation.text.contains(sample.concealed)
            #expect(!leaked, "Pipeline grammar \(sample.id)")
            #expect(presentation.redactionCount > 0)
            #expect(try Data(contentsOf: url).elementsEqual(original))
            let after = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
            #expect(before[.posixPermissions] as? NSNumber == after[.posixPermissions] as? NSNumber)
        }
    }

    @Test func extensionlessCredentialParsingPreservesSourceBytesAndMetadataOnlyNames() throws {
        for sample in Self.positives where sample.family == .unnamed {
            let input = Data(sample.text.utf8)
            let original = Array(input)
            var context = RequestContext(budget: .standard)
            context.nameHint = PreviewNameHint(filename: sample.filename, suffix: "")
            let document = try ExtensionlessTextAdapter().parse(FileBytes(data: input), context: context)
            #expect(Array(input) == original)
            let unchanged = document.text.utf8.elementsEqual(sample.text.utf8)
            #expect(unchanged)
            #expect(document.usesStructuredPrivacy)
            #expect(!document.sensitiveRanges.isEmpty)
        }
    }
}

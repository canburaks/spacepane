import Foundation
import Testing

/// Synthetic, inert samples: no provider-issued values or user files. The labels are the only
/// descriptions printed by parameterized tests. Families describe grammars, not catalog formats.
enum Q16CredentialCorpus {
    struct Positive: Sendable, CustomTestStringConvertible {
        let family: String
        let variant: Int
        let line: String
        let credential: String
        let structured: Bool
        var testDescription: String { "\(family)/\(variant)" }
    }

    struct Ordinary: Sendable, CustomTestStringConvertible {
        let index: Int
        let line: String
        var testDescription: String { "ordinary/\(index)" }
    }

    /// Independent expectations cover separators, camel case, acronym boundaries and legacy aliases.
    static let fieldNames = [
        "password", "passwd", "pwd", "pass", "passphrase", "secret", "token", "auth",
        "authorization", "credential", "credentials", "cookie", "session", "dsn", "mnemonic",
        "api_key", "accessKey", "private.key", "secret-key", "clientSecret", "signing_key",
        "encryptionKey", "master_key", "client_key", "key_data", "AccountKey", "aws_access_key_id",
        "connectionstring", "requirepass", "masterauth", "sessionid", "_auth", "APIKey", "cacheKey",
        "api\u{200B}Key"
    ]

    private static let fieldSamples: [Positive] = fieldNames.enumerated().flatMap { index, name in
        (0..<4).map { variant in
            let credential = "synthetic-q16-field-\(index)-\(variant)"
            let line: String
            switch variant {
            case 0: line = "\(name)=\(credential)"
            case 1: line = "\(name): \(credential)"
            case 2: line = "\"\(name)\" = '\(credential)'"
            default: line = "\"\(name)\": \"\(credential)\""
            }
            return Positive(family: "field-\(index)", variant: variant, line: line,
                            credential: credential, structured: false)
        }
    }

    private static func payload(_ variant: Int, count: Int) -> String {
        let alphabet = "Aa1Bb2Cc3Dd4Ee5Ff6Gg7Hh8Ii9Jj0SyntheticFixtureOnly"
        return String((0..<count).map { offset in Array(alphabet)[(offset + variant) % alphabet.count] })
    }

    /// Published prefix/shape families, with deliberately non-issued payloads. Prefix recognition is
    /// a concealment heuristic: it does not validate a credential or contact a provider.
    private static let valueFactories: [(String, @Sendable (Int) -> String)] = [
        ("stripe-secret-test", { "sk_test_" + payload($0, count: 32) }),
        ("stripe-secret-live", { "sk_live_" + payload($0, count: 32) }),
        ("stripe-restricted-test", { "rk_test_" + payload($0, count: 32) }),
        ("stripe-restricted-live", { "rk_live_" + payload($0, count: 32) }),
        ("stripe-organization", { "sk_org_" + payload($0, count: 32) }),
        ("slack-bot", { "xoxb-123456789012-987654321098-" + payload($0, count: 24) }),
        ("slack-user", { "xoxp-123456789012-987654321098-" + payload($0, count: 24) }),
        ("slack-app-user", { "xoxa-" + payload($0, count: 40) }),
        ("slack-configuration", { "xoxe.xoxp-" + payload($0, count: 40) }),
        ("slack-browser", { "xoxs-" + payload($0, count: 40) }),
        ("slack-refresh", { "xoxr-" + payload($0, count: 40) }),
        ("slack-legacy", { "xoxo-" + payload($0, count: 40) }),
        ("slack-app-level", { "xapp-1-" + payload($0, count: 36) }),
        ("google-api", { "AIza" + payload($0, count: 35) }),
        ("gitlab-personal", { "glpat-" + payload($0, count: 32) }),
        ("npm-access", { "npm_" + payload($0, count: 36) }),
        ("pypi-upload", { "pypi-AgE" + payload($0, count: 48) }),
        ("sendgrid-api", { "SG." + payload($0, count: 22) + "." + payload($0, count: 43) }),
        ("encoded-private-pem", {
            Data("-----BEGIN PRIVATE KEY-----\nsynthetic-only-\($0)\n-----END PRIVATE KEY-----".utf8).base64EncodedString()
        }),
        ("azure-account", { "AccountKey=" + Data("synthetic-account-\($0)".utf8).base64EncodedString() }),
        ("azure-shared-key", { "SharedAccessKey=" + Data("synthetic-access-\($0)".utf8).base64EncodedString() }),
        ("azure-shared-signature", { "SharedAccessSignature=sr=https%3A%2F%2Fexample.test&sig=synthetic-q16-\($0)&se=1234567890" })
    ]

    private static let valueSamples: [Positive] = valueFactories.flatMap { family, makeValue in
        (0..<4).map { variant in
            let credential = makeValue(variant)
            let line: String
            switch variant {
            case 0: line = "payload \(credential)"
            case 1: line = "note: \(credential)"
            case 2: line = "{\"value\":\"\(credential)\"}"
            default: line = "row,\"\(credential)\",ordinary"
            }
            return Positive(family: family, variant: variant, line: line,
                            credential: credential, structured: true)
        }
    }

    static let positives = fieldSamples + valueSamples

    static let ordinary: [Ordinary] = [
        "The basic programming course starts on Monday.",
        "The basic configuration guide has several examples.",
        "Bearer certificates describe ownership of the paper document.",
        "A bearer instrument can be transferred to another owner.",
        "The basic principles remain easy to explain.",
        "A bearer endorsement appears on this historical form.",
        "We teach BASIC programming as a historical language.",
        "basic arithmetic is useful in the workshop.",
        "bearer documents belong in the history archive.",
        "basic algorithms need careful explanations.",
        "public_key = published-example",
        "ssh_public_key = published-example",
        "publicKey: published-example",
        "primary_key = record_id",
        "primaryKey: record_id",
        "foreign_key = parent_id",
        "foreignKey: parent_id",
        "sort_key = created_at",
        "sortKey: created_at",
        "partition_key = region",
        "partitionKey: region",
        "hot_key = cmd_f",
        "hotKey: cmd_f",
        "key_path = preferences.appearance",
        "keyPath: preferences.appearance",
        "key_id = identifier",
        "keyId: identifier",
        "monkey = animal",
        "compass = north",
        "bypass = closed",
        "passwordless_mode = enabled",
        "tokenizer = lexer",
        "tokenization = lexical_analysis",
        "secretariat = room_12",
        "records_count = 7",
        "authorship = anonymous",
        "author = Ada",
        "cookiecutter = template",
        "sessional = term",
        "passwdic = glossary",
        "The file contains plain text for a preview.",
        "A tree has branches and leaves.",
        "We preserve source code units when displaying text.",
        "The database table has a primary key.",
        "The database table has a foreign key.",
        "The map legend shows a compass rose.",
        "A monkey climbed the tree.",
        "A passwordless login guide explains public authentication.",
        "The tokenizer separates words from punctuation.",
        "A secretariat schedules the meeting.",
        "This published key is an example label.",
        "This is a basic preview of the sample document.",
        "The bearer of good news arrived early.",
        "Use semantic leading and trailing layout.",
        "The application processes local files.",
        "Read-only previews preserve source bytes.",
        "A redaction count reports how many values were concealed.",
        "A finding describes its kind and displayed line.",
        "No scripts are executed by this preview.",
        "A theme changes colors and font choices.",
        "Local notes have a title and body.",
        "A Markdown heading begins with a hash sign.",
        "The outline lists headings in document order.",
        "A table can show rows and columns.",
        "The source view supports selection and copying.",
        "Search highlights an ordinary word in safe text.",
        "The sidebar lists application destinations.",
        "The window can be resized by its owner.",
        "The menu command opens the current screen.",
        "A sample image uses synthetic geometry.",
        "The catalog contains stable logical type identifiers.",
        "The thumbnail does not include sensitive content.",
        "Rendering begins after file classification.",
        "A parser reads bounded bytes.",
        "The request checks cancellation at progress points.",
        "A malformed document produces an explicit fallback.",
        "The footer shows a row count.",
        "The display language changes application copy.",
        "File contents retain their original language.",
        "A byte count is formatted for the presentation locale.",
        "The page is visible in a narrow window.",
        "A keyboard shortcut selects the next mode.",
        "The font sample is inert text.",
        "The chart has a legend and axis labels.",
        "The cache is bounded and contains safe results.",
        "The preview host controls its own window.",
        "A unit test uses synthetic input.",
        "The fixture contains no provider-issued credentials.",
        "The matrix records observed host behavior.",
        "The extension uses a validated settings snapshot.",
        "A nested array has three elements.",
        "A nested object has two properties.",
        "The first line ends with a newline.",
        "A quoted string can contain Unicode.",
        "A line number refers to displayed text.",
        "The first column contains names.",
        "The second column contains quantities.",
        "The third column contains descriptions.",
        "The overview shows the file type.",
        "A density setting changes spacing.",
        "Header labels describe the current mode.",
        "A disabled type produces a disabled state.",
        "The app never promises provider priority.",
        "The help page explains setup steps.",
        "An import operation validates inert schema data.",
        "The export operation writes only an explicitly chosen file.",
        "A native outline preserves expansion state.",
        "A document has ordinary punctuation: commas, quotes, periods.",
        "Published Stripe samples begin pk_test_example.",
        "The short prefix sk_test_ is a label with no payload.",
        "The short prefix xoxb- is a label with no payload.",
        "The short prefix glpat- is a label with no payload.",
        "The short prefix npm_ is a label with no payload.",
        "The short prefix pypi- is a label with no payload.",
        "The short prefix AIza is a label with no payload.",
        "A public PEM header is -----BEGIN PUBLIC KEY-----.",
        "A certificate header is -----BEGIN CERTIFICATE-----.",
        "A private key header is mentioned in documentation without a body.",
        "Clone ssh://git@git.example.test/team/repo.git.",
        "Open https://example.test/guide for documentation."
    ].enumerated().map { Ordinary(index: $0.offset, line: $0.element) }
}

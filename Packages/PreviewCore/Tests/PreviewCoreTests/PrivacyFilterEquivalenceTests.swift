import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

/// The optimized filter (one contiguous UTF-16 copy, literal gates, sparse progress checkpoints and
/// a sorted offset cursor) must conceal exactly what the previous implementation concealed.
@Suite("Privacy filter equivalence")
struct PrivacyFilterEquivalenceTests {
    private enum Outcome: Equatable {
        case value(text: String, count: Int, syntax: TextSyntax)
        case failure(PreviewFailure)
        case other(String)

        init(_ body: () throws -> SafeText) {
            do {
                let safe = try body()
                self = .value(text: safe.text, count: safe.redactionCount, syntax: safe.syntax)
            } catch let failure as PreviewFailure {
                self = .failure(failure)
            } catch {
                self = .other(String(describing: type(of: error)))
            }
        }
    }

    private let optimized = DefaultPrivacyFilter()
    private let reference = ReferencePrivacyFilter()

    private func compare(_ document: ParsedTextDocument, budget: PreviewBudget = .standard,
                         sourceLocation: SourceLocation = #_sourceLocation) -> Outcome {
        let actual = Outcome { try optimized.filter(document, context: RequestContext(budget: budget)) }
        let expected = Outcome { try reference.filter(document, context: RequestContext(budget: budget)) }
        #expect(actual == expected, "Optimized filter diverged for \(document.text.debugDescription)",
                sourceLocation: sourceLocation)
        return actual
    }

    private static let credentials = [
        "AKIAABCDEFGHIJKLMNOP",
        "ASIAABCDEFGHIJKLMNOP",
        "ghp_" + String(repeating: "a1", count: 18),
        "gho_" + String(repeating: "B2", count: 18),
        "ghu_" + String(repeating: "c3", count: 18),
        "ghs_" + String(repeating: "D4", count: 18),
        "ghr_" + String(repeating: "e5", count: 18),
        "github_pat_" + String(repeating: "f6", count: 12),
        "sk-" + String(repeating: "g7", count: 12),
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzeW50aGV0aWMifQ.c3ludGhldGljLXNpZw",
        "Bearer abcdefgh12345678",
        "basic dGVzdDp0ZXN0MTIz",
        "-----BEGIN PRIVATE KEY-----\nc3ludGhldGljLWJvZHk=\n-----END PRIVATE KEY-----"
    ]

    @Test(arguments: credentials)
    func everyCredentialShapeIsConcealedLikeBefore(credential: String) {
        for template in ["x %@ y", "%@", "key: %@\nnext", "😀日本語 %@ \u{2028} é\r\n"] {
            let text = template.replacingOccurrences(of: "%@", with: credential)
            let outcome = compare(ParsedTextDocument(text: text))
            guard case .value(let safe, let count, _) = outcome else {
                Issue.record("Unexpected failure for credential template")
                continue
            }
            #expect(count >= 1)
            #expect(!safe.contains(credential))
        }
    }

    @Test(arguments: [
        "", " ", "\n", "plain text only", "ghp_short", "gho_", "github_pat_", "sk-abc", "sk-", "eyJ", "eyJ.a.b",
        "AKIA1234", "ASIA", "-----BEGIN ", "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----",
        "-----BEGIN RSA PRIVATE KEY-----\nbody without end", "task-aaaaaaaaaaaaaaaaaaaaa", "risk-bbbbbbbbbbbbbbbbbbbbbb",
        "bearer short", "Bearer", "baſic dGVzdDp0ZXN0MTIz", "BASIC dGVzdDp0ZXN0MTIz", "ßasic Kelvin K bearer aaaaaaaaaa",
        "password=synthetic-value", "PASSWORD : synthetic-value\nnext line", "\"api_key\" = 'synthetic'", "token=\"unterminated\nnext",
        "secret: {\n  nested: value\n}\nafter", "client_secret = '''\nmulti\nline'''\nafter",
        "a: 😀\nb: 日本語\nauth_token: \u{85}tail", "passwd:\r\nvalue\r\nmore", "name = value\nsafe: yes"
    ])
    func handwrittenEdgeCasesMatchTheReference(text: String) {
        _ = compare(ParsedTextDocument(text: text))
        _ = compare(ParsedTextDocument(text: text, usesStructuredPrivacy: true))
    }

    @Test func randomizedDocumentsMatchTheReferenceForBothPrivacyModes() {
        var generator = SplitMix64(seed: 0x5EED_CAFE)
        let fragments: [String] = Self.credentials + [
            "ghp_", "sk-", "eyJ", "AKIA", "ASIA", "-----BEGIN ", "-----END PRIVATE KEY-----", "bearer ", "Basic ", "baſic ",
            "password", "Password", "api_key", "token", "secret", "name", "value", "key", "x", " ", "  ", "\t", ":", "=", ": ", " = ",
            "\"", "'", "\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}", "é", "e\u{301}", "日本語", "😀", "🌍", "𝒳", "K", "ß", "İ",
            "0123456789", "abcdefghijklmnop", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "-", "_", ".", "{", "}", "[", "]", ",", "\\"
        ]
        for _ in 0..<600 {
            let count = Int(generator.next() % 40)
            var text = ""
            for _ in 0..<count { text += fragments[Int(generator.next() % UInt64(fragments.count))] }
            _ = compare(ParsedTextDocument(text: text))
            _ = compare(ParsedTextDocument(text: text, usesStructuredPrivacy: true))
        }
    }

    @Test func structuredSensitiveRangesAreTranslatedLikeBeforeIncludingBoundaryErrors() throws {
        let sources = [
            #"{"password":"synthetic-private-value","name":"🌍 日本語","token":"a😀b","rows":[1,2,3]}"#,
            "{\n  \"café\": \"é\",\n  \"secret\": \"x\\u0041\"\n}",
            #"{"a":"😀😀😀","apiKey":"😀","z":null}"#
        ]
        for source in sources {
            let context = RequestContext(budget: .standard)
            let parsed = try JSONSourceAdapter().parse(DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count),
                                                     context: context)
            #expect(!parsed.sensitiveRanges.isEmpty)
            _ = compare(parsed)
        }
        // Offsets inside a scalar, reversed, repeated and past the end fail identically.
        let text = "a😀b日本語c"
        let utf8 = text.utf8.count
        let ranges: [[Range<Int>]] = [
            [2..<3], [1..<2], [0..<utf8], [utf8..<utf8], [3..<3, 3..<3], [1..<5, 2..<8], [0..<(utf8 + 1)],
            [0..<1, 5..<6, 6..<utf8]
        ]
        for set in ranges {
            let document = ParsedTextDocument(text: text, sensitiveRanges: set.map { SensitiveRange(utf8Range: $0) },
                                              usesStructuredPrivacy: true)
            _ = compare(document)
        }
        _ = compare(ParsedTextDocument(text: "abc", sensitiveRanges: [.init(utf8Range: 0..<3)], usesStructuredPrivacy: true),
                    budget: PreviewBudget(maxJSONNodes: 1))
    }

    @Test func sensitiveRangeCountAndOutputBudgetsAreStillEnforced() {
        let many = (0..<5).map { SensitiveRange(utf8Range: $0..<($0 + 1)) }
        let document = ParsedTextDocument(text: "abcdefgh", sensitiveRanges: many, usesStructuredPrivacy: true)
        #expect(compare(document, budget: PreviewBudget(maxJSONNodes: 2)) == .failure(.tooManyNodes))
        let large = ParsedTextDocument(text: String(repeating: "a", count: 4_000))
        #expect(compare(large, budget: PreviewBudget(maxOutputUTF8Bytes: 1_000)) == .failure(.outputTooLarge))
    }

    @Test func deadlineInterruptsTheScanInsteadOfWaitingForItToFinish() {
        // No assignment or credential ever matches, so only progress events can notice the deadline
        // inside the long key pass; match callbacks would otherwise check it for us.
        let document = ParsedTextDocument(text: String(repeating: "lorem ipsum dolor sit amet\n", count: 70_000))
        let clock = ContinuousClock()
        var fullDuration = Duration.zero
        let completed = Outcome {
            let start = clock.now
            defer { fullDuration = start.duration(to: clock.now) }
            return try optimized.filter(document, context: RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)))
        }
        guard case .value = completed else { Issue.record("The unconstrained scan must complete"); return }
        let deadline = max(1, Int(fullDuration / .milliseconds(1)) / 4)
        var interruptedDuration = Duration.zero
        let interrupted = Outcome {
            let start = clock.now
            defer { interruptedDuration = start.duration(to: clock.now) }
            return try optimized.filter(document, context: RequestContext(budget: PreviewBudget(maxMilliseconds: deadline)))
        }
        #expect(interrupted == .failure(.deadlineExceeded))
        #expect(interruptedDuration < fullDuration * 0.75, "Deadline \(deadline) ms ignored: \(interruptedDuration) of \(fullDuration)")
        let expired = Outcome { try optimized.filter(document, context: RequestContext(budget: PreviewBudget(maxMilliseconds: 0))) }
        #expect(expired == .failure(.deadlineExceeded))
    }

    @Test func cancellationIsObservedBeforeAnyWork() async {
        let document = ParsedTextDocument(text: String(repeating: "key: value\n", count: 20_000))
        let task = Task.detached { [optimized] in
            withUnsafeCurrentTask { $0?.cancel() }
            return Outcome { try optimized.filter(document, context: RequestContext(budget: .standard)) }
        }
        #expect(await task.value == .other("CancellationError"))
    }
}

/// Deterministic generator so every run covers the same randomized corpus.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

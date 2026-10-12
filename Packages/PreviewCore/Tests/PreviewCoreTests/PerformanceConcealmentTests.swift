import Foundation
import Synchronization
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewCore

/// Decision 027, Q-43: the privacy filter builds the safe text in one forward, cancellable pass and returns
/// a native Swift string. These tests hold the result to the previous behaviour, byte for byte. A plain
/// `String ==` is canonical equivalence and would miss a normalization, so texts are compared scalar by
/// scalar, against `ReferencePrivacyFilter` (the verbatim pre-optimization filter) and against the mutable
/// string replacement the old code used, written out here. They add the shapes that made that loop
/// quadratic and the limits the new pass enforces. Nothing here waits on time.
@Suite("Linear concealment")
struct PerformanceConcealmentTests {
    /// What one filter run produced, with a compact description so a mismatch on a large text stays readable.
    private struct Exact: Equatable, CustomStringConvertible {
        let scalars: [UInt32]
        let count: Int
        let syntax: TextSyntax

        var description: String {
            "\(scalars.count) scalars, \(count) concealed, \(syntax), starting \(scalars.prefix(24).map { String($0, radix: 16) })"
        }
    }

    private enum Outcome: Equatable {
        case value(Exact)
        case failure(PreviewFailure)
        case other(String)

        init(_ body: () throws -> SafeText) {
            do {
                let safe = try body()
                self = .value(Exact(scalars: safe.text.unicodeScalars.map(\.value), count: safe.redactionCount, syntax: safe.syntax))
            } catch let failure as PreviewFailure {
                self = .failure(failure)
            } catch {
                self = .other(String(describing: type(of: error)))
            }
        }
    }

    private let optimized = DefaultPrivacyFilter()
    private let reference = ReferencePrivacyFilter()

    /// Roomy enough that a debug build on a loaded runner never trips the deadline on the large shapes.
    private static let generous = PreviewBudget(maxMilliseconds: 30_000)
    private static let token = SecretFieldPolicy.concealmentToken
    private static let hostingToken = "ghp_" + String(repeating: "a1", count: 18)
    private static let bearer = "Bearer abcdefgh12345678"
    private static let apiKey = "sk-" + String(repeating: "g7", count: 12)

    @discardableResult
    private func compare(_ document: ParsedTextDocument, label: String, budget: PreviewBudget? = nil,
                         sourceLocation: SourceLocation = #_sourceLocation) -> Outcome {
        let used = budget ?? Self.generous
        let actual = Outcome { try optimized.filter(document, context: RequestContext(budget: used)) }
        let expected = Outcome { try reference.filter(document, context: RequestContext(budget: used)) }
        #expect(actual == expected, "Linear concealment diverged from the reference for \(label)", sourceLocation: sourceLocation)
        return actual
    }

    private func isNative(_ text: String) -> Bool {
        text.utf8.withContiguousStorageIfAvailable { _ in true } ?? false
    }

    /// Whether `needle` occurs in `text` scalar for scalar. `String.contains` compares Characters, so a combining mark
    /// right after the last bullet of a token ("••••" then U+0301) makes it a different Character and hides the token.
    /// The filter works on code units, so its assertions must too.
    private func containsScalars(_ text: String, _ needle: String) -> Bool {
        let haystack = Array(text.unicodeScalars)
        let wanted = Array(needle.unicodeScalars)
        guard let first = wanted.first else { return true }
        guard haystack.count >= wanted.count else { return false }
        for start in 0...(haystack.count - wanted.count) where haystack[start] == first {
            if haystack[start..<(start + wanted.count)].elementsEqual(wanted) { return true }
        }
        return false
    }

    private func scalars(_ text: String) -> [UInt32] {
        text.unicodeScalars.map(\.value)
    }

    private func finding(_ kind: PreviewFindingKind, in safe: SafeText) -> PreviewFinding? {
        safe.findings.first { $0.kind == kind }
    }

    /// Finding counts sum to the redactions, and every finding line is a displayed line that holds a token:
    /// the inventory still points at the text this filter produced.
    private func expectFindingsMatchTheText(_ safe: SafeText, label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let total = safe.findings.reduce(0) { $0 + $1.count }
        #expect(total == safe.redactionCount, "Finding counts must sum to the redaction count for \(label)",
                sourceLocation: sourceLocation)
        let index = LogicalLines.starts(in: safe.text)
        let units = Array(safe.text.utf16)
        for found in safe.findings {
            for line in found.lines {
                guard line >= 1, line <= index.starts.count else {
                    Issue.record("Finding line \(line) is outside the \(index.starts.count) displayed lines for \(label)",
                                 sourceLocation: sourceLocation)
                    continue
                }
                let lower = index.starts[line - 1]
                let upper = line < index.starts.count ? index.starts[line] : index.utf16Length
                let displayed = String(decoding: units[lower..<upper], as: UTF16.self)
                #expect(containsScalars(displayed, Self.token), "Displayed line \(line) holds no concealment for \(label)",
                        sourceLocation: sourceLocation)
            }
        }
    }

    // MARK: The existing equivalence corpus, compared byte for byte

    /// The same corpus as `PrivacyFilterEquivalenceTests`, whose comparison is canonical equivalence.
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

    private static let edgeCases = [
        "", " ", "\n", "plain text only", "ghp_short", "gho_", "github_pat_", "sk-abc", "sk-", "eyJ", "eyJ.a.b",
        "AKIA1234", "ASIA", "-----BEGIN ", "-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----",
        "-----BEGIN RSA PRIVATE KEY-----\nbody without end", "task-aaaaaaaaaaaaaaaaaaaaa", "risk-bbbbbbbbbbbbbbbbbbbbbb",
        "bearer short", "Bearer", "baſic dGVzdDp0ZXN0MTIz", "BASIC dGVzdDp0ZXN0MTIz", "ßasic Kelvin K bearer aaaaaaaaaa",
        "password=synthetic-value", "PASSWORD : synthetic-value\nnext line", "\"api_key\" = 'synthetic'", "token=\"unterminated\nnext",
        "secret: {\n  nested: value\n}\nafter", "client_secret = '''\nmulti\nline'''\nafter",
        "a: 😀\nb: 日本語\nauth_token: \u{85}tail", "passwd:\r\nvalue\r\nmore", "name = value\nsafe: yes",
        "postgres://app:synthetic-password@db.example.invalid/prod", "ssh://git@host/repo", "redis://:synthetic@cache:6379/0"
    ]

    private static let fragments: [String] = credentials + [
        "ghp_", "sk-", "eyJ", "AKIA", "ASIA", "-----BEGIN ", "-----END PRIVATE KEY-----", "bearer ", "Basic ", "baſic ",
        "password", "Password", "api_key", "token", "secret", "name", "value", "key", "x", " ", "  ", "\t", ":", "=", ": ", " = ",
        "\"", "'", "\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}", "é", "e\u{301}", "日本語", "😀", "🌍", "𝒳", "K", "ß", "İ",
        "0123456789", "abcdefghijklmnop", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "-", "_", ".", "{", "}", "[", "]", ",", "\\", "://", "@"
    ]

    @Test func everyCredentialShapeInEveryTemplateMatchesTheReferenceByteForByte() {
        for credential in Self.credentials {
            for template in ["x %@ y", "%@", "key: %@\nnext", "😀日本語 %@ \u{2028} é\r\n"] {
                let text = template.replacingOccurrences(of: "%@", with: credential)
                guard case .value(let exact) = compare(ParsedTextDocument(text: text), label: text.debugDescription) else {
                    Issue.record("A credential template must filter without failing: \(text.debugDescription)")
                    continue
                }
                #expect(exact.count >= 1)
                #expect(!exact.scalars.isEmpty)
            }
        }
    }

    @Test func handwrittenEdgeCasesMatchTheReferenceInBothPrivacyModes() {
        for text in Self.edgeCases {
            compare(ParsedTextDocument(text: text), label: text.debugDescription)
            compare(ParsedTextDocument(text: text, usesStructuredPrivacy: true), label: text.debugDescription)
        }
    }

    @Test func randomizedDocumentsMatchTheReferenceByteForByte() {
        var generator = PerformanceSplitMix64(seed: 0x5EED_CAFE)
        for _ in 0..<400 {
            let text = Self.randomText(&generator, maximumFragments: 40)
            compare(ParsedTextDocument(text: text), label: text.debugDescription)
            compare(ParsedTextDocument(text: text, usesStructuredPrivacy: true), label: text.debugDescription)
        }
    }

    @Test func randomStructuredRangesOverlapAdjoinAndRepeatLikeTheReference() {
        var generator = PerformanceSplitMix64(seed: 0xC0FF_EE11)
        for _ in 0..<250 {
            let text = Self.randomText(&generator, maximumFragments: 30)
            // Every scalar boundary as a UTF-8 offset, so each generated range is valid for the document.
            var boundaries = [0]
            var offset = 0
            for scalar in text.unicodeScalars {
                offset += scalar.utf8.count
                boundaries.append(offset)
            }
            let rangeCount = Int(generator.next() % 12)
            var sensitive: [SensitiveRange] = []
            for _ in 0..<rangeCount {
                let first = boundaries[Int(generator.next() % UInt64(boundaries.count))]
                let second = boundaries[Int(generator.next() % UInt64(boundaries.count))]
                sensitive.append(SensitiveRange(utf8Range: min(first, second)..<max(first, second)))
            }
            let label = "\(text.debugDescription) \(sensitive.map(\.utf8Range))"
            compare(ParsedTextDocument(text: text, sensitiveRanges: sensitive, usesStructuredPrivacy: true), label: label)
            compare(ParsedTextDocument(text: text, sensitiveRanges: sensitive), label: label)
        }
    }

    // MARK: Adversarial shapes

    @Test func oneMegabyteWithoutAMatchIsTheSameTextAndMatchesTheReference() throws {
        let line = "lorem ipsum dolor sit amet, consectetur 日本語 adipiscing 🌍 elit\n"
        let text = String(repeating: line, count: 1_000_000 / line.utf8.count + 1)
        #expect(text.utf8.count >= 1_000_000)
        let document = ParsedTextDocument(text: text)
        let safe = try optimized.filter(document, context: RequestContext(budget: Self.generous))
        #expect(safe.redactionCount == 0)
        #expect(safe.findings.isEmpty)
        #expect(safe.text.unicodeScalars.elementsEqual(text.unicodeScalars))
        #expect(isNative(safe.text))
        compare(document, label: "one megabyte without a match")
    }

    @Test func tenThousandMatchesMatchTheReferenceAndAreAllConcealed() throws {
        let text = (0..<10_000).map { "password=value-\($0)\n" }.joined()
        let document = ParsedTextDocument(text: text)
        compare(document, label: "ten thousand assignments")
        let safe = try optimized.filter(document, context: RequestContext(budget: Self.generous))
        #expect(safe.redactionCount == 10_000)
        #expect(safe.text == String(repeating: "password=\(Self.token)\n", count: 10_000))
        let found = try #require(finding(.secretSensitiveField, in: safe))
        #expect(found.count == 10_000)
        #expect(found.lines == Array(1...PreviewFinding.maximumLines))
        #expect(safe.findings.count == 1)
        #expect(isNative(safe.text))
        expectFindingsMatchTheText(safe, label: "ten thousand assignments")
    }

    @Test func manyTokensOnOneLineAreConcealedSeparatelyAndKeepTheirSpaces() throws {
        // 400 tokens of 41 bytes each stay inside one line of the 32 KiB limit.
        let text = String(repeating: Self.hostingToken + " ", count: 400)
        let document = ParsedTextDocument(text: text)
        compare(document, label: "four hundred tokens on one line")
        let safe = try optimized.filter(document, context: RequestContext(budget: Self.generous))
        #expect(safe.redactionCount == 400)
        #expect(safe.text == String(repeating: Self.token + " ", count: 400))
        #expect(finding(.secretCodeHostingToken, in: safe)?.lines == [1])
        expectFindingsMatchTheText(safe, label: "four hundred tokens on one line")
    }

    @Test func overlappingAssignmentAndValueMatchesMergeIntoOneRangePerLine() throws {
        let line = "api_key = \(Self.bearer) \(Self.hostingToken) \(Self.apiKey)\n"
        let text = String(repeating: line, count: 300)
        let document = ParsedTextDocument(text: text)
        compare(document, label: "overlapping assignment and value matches")
        let safe = try optimized.filter(document, context: RequestContext(budget: Self.generous))
        #expect(safe.redactionCount == 300)
        // The most specific source among the merged parts names the range.
        #expect(safe.findings.map(\.kind) == [.secretCodeHostingToken])
        #expect(safe.findings.first?.count == 300)
        expectFindingsMatchTheText(safe, label: "overlapping assignment and value matches")
    }

    @Test(arguments: ["\r\n", "\r", "\n", "\u{85}", "\u{2028}", "\u{2029}"])
    func everyLineSeparatorKeepsTheSameConcealmentAndLines(separator: String) throws {
        let text = ["password=secret-value-one", "token: \(Self.hostingToken)", "plain=1"].joined(separator: separator)
        let document = ParsedTextDocument(text: text)
        compare(document, label: "separator \(separator.debugDescription)")
        let safe = try optimized.filter(document, context: RequestContext(budget: Self.generous))
        #expect(safe.text == ["password=\(Self.token)", "token:\(Self.token)", "plain=1"].joined(separator: separator))
        #expect(safe.redactionCount == 2)
        #expect(finding(.secretSensitiveField, in: safe)?.lines == [1])
        #expect(finding(.secretCodeHostingToken, in: safe)?.lines == [2])
        expectFindingsMatchTheText(safe, label: "separator \(separator.debugDescription)")
    }

    @Test func combiningMarksAndSupplementaryCharactersAroundRangesAreKeptExactly() {
        // A range may end between a base character and its combining mark; the scalars after it must survive unchanged.
        let texts = [
            "password=e\u{301}\u{301}x\nafter",
            "password=a\u{301}",
            "Bearer abcdefgh12345678\u{301} tail",
            "token: \(Self.hostingToken)\u{301} tail",
            "😀password=😀🌍\u{301}\n🌍next",
            "e\u{301}\(Self.hostingToken)e\u{301}",
            "k\u{301}ey: \(Self.apiKey)\u{200D}\u{FE0F}",
            "password=ab\u{2028}cd\nnext",
            "\u{FEFF}api_key=\(Self.hostingToken)\u{FEFF}",
            "𝒳 \(Self.bearer) 𝒳 \(Self.apiKey) 𝒳"
        ]
        for text in texts {
            compare(ParsedTextDocument(text: text), label: text.debugDescription)
            compare(ParsedTextDocument(text: text, usesStructuredPrivacy: true), label: text.debugDescription)
        }
    }

    @Test func aMultilinePrivateKeyCollapsesToOneTokenAndFindingsStayOnTheDisplayedLine() throws {
        let key = "-----BEGIN PRIVATE KEY-----\nc3ludGhldGljLWJvZHk=\nc3ludGhldGljLW1vcmU=\n-----END PRIVATE KEY-----"
        let text = "first\n\(key)\nmiddle\nid AKIAABCDEFGHIJKLMNOP\nlast"
        let document = ParsedTextDocument(text: text)
        compare(document, label: "multiline private key")
        let safe = try optimized.filter(document, context: RequestContext(budget: Self.generous))
        #expect(safe.text == "first\n\(Self.token)\nmiddle\nid \(Self.token)\nlast")
        #expect(finding(.secretPrivateKey, in: safe)?.lines == [2])
        #expect(finding(.secretCloudAccessKey, in: safe)?.lines == [4])
        expectFindingsMatchTheText(safe, label: "multiline private key")
    }

    @Test func fortyThousandTokensInAboutAMegabyteFinishAndAreAllConcealed() throws {
        // Past the default node budget, so the budget is raised: this is the linear pass at scale, not the cap.
        let budget = PreviewBudget(maxJSONNodes: 100_000, maxMilliseconds: 30_000)
        let text = (0..<40_000).map { "ghp_aaaaaaaaaaaaaaaaaaaa\($0)\n" }.joined()
        #expect(text.utf8.count > 1_000_000)
        let safe = try optimized.filter(ParsedTextDocument(text: text), context: RequestContext(budget: budget))
        #expect(safe.redactionCount == 40_000)
        #expect(safe.text == String(repeating: Self.token + "\n", count: 40_000))
        let found = try #require(finding(.secretCodeHostingToken, in: safe))
        #expect(found.count == 40_000)
        #expect(found.lines == Array(1...PreviewFinding.maximumLines))
        #expect(isNative(safe.text))
    }

    // MARK: The filter's own matches are limited by the node budget

    @Test func matchesWithinTheNodeBudgetAreConcealedLikeTheReference() throws {
        let budget = PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)
        let text = (0..<50).map { "password=v\($0)\n" }.joined()
        let document = ParsedTextDocument(text: text)
        compare(document, label: "exactly the node budget", budget: budget)
        let safe = try optimized.filter(document, context: RequestContext(budget: budget))
        #expect(safe.redactionCount == 50)
        #expect(safe.text == String(repeating: "password=\(Self.token)\n", count: 50))
    }

    @Test func assignmentsBeyondTheNodeBudgetConcealTheWholeText() throws {
        let budget = PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)
        let text = (0..<51).map { "password=v\($0)\nplain=\($0)\n" }.joined()
        let safe = try optimized.filter(ParsedTextDocument(text: text), context: RequestContext(budget: budget))
        #expect(safe.text == Self.token)
        #expect(safe.redactionCount == 1)
        #expect(safe.findings == [PreviewFinding(kind: .secretSensitiveField, count: 1, lines: [1])])
        #expect(isNative(safe.text))
    }

    @Test func valueMatchesBeyondTheNodeBudgetConcealTheWholeTextInStructuredDocumentsToo() throws {
        let budget = PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)
        let text = (0..<51).map { "id-\($0) " + Self.hostingToken + "\n" }.joined()
        let safe = try optimized.filter(ParsedTextDocument(text: text, usesStructuredPrivacy: true),
                                        context: RequestContext(budget: budget))
        #expect(safe.text == Self.token)
        #expect(safe.redactionCount == 1)
        #expect(safe.findings == [PreviewFinding(kind: .secretSensitiveField, count: 1, lines: [1])])
    }

    @Test func assignmentsAndValuesAreCountedTogetherAgainstTheNodeBudget() throws {
        let budget = PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)
        let assignments = (0..<30).map { "password=v\($0)\n" }.joined()
        let tokens = (0..<30).map { "\(Self.hostingToken)\($0)\n" }.joined()
        let safe = try optimized.filter(ParsedTextDocument(text: assignments + tokens), context: RequestContext(budget: budget))
        #expect(safe.text == Self.token)
        #expect(safe.redactionCount == 1)
    }

    @Test func anAdaptersRangesAreNotCountedAgainstTheFiltersOwnLimit() throws {
        // Fifty adapter ranges (the most the budget accepts) plus fifty of the filter's own: both stay exact.
        let budget = PreviewBudget(maxJSONNodes: 50, maxMilliseconds: 30_000)
        let text = (0..<50).map { "item\($0) password=v\($0)\n" }.joined()
        var sensitive: [SensitiveRange] = []
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(50) {
            sensitive.append(SensitiveRange(utf8Range: offset..<(offset + 5)))
            offset += line.utf8.count + 1
        }
        let document = ParsedTextDocument(text: text, sensitiveRanges: sensitive)
        compare(document, label: "adapter ranges plus own matches", budget: budget)
        let safe = try optimized.filter(document, context: RequestContext(budget: budget))
        #expect(safe.redactionCount == 100)
    }

    // MARK: Native result

    @Test func theSafeTextIsANativeStringWhetherOrNotAnythingWasConcealed() throws {
        for text in ["", "no secrets here", "password=synthetic é 😀", "a \(Self.hostingToken) b \(Self.bearer) c"] {
            let safe = try optimized.filter(ParsedTextDocument(text: text), context: RequestContext(budget: .standard))
            #expect(isNative(safe.text), "Safe text must have contiguous UTF-8 for \(text.debugDescription)")
        }
    }

    @Test func findingsPointAtTheDisplayedLinesOfTheTextTheFilterProduced() throws {
        var generator = PerformanceSplitMix64(seed: 0xF1ED_1AB5)
        for _ in 0..<200 {
            let text = Self.randomText(&generator, maximumFragments: 40)
            let safe = try optimized.filter(ParsedTextDocument(text: text), context: RequestContext(budget: Self.generous))
            expectFindingsMatchTheText(safe, label: text.debugDescription)
        }
    }

    // MARK: The forward pass itself

    @Test func theForwardPassMatchesReverseReplacementInAMutableString() throws {
        var generator = PerformanceSplitMix64(seed: 0xBAD_C0DE)
        let context = RequestContext(budget: Self.generous)
        for _ in 0..<400 {
            let text = Self.randomText(&generator, maximumFragments: 30)
            let units = Array(text.utf16)
            // Scalar boundaries in UTF-16 units; sorted cuts pair up into ascending ranges that may touch or be empty.
            var boundaries = [0]
            var unit = 0
            for scalar in text.unicodeScalars {
                unit += scalar.utf16.count
                boundaries.append(unit)
            }
            let pairs = Int(generator.next() % 10)
            var cuts: [Int] = []
            for _ in 0..<(pairs * 2) { cuts.append(boundaries[Int(generator.next() % UInt64(boundaries.count))]) }
            cuts.sort()
            var ranges: [NSRange] = []
            for pair in 0..<pairs { ranges.append(NSRange(location: cuts[pair * 2], length: cuts[pair * 2 + 1] - cuts[pair * 2])) }
            let legacy = NSMutableString(string: text)
            for range in ranges.reversed() { legacy.replaceCharacters(in: range, with: Self.token) }
            let forward = try DefaultPrivacyFilter.concealed(units, ranges: ranges, context: context)
            let expected = legacy as String
            #expect(scalars(forward) == scalars(expected), "Forward pass diverged for \(text.debugDescription) \(ranges)")
            #expect(isNative(forward))
        }
    }

    @Test func noRangesLeaveTheTextUnchanged() throws {
        let text = "unchanged é 😀\r\n"
        let result = try DefaultPrivacyFilter.concealed(Array(text.utf16), ranges: [], context: RequestContext(budget: .standard))
        #expect(scalars(result) == scalars(text))
    }

    @Test func rangesThatBreakTheContractAreRejectedInsteadOfTrapping() {
        let units = Array("abcdef".utf16)
        let context = RequestContext(budget: .standard)
        let broken: [[NSRange]] = [
            [NSRange(location: 4, length: 5)],
            [NSRange(location: 3, length: 1), NSRange(location: 1, length: 1)],
            [NSRange(location: 1, length: 3), NSRange(location: 2, length: 1)],
            [NSRange(location: -1, length: 2)]
        ]
        for ranges in broken {
            #expect(throws: PreviewFailure.malformedDocument) {
                try DefaultPrivacyFilter.concealed(units, ranges: ranges, context: context)
            }
        }
    }

    @Test func theForwardPassChecksCancellationOncePerBatchOfRanges() throws {
        let units = Array(String(repeating: "abc", count: 10_000).utf16)
        let ranges = (0..<10_000).map { NSRange(location: $0 * 3, length: 1) }
        let seen = PerformanceTally()
        var context = RequestContext(budget: Self.generous)
        context.checkpointObserver = { seen.increment() }
        _ = try DefaultPrivacyFilter.concealed(units, ranges: ranges, context: context)
        // One check at ranges 0, 256, 512 ... and one at the end: 40 + 1 for 10,000 ranges, never one per range.
        #expect((39...45).contains(seen.value), "Checkpoints: \(seen.value)")
    }

    @Test func cancellationAtAnInnerCheckpointStopsTheForwardPass() async {
        let units = Array(String(repeating: "abc", count: 10_000).utf16)
        let ranges = (0..<10_000).map { NSRange(location: $0 * 3, length: 1) }
        let seen = PerformanceTally()
        var context = RequestContext(budget: Self.generous)
        context.checkpointObserver = {
            seen.increment()
            if seen.value == 3 { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let cancelling = context
        let task = Task.detached {
            do {
                _ = try DefaultPrivacyFilter.concealed(units, ranges: ranges, context: cancelling)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        #expect(await task.value, "The pass completed despite cancellation")
        // Entry (range 0), range 256 and range 512: it stops at the third and goes no further.
        #expect(seen.value == 3)
    }

    @Test func aDocumentCancelledBeforeAnyWorkReportsCancellation() async {
        let text = (0..<2_000).map { "password=v\($0)\n" }.joined()
        let document = ParsedTextDocument(text: text)
        let task = Task.detached { [optimized] in
            withUnsafeCurrentTask { $0?.cancel() }
            return Outcome { try optimized.filter(document, context: RequestContext(budget: .standard)) }
        }
        #expect(await task.value == .other("CancellationError"))
    }

    // MARK: Through the pipeline

    @Test func aFileOfTenThousandSecretsPreviewsInOneRequestWithNativeText() async {
        struct MemoryReader: PreviewFileReading {
            let data: Data
            func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
        }
        let text = (0..<10_000).map { "password=synthetic-value-\($0)\n" }.joined()
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations, reader: MemoryReader(data: Data(text.utf8)))
        let outcome = await pipeline.preview(url: URL(fileURLWithPath: "/unused/dense.txt"), budget: Self.generous)
        guard case .ready(let presentation) = outcome else { Issue.record("Expected a ready preview: \(outcome)"); return }
        #expect(presentation.redactionCount == 10_000)
        #expect(!containsScalars(presentation.text, "synthetic-value"))
        let sensitive = presentation.findings.first { $0.kind == .secretSensitiveField }
        #expect(sensitive?.count == 10_000)
        #expect(isNative(presentation.text))
    }

    // MARK: Support

    private static func randomText(_ generator: inout PerformanceSplitMix64, maximumFragments: Int) -> String {
        let count = Int(generator.next() % UInt64(maximumFragments))
        var text = ""
        for _ in 0..<count { text += fragments[Int(generator.next() % UInt64(fragments.count))] }
        return text
    }
}

/// A counter that any thread may read, as a checkpoint observer needs.
private final class PerformanceTally: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

/// Deterministic generator so every run covers the same randomized corpus.
private struct PerformanceSplitMix64 {
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

import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct BytesReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes { FileBytes(data: data) }
}

/// What the privacy stage reports about concealed secrets: kinds, counts and displayed lines, never values.
@Suite("Secret inventory")
struct SecretInventoryTests {
    private static let cloudKey = "AKIAABCDEFGHIJKLMNOP"
    private static let hostingToken = "ghp_" + String(repeating: "a1", count: 18)
    private static let apiKey = "sk-" + String(repeating: "g7", count: 12)
    private static let webToken = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJzeW50aGV0aWMifQ.c3ludGhldGljLXNpZw"
    private static let bearer = "Bearer abcdefgh12345678"
    private static let privateKey = "-----BEGIN PRIVATE KEY-----\nc3ludGhldGljLWJvZHk=\nc3ludGhldGljLW1vcmU=\n-----END PRIVATE KEY-----"

    private let filter = DefaultPrivacyFilter()

    private func safeText(_ text: String, structured: Bool = false, ranges: [SensitiveRange] = []) throws -> SafeText {
        try filter.filter(ParsedTextDocument(text: text, sensitiveRanges: ranges, usesStructuredPrivacy: structured),
                          context: RequestContext(budget: .standard))
    }

    private func finding(_ kind: PreviewFindingKind, in safe: SafeText) -> PreviewFinding? {
        safe.findings.first { $0.kind == kind }
    }

    @Test func eachKindIsReportedWithItsDisplayedLine() throws {
        let text = [
            "# synthetic fixture",
            "region us-east-1 id \(Self.cloudKey)",
            "note \(Self.hostingToken)",
            "service \(Self.apiKey)",
            "jwt \(Self.webToken)",
            "curl \(Self.bearer)",
            "password: synthetic-field-value",
            Self.privateKey,
            "tail"
        ].joined(separator: "\n")
        let safe = try safeText(text)
        #expect(safe.redactionCount == 7)
        #expect(safe.findings.map(\.kind) == [.secretPrivateKey, .secretCloudAccessKey, .secretCodeHostingToken, .secretAPIKey,
                                              .secretWebToken, .secretAuthorizationHeader, .secretSensitiveField])
        // The key spans four source lines but collapses to one displayed line, so "tail" is line 9.
        #expect(finding(.secretCloudAccessKey, in: safe)?.lines == [2])
        #expect(finding(.secretCodeHostingToken, in: safe)?.lines == [3])
        #expect(finding(.secretAPIKey, in: safe)?.lines == [4])
        #expect(finding(.secretWebToken, in: safe)?.lines == [5])
        #expect(finding(.secretAuthorizationHeader, in: safe)?.lines == [6])
        #expect(finding(.secretSensitiveField, in: safe)?.lines == [7])
        #expect(finding(.secretPrivateKey, in: safe)?.lines == [8])
        #expect(safe.findings.allSatisfy { $0.count == 1 })
        #expect(safe.findings.map(\.severity) == Array(repeating: .info, count: 7))
        #expect(safe.text.split(separator: "\n", omittingEmptySubsequences: false).last == "tail")
        #expect(LogicalLines.starts(in: safe.text).starts.count == 9)
    }

    @Test(arguments: [
        ("api_key = \(apiKey)", PreviewFindingKind.secretAPIKey),
        ("token: \(cloudKey)", .secretCloudAccessKey),
        ("password = \(hostingToken)", .secretCodeHostingToken),
        ("Authorization: \(bearer)", .secretAuthorizationHeader),
        ("Authorization: Bearer \(webToken)", .secretWebToken),
        ("credential \(bearer)", .secretAuthorizationHeader),
        ("private_key = \"\(privateKey)\"", .secretPrivateKey),
        ("-----BEGIN PRIVATE KEY-----\npassword: synthetic-field-value\n-----END PRIVATE KEY-----", .secretPrivateKey),
        ("-----BEGIN RSA PRIVATE KEY-----\npassword: synthetic-field-value\nunterminated", .secretPrivateKey),
        ("password: synthetic-field-value", .secretSensitiveField)
    ])
    func overlappingConcealmentsTakeTheMostSpecificKind(text: String, expected: PreviewFindingKind) throws {
        let safe = try safeText(text)
        #expect(safe.findings.map(\.kind) == [expected], "\(safe.findings)")
        #expect(safe.findings.first?.count == safe.redactionCount)
    }

    @Test func aMultilinePrivateKeyCollapsesLinesAndLaterSecretsFollowTheCollapse() throws {
        let text = "first\n\(Self.privateKey)\nmiddle\nid \(Self.cloudKey)\nlast"
        let safe = try safeText(text)
        #expect(safe.text == "first\n••••\nmiddle\nid ••••\nlast")
        #expect(finding(.secretPrivateKey, in: safe)?.lines == [2])
        #expect(finding(.secretCloudAccessKey, in: safe)?.lines == [4])
        // The cloud key is on source line 8 but displayed line 4, the line the gutter shows for it.
        #expect(LogicalLines.lineNumbers(forUTF16Offsets: [(safe.text as NSString).range(of: "id ••••").location + 3],
                                         in: safe.text) == [4])
    }

    @Test func severalConcealmentsOnOneLineCountSeparatelyButShareTheLine() throws {
        let text = "a \(Self.cloudKey) b \(Self.cloudKey)\nc \(Self.cloudKey)"
        let safe = try safeText(text)
        #expect(safe.findings.count == 1)
        #expect(safe.findings.first?.count == 3)
        #expect(safe.findings.first?.lines == [1, 2])
    }

    @Test(arguments: ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"])
    func lineSeparatorsCountLikeTheGutter(separator: String) throws {
        let text = ["first", "x \(Self.cloudKey)", "", "y \(Self.hostingToken)", "end"].joined(separator: separator)
        let safe = try safeText(text)
        #expect(finding(.secretCloudAccessKey, in: safe)?.lines == [2])
        #expect(finding(.secretCodeHostingToken, in: safe)?.lines == [4])
        // Same offsets the gutter would number from the displayed text.
        let displayed = safe.text as NSString
        var offsets: [Int] = []
        var found = displayed.range(of: "••••")
        while found.location != NSNotFound {
            offsets.append(found.location)
            let next = NSMaxRange(found)
            found = displayed.range(of: "••••", options: [], range: NSRange(location: next, length: displayed.length - next))
        }
        #expect(LogicalLines.lineNumbers(forUTF16Offsets: offsets, in: safe.text) == [2, 4])
    }

    @Test func linesCountUTF16UnitsInsideSupplementaryAndCombiningText() throws {
        let text = "😀😀 日本語 e\u{301}\n😀 id \(Self.cloudKey) 🌍\n\u{2028}key: \(Self.apiKey)"
        let safe = try safeText(text)
        #expect(finding(.secretCloudAccessKey, in: safe)?.lines == [2])
        #expect(finding(.secretSensitiveField, in: safe) == nil)
        #expect(finding(.secretAPIKey, in: safe)?.lines == [4])
    }

    @Test func findingsKeepTheFirstSixtyFourLinesAndStillCountEveryOccurrence() throws {
        let text = (0..<200).map { "line \($0) \(Self.cloudKey)" }.joined(separator: "\n")
        let safe = try safeText(text)
        let found = try #require(finding(.secretCloudAccessKey, in: safe))
        #expect(found.count == 200)
        #expect(found.lines == Array(1...PreviewFinding.maximumLines))
        #expect(safe.redactionCount == 200)
    }

    @Test func plainTextAndEmptyDocumentsReportNothing() throws {
        for text in ["", "no secrets here\nat all", "token without separator", "ghp_short sk-abc eyJ.a.b AKIA1234"] {
            let safe = try safeText(text)
            #expect(safe.redactionCount == 0)
            #expect(safe.findings.isEmpty)
        }
        #expect(try safeText("{\"name\":\"safe\"}", structured: true).findings.isEmpty)
    }

    @Test func structuredRangesAreSensitiveFieldsUnlessAValuePatternRefinesThem() async throws {
        let source = #"{"password":"synthetic-field-value","aws":"\#(Self.cloudKey)","access_key":"\#(Self.cloudKey)","name":"visible"}"#
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: BytesReader(data: Data(source.utf8)))
        guard case .ready(let presentation) = await pipeline.preview(url: URL(fileURLWithPath: "/unused/config.json")) else {
            Issue.record("expected a ready JSON presentation")
            return
        }
        #expect(!presentation.text.contains("synthetic-field-value"))
        #expect(!presentation.text.contains(Self.cloudKey))
        // "password" is a structured range only; "aws" is concealed by the value pattern alone; "access_key"
        // is both, and merges into a cloud key.
        let kinds = presentation.findings.map(\.kind)
        #expect(kinds == [.secretCloudAccessKey, .secretSensitiveField])
        #expect(presentation.findings.map(\.count) == [2, 1])
        #expect(presentation.findings.reduce(0) { $0 + $1.count } == presentation.redactionCount)
        let expectedLines = replacementLines(in: presentation.text)
        let reported = Set(presentation.findings.flatMap(\.lines))
        #expect(reported == Set(expectedLines))
        #expect(!reported.isEmpty)
    }

    @Test func structuredRangesWithoutValuePatternsAreSensitiveFields() throws {
        let text = "{\n  \"token\": \"synthetic-a\",\n  \"keep\": 1,\n  \"password\": \"synthetic-b\"\n}"
        let ranges = ["synthetic-a", "synthetic-b"].map { value -> SensitiveRange in
            let start = text.range(of: "\"\(value)\"")!
            return SensitiveRange(utf8Range: text.utf8.distance(from: text.startIndex, to: start.lowerBound)
                                  ..< text.utf8.distance(from: text.startIndex, to: start.upperBound))
        }
        let safe = try safeText(text, structured: true, ranges: ranges)
        #expect(safe.findings.map(\.kind) == [.secretSensitiveField])
        #expect(safe.findings.first?.count == 2)
        #expect(safe.findings.first?.lines == [2, 4])
    }

    @Test func countsAlwaysSumToTheRedactionCountAndEveryLineHoldsAReplacement() throws {
        var generator = SplitMix64(seed: 0x1BAD_5EED)
        let fragments: [String] = [
            Self.cloudKey, Self.hostingToken, Self.apiKey, Self.webToken, Self.bearer, Self.privateKey,
            "password", "token", "api_key", "secret", ":", "=", ": ", " = ", "\"", "'", "\n", "\r\n", "\r", "\u{85}", "\u{2028}",
            "x", " ", "é", "e\u{301}", "日本語", "😀", "-----BEGIN ", "-----END PRIVATE KEY-----", "AKIA", "ghp_", "eyJ", "sk-"
        ]
        for _ in 0..<500 {
            var text = ""
            for _ in 0..<Int(generator.next() % 40) { text += fragments[Int(generator.next() % UInt64(fragments.count))] }
            for structured in [false, true] {
                let safe = try safeText(text, structured: structured)
                #expect(safe.findings.reduce(0) { $0 + $1.count } == safe.redactionCount, "\(text.debugDescription)")
                #expect(safe.findings.allSatisfy { $0.count >= 1 && !$0.lines.isEmpty && $0.lines == $0.lines.sorted() })
                #expect(Set(safe.findings.map(\.kind)).count == safe.findings.count)
                let occupied = LogicalLines.starts(in: safe.text)
                let holders = Set(safe.findings.flatMap(\.lines))
                // Every reported line exists and shows a replacement; with few occurrences the lines are exactly those.
                #expect(holders.allSatisfy { (1...occupied.starts.count).contains($0) })
                #expect(holders == Set(replacementLines(in: safe.text)), "\(text.debugDescription)")
            }
        }
    }

    /// Displayed lines holding a replacement, counted by the gutter's own definition of a line.
    private func replacementLines(in text: String) -> [Int] {
        let nsText = text as NSString
        let starts = LogicalLines.starts(in: text)
        return starts.starts.indices.compactMap { index in
            let end = index + 1 < starts.starts.count ? starts.starts[index + 1] : starts.utf16Length
            // A literal code-unit search: a combining mark after a replacement must not hide it from String.contains.
            return nsText.range(of: "••••", options: .literal,
                                range: NSRange(location: starts.starts[index], length: end - starts.starts[index])).location != NSNotFound
                ? index + 1 : nil
        }
    }

    @Test func findingsNeverCarryKeyNamesPatternsOrValues() throws {
        let text = "password: synthetic-field-value\naws \(Self.cloudKey)\n\(Self.privateKey)\ntoken \(Self.webToken)"
        let description = String(describing: try safeText(text).findings)
        for forbidden in ["password", "synthetic", "AKIA", "BEGIN", "PRIVATE", "eyJ", "c3ludGhldGlj", "token"] {
            #expect(!description.contains(forbidden), "\(forbidden)")
        }
    }

    @Test func cancellationAndDeadlineStillInterruptDocumentsThatConcealSecrets() async {
        let text = (0..<2_000).map { "line \($0) \(Self.cloudKey)" }.joined(separator: "\n")
        let document = ParsedTextDocument(text: text)
        let task = Task.detached { [filter] in
            withUnsafeCurrentTask { $0?.cancel() }
            return Result { try filter.filter(document, context: RequestContext(budget: .standard)) }
        }
        let cancelled = await task.value
        #expect(throws: CancellationError.self) { try cancelled.get() }
        #expect(throws: PreviewFailure.deadlineExceeded) {
            try filter.filter(document, context: RequestContext(budget: PreviewBudget(maxMilliseconds: 0)))
        }
        #expect(throws: PreviewFailure.outputTooLarge) {
            try filter.filter(ParsedTextDocument(text: text), context: RequestContext(budget: PreviewBudget(maxOutputUTF8Bytes: 100)))
        }
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

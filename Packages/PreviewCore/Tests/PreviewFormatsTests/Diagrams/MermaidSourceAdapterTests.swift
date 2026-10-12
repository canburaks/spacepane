import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Mermaid source adapter")
struct MermaidSourceAdapterTests {
    private let secret = "synthetic-secret-value"

    private func parse(_ source: String, budget: PreviewBudget = .standard) throws -> ParsedTextDocument {
        try MermaidSourceAdapter().parse(DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count),
                                         context: RequestContext(budget: budget))
    }

    /// The text with every recorded range replaced the way the shared privacy filter does.
    private func concealed(_ source: String) throws -> String {
        let document = try parse(source)
        var bytes = Array(document.text.utf8)
        for range in document.sensitiveRanges.sorted(by: { $0.utf8Range.lowerBound > $1.utf8Range.lowerBound }) {
            bytes.replaceSubrange(range.utf8Range, with: Array("••••".utf8))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    @Test func sourcePassesThroughUnchangedWithStructuredPrivacy() throws {
        let source = "flowchart TD\n    A[Start] --> B{Choice}\n%% a comment\n"
        let document = try parse(source)
        #expect(document.text == source)
        #expect(document.syntax == .mermaid)
        #expect(document.usesStructuredPrivacy)
        #expect(document.sensitiveRanges.isEmpty)
        #expect(document.images.isEmpty)
    }

    // MARK: Concealment keeps the diagram's structure

    @Test(arguments: [
        ("A[Token: JWT] --> B", "A[Token: ••••] --> B"),
        ("A[\"password = SECRET\"] --> B", "A[\"password = ••••\"] --> B"),
        ("A -->|secret: SECRET| B", "A -->|secret: ••••| B"),
        ("A((client_secret: SECRET)) --> B", "A((client_secret: ••••)) --> B"),
        ("A([api_key: SECRET]) --> B", "A([api_key: ••••]) --> B"),
        ("A{{Access Key: SECRET}} --> B", "A{{Access Key: ••••}} --> B"),
        ("A[Status: fine] --> B", "A[Status: fine] --> B"),
        ("A[Token count 5] --> B", "A[Token count 5] --> B"),
        ("A[<b>Password</b>: SECRET<br/>next] --> B", "A[<b>Password</b>: ••••<br/>next] --> B")
    ])
    func labelValuesAreConcealedUpToTheEndOfTheLabel(source: String, expected: String) throws {
        let output = try concealed("flowchart TD\n" + source.replacingOccurrences(of: "SECRET", with: secret))
        #expect(output == "flowchart TD\n" + expected)
        #expect(!output.contains(secret))
    }

    @Test(arguments: [
        "sequenceDiagram\nAlice->>Bob: password: SECRET",
        "sequenceDiagram\nNote over Alice: token = SECRET",
        "flowchart TD\n%% password=SECRET",
        "flowchart TD\n%%{init: {\"apiKey\": \"SECRET\"}}%%\nA --> B",
        "stateDiagram-v2\nS1 : secret: SECRET",
        "pie title token: SECRET\n\"A\" : 1",
        "flowchart TD\nA --> B\n%% Authorization: Bearer SECRET"
    ])
    func valuesOutsideLabelsAreConcealedThroughTheEndOfTheLine(template: String) throws {
        let source = template.replacingOccurrences(of: "SECRET", with: secret)
        let output = try concealed(source)
        #expect(!output.contains(secret))
        #expect(output.contains("••••"))
    }

    @Test func frontMatterSecretsConcealNestedValues() throws {
        let source = "---\ntitle: Example\nconfig:\n  password:\n    nested: \(secret)\n  theme: dark\n---\nflowchart TD\nA --> B\n"
        let output = try concealed(source)
        #expect(!output.contains(secret))
        #expect(output.contains("title: Example"))
        #expect(output.hasPrefix("---\ntitle: Example\nconfig:\n  password:"))
    }

    @Test func multilineValuesConcealTheRestOfTheFile() throws {
        let source = "flowchart TD\n%% password: {\nA --> \(secret)\n"
        #expect(!(try concealed(source)).contains(secret))
        let quoted = "sequenceDiagram\nA->>B: token: \"opens here\nand continues \(secret)\n"
        #expect(!(try concealed(quoted)).contains(secret))
    }

    @Test func unicodeValuesAreCutAtScalarBoundaries() throws {
        let output = try concealed("flowchart TD\nA[Token: 日本語-значение-😀] --> B[Ünï 😀]")
        #expect(output == "flowchart TD\nA[Token: ••••] --> B[Ünï 😀]")
        let crlf = try concealed("flowchart TD\r\nA[Token: \(secret)] --> B\r\nB --> C\r\n")
        #expect(crlf == "flowchart TD\r\nA[Token: ••••] --> B\r\nB --> C\r\n")
    }

    @Test func rangesAreSortedDisjointAndInsideTheText() throws {
        var lines = ["flowchart TD"]
        for index in 0..<200 { lines.append("N\(index)[token: \(secret)\(index)] --> N\(index + 1)[ok]") }
        let document = try parse(lines.joined(separator: "\n"))
        #expect(document.sensitiveRanges.count == 200)
        let ranges = document.sensitiveRanges.map(\.utf8Range)
        #expect(ranges == ranges.sorted { $0.lowerBound < $1.lowerBound })
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound <= b.lowerBound) }
        #expect(ranges.allSatisfy { $0.upperBound <= document.text.utf8.count })
    }

    // MARK: Bounds, cancellation and limits

    @Test func lineAndInputBudgetsAreEnforcedBeforeParsing() {
        #expect(throws: PreviewFailure.tooManyLines) { try parse(String(repeating: "A --> B\n", count: 50), budget: PreviewBudget(maxTextLines: 10)) }
        #expect(throws: PreviewFailure.lineTooLong) { try parse("A[" + String(repeating: "x", count: 100) + "]", budget: PreviewBudget(maxLineUTF8Bytes: 50)) }
        #expect(throws: PreviewFailure.inputTooLarge) { try parse(String(repeating: "x", count: 100), budget: PreviewBudget(maxInputBytes: 50)) }
        #expect(throws: PreviewFailure.outputTooLarge) { try parse(String(repeating: "x", count: 100), budget: PreviewBudget(maxInputBytes: 200, maxOutputUTF8Bytes: 50)) }
    }

    @Test func cancellationAndExpiredDeadlinesComeFirst() async {
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try MermaidSourceAdapter().parse(DecodedText(text: "flowchart TD\nA --> B", encoding: .utf8, byteCount: 20),
                                                 context: RequestContext(budget: .standard))
            }
        }
        await task.value
        #expect(throws: PreviewFailure.deadlineExceeded) { try parse("flowchart TD\nA --> B", budget: PreviewBudget(maxMilliseconds: 0)) }
    }

    @Test func binaryLookingAndEmptyTextAreAccepted() throws {
        #expect(try parse("").text.isEmpty)
        #expect(try parse("\u{0}\u{1}not a diagram").syntax == .mermaid)
    }
}

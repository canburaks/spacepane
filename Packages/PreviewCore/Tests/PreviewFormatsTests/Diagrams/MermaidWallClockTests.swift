import Foundation
import Testing
import PreviewContracts
import PreviewFormats

/// This existing real-deadline probe runs in the isolated wall-clock pass. Parallel CPU-heavy
/// package tests must not spend the parser's production deadline before it can make progress.
@Suite("Mermaid source real-deadline probe", .serialized)
struct MermaidWallClockTests {
    @Test func aLargeFileIsScannedInBoundedTime() throws {
        var lines = ["flowchart LR"]
        for index in 0..<12_000 { lines.append("N\(index)[Label \(index): value] --> N\(index + 1)") }
        let started = ContinuousClock.now
        let source = lines.joined(separator: "\n")
        let document = try MermaidSourceAdapter().parse(
            DecodedText(text: source, encoding: .utf8, byteCount: source.utf8.count),
            context: RequestContext(budget: .standard))
        #expect(document.sensitiveRanges.isEmpty)
        #expect(started.duration(to: .now) < .seconds(10))
    }
}

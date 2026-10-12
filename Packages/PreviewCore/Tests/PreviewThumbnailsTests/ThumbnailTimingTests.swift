import Foundation
import SQLite3
import Testing
import PreviewContracts
import PreviewFormats
@testable import PreviewThumbnails

/// Records end-to-end request times on the machine running the suite. Absolute numbers are only
/// meaningful from a Release build (`swift test -c release`), so the default run asserts nothing
/// about speed and prints only when THUMBNAIL_TIMINGS is set.
@Suite("Thumbnail timings")
struct ThumbnailTimingTests {
    private func text(bytes target: Int, line: (Int) -> String) -> String {
        var result = ""
        var index = 0
        while result.utf8.count < target { result += line(index) + "\n"; index += 1 }
        return result
    }

    @Test func recordRequestTimesAtTheInputBudget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = 250_000
        let database = fixture.directory.appendingPathComponent("big.sqlite")
        var handle: OpaquePointer?
        #expect(sqlite3_open(database.path, &handle) == SQLITE_OK)
        sqlite3_exec(handle, "CREATE TABLE t(id INTEGER, name TEXT, body TEXT);", nil, nil, nil)
        sqlite3_exec(handle, "BEGIN;", nil, nil, nil)
        for index in 0..<4_000 {
            sqlite3_exec(handle, "INSERT INTO t VALUES (\(index), 'name\(index)', '\(String(repeating: "x", count: 200))');", nil, nil, nil)
        }
        sqlite3_exec(handle, "COMMIT;", nil, nil, nil)
        sqlite3_close(handle)
        let files: [(String, URL)] = [
            ("250 KB plain text", try fixture.file("big.txt", text(bytes: target) { "Paragraph \($0) with a sentence of ordinary prose that wraps." })),
            ("250 KB source", try fixture.file("big.swift", text(bytes: target) { "func value\($0)(argument: Int) -> Int { return argument + \($0) } // note" })),
            ("250 KB pretty JSON", try fixture.file("big.json", "[" + (0..<4_000).map { "\n  {\"id\": \($0), \"name\": \"item \($0)\", \"tags\": [\"a\", \"b\"]}" }.joined(separator: ",") + "\n]")),
            ("250 KB minified JSON", try fixture.file("min.json", "[" + (0..<4_500).map { "{\"id\":\($0),\"name\":\"item \($0)\",\"tags\":[\"a\",\"b\"]}" }.joined(separator: ",") + "]")),
            ("250 KB CSV", try fixture.file("big.csv", "id,name,city\n" + text(bytes: target) { "\($0),Name \($0),City \($0 % 97)" })),
            ("250 KB Markdown", try fixture.file("big.md", "# Title\n\n" + text(bytes: target) { "- item \($0) with **bold** and a [link](https://example.invalid/\($0))" })),
            ("SQLite (about 1 MB)", database)
        ]
        let recording = ProcessInfo.processInfo.environment["THUMBNAIL_TIMINGS"] != nil
        // Default limits, as the extension runs them: 300 ms pipeline deadline, 1 s hard timeout.
        let service = ContentThumbnailService(registrations: StandardFormatAdapters.registrations, preferences: .fixed(.defaults))
        for (label, url) in files {
            var samples: [Double] = []
            var shape = "generic"
            for _ in 0..<5 {
                let clock = ContinuousClock()
                let start = clock.now
                let outcome = await service.outcome(for: url, geometry: geometry(256))
                let elapsed = clock.now - start
                samples.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
                switch outcome {
                case .content(let scene): shape = "content(\(scene.content.drawnStrings.isEmpty ? "picture" : "text"))"
                case .generic(let reason): shape = "generic(\(reason))"
                }
            }
            samples.sort()
            if recording { print("THUMBNAIL_TIMING \(label): median \(String(format: "%.1f", samples[2])) ms, max \(String(format: "%.1f", samples[4])) ms, \(shape)") }
        }
    }
}

import Foundation
import PreviewContracts
import PreviewCore
import PreviewFormats

private struct Entry: Codable {
    let formatID: String
    let path: String
    let variant: String
}
private struct Result: Codable {
    let formatID: String
    let variant: String
    let state: String
    let outputBytes: Int
}
private enum Failure: Error { case arguments, outcome }

@main private struct AdversarialCorpusChecks {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { throw Failure.arguments }
        let entries = try JSONDecoder().decode([Entry].self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        var results: [Result] = []
        for entry in entries {
            let outcome = await pipeline.preview(url: URL(fileURLWithPath: entry.path), budget: .standard)
            let state: String
            var bytes = 0
            switch outcome {
            case .ready(let presentation):
                guard presentation.formatID.rawValue == entry.formatID,
                      presentation.text.utf8.count <= PreviewBudget.standard.maxOutputUTF8Bytes,
                      presentation.lineCount <= PreviewBudget.standard.maxTextLines else { throw Failure.outcome }
                state = "ready"
                bytes = presentation.text.utf8.count
                // Baseline fixtures retain their declared sensitive keys. Mutations
                // may change those keys; no unsupported universal-redaction claim.
                if ["original", "secret-name"].contains(entry.variant), presentation.text.contains("synthetic-host-matrix-secret") {
                    throw Failure.outcome
                }
                if entry.formatID == "container.folder",
                   presentation.text.contains("synthetic private child payload") || presentation.text.contains("synthetic folder payload") {
                    throw Failure.outcome
                }
            case .unavailable(let failure): state = "unavailable.\(failure)"
            case .disabledByUser(let id):
                guard [.iges, .step].contains(id), id.rawValue == entry.formatID else { throw Failure.outcome }
                state = "disabledByDefault"
            case .geometryReady(let presentation):
                // Mesh formats read in process: a mutated file may still be a valid, bounded mesh.
                guard presentation.formatID.rawValue == entry.formatID,
                      presentation.mesh.outputByteCount <= PreviewBudget.standard.maxOutputUTF8Bytes else { throw Failure.outcome }
                state = "geometryReady"
            case .cancelled: throw Failure.outcome
            }
            results.append(.init(formatID: entry.formatID, variant: entry.variant, state: state, outputBytes: bytes))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(results))
        FileHandle.standardOutput.write(Data([10]))
    }
}

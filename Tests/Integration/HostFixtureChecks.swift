import Foundation
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats
import PreviewCADFormats

private struct Manifest: Decodable {
    let fixtures: [Fixture]
    struct Fixture: Decodable { let formatID: String; let path: String }
}
private struct Result: Encodable {
    let formatID: String
    let path: String
    let contentType: String?
    let parsed: Bool
    let concealed: Bool
}
private enum Failure: Error { case invalidArguments, unexpectedOutcome }

@main struct HostFixtureChecks {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.invalidArguments }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations + CADFormatAdapters.registrations(workerURL: URL(fileURLWithPath: CommandLine.arguments[2])))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: .iges); preferences.setEnabled(true, for: .step)
        var results: [Result] = []
        for fixture in manifest.fixtures {
            let url = directory.appendingPathComponent(fixture.path)
            let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
            let outcome = await pipeline.preview(url: url, preferences: preferences)
            if case .geometryReady(let presentation) = outcome {
                guard presentation.formatID.rawValue == fixture.formatID else { throw Failure.unexpectedOutcome }
                results.append(.init(formatID: fixture.formatID, path: fixture.path,
                    contentType: type?.identifier, parsed: true, concealed: false))
                continue
            }
            guard case .ready(let presentation) = outcome,
                  presentation.formatID.rawValue == fixture.formatID else {
                print("Unexpected fixture outcome: \(fixture.formatID)")
                throw Failure.unexpectedOutcome
            }
            guard !presentation.text.contains("synthetic-host-matrix-secret") else { throw Failure.unexpectedOutcome }
            results.append(.init(formatID: fixture.formatID, path: fixture.path,
                                 contentType: type?.identifier, parsed: true,
                                 concealed: presentation.redactionCount > 0))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(results))
        FileHandle.standardOutput.write(Data([10]))
    }
}

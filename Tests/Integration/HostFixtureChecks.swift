import Foundation
import UniformTypeIdentifiers
import PreviewContracts
import PreviewCore
import PreviewFormats

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
        guard CommandLine.arguments.count == 2 else { throw Failure.invalidArguments }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        // Version 1.0 ships without the STEP and IGES previews, so the fixture set holds no CAD file and the
        // standard registrations are the whole product.
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        let preferences = PreviewPreferencesSnapshot.defaults
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

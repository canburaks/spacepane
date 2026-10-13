import Foundation
import PreviewContracts
import PreviewCore
import PreviewCADFormats

private enum CheckFailure: Error { case arguments, outcome }
@main struct CADFixtureChecks {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("CAD integration check failed.\n".utf8)); exit(1) }
    }
    static func run() async throws {
        guard CommandLine.arguments.count >= 3 else { throw CheckFailure.arguments }
        let worker = URL(fileURLWithPath: CommandLine.arguments[1])
        // Version 1.0 keeps the two CAD descriptors out of the product catalog; this manual check of the CAD
        // module adds them back from the file the build validator also reads (this source sits in Tests/Integration).
        let entries = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Configuration/CADFormatCatalogEntries.json")
        let catalog = try FormatCatalog.standard.appending(entriesJSON: Data(contentsOf: entries))
        let pipeline = PreviewPipeline(catalog: catalog, registrations: CADFormatAdapters.registrations(workerURL: worker))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: .iges, catalog: catalog); preferences.setEnabled(true, for: .step, catalog: catalog)
        for argument in CommandLine.arguments.dropFirst(2) {
            let url = URL(fileURLWithPath: argument)
            let begin = ContinuousClock.now
            let result = await pipeline.preview(url: url, preferences: preferences)
            guard case .geometryReady(let presentation) = result else {
                if case .unavailable(let failure) = result { FileHandle.standardError.write(Data("CAD check unavailable: \(failure)\n".utf8)) }
                throw CheckFailure.outcome
            }
            let duration = begin.duration(to: .now)
            print("\(presentation.formatID.rawValue) vertices=\(presentation.mesh.positions.count) triangles=\(presentation.mesh.indices.count / 3) faces=\(presentation.mesh.faceCount) bytes=\(presentation.byteCount) duration=\(duration)")
        }
    }
}

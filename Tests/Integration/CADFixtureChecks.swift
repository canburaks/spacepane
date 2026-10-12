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
        let pipeline = PreviewPipeline(registrations: CADFormatAdapters.registrations(workerURL: worker))
        var preferences = PreviewPreferencesSnapshot.defaults
        preferences.setEnabled(true, for: .iges); preferences.setEnabled(true, for: .step)
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

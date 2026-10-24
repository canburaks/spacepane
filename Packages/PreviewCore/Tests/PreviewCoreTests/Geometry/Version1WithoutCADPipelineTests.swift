import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
import PreviewFileAccess
@testable import PreviewCore
import PreviewFormats

/// Version 1.0 ships without the STEP and IGES previews. A file of either kind meets the standard registrations only,
/// so it must come out as the ordinary "unsupported type" result: no crash, no CAD failure and no text dump of the
/// model, which is plain text a generic text fallback could otherwise show.
@Suite("Version 1.0 without CAD previews")
struct Version1WithoutCADPipelineTests {
    private struct PlainDataTypes: PreviewContentTypeReading {
        func contentType(for url: URL) throws -> UTType? { .data }
    }

    private static let secret = "synthetic-cad-cut-secret"
    private static let models: [(name: String, text: String)] = [
        ("part.step", "ISO-10303-21;\nHEADER;\nFILE_NAME('part','',(''),(''),'','','');\nENDSEC;\nDATA;\n#1=CARTESIAN_POINT('\(secret)',(0.,0.,0.));\nENDSEC;\nEND-ISO-10303-21;\n"),
        ("part.STP", "ISO-10303-21;\nDATA;\n#1=CARTESIAN_POINT('\(secret)',(0.,0.,0.));\nENDSEC;\nEND-ISO-10303-21;\n"),
        ("part.igs", "                                                                        S      1\n1H,,1H;,\(secret);                                                      G      1\n"),
        ("part.IGES", "                                                                        S      1\n1H,,1H;,\(secret);                                                      G      1\n"),
    ]

    private func withModels(_ body: (URL, [URL]) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("no-cad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try Self.models.map { model -> URL in
            let url = directory.appendingPathComponent(model.name)
            try Data(model.text.utf8).write(to: url)
            return url
        }
        try await body(directory, urls)
    }

    @Test func standardRegistrationsRegisterNoCADFormat() {
        let registered = StandardFormatAdapters.registrations.map(\.formatID.rawValue)
        #expect(registered.count == 81)
        #expect(!registered.contains { $0.hasPrefix("cad.") })
    }

    @Test func aSTEPOrIGESFileIsAnUnsupportedTypeThroughTheRealPipeline() async throws {
        try await withModels { _, urls in
            let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
            for url in urls {
                #expect(await pipeline.preview(url: url) == .unavailable(.unsupportedFormat), "\(url.lastPathComponent)")
                #expect(await pipeline.inspect(url: url) == .unsupported, "\(url.lastPathComponent)")
                // A saved choice for the old id changes nothing: the file is still not a catalog format.
                let preferences = PreviewPreferencesSnapshot(formatOverrides: [.step: true, .iges: true])
                #expect(await pipeline.preview(url: url, preferences: preferences) == .unavailable(.unsupportedFormat))
            }
        }
    }

    @Test func theSameFilesAreUnsupportedWhenTheSystemTypesThemAsPlainData() async throws {
        // What macOS reports for a suffix no installed app declares, so the result does not depend on this Mac.
        try await withModels { _, urls in
            let classifier = PreviewFileClassifier(access: BoundedReadAccess(), contentTypes: PlainDataTypes())
            let pipeline = PreviewPipeline(catalog: .standard, registrations: StandardFormatAdapters.registrations,
                                           classifier: classifier)
            for url in urls {
                #expect(await pipeline.preview(url: url) == .unavailable(.unsupportedFormat), "\(url.lastPathComponent)")
                #expect(await pipeline.inspect(url: url) == .unsupported, "\(url.lastPathComponent)")
            }
        }
    }

    @Test func noOutcomeCarriesTheModelTextOrACADFailure() async throws {
        try await withModels { _, urls in
            let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
            for url in urls {
                let outcome = await pipeline.preview(url: url)
                if case .ready = outcome { Issue.record("\(url.lastPathComponent) was shown as text") }
                if case .geometryReady = outcome { Issue.record("\(url.lastPathComponent) was shown as geometry") }
            }
        }
    }
}

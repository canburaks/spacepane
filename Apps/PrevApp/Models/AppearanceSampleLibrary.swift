import Foundation
import PreviewContracts

/// Bundled synthetic items, one per catalog format, for the Theme page's live sample.
/// They hold no user data. A sample is written to a private temporary directory and
/// then read through the same pipeline as any other file, so it looks as it would in Finder.
struct AppearanceSampleLibrary: Sendable {
    enum Failure: Error { case unavailable, invalid }

    private static let resourceName = "AppearanceSamples"
    private static let resourceExtension = "json"
    private static let supportedVersion = 1
    // The generator enforces the same bounds; the companion checks them again before writing.
    private static let maximumManifestBytes = 1_048_576
    private static let maximumFileBytes = 65_536
    private static let maximumFilesPerSample = 16

    private let manifestURL: URL?

    init(bundle: Bundle = .main) {
        manifestURL = bundle.url(forResource: Self.resourceName, withExtension: Self.resourceExtension)
    }

    /// Checks read the repository's manifest directly.
    init(manifestURL: URL) { self.manifestURL = manifestURL }

    /// The formats that have a sample, in manifest order.
    @concurrent func formatIDs() async throws -> [FormatID] {
        try manifest().samples.map { FormatID(rawValue: $0.formatID) }
    }

    /// Writes one format's sample below `directory` and returns its root file or folder.
    @concurrent func materialize(_ id: FormatID, in directory: URL) async throws -> URL {
        guard let sample = try manifest().samples.first(where: { $0.formatID == id.rawValue }) else {
            throw Failure.unavailable
        }
        guard Self.isComponent(sample.root), (1...Self.maximumFilesPerSample).contains(sample.files.count) else {
            throw Failure.invalid
        }
        let manager = FileManager.default
        let container = directory.appendingPathComponent(id.rawValue, isDirectory: true)
        try? manager.removeItem(at: container)
        for file in sample.files {
            try Task.checkCancellation()
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            // Every path stays inside the sample's own root; nothing can reach outside the container.
            guard components.first == sample.root, components.allSatisfy(Self.isComponent),
                  let data = Data(base64Encoded: file.data), data.count <= Self.maximumFileBytes else {
                throw Failure.invalid
            }
            let destination = components.reduce(container) { $0.appendingPathComponent($1) }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }
        return container.appendingPathComponent(sample.root)
    }

    private struct Manifest: Decodable {
        struct Sample: Decodable {
            struct File: Decodable {
                let path: String
                let data: String
            }
            let formatID: String
            let root: String
            let files: [File]
        }
        let version: Int
        let samples: [Sample]
    }

    private func manifest() throws -> Manifest {
        guard let manifestURL else { throw Failure.unavailable }
        let handle = try FileHandle(forReadingFrom: manifestURL)
        defer { try? handle.close() }
        guard let bytes = try handle.read(upToCount: Self.maximumManifestBytes + 1),
              bytes.count <= Self.maximumManifestBytes else { throw Failure.invalid }
        let manifest = try JSONDecoder().decode(Manifest.self, from: bytes)
        guard manifest.version == Self.supportedVersion else { throw Failure.invalid }
        return manifest
    }

    private static func isComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\0")
    }
}

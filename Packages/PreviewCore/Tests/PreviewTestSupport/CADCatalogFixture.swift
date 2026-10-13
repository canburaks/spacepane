import Foundation
import PreviewContracts

/// A file of this repository outside the package, found from this source file rather than the working directory.
public enum RepositoryFile {
    public static func url(_ relativePath: String, file: StaticString = #filePath) -> URL {
        var directory = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        preconditionFailure("\(relativePath) not found above \(file)")
    }
}

/// The two CAD descriptors (`cad.iges`, `cad.step`) that version 1.0 keeps out of the product catalog. They live in
/// `Configuration/CADFormatCatalogEntries.json`, which the build validator also reads, so the CAD tests exercise
/// the same descriptors the product would ship again.
public enum CADCatalogFixture {
    public static let entriesURL = RepositoryFile.url("Configuration/CADFormatCatalogEntries.json")

    /// The product catalog with the two CAD descriptors appended, as it was before version 1.0 cut them.
    public static func catalog() throws -> FormatCatalog {
        try FormatCatalog.standard.appending(entriesJSON: Data(contentsOf: entriesURL))
    }
}

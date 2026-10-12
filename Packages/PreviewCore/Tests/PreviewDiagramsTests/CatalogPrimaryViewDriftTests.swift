import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewRenderers

/// The Theme page's built-in samples, one per catalog format (`script/generate_appearance_samples.py`).
private let appearanceSamplesManifest: URL = {
    // .../Packages/PreviewCore/Tests/PreviewDiagramsTests/<this file> -> the repository root is five levels up.
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    return root.appendingPathComponent("Apps/PrevApp/Resources/AppearanceSamples.json")
}()

private extension NativePreviewMode {
    /// The catalog name of a mode a format can open in; nil for the modes no format opens in first.
    var primaryView: PrimaryView? {
        switch self {
        case .source: .source
        case .outline: .outline
        case .records: .records
        case .rendered: .rendered
        case .summary: .summary
        case .table: .table
        case .rows: .rows
        case .plot: .plot
        case .files: .files
        case .pages: .pages
        case .diagram: .diagram
        default: nil
        }
    }
}

/// The catalog's `primaryView` must equal the mode the renderer's policy opens for the format's built-in sample
/// (decision 027, Q-32; owner decision D1): the companion names the view, so the catalog may never promise one
/// the preview does not open. Every text format needs a sample that previews; the geometry formats are covered
/// by `CatalogPrimaryViewTests` and are skipped here because they are off by default or need the viewport.
@Suite("Catalog primary views against the mode policy",
       .enabled(if: FileManager.default.fileExists(atPath: appearanceSamplesManifest.path)))
struct CatalogPrimaryViewDriftTests {
    @Test @MainActor func everyTextFormatOpensInItsCatalogPrimaryView() async throws {
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: appearanceSamplesManifest)) as? [String: Any])
        let samples = try #require(manifest["samples"] as? [[String: Any]])
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations)
        let locale = Locale(identifier: "en_US")
        var checked: Set<FormatID> = []
        var drift: [String] = []
        for sample in samples {
            let rawID = try #require(sample["formatID"] as? String)
            let formatID = FormatID(rawValue: rawID)
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: formatID), "\(rawID) is not in the catalog")
            if descriptor.presentation == .geometry { continue }
            let files = try #require(sample["files"] as? [[String: Any]])
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            for file in files {
                let url = directory.appendingPathComponent(try #require(file["path"] as? String))
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoded = try #require(file["data"] as? String)
                try #require(Data(base64Encoded: encoded)).write(to: url)
            }
            // The manifest names the item to preview (a file, a folder or a bundle); a multi-file sample without a root
            // would otherwise preview its temporary parent folder.
            let firstPath = try #require(files[0]["path"] as? String)
            let root = (sample["root"] as? String) ?? firstPath
            let target = directory.appendingPathComponent(root)
            let outcome = await pipeline.preview(url: target, budget: PreviewBudget(maxMilliseconds: 30_000))
            guard case .ready(let presentation) = outcome else {
                drift.append("\(rawID): the sample did not preview (\(outcome))")
                continue
            }
            guard presentation.formatID == formatID else {
                drift.append("\(rawID): the sample was classified as \(presentation.formatID.rawValue)")
                continue
            }
            let opened = SafePreviewModes(presentation, locale: locale).initialMode(for: formatID)
            guard let view = opened.primaryView else {
                drift.append("\(rawID): opens in \(opened), which no catalog view names")
                continue
            }
            checked.insert(formatID)
            if view != descriptor.primaryView {
                drift.append("\(rawID): the catalog says \(descriptor.primaryView.rawValue), the sample opens in \(view.rawValue)")
            }
        }
        #expect(drift.isEmpty, "\(drift.joined(separator: "; "))")
        let unchecked = FormatCatalog.standard.descriptors
            .filter { $0.presentation == .text && !checked.contains($0.id) }
            .map(\.id.rawValue).sorted()
        #expect(unchecked.isEmpty, "text formats whose sample did not reach the policy: \(unchecked.joined(separator: ", "))")
    }
}

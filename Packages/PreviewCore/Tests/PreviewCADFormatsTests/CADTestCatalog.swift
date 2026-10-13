import PreviewContracts
import PreviewTestSupport

/// The product catalog plus the two CAD descriptors that version 1.0 keeps in
/// `Configuration/CADFormatCatalogEntries.json`. The pipelines and preference snapshots in this module's tests use
/// it, because the product catalog alone no longer classifies a STEP or IGES file.
let cadCatalog: FormatCatalog = {
    do { return try CADCatalogFixture.catalog() } catch { preconditionFailure("CAD catalog entries unreadable: \(error)") }
}()

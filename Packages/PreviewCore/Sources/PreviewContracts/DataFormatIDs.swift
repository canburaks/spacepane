import Foundation

/// Stable identifiers of the columnar, scientific, web-capture and geographic data formats.
/// They are persisted in file-type choices; never change a raw value.
public extension FormatID {
    static let parquet = FormatID(rawValue: "data.parquet")
    static let avro = FormatID(rawValue: "data.avro")
    static let arrow = FormatID(rawValue: "data.arrow")
    static let numpy = FormatID(rawValue: "data.numpy")
    static let numpyArchive = FormatID(rawValue: "data.numpy-archive")
    static let har = FormatID(rawValue: "data.har")
    static let geoJSON = FormatID(rawValue: "data.geojson")
    static let gpx = FormatID(rawValue: "data.gpx")
    static let kml = FormatID(rawValue: "data.kml")

    /// Formats whose adapters write the shared data summary envelope (`DataSummaryKeys`).
    static let dataSummaryFormats: Set<FormatID> = [
        .parquet, .avro, .arrow, .numpy, .numpyArchive, .har, .geoJSON, .gpx, .kml
    ]
}

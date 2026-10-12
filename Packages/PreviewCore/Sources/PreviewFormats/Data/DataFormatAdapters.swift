import PreviewContracts

/// Columnar, scientific, web-capture and geographic data formats. Parquet, Avro, Arrow and NumPy
/// read only the bytes they need through the bounded random-access source; HAR, GeoJSON, GPX and
/// KML need their whole (budget-limited) document.
public enum DataFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .parquet, randomAccessAdapter: { ParquetAdapter() }),
        AdapterRegistration(formatID: .avro, randomAccessAdapter: { AvroAdapter() }),
        AdapterRegistration(formatID: .arrow, randomAccessAdapter: { ArrowAdapter() }),
        AdapterRegistration(formatID: .numpy, randomAccessAdapter: { NumPyAdapter() }),
        AdapterRegistration(formatID: .numpyArchive, randomAccessAdapter: { NumPyArchiveAdapter() }),
        AdapterRegistration(formatID: .har, binaryAdapter: { HARAdapter() }),
        AdapterRegistration(formatID: .geoJSON, binaryAdapter: { GeoJSONAdapter() }),
        AdapterRegistration(formatID: .gpx, binaryAdapter: { GPXAdapter() }),
        AdapterRegistration(formatID: .kml, binaryAdapter: { KMLAdapter() })
    ]
}

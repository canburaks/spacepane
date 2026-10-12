import PreviewContracts

public enum ContainerFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .sqlite, sourcePolicy: .sqliteSnapshot, binaryAdapter: { SQLiteInspectionAdapter() }),
        AdapterRegistration(formatID: .zip, defaultBudget: .containerScan, randomAccessAdapter: { ZIPListingAdapter() }),
        AdapterRegistration(formatID: .tar, defaultBudget: .containerScan, randomAccessAdapter: { TARListingAdapter() }),
        AdapterRegistration(formatID: .gzip, defaultBudget: .containerScan, binaryAdapter: { GZIPPreviewAdapter() }),
        AdapterRegistration(formatID: .xip, defaultBudget: .containerScan, randomAccessAdapter: { XIPListingAdapter() }),
        AdapterRegistration(formatID: .folder, urlAdapter: { FolderSummaryAdapter() }),
        AdapterRegistration(formatID: .midi, binaryAdapter: { MIDIAdapter() })
    ]
}

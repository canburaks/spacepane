import PreviewContracts

/// Registrations for the ebook, comic and web-archive formats. Each reads its source through bounded random
/// access, because its useful parts (a central directory, a cover, a head window) are not the whole file.
public enum DocumentFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .comicBook, defaultBudget: .containerScan, randomAccessAdapter: { ComicBookAdapter() }),
        AdapterRegistration(formatID: .epub, defaultBudget: .containerScan, randomAccessAdapter: { EPUBAdapter() }),
        AdapterRegistration(formatID: .fictionBook, randomAccessAdapter: { FictionBookAdapter() }),
        AdapterRegistration(formatID: .webArchive, randomAccessAdapter: { WebArchiveAdapter() })
    ]
}

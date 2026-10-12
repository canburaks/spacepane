import Foundation

/// Locale-aware wording of the listed facts shared by the Files table and the Tree. Names, paths and
/// file contents are never formatted or translated; only app-owned labels and numeric/date values are.
enum SafeListingFormatting {
    /// The localized kind of an entry. A value the app has no label for (an adapter's own spelling) is
    /// shown as written.
    static func kindLabel(_ kind: String) -> String {
        SummaryLabelSet.entryKinds[kind].map { PreviewStrings.text($0) } ?? kind
    }

    static func sizeText(_ bytes: Int64, locale: Locale) -> String {
        bytes.formatted(ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false,
                                             includesActualByteCount: false, locale: locale))
    }

    static func countText(_ count: Int, locale: Locale) -> String {
        Int64(count).formatted(.number.locale(locale))
    }

    /// Short date and time. Stored wall-clock stamps (`usesUTC`) are shown in UTC so their digits stay
    /// unchanged; real instants are shown in the viewer's time zone.
    static func dateText(_ date: Date, locale: Locale, usesUTC: Bool) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale,
                                        calendar: locale.calendar, timeZone: usesUTC ? .gmt : .current))
    }

    /// Marks a number that is only a lower bound, such as the size of a partly listed folder.
    static func atLeast(_ text: String, locale: Locale) -> String {
        PreviewStrings.format(.listingAtLeast, arguments: [text], locale: locale)
    }
}

/// The Files mode: every listed entry as a row with Name, Kind, Size and Modified columns.
enum SafeListingFiles {
    static func table(_ listing: SafeListing, tree: SafeListingTree?, locale: Locale) -> SafeTable {
        // Hierarchical order with folders first; without a tree the adapter's listing order is kept.
        let order = tree?.entryOrder ?? Array(listing.entries.indices)
        var rows: [[String]] = []
        var sizes: [Double?] = []
        var dates: [Double?] = []
        rows.reserveCapacity(order.count)
        sizes.reserveCapacity(order.count)
        dates.reserveCapacity(order.count)
        for index in order {
            let entry = listing.entries[index]
            // A folder's own allocation size is never shown as a size; its listed total is in Tree.
            let size = entry.isDirectory ? nil : entry.bytes
            rows.append([
                entry.path,
                SafeListingFormatting.kindLabel(entry.isDirectory ? "directory" : entry.kind),
                size.map { SafeListingFormatting.sizeText($0, locale: locale) } ?? "",
                entry.modified.map { SafeListingFormatting.dateText($0, locale: locale, usesUTC: listing.usesUTC) } ?? ""
            ])
            sizes.append(size.map(Double.init))
            dates.append(entry.modified?.timeIntervalSince1970)
        }
        let columns = [PreviewStrings.text(.summaryName), PreviewStrings.text(.listingColumnKind),
                       PreviewStrings.text(.listingColumnSize),
                       PreviewStrings.text(listing.usesUTC ? .listingModifiedUTC : .listingModified)]
        return SafeTable(columns: columns, rows: rows, truncation: listing.isPartial ? [.partialListing] : [],
                         columnKinds: [.text, .text, .number, .date], sortKeys: [2: sizes, 3: dates], origin: .listing)
    }
}

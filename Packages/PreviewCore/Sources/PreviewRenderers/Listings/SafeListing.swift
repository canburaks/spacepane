import Foundation
import PreviewContracts

/// One listed folder or archive entry, read back from the concealed summary text.
struct SafeListingEntry: Equatable, Sendable {
    let path: String
    /// The adapter's raw `type` value ("file", "directory", "symlink", "package", …).
    let kind: String
    let bytes: Int64?
    let modified: Date?
    let isEncrypted: Bool
    /// Direct children, present only when the adapter counted them exactly.
    let itemCount: Int?

    var isDirectory: Bool { kind == "directory" || path.hasSuffix("/") }

    // Exact code units, so a replacement that differs only by canonical equivalence is still a change.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.bytes == rhs.bytes && lhs.modified == rhs.modified
            && lhs.isEncrypted == rhs.isEncrypted && lhs.itemCount == rhs.itemCount
            && lhs.path.utf8.elementsEqual(rhs.path.utf8)
    }
}

/// The listing-shaped summary written by the folder and archive adapters: a root object whose `entries`
/// array holds objects with `path`, `type` and `bytes`. It is recognized from the **concealed** summary
/// JSON, never from source bytes, and by its shape rather than by a list of formats, so any adapter that
/// registers a summary schema and writes this shape gets the Files and Tree modes.
struct SafeListing: Equatable, Sendable {
    /// Summary text above this size is not parsed (twice the largest listing the adapters can write).
    static let maximumSourceUTF8Bytes = 8_388_608
    static let maximumEntries = 20_000

    let entries: [SafeListingEntry]
    /// The adapter stopped at a limit (or could not enter a folder), so counts and totals are incomplete.
    let isPartial: Bool
    /// The adapter marked every date as a stored wall-clock value to show unchanged (`timeZone: UTC`).
    let usesUTC: Bool

    /// Returns nil unless `presentation` is a summary whose schema is registered and whose root has the
    /// listing shape. Concealment that broke the JSON, a shape violation or an oversized text all decline.
    static func parse(_ presentation: TextPresentation) -> SafeListing? {
        guard presentation.syntax == .json, SafeSchemaLabels.formats.contains(presentation.formatID),
              presentation.text.utf8.count <= maximumSourceUTF8Bytes,
              // Cheap rejection before parsing: a listing always names its entries array.
              presentation.text.contains("\"entries\"") else { return nil }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(presentation.text.utf8))) as? [String: Any],
              let rawEntries = root["entries"] as? [Any], !rawEntries.isEmpty, rawEntries.count <= maximumEntries else { return nil }
        let formatter = ISO8601DateFormatter()
        var entries: [SafeListingEntry] = []
        entries.reserveCapacity(rawEntries.count)
        for raw in rawEntries {
            guard let object = raw as? [String: Any], let path = object["path"] as? String, !path.isEmpty,
                  let kind = object["type"] as? String else { return nil }
            entries.append(SafeListingEntry(
                path: path, kind: kind, bytes: integer(object["bytes"]),
                modified: (object["modified"] as? String).flatMap { formatter.date(from: $0) },
                isEncrypted: (object["encrypted"] as? Bool) == true,
                itemCount: integer(object["items"]).flatMap { Int(exactly: $0) }))
        }
        return SafeListing(entries: entries, isPartial: (root["partial"] as? Bool) == true,
                           usesUTC: (root["timeZone"] as? String) == "UTC")
    }

    /// A JSON integer (not a boolean or fractional number); `null`, missing and concealed values are nil.
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number as CFNumber) else { return nil }
        return number.int64Value
    }
}

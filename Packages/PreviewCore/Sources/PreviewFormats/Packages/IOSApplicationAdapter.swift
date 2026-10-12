import Foundation
import PreviewContracts

/// Summarizes an iOS/iPadOS application archive (`.ipa`): the bundle's `Info.plist`, the embedded
/// provisioning profile, a decodable icon and the archive's file listing.
///
/// The archive is a ZIP file read through the shared bounded reader. Only three members are ever read
/// (the property list, the profile and one icon PNG); nothing is extracted, executed or written.
public struct IOSApplicationAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let maximumInfoPropertyListBytes = 1_048_576
    static let maximumProfileBytes = 262_144
    /// Icon candidates tried (largest first) before giving up; some iOS PNGs are in a size-optimized
    /// encoding that ImageIO declines, and they are omitted rather than shown wrongly.
    static let iconAttempts = 3

    private let now: @Sendable () -> Date

    public init() { self.init(now: { Date() }) }
    init(now: @escaping @Sendable () -> Date) { self.now = now }

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let archive = try ZIPArchiveReader.read(source, context: context)
        guard let infoEntry = Self.infoEntry(in: archive) else { throw PreviewFailure.malformedDocument }
        let appRoot = String(infoEntry.path.dropLast("Info.plist".count))
        let info = try BoundedPropertyList.dictionary(
            try ZIPArchiveReader.readMember(infoEntry, from: source, maximumBytes: Self.maximumInfoPropertyListBytes, context: context),
            context: context)

        var fields = BundleInfoSummary.fields(info)
        if let profile = try optional({ try profileFields(archive: archive, appRoot: appRoot, source: source, context: context) }) {
            fields.add("provisioning", profile)
        }
        let icon = try optional { try iconImage(archive: archive, appRoot: appRoot, info: info, source: source, context: context) }
        let capacity = PackageSummary.listingCapacity(context)
        let entries = archive.entries.prefix(capacity).map {
            ContainerEntry(path: $0.path, kind: $0.kind, size: $0.uncompressedSize, modified: $0.modified, isEncrypted: $0.isEncrypted)
        }
        fields.listing(format: archive.isZip64 ? "ZIP64" : "ZIP", entries: Array(entries), partial: archive.entries.count > capacity)
        return try PackageSummary.document(fields.value, context: context, images: icon.map { [$0] } ?? [])
    }

    /// The first `Payload/<name>.app/Info.plist`, by path order so the choice is deterministic.
    static func infoEntry(in archive: ZIPArchive) -> ZIPEntry? {
        archive.entries.filter { entry in
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            return entry.kind == "file" && parts.count == 3 && parts[0] == "Payload"
                && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }.min { $0.path < $1.path }
    }

    private func profileFields(archive: ZIPArchive, appRoot: String, source: any PreviewByteSource,
                               context: RequestContext) throws -> SummaryValue? {
        guard let entry = archive.entry(at: appRoot + "embedded.mobileprovision") else { return nil }
        let data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: Self.maximumProfileBytes, context: context)
        let profile = try ProvisioningProfileSummary.profile(from: data, context: context)
        return ProvisioningProfileSummary.fields(profile, now: now()).value
    }

    private func iconImage(archive: ZIPArchive, appRoot: String, info: [String: Any], source: any PreviewByteSource,
                           context: RequestContext) throws -> PreviewImage? {
        let bases = BundleInfoSummary.iconBaseNames(info)
        guard !bases.isEmpty else { return nil }
        let candidates = archive.entries.filter { entry in
            guard entry.kind == "file", entry.path.hasPrefix(appRoot), entry.uncompressedSize <= PackageIconImages.maximumEncodedBytes else { return false }
            let name = String(entry.path.dropFirst(appRoot.count))
            return !name.contains("/") && name.lowercased().hasSuffix(".png") && bases.contains { name.hasPrefix($0) }
        }.sorted { $0.uncompressedSize != $1.uncompressedSize ? $0.uncompressedSize > $1.uncompressedSize : $0.path < $1.path }
        for entry in candidates.prefix(Self.iconAttempts) {
            let data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: PackageIconImages.maximumEncodedBytes, context: context)
            // The icon carries no label: a member name is untrusted text that would bypass the privacy stage.
            if let image = PackageIconImages.validatedPNG(data) { return image }
        }
        return nil
    }

    /// Optional members (profile, icon) never fail the summary: a bounded-reader refusal or a malformed
    /// member simply omits that part. Cancellation and an expired deadline still propagate.
    private func optional<T>(_ body: () throws -> T?) throws -> T? {
        do { return try body() }
        catch PreviewFailure.deadlineExceeded { throw PreviewFailure.deadlineExceeded }
        catch is PreviewFailure { return nil }
    }
}

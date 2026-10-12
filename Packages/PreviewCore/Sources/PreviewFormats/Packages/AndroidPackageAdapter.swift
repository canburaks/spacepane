import Foundation
import PreviewContracts

/// Summarizes an Android package (`.apk`) or App Bundle (`.aab`): the manifest's package name,
/// versions, SDK levels, permissions and component counts, plus the archive's file listing.
///
/// The archive is read through the shared bounded ZIP reader and only the manifest member is read: an
/// APK keeps compiled binary XML at the root, a bundle keeps protobuf XML under its base module.
/// Signature blocks, resources, dex code and native libraries are never read or executed, and no
/// signature verification is claimed.
public struct AndroidPackageAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    /// Where each package kind keeps its manifest, in the order tried.
    static let manifestPaths = ["AndroidManifest.xml", "base/manifest/AndroidManifest.xml"]
    static let maximumManifestBytes = 2_097_152

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let archive = try ZIPArchiveReader.read(source, context: context)
        guard let entry = Self.manifestPaths.lazy.compactMap({ archive.entry(at: $0) }).first(where: { $0.kind == "file" }) else {
            throw PreviewFailure.malformedDocument
        }
        let manifestData = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: Self.maximumManifestBytes, context: context)
        let manifest = try Self.manifest(manifestData, context: context)

        var fields = SummaryFields()
        fields.text("packageName", manifest.packageName)
        fields.text("applicationLabel", manifest.applicationLabel)
        fields.number("versionCode", manifest.versionCode)
        fields.text("versionName", manifest.versionName)
        fields.text("minSdkVersion", manifest.minimumSDK)
        fields.text("targetSdkVersion", manifest.targetSDK)
        fields.text("compileSdkVersion", manifest.compileSDK)
        fields.flag("debuggable", manifest.isDebuggable)
        fields.number("activities", manifest.activities)
        fields.number("services", manifest.services)
        fields.number("receivers", manifest.receivers)
        fields.number("providers", manifest.providers)
        if !manifest.permissions.isEmpty {
            fields.number("permissionCount", manifest.permissions.count)
            fields.list("permissions", manifest.permissions)
        }
        let capacity = PackageSummary.listingCapacity(context)
        let entries = archive.entries.prefix(capacity).map {
            ContainerEntry(path: $0.path, kind: $0.kind, size: $0.uncompressedSize, modified: $0.modified, isEncrypted: $0.isEncrypted)
        }
        fields.listing(format: archive.isZip64 ? "ZIP64" : "ZIP", entries: Array(entries), partial: archive.entries.count > capacity)
        return try PackageSummary.document(fields.value, context: context)
    }

    /// Compiled binary XML begins with its chunk header (type 3, header size 8); a bundle's protobuf XML
    /// begins with the tag of its `element` field. Anything else is neither and is not guessed at.
    private static let binaryXMLHeader: [UInt8] = [0x03, 0x00, 0x08, 0x00]
    private static let protobufElementTag: UInt8 = 0x0A

    static func manifest(_ data: Data, context: RequestContext) throws -> AndroidManifestSummary {
        if data.starts(with: binaryXMLHeader) { return try AndroidBinaryXML.parseManifest(data, context: context) }
        if data.first == protobufElementTag { return try AndroidProtoXML.parseManifest(data, context: context) }
        throw PreviewFailure.unsupportedFormat
    }
}

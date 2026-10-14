import Foundation
import PreviewContracts

/// Summarizes a Python wheel (`.whl`): its name, version, requirements and the commands it installs, read
/// from the `.dist-info` folder, what installing it would put where Python runs code by itself, and the
/// archive's file listing (decision 030).
///
/// The wheel is a ZIP read through the shared bounded reader. Only four kinds of member are read, each
/// from its beginning and no further than its cap: `METADATA`, `WHEEL`, `entry_points.txt` and the `.pth`
/// files that installation would place in site-packages, plus the first bytes of the other files to
/// recognize native code. Nothing is extracted, imported or run, and a nested archive is never opened.
/// Findings sit on the summary and carry no lines and no source value.
public struct PythonWheelAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let maximumMetadataBytes = 1_048_576
    static let maximumSmallFileBytes = 65_536
    static let maximumPathFileBytes = 65_536
    static let maximumPathFiles = 32
    /// Compressed bytes the native-code check may read in all; the rest of the request's input budget
    /// stays free for the listing.
    static let maximumNativeScanBytes = 2_097_152
    static let maximumLicenseBytes = 200

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let archive = try ZIPArchiveReader.read(source, context: context)
        let layout = try WheelLayout(archive.entries, context: context)
        guard let metadataEntry = archive.entry(at: layout.distInfo + "/METADATA"), metadataEntry.kind == "file" else {
            throw PreviewFailure.malformedDocument
        }
        func member(_ name: String, limit: Int) throws -> Data? {
            guard let entry = archive.entry(at: layout.distInfo + "/" + name) else { return nil }
            return try ZIPMemberPrefix.read(entry, from: source, maximumBytes: limit, context: context)
        }
        let metadata = try WheelHeaders(
            member("METADATA", limit: Self.maximumMetadataBytes) ?? Data(),
            keeping: ["name", "version", "summary", "requires-python", "requires-dist", "license-expression", "license"],
            context: context)
        let wheel = try WheelHeaders(
            member("WHEEL", limit: Self.maximumSmallFileBytes) ?? Data(),
            keeping: ["wheel-version", "generator", "root-is-purelib", "tag"], context: context)
        let commands = try member("entry_points.txt", limit: Self.maximumSmallFileBytes)
            .map { try WheelEntryPoints.commandNames($0, context: context) } ?? []

        var fields = SummaryFields()
        fields.text("name", metadata.first("name") ?? layout.identity.name)
        fields.text("version", metadata.first("version") ?? layout.identity.version)
        fields.text("summary", metadata.first("summary"))
        fields.text("requiresPython", metadata.first("requires-python"))
        fields.list("dependencies", metadata.all("requires-dist"))
        fields.text("license", (metadata.first("license-expression") ?? metadata.first("license"))
            .map { PackageSummary.clipped($0, limit: Self.maximumLicenseBytes) })
        fields.text("wheelVersion", wheel.first("wheel-version"))
        fields.text("generator", wheel.first("generator"))
        fields.flag("pureLibrary", wheel.first("root-is-purelib").flatMap(Self.boolean))
        fields.list("tags", wheel.all("tag"))
        fields.list("commands", commands)

        let startupLines = try startupCodeLines(layout.startupFiles, source: source, context: context)
        fields.list("startupFiles", layout.startupFiles.map(\.path))
        fields.list("installedScripts", layout.installedScripts)
        let native = try nativeModules(archive, source: source, context: context)
        if native.count > 0 { fields.number("nativeModules", native.count) }

        let capacity = PackageSummary.listingCapacity(context)
        let entries = archive.entries.prefix(capacity).map {
            ContainerEntry(path: $0.path, kind: $0.kind, size: $0.uncompressedSize, modified: $0.modified, isEncrypted: $0.isEncrypted)
        }
        fields.listing(format: archive.isZip64 ? "ZIP64" : "ZIP", entries: Array(entries), partial: archive.entries.count > capacity)

        var findings: [PreviewFinding] = []
        if startupLines > 0 { findings.append(PreviewFinding(kind: .installStartupCode, count: startupLines)) }
        if let finding = native.finding { findings.append(finding) }
        return try PackageSummary.document(fields.value, context: context, findings: findings)
    }

    /// The number of lines, over all path files, that Python's `site` module runs at every start.
    private func startupCodeLines(_ files: [ZIPEntry], source: any PreviewByteSource, context: RequestContext) throws -> Int {
        var total = 0
        for entry in files.prefix(Self.maximumPathFiles) {
            let data = try ZIPMemberPrefix.read(entry, from: source, maximumBytes: Self.maximumPathFileBytes, context: context)
            total += try PythonStartupLines.lines(in: String(decoding: data, as: UTF8.self), context: context).count
        }
        return total
    }

    /// Counts native-code members by name and by leading bytes. Reading stops quietly when the request's
    /// input budget or this check's own allowance runs out: the count is then of the members checked.
    private func nativeModules(_ archive: ZIPArchive, source: any PreviewByteSource,
                               context: RequestContext) throws -> NativeCodeTally {
        var tally = NativeCodeTally()
        var scanned = 0
        var exhausted = false
        for (index, entry) in archive.entries.enumerated() where entry.kind == "file" {
            if index.isMultiple(of: 256) { try context.checkpoint() }
            try tally.add(path: entry.path) {
                let cost = ZIPMemberPrefix.compressedReadSize(of: entry, maximumBytes: NativeCodeSignature.prefixLength)
                guard !exhausted, entry.uncompressedSize >= 4, scanned + cost <= Self.maximumNativeScanBytes else { return nil }
                scanned += cost
                do {
                    return try ZIPMemberPrefix.read(entry, from: source, maximumBytes: NativeCodeSignature.prefixLength, context: context)
                } catch PreviewFailure.inputTooLarge {
                    exhausted = true
                    return nil
                }
            }
        }
        return tally
    }

    /// The wheel format writes `true` or `false`; anything else is no fact.
    private static func boolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true": true
        case "false": false
        default: nil
        }
    }
}

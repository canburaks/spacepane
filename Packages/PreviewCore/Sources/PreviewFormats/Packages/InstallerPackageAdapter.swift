import Foundation
import Security
import PreviewContracts

/// Summarizes a flat installer package (`.pkg`, a XAR container): the table-of-contents listing, the
/// installer `Distribution` and each component's `PackageInfo`, and the names of the signing certificates.
///
/// Only the table of contents and these small metadata members are read. Payloads, bills of materials
/// and scripts are never opened: script file names come from `PackageInfo` and script contents are never
/// read or shown. The package signature is not verified. Bundle-style (directory) packages are not flat
/// archives and are declined by the reader before this adapter runs.
public struct InstallerPackageAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let maximumDistributionBytes = 524_288
    static let maximumPackageInfoBytes = 262_144
    static let maximumPackageInfoMembers = 32

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let limits = ContainerLimits(context: context)
        let archive = try XARArchiveReader.read(source, context: context, limits: limits)

        var distribution = InstallerMetadata()
        if let index = archive.entries.firstIndex(where: { $0.parent == nil && $0.name == "Distribution" && !$0.isDirectory }),
           let metadata = try optionalMetadata(archive.entries[index], kind: .distribution, limit: Self.maximumDistributionBytes,
                                               archive: archive, source: source, context: context) {
            distribution = metadata
        }
        var records = distribution.records
        var members = 0
        for (index, entry) in archive.entries.enumerated() where entry.name == "PackageInfo" && !entry.isDirectory && depth(of: index, in: archive) <= 2 {
            members += 1
            guard members <= Self.maximumPackageInfoMembers else { break }
            guard let metadata = try optionalMetadata(entry, kind: .packageInfo, limit: Self.maximumPackageInfoBytes,
                                                      archive: archive, source: source, context: context) else { continue }
            for record in metadata.records { InstallerMetadata.merge(record, into: &records) }
        }

        var fields = SummaryFields()
        fields.text("title", distribution.title)
        fields.text("version", distribution.productVersion)
        fields.text("minimumOSVersion", distribution.minimumOSVersion)
        fields.list("hostArchitectures", distribution.hostArchitectures)
        if !records.isEmpty {
            fields.add("packages", .array(records.prefix(PackageSummary.maximumListItems).map { $0.summaryValue() }))
        }
        fields.flag("signed", archive.hasSignature ? true : nil)
        fields.list("signers", archive.signatureCertificates.compactMap(Self.certificateName))
        // The signature is read as stored; it is never verified.
        fields.flag("signatureVerified", false)

        let capacity = PackageSummary.listingCapacity(context)
        var entries: [ContainerEntry] = []
        var skipped = false
        for index in archive.entries.indices {
            try context.checkpoint()
            if entries.count == capacity { skipped = true; break }
            let entry = archive.entries[index]
            guard let path = archive.path(of: index), (try? safeArchivePath(path)) != nil else { skipped = true; continue }
            entries.append(ContainerEntry(path: path, kind: entry.isDirectory ? "directory" : "file", size: entry.size, modified: entry.modified))
        }
        fields.listing(format: "XAR", entries: entries, partial: skipped)
        return try PackageSummary.document(fields.value, context: context)
    }

    private func depth(of index: Int, in archive: XARArchive) -> Int {
        var count = 1
        var current = archive.entries[index].parent
        while let parent = current, count <= 64 {
            count += 1
            current = archive.entries[parent].parent
        }
        return count
    }

    /// A metadata member that cannot be read or understood is left out; the rest of the summary stands.
    private func optionalMetadata(_ entry: XARFileEntry, kind: InstallerMetadata.Kind, limit: Int, archive: XARArchive,
                                  source: any PreviewByteSource, context: RequestContext) throws -> InstallerMetadata? {
        do {
            let data = try XARArchiveReader.readData(entry, in: archive, from: source, maximumBytes: limit, context: context)
            return try InstallerMetadata.parse(data, kind: kind, context: context)
        } catch PreviewFailure.deadlineExceeded {
            throw PreviewFailure.deadlineExceeded
        } catch is PreviewFailure {
            return nil
        }
    }

    private static func certificateName(_ base64: String) -> String? {
        guard let der = PEMScanner.decodeBase64(Array(base64.utf8)[...], maximumDecodedBytes: 16_384),
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        return SecCertificateCopySubjectSummary(certificate) as String?
    }
}

/// One installable component named by a `Distribution` reference or a `PackageInfo` document.
struct InstallerPackageRecord: Equatable {
    var identifier: String
    var version: String?
    var installLocation: String?
    var installKilobytes: Int?
    var payloadFiles: Int?
    var scripts: [String] = []

    func summaryValue() -> SummaryValue {
        var fields = SummaryFields()
        fields.text("identifier", identifier)
        fields.text("version", version)
        fields.text("installLocation", installLocation)
        fields.number("installKilobytes", installKilobytes)
        fields.number("payloadFiles", payloadFiles)
        fields.list("scripts", scripts)
        return fields.value
    }
}

/// Facts read from `Distribution` or `PackageInfo`, two small XML documents with different roots.
struct InstallerMetadata: Equatable {
    enum Kind { case distribution, packageInfo }
    var title: String?
    var productVersion: String?
    var minimumOSVersion: String?
    var hostArchitectures: [String] = []
    var records: [InstallerPackageRecord] = []

    /// Fills the gaps of an existing record with the same identifier, or appends a new one.
    static func merge(_ record: InstallerPackageRecord, into records: inout [InstallerPackageRecord]) {
        guard let index = records.firstIndex(where: { $0.identifier == record.identifier }) else { records.append(record); return }
        records[index].version = records[index].version ?? record.version
        records[index].installLocation = records[index].installLocation ?? record.installLocation
        records[index].installKilobytes = records[index].installKilobytes ?? record.installKilobytes
        records[index].payloadFiles = records[index].payloadFiles ?? record.payloadFiles
        if records[index].scripts.isEmpty { records[index].scripts = record.scripts }
    }

    static func parse(_ data: Data, kind: Kind, context: RequestContext) throws -> InstallerMetadata {
        try context.checkpoint()
        // XMLParser can expand internal entities before its delegate sees them.
        let text = String(decoding: data, as: UTF8.self)
        guard !text.localizedCaseInsensitiveContains("<!DOCTYPE"), !text.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw PreviewFailure.unsupportedFormat
        }
        let reader = InstallerXMLReader(kind: kind, context: context)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        guard parser.parse(), reader.failure == nil else { throw reader.failure ?? .malformedDocument }
        return reader.metadata
    }
}

private final class InstallerXMLReader: NSObject, XMLParserDelegate {
    private static let maximumScripts = 16

    let kind: InstallerMetadata.Kind
    let context: RequestContext
    var failure: PreviewFailure?
    var metadata = InstallerMetadata()
    private var path: [String] = []
    private var characters = ""
    private var nodes = 0
    private var packageInfo: InstallerPackageRecord?

    init(kind: InstallerMetadata.Kind, context: RequestContext) {
        self.kind = kind
        self.context = context
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        do {
            try context.checkpoint()
            nodes += 1
            guard nodes <= context.budget.maxJSONNodes, path.count < context.budget.maxJSONDepth else { throw PreviewFailure.tooManyNodes }
            let parent = path.last
            path.append(elementName)
            characters = ""
            switch kind {
            case .distribution: distributionElement(elementName, attributes)
            case .packageInfo: packageInfoElement(elementName, parent: parent, attributes)
            }
        } catch { stop(parser, error: error) }
    }

    private func distributionElement(_ name: String, _ attributes: [String: String]) {
        switch name {
        case "product": metadata.productVersion = metadata.productVersion ?? nonEmpty(attributes["version"])
        case "options":
            if metadata.hostArchitectures.isEmpty, let list = attributes["hostArchitectures"] {
                metadata.hostArchitectures = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        case "os-version": metadata.minimumOSVersion = metadata.minimumOSVersion ?? nonEmpty(attributes["min"])
        case "pkg-ref":
            guard let identifier = nonEmpty(attributes["id"]) else { return }
            var record = InstallerPackageRecord(identifier: identifier)
            record.version = nonEmpty(attributes["version"])
            record.installKilobytes = attributes["installKBytes"].flatMap { Int($0) }
            InstallerMetadata.merge(record, into: &metadata.records)
        default: break
        }
    }

    private func packageInfoElement(_ name: String, parent: String?, _ attributes: [String: String]) {
        switch (name, parent) {
        case ("pkg-info", _):
            guard let identifier = nonEmpty(attributes["identifier"]) else { return }
            var record = InstallerPackageRecord(identifier: identifier)
            record.version = nonEmpty(attributes["version"])
            record.installLocation = nonEmpty(attributes["install-location"])
            packageInfo = record
        case ("payload", _):
            packageInfo?.payloadFiles = attributes["numberOfFiles"].flatMap { Int($0) }
            packageInfo?.installKilobytes = attributes["installKBytes"].flatMap { Int($0) }
        case (_, "scripts"):
            // Script file names only: the files themselves live in a separate archive member that is never read.
            guard packageInfo?.scripts.count ?? 0 < Self.maximumScripts, let file = nonEmpty(attributes["file"]) else { return }
            let name = (file as NSString).lastPathComponent
            if BundleDirectory.isPlainComponent(name) { packageInfo?.scripts.append(name) }
        default: break
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return PackageSummary.clipped(value, limit: 512)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard characters.utf8.count + string.utf8.count <= context.budget.maxLineUTF8Bytes else {
            stop(parser, error: PreviewFailure.outputTooLarge)
            return
        }
        characters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        do {
            try context.checkpoint()
            guard path.last == elementName else { throw PreviewFailure.malformedDocument }
            if kind == .distribution, elementName == "title", metadata.title == nil { metadata.title = nonEmpty(characters) }
            if kind == .packageInfo, elementName == "pkg-info", let record = packageInfo {
                metadata.records.append(record)
                packageInfo = nil
            }
            path.removeLast()
            characters = ""
        } catch { stop(parser, error: error) }
    }

    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
        stop(parser, error: PreviewFailure.unsupportedFormat)
    }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        stop(parser, error: PreviewFailure.unsupportedFormat)
    }
    private func stop(_ parser: XMLParser, error: any Error) {
        failure = error as? PreviewFailure ?? .deadlineExceeded
        parser.abortParsing()
    }
}

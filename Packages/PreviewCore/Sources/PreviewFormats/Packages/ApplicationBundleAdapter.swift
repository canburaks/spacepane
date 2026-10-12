import Foundation
import PreviewContracts

/// Summarizes a macOS application bundle: identity and version from `Info.plist`, the executable's
/// architectures, the embedded code signature (read, never validated) and the bundle's size.
///
/// The bundle is a directory, so this is a URL adapter with the directory read policy. It opens only
/// `Info.plist`, the first bytes of the main executable and one icon file, each through descriptor-relative,
/// non-following reads that draw on the request's input allowance. Nothing in the bundle is executed,
/// loaded, modified or extracted.
public struct ApplicationBundleAdapter: URLFormatAdapter {
    /// The most items the size walk visits before the summary is flagged partial.
    static let maximumWalkedItems = 25_000
    static let maximumWalkDepth = 32
    /// Share of the request deadline the size walk may spend; the signature lookup needs the rest.
    static let walkTimeShare = 0.35
    static let maximumInfoPropertyListBytes = 1_048_576
    static let maximumIconFileBytes = 2_097_152

    private let access: DirectoryReadAccess
    private let signatureReader: any CodeSignatureReader

    public init() { self.init(signatureReader: SecurityCodeSignatureReader()) }
    init(signatureReader: any CodeSignatureReader, access: DirectoryReadAccess = DirectoryReadAccess()) {
        self.signatureReader = signatureReader
        self.access = access
    }

    public func parse(url: URL, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard url.isFileURL else { throw PreviewFailure.unreadableFile }
        let started = ContinuousClock.now
        return try access.policy.withoutMaterializing {
            try parseMaterialized(url: url, context: context, started: started)
        }
    }

    private func parseMaterialized(url: URL, context: RequestContext, started: ContinuousClock.Instant) throws -> ParsedTextDocument {
        let bundle = try BundleDirectory(url: url, allowance: context.budget.maxInputBytes, access: access)
        // macOS bundles keep their manifest under Contents; flat (shallow) bundles keep it at the root.
        let layouts: [(root: [String], executables: [String], resources: [String])] = [
            (["Contents"], ["Contents", "MacOS"], ["Contents", "Resources"]),
            ([], [], [])
        ]
        var info: [String: Any]?
        var layout = layouts[0]
        for candidate in layouts {
            let read = try bundle.read(candidate.root + ["Info.plist"], limit: Self.maximumInfoPropertyListBytes,
                                       wholeFile: true, context: context)
            switch read {
            case .absent: continue
            case .tooLarge: throw PreviewFailure.inputTooLarge
            case .content(let data):
                info = try BoundedPropertyList.dictionary(data, context: context)
                layout = candidate
            }
            if info != nil { break }
        }
        guard let info else { throw PreviewFailure.malformedDocument }

        var fields = BundleInfoSummary.fields(info)
        if let machO = try executableSummary(info: info, bundle: bundle, folder: layout.executables, context: context) {
            fields.list("architectures", machO.architectures, limit: MachOHeader.maximumFatArchitectures)
            fields.text("executableKind", machO.layout.rawValue)
        }
        let icon = try iconImage(info: info, bundle: bundle, folder: layout.resources, context: context)

        let walkBudget = Double(context.budget.maxMilliseconds) * Self.walkTimeShare
        let measurement = try bundle.measure(maximumItems: Self.maximumWalkedItems, maximumDepth: Self.maximumWalkDepth,
                                             softDeadline: started.advanced(by: .milliseconds(Int(walkBudget))),
                                             context: context)
        fields.add("signature", try signatureReader.read(url: url, context: context).summaryValue())
        fields.number("bundleSize", measurement.bytes)
        fields.number("bundleItems", measurement.items)
        fields.flag("partial", measurement.isPartial)
        try bundle.requireAvailable()
        return try PackageSummary.document(fields.value, context: context, images: icon.map { [$0] } ?? [])
    }

    private func executableSummary(info: [String: Any], bundle: BundleDirectory, folder: [String],
                                   context: RequestContext) throws -> MachOSummary? {
        guard let name = PlistAccess.string(info, "CFBundleExecutable"), BundleDirectory.isPlainComponent(name) else { return nil }
        guard case .content(let header) = try bundle.read(folder + [name], limit: MachOHeader.prefixLength,
                                                          wholeFile: false, context: context) else { return nil }
        return MachOHeader.summary(of: header)
    }

    /// The `.icns` named by `CFBundleIconFile`. Asset-catalog icons live in a private format and are not read.
    private func iconImage(info: [String: Any], bundle: BundleDirectory, folder: [String],
                           context: RequestContext) throws -> PreviewImage? {
        guard let name = PlistAccess.string(info, "CFBundleIconFile"), BundleDirectory.isPlainComponent(name) else { return nil }
        let candidates = (name as NSString).pathExtension.isEmpty ? [name + ".icns"] : [name]
        for candidate in candidates {
            let read: BundleFileRead
            do { read = try bundle.read(folder + [candidate], limit: Self.maximumIconFileBytes, wholeFile: true, context: context) }
            // An icon larger than what remains of the input allowance is optional content: skip it.
            catch PreviewFailure.inputTooLarge { continue }
            guard case .content(let data) = read else { continue }
            if let image = try ICNSIcon.largestImage(in: data, context: context) { return image }
        }
        return nil
    }
}

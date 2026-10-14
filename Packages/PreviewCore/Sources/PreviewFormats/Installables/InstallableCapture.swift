import Foundation
import PreviewContracts

/// What the TAR listing keeps of a decoded archive for the install-time inspectors (decision 030).
///
/// The listing walks a TAR that is already decoded in memory and hands every regular member here. The
/// capture keeps two things, both bounded, and nothing else:
///
/// - the payloads of the few files an inspector reads (`package.json`, `pyproject.toml` directly inside
///   a top folder), by normalized path, each at most `maximumPayloadBytes`, at most `maximumPayloads`
///   of them and `maximumTotalBytes` together; a larger file is simply not kept and the inspector
///   sees it as absent;
/// - a native-code count (`NativeCodeTally`), which looks at no more than the first
///   `NativeCodeSignature.prefixLength` bytes of at most `NativeCodeTally.maximumMagicChecks` members.
///
/// Nothing in the archive is extracted, run or opened as a nested archive.
struct InstallableCapture {
    static let maximumPayloadBytes = 1_048_576
    static let maximumPayloads = 64
    static let maximumTotalBytes = 4_194_304
    /// Files that inspectors read when they sit directly inside the top folder.
    static let requestedNames = ["package.json", "pyproject.toml"]

    private(set) var payloads: [String: Data] = [:]
    private(set) var native = NativeCodeTally()
    private var keptBytes = 0

    /// Records one listed member. Anything that is not a regular file is ignored.
    mutating func observe(_ entry: ContainerEntry, payload: ArraySlice<UInt8>) {
        guard entry.kind == ContainerEntryKind.file.rawValue else { return }
        native.add(path: entry.path) { Data(payload.prefix(NativeCodeSignature.prefixLength)) }
        guard Self.requestedNames.contains(where: { entry.path.hasSuffix($0) }),
              let parts = InstallableLayout.components(of: entry.path), parts.count == 2,
              Self.requestedNames.contains(where: { parts[1].equalsExactly($0) }) else { return }
        let key = parts.joined(separator: "/")
        // A later member of the same name replaces the earlier one when the archive is unpacked.
        if let replaced = payloads.removeValue(forKey: key) { keptBytes -= replaced.count }
        guard payload.count <= Self.maximumPayloadBytes, payloads.count < Self.maximumPayloads,
              payload.count <= Self.maximumTotalBytes - keptBytes else { return }
        payloads[key] = Data(payload)
        keptBytes += payload.count
    }

    /// The install-time findings for the finished listing: those of the npm or Python inspector that
    /// recognizes the archive, and none for any other archive.
    func findings(for entries: [ContainerEntry], context: RequestContext) throws -> [PreviewFinding] {
        guard let layout = try InstallableLayout.find(in: entries, context: context) else { return [] }
        return try InstallableInspectors.findings(layout: layout, capture: self, context: context)
    }
}

import Foundation
import PreviewContracts

/// Invisible characters found in manifest strings and script members, counted the way the pipeline's
/// hidden-content scan counts them: one finding per kind, whose count is the number of characters. The
/// findings carry no lines and no decoded text, because a package is not a text file with a gutter.
struct AddOnHiddenTally {
    private var counts: [HiddenCharacterClass: Int] = [:]

    mutating func add(_ text: String, context: RequestContext) throws {
        for span in try HiddenCharacters.spans(in: text, checkpoint: context.checkpoint) {
            counts[span.kind, default: 0] += span.scalarCount
        }
    }

    var findings: [PreviewFinding] {
        HiddenCharacterClass.allCases.compactMap { characterClass in
            counts[characterClass].map { PreviewFinding(kind: Self.kind(characterClass), count: $0) }
        }
    }

    private static func kind(_ characterClass: HiddenCharacterClass) -> PreviewFindingKind {
        switch characterClass {
        case .bidirectionalControl: .hiddenBidirectionalControls
        case .zeroWidth: .hiddenZeroWidth
        case .tag: .hiddenUnicodeTags
        case .variationSelector: .hiddenVariationSelectors
        case .privateUse: .hiddenPrivateUse
        }
    }
}

extension AddOnArchive {
    /// Suffixes of members that are not machine code, so a content probe is not spent on them.
    private static let plainSuffixes: Set<String> = [
        "js", "mjs", "cjs", "ts", "json", "md", "txt", "map", "css", "html", "htm", "svg", "png", "jpg", "jpeg", "gif",
        "ico", "webp", "woff", "woff2", "ttf", "otf", "yml", "yaml", "xml", "py", "pyc", "pyi", "wasm", "lock"
    ]
    private static let scriptSuffixes: Set<String> = ["js", "mjs", "cjs", "ts", "py"]

    /// Paths of the members that are native code (decision 030, `artifact.nativeCode`): native libraries
    /// and add-ons by name, and any other member whose leading bytes are a Mach-O, ELF or Windows
    /// executable. At most `AddOnLimits.contentProbes` members are probed, each by reading one header.
    func nativeMembers() throws -> [String] {
        var native: [String] = []
        var probes = 0
        for entry in archive.entries {
            try context.checkpoint()
            guard entry.kind == "file", !entry.isEncrypted else { continue }
            if NativeCodeSignature.hasNativeSuffix(entry.path) { native.append(entry.path); continue }
            guard probes < AddOnLimits.contentProbes, entry.uncompressedSize >= AddOnLimits.smallestProbedMember,
                  !Self.plainSuffixes.contains(Self.suffix(of: entry.path)) else { continue }
            probes += 1
            let head = try Self.optional { try prefix(of: entry, limit: NativeCodeSignature.prefixLength) }
            if let head, NativeCodeSignature.isNativeBinary(prefix: head) { native.append(entry.path) }
        }
        return native
    }

    /// Adds the invisible characters of the leading bytes of at most `AddOnLimits.scriptMembers` script
    /// members, `preferred` paths first (the declared entry points) and then the package's own code
    /// before its `node_modules`, shallow before deep. Each member is read up to
    /// `AddOnLimits.scriptMemberBytes` and all of them together to `AddOnLimits.scriptTotalBytes`.
    func addScriptText(preferred: [String], to tally: inout AddOnHiddenTally) throws {
        var remaining = AddOnLimits.scriptTotalBytes
        for entry in scriptEntries(preferred: preferred).prefix(AddOnLimits.scriptMembers) {
            try context.checkpoint()
            guard remaining > 0 else { break }
            guard let data = try Self.optional({ try prefix(of: entry, limit: min(AddOnLimits.scriptMemberBytes, remaining)) }) else { continue }
            remaining -= data.count
            var text = String(decoding: data, as: UTF8.self)
            // A byte-order mark is how some editors start a file; it is not hidden text.
            if text.unicodeScalars.first?.value == 0xFEFF { text.unicodeScalars.removeFirst() }
            try tally.add(text, context: context)
        }
    }

    private func scriptEntries(preferred: [String]) -> [ZIPEntry] {
        var chosen: [ZIPEntry] = []
        var seen = Set<String>()
        for path in preferred {
            for candidate in AddOnPath.candidates(path) {
                guard let entry = archive.entry(at: candidate), Self.isScript(entry), seen.insert(entry.path).inserted else { continue }
                chosen.append(entry)
            }
        }
        let others = archive.entries.filter { Self.isScript($0) && !seen.contains($0.path) }.sorted { first, second in
            let (a, b) = (Self.rank(first.path), Self.rank(second.path))
            return a != b ? a < b : first.path < second.path
        }
        return chosen + others
    }

    private static func isScript(_ entry: ZIPEntry) -> Bool {
        entry.kind == "file" && !entry.isEncrypted && entry.uncompressedSize > 0
            && scriptSuffixes.contains(suffix(of: entry.path)) && !entry.path.lowercased().hasSuffix(".d.ts")
    }

    /// Code of the package itself sorts before its dependencies, and shallow before deep.
    private static func rank(_ path: String) -> Int {
        let parts = path.split(separator: "/")
        return (parts.contains("node_modules") ? 1_000_000 : 0) + parts.count
    }

    private static func suffix(of path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

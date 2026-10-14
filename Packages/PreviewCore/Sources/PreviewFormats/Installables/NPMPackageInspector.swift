import Foundation
import PreviewContracts

/// Install-time facts of an npm tarball (decision 030): what `npm install` of the package would run or
/// fetch, read from the tarball's `package.json`. The file is parsed with the strict, bounded JSON
/// cursor; scripts are never run, and their text is only handed to `ScriptEffectsLens`, which reads
/// without evaluating anything. Findings carry counts, never a script, a URL or a package name.
///
/// This lens would not have caught a compromise that puts its code in an ordinary module with no
/// install hook; it reports declared behaviour only.
enum NPMPackageInspector {
    /// Longest lifecycle script text analyzed. A longer script is analyzed up to this length.
    static let maximumScriptBytes = 65_536
    /// Longest dependency specification looked at.
    static let maximumSpecificationBytes = 1_024

    /// The scripts npm runs when a package is installed or prepared: the names `AutoRunRules` counts in a
    /// standalone package.json, so the tarball and its manifest agree.
    static let lifecycleScripts = ["preinstall", "install", "postinstall", "prepare", "preprepare", "postprepare"]

    struct Manifest {
        /// Non-empty lifecycle scripts by name; npm treats an empty script as absent.
        var scripts: [String: String] = [:]
        /// `"gypfile": false` stops npm from building a `binding.gyp` it finds.
        var disablesNativeBuild = false
        var remoteDependencies = 0
    }

    /// The findings for a tarball whose top folder holds a readable `package.json`, or `nil` when the
    /// tarball is not recognized as an npm package: no such file, one too large to have been kept, or one
    /// that is not a JSON object.
    static func findings(layout: InstallableLayout, capture: InstallableCapture,
                         context: RequestContext) throws -> [PreviewFinding]? {
        guard layout.has("package.json"), let data = capture.payloads[layout.path(of: "package.json")],
              let manifest = try manifest(data, context: context) else { return nil }
        var found: [PreviewFinding] = []
        if !manifest.scripts.isEmpty {
            found.append(PreviewFinding(kind: .autorunInstallScripts, count: manifest.scripts.count))
            found += try scriptFindings(manifest, context: context)
        }
        // With a binding.gyp and no install or preinstall script, npm runs `node-gyp rebuild` by itself.
        if layout.has("binding.gyp"), !manifest.disablesNativeBuild,
           manifest.scripts["install"] == nil, manifest.scripts["preinstall"] == nil {
            found.append(PreviewFinding(kind: .installNativeBuild, count: 1))
        }
        if manifest.remoteDependencies > 0 {
            found.append(PreviewFinding(kind: .installRemoteDependencies, count: manifest.remoteDependencies))
        }
        return found
    }

    // MARK: Scripts

    /// The `script.*` findings of the lifecycle scripts read as shell, each script on its own, as npm runs
    /// them. The lines the lens reports point into script text that is not on screen, so they are dropped.
    private static func scriptFindings(_ manifest: Manifest, context: RequestContext) throws -> [PreviewFinding] {
        let request = PreviewLensRequest(formatID: .sourceCode, fileName: "install.sh", sourceLanguage: .shell)
        var found: [PreviewFinding] = []
        for name in lifecycleScripts {
            guard let text = manifest.scripts[name] else { continue }
            for finding in try ScriptEffectsLens().findings(in: text, request: request, context: context)
            where finding.kind.rawValue.hasPrefix("script.") {
                found.append(PreviewFinding(kind: finding.kind, severity: finding.severity, count: finding.count))
            }
        }
        return PreviewFindings.normalized(found)
    }

    // MARK: Manifest

    static func manifest(_ data: Data, context: RequestContext) throws -> Manifest? {
        var reader = DataJSONReader(bytes: [UInt8](data), context: context)
        var manifest = Manifest()
        var remote: [String: Int] = [:]
        do {
            try reader.document { reader in
                guard try reader.peekKind() == .object else { throw PreviewFailure.malformedDocument }
                // Members are read in order and a repeated key replaces the earlier one, as `JSON.parse` does.
                try reader.forEachMember(depth: 1) { key, reader in
                    if key.equalsExactly("scripts") {
                        manifest.scripts = try readScripts(&reader)
                    } else if key.equalsExactly("dependencies") || key.equalsExactly("optionalDependencies") {
                        remote[key] = try countRemoteDependencies(&reader)
                    } else if key.equalsExactly("gypfile") {
                        if try reader.peekKind() == .boolean {
                            manifest.disablesNativeBuild = try !reader.boolean()
                        } else {
                            try reader.skipValue(depth: 2)
                            manifest.disablesNativeBuild = false
                        }
                    }
                }
            }
        } catch PreviewFailure.malformedDocument { return nil }
        catch PreviewFailure.structureTooDeep { return nil }
        manifest.remoteDependencies = remote.values.reduce(0, +)
        return manifest
    }

    private static func readScripts(_ reader: inout DataJSONReader) throws -> [String: String] {
        guard try reader.peekKind() == .object else {
            try reader.skipValue(depth: 2)
            return [:]
        }
        var scripts: [String: String] = [:]
        try reader.forEachMember(depth: 2) { name, reader in
            guard let lifecycle = lifecycleScripts.first(where: { name.equalsExactly($0) }),
                  try reader.peekKind() == .string else {
                try reader.skipValue(depth: 3)
                return
            }
            let text = try reader.string(maximumBytes: maximumScriptBytes).text
            scripts[lifecycle] = text.isEmpty ? nil : text
        }
        return scripts
    }

    private static func countRemoteDependencies(_ reader: inout DataJSONReader) throws -> Int {
        guard try reader.peekKind() == .object else {
            try reader.skipValue(depth: 2)
            return 0
        }
        var remote: Set<String> = []
        try reader.forEachMember(depth: 2) { name, reader in
            var isRemote = false
            if try reader.peekKind() == .string {
                isRemote = isRemoteSource(try reader.string(maximumBytes: maximumSpecificationBytes).text)
            } else {
                // A value that is not a string names no source.
                try reader.skipValue(depth: 3)
            }
            // A repeated name replaces the earlier entry.
            if isRemote { remote.insert(name) } else { remote.remove(name) }
        }
        return remote.count
    }

    // MARK: Dependency sources

    private static let remotePrefixes = ["git+", "git:", "github:", "gitlab:", "bitbucket:", "gist:", "http://", "https://"]

    /// Whether a dependency specification names a Git repository or a URL rather than a registry version:
    /// a Git or hosting-service scheme, an `http(s)` address, or the GitHub shorthand `owner/repo`, which
    /// may end in `#ref`. Registry ranges, tags, `npm:` aliases, `file:`, `link:` and `workspace:` are not.
    static func isRemoteSource(_ specification: String) -> Bool {
        let value = specification.trimmingCharacters(in: .whitespaces)
        let lowered = value.lowercased()
        return remotePrefixes.contains { lowered.hasPrefix($0) } || isGitHubShorthand(value)
    }

    /// `owner/repo` with the character rules of npm's hosted-Git parser: no scheme, scope, path prefix or
    /// version-range operator, exactly one slash, and nothing else that makes the text a path or a range.
    private static func isGitHubShorthand(_ value: String) -> Bool {
        let base = value.prefix(while: { $0 != "#" })
        let parts = base.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let first = parts[0].first, !parts[1].isEmpty else { return false }
        let forbidden: Set<Character> = [":", "@", "%"]
        let rangeOrPath: Set<Character> = [".", "-", "~", "^", "<", ">", "=", "*", "|"]
        guard !rangeOrPath.contains(first) else { return false }
        return base.allSatisfy { !$0.isWhitespace && !forbidden.contains($0) }
    }
}

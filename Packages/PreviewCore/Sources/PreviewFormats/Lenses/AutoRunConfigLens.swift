import Foundation
import PreviewContracts

/// Auto-run configuration lens: editor tasks that run when a folder opens, AI-agent hooks and permissions,
/// MCP servers, dev-container commands and package install scripts (decision 029).
///
/// These files make a tool run commands without the user starting them, so the lens states what the
/// file declares, how many times, and where. It does not say what a command does and never carries one.
///
/// Recognition is conservative: a file is read only when its name and its folder both belong to a tool
/// that reads it (`tasks.json` in `.vscode`, `settings.json` in `.claude`, `mcp.json` in `.cursor`, `hooks.json`
/// in `.cursor`), and a finding appears only for the structure that tool reads. A VS Code workspace file is
/// recognized by its `.code-workspace` suffix alone, because workspace names are free. The same text under
/// any other name or in any other folder says nothing. Names and folders compare ignoring ASCII case, as
/// macOS volumes do; the keys inside the file compare by code units.
///
/// The lens reads the displayed, concealed text through `LensJSON`, which accepts the comments and
/// trailing commas these files carry and the concealment token where a secret value stood.
public struct AutoRunConfigLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        try context.checkpoint()
        let roles = AutoRunRoles(fileName: request.fileName, folder: request.parentDirectoryName)
        guard !roles.isEmpty, let root = try LensJSON.parse(text, context: context), root.members != nil else { return [] }
        var tally = AutoRunTally()
        if roles.contains(.editorTasks) { AutoRunRules.editorTasks(root, into: &tally) }
        if roles.contains(.workspaceFile) { AutoRunRules.workspaceTasks(root, into: &tally) }
        if roles.contains(.cursorHooks) { AutoRunRules.cursorHooks(root, into: &tally) }
        if roles.contains(.agentSettings) { AutoRunRules.agentSettings(root, into: &tally) }
        if roles.contains(.servers) { AutoRunRules.servers(root, readsEditorKey: roles.contains(.editorServersKey), into: &tally) }
        if roles.contains(.devContainer) { AutoRunRules.devContainer(root, into: &tally) }
        if roles.contains(.packageManifest) { AutoRunRules.packageScripts(root, into: &tally) }
        return tally.findings
    }
}

/// What a file is to the tools that read it, from its name and folder alone.
struct AutoRunRoles: OptionSet {
    let rawValue: Int
    static let editorTasks = AutoRunRoles(rawValue: 1)
    static let agentSettings = AutoRunRoles(rawValue: 2)
    /// The file may declare MCP servers under `mcpServers`.
    static let servers = AutoRunRoles(rawValue: 4)
    /// VS Code's own `.vscode/mcp.json` keeps its servers under `servers`.
    static let editorServersKey = AutoRunRoles(rawValue: 8)
    static let devContainer = AutoRunRoles(rawValue: 16)
    static let packageManifest = AutoRunRoles(rawValue: 32)
    /// A VS Code workspace file (`*.code-workspace`, any folder): folder-open tasks under `tasks.tasks`.
    static let workspaceFile = AutoRunRoles(rawValue: 64)
    /// Cursor's `hooks.json` in a `.cursor` folder: commands under `hooks.<event>[]`.
    static let cursorHooks = AutoRunRoles(rawValue: 128)

    /// Folders whose `mcp.json` is an MCP configuration: Cursor, VS Code, Roo Code and Amazon Q.
    private static let mcpFolders = [".cursor", ".vscode", ".roo", ".amazonq"]

    init(rawValue: Int) { self.rawValue = rawValue }

    init(fileName: String, folder: String?) {
        let folder = folder ?? ""
        func isFile(_ name: String) -> Bool { fileName.equalsIgnoringASCIICase(name) }
        func isFolder(_ name: String) -> Bool { folder.equalsIgnoringASCIICase(name) }
        var roles: AutoRunRoles = []
        if isFile("tasks.json"), isFolder(".vscode") { roles.insert(.editorTasks) }
        if isFile("settings.json") || isFile("settings.local.json"), isFolder(".claude") { roles.formUnion([.agentSettings, .servers]) }
        if isFile(".mcp.json") || isFile("claude_desktop_config.json") { roles.insert(.servers) }
        if isFile("mcp.json"), Self.mcpFolders.contains(where: isFolder) {
            roles.insert(.servers)
            if isFolder(".vscode") { roles.insert(.editorServersKey) }
        }
        if isFile("settings.json"), isFolder(".gemini") { roles.insert(.servers) }
        if isFile("mcp_config.json"), isFolder("windsurf") { roles.insert(.servers) }
        if isFile("devcontainer.json") || isFile(".devcontainer.json") { roles.insert(.devContainer) }
        if isFile("package.json") { roles.insert(.packageManifest) }
        if fileName.hasSuffixIgnoringASCIICase(".code-workspace") { roles.insert(.workspaceFile) }
        if isFile("hooks.json"), isFolder(".cursor") { roles.insert(.cursorHooks) }
        self = roles
    }
}

/// Occurrences per kind: a count and the lines they sit on.
struct AutoRunTally {
    private var occurrences: [PreviewFindingKind: (count: Int, lines: [Int])] = [:]

    mutating func add(_ kind: PreviewFindingKind, count: Int = 1, line: Int) {
        var entry = occurrences[kind] ?? (0, [])
        entry.count += count
        entry.lines.append(line)
        occurrences[kind] = entry
    }

    /// One finding per kind found, in the contract's declaration order.
    var findings: [PreviewFinding] {
        PreviewFindingKind.allCases.compactMap { kind in
            occurrences[kind].map { PreviewFinding(kind: kind, count: $0.count, lines: $0.lines) }
        }
    }
}

extension String {
    /// Equality with ASCII letters folded; every other character must match exactly.
    func equalsIgnoringASCIICase(_ other: String) -> Bool {
        func folded(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
        return utf8.count == other.utf8.count && zip(utf8, other.utf8).allSatisfy { folded($0) == folded($1) }
    }

    /// Suffix equality with ASCII letters folded, as `equalsIgnoringASCIICase`.
    func hasSuffixIgnoringASCIICase(_ suffix: String) -> Bool {
        func folded(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
        let tail = utf8.suffix(suffix.utf8.count)
        return tail.count == suffix.utf8.count && zip(tail, suffix.utf8).allSatisfy { folded($0) == folded($1) }
    }
}

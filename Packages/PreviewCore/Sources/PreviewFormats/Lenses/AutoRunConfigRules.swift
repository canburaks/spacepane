import Foundation

/// The structure each tool reads, and the occurrences it makes. Every rule takes the root object of a file
/// whose name and folder already agree (`AutoRunRoles`) and adds to the tally; a value of another shape
/// than the tool expects adds nothing. Keys and enumerated values compare by code units.
enum AutoRunRules {
    // MARK: VS Code tasks

    /// A task whose `runOptions.runOn` is `folderOpen` starts when the folder is opened in the editor
    /// (once the user allows automatic tasks). The finding points at the `runOn` key.
    static func editorTasks(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        folderOpenTasks(root.member("tasks")?.value.elements ?? [], into: &tally)
    }

    /// A workspace file keeps its tasks one level down, as `tasks: { version, tasks: [...] }`; the same task
    /// rule applies to the inner list. A top-level array under `tasks` is not a workspace shape and adds nothing.
    static func workspaceTasks(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        folderOpenTasks(root.member("tasks")?.value.member("tasks")?.value.elements ?? [], into: &tally)
    }

    private static func folderOpenTasks(_ tasks: [LensJSONNode], into tally: inout AutoRunTally) {
        for task in tasks {
            guard let runOn = task.member("runOptions")?.value.member("runOn"), runOn.value.isString("folderOpen") else { continue }
            tally.add(.autorunFolderOpenTask, line: runOn.line)
        }
    }

    // MARK: Claude Code settings

    /// Hook commands (`hooks.<Event>[].hooks[]`) run around the agent's tool use; the broad permissions are
    /// bypass mode, every project MCP server, and an allow rule that grants every shell command.
    static func agentSettings(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        for event in root.member("hooks")?.value.members ?? [] {
            for group in event.value.elements ?? [] {
                for hook in group.member("hooks")?.value.elements ?? [] {
                    if let line = hookCommandLine(hook) { tally.add(.autorunAgentHooks, line: line) }
                }
            }
        }
        if let permissions = root.member("permissions")?.value {
            if let mode = permissions.member("defaultMode"), mode.value.isString("bypassPermissions") {
                tally.add(.autorunAgentPermissions, line: mode.line)
            }
            for rule in permissions.member("allow")?.value.elements ?? [] {
                if let text = rule.string, allowsEveryShellCommand(text) { tally.add(.autorunAgentPermissions, line: rule.line) }
            }
        }
        if let flag = root.member("enableAllProjectMcpServers"), flag.value.bool == true {
            tally.add(.autorunAgentPermissions, line: flag.line)
        }
    }

    /// A hook runs a command when its type is `command` or it carries a command; the line is the command's.
    private static func hookCommandLine(_ hook: LensJSONNode) -> Int? {
        let command = hook.member("command")
        let hasCommand = command?.value.hasContent == true
        guard hook.member("type")?.value.isString("command") == true || hasCommand else { return nil }
        return command?.line ?? hook.line
    }

    private static func allowsEveryShellCommand(_ rule: String) -> Bool {
        ["Bash", "Bash(*)", "Bash(:*)"].contains { rule.equalsExactly($0) }
    }

    // MARK: Cursor hooks

    /// Cursor's `hooks.json` maps each event (`beforeShellExecution`, `afterFileEdit`, ...) to a list of entries;
    /// an entry with a non-empty string `command` runs that command. Other keys, event names and entries
    /// (a prompt hook has no command) add nothing, and the file's `version` is not required.
    static func cursorHooks(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        for event in root.member("hooks")?.value.members ?? [] {
            for entry in event.value.elements ?? [] {
                guard let command = entry.member("command"), let text = command.value.string, !text.isEmpty else { continue }
                tally.add(.autorunAgentHooks, line: command.line)
            }
        }
    }

    // MARK: MCP servers

    private static let remoteTypes = ["sse", "http", "streamable-http"]
    private static let addressKeys = ["url", "serverUrl", "httpUrl"]

    /// Each server with a `command` starts a local process; each with an address, or declared as `sse`,
    /// `http` or `streamable-http`, connects to a remote one. The keys of every `env` object are counted
    /// together; their values are never read.
    static func servers(_ root: LensJSONNode, readsEditorKey: Bool, into tally: inout AutoRunTally) {
        servers(root, containers: readsEditorKey ? ["mcpServers", "servers"] : ["mcpServers"], into: &tally)
    }

    /// A workspace file's `settings.mcp` object holds servers in the shape of `.vscode/mcp.json`: a `servers`
    /// object with the same entries, read by the same rule.
    static func workspaceServers(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        guard let mcp = root.member("settings")?.value.member("mcp")?.value else { return }
        servers(mcp, containers: ["servers"], into: &tally)
    }

    private static func servers(_ root: LensJSONNode, containers: [String], into tally: inout AutoRunTally) {
        for container in containers {
            for server in root.member(container)?.value.members ?? [] where server.value.members != nil {
                let node = server.value
                // Claude Desktop, Cursor and VS Code skip a server marked `"disabled": true`; it neither starts nor connects.
                if node.member("disabled")?.value.bool == true { continue }
                var runs = false
                if let command = node.member("command"), command.value.hasContent {
                    tally.add(.autorunLocalServers, line: command.line)
                    runs = true
                }
                if let address = addressKeys.lazy.compactMap({ node.member($0) }).first(where: { $0.value.hasContent }) {
                    tally.add(.autorunRemoteServers, line: address.line)
                    runs = true
                } else if let type = node.member("type"), let name = type.value.string,
                          remoteTypes.contains(where: { name.equalsIgnoringASCIICase($0) }) {
                    tally.add(.autorunRemoteServers, line: type.line)
                    runs = true
                }
                // An entry that starts or reaches nothing has no environment worth reporting.
                if runs, let env = node.member("env"), let variables = env.value.members, !variables.isEmpty {
                    tally.add(.autorunServerEnvironment, count: variables.count, line: env.line)
                }
            }
        }
    }

    // MARK: Dev containers

    private static let containerCommands = [
        "onCreateCommand", "updateContentCommand", "postCreateCommand", "postStartCommand", "postAttachCommand"
    ]

    /// `initializeCommand` runs on the host before the container exists; the others run inside it.
    static func devContainer(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        if let host = root.member("initializeCommand"), host.value.hasContent {
            tally.add(.autorunHostCommand, line: host.line)
        }
        for name in containerCommands {
            if let command = root.member(name), command.value.hasContent { tally.add(.autorunContainerCommands, line: command.line) }
        }
    }

    // MARK: package.json

    /// The lifecycle scripts npm runs on install or prepare; the npm tarball inspector counts the same names.
    static let installScripts = ["preinstall", "install", "postinstall", "prepare", "preprepare", "postprepare"]

    /// Scripts the package manager runs when the package is installed or prepared.
    static func packageScripts(_ root: LensJSONNode, into tally: inout AutoRunTally) {
        for script in root.member("scripts")?.value.members ?? [] where installScripts.contains(where: { script.key.equalsExactly($0) }) {
            if script.value.string?.isEmpty == false || script.value.isConcealed { tally.add(.autorunInstallScripts, line: script.line) }
        }
    }
}

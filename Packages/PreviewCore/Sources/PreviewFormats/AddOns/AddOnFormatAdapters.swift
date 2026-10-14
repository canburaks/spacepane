import PreviewContracts

/// Explicit registrations for MCP bundles and for editor and browser extensions (decision 030). Each reads
/// its archive through the random-access path under the container-scan budget. `.xpi` and `.crx` share one
/// registration because they are one format: the adapter recognizes a CRX header by its content.
public enum AddOnFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .mcpBundle, defaultBudget: .containerScan, randomAccessAdapter: { MCPBundleAdapter() }),
        AdapterRegistration(formatID: .editorExtension, defaultBudget: .containerScan, randomAccessAdapter: { EditorExtensionAdapter() }),
        AdapterRegistration(formatID: .browserExtension, defaultBudget: .containerScan, randomAccessAdapter: { BrowserExtensionAdapter() })
    ]
}

import Foundation

/// Stable identities for the AI model, add-on and Python package formats of decision 030. The raw
/// values are persisted file-type preference keys; never derive them from a display name.
public extension FormatID {
    /// GGUF model files (`.gguf`), read from the header only.
    static let gguf = FormatID(rawValue: "ml.gguf")
    /// safetensors model files (`.safetensors`), read from the JSON header only.
    static let safetensors = FormatID(rawValue: "ml.safetensors")
    /// PyTorch checkpoints and Python pickles (`.pt`, `.pth`, `.ckpt`, `.pickle`, `.joblib`), scanned
    /// for what loading them would import; never loaded.
    static let pickle = FormatID(rawValue: "ml.pickle")
    /// MCP bundles (`.mcpb`, and the earlier `.dxt` name): a packaged local server for AI apps.
    static let mcpBundle = FormatID(rawValue: "package.mcp-bundle")
    /// Visual Studio Code extension packages (`.vsix`).
    static let editorExtension = FormatID(rawValue: "package.editor-extension")
    /// Browser extension packages (`.xpi`, `.crx`).
    static let browserExtension = FormatID(rawValue: "package.browser-extension")
    /// Python wheels (`.whl`).
    static let pythonWheel = FormatID(rawValue: "package.python-wheel")
}

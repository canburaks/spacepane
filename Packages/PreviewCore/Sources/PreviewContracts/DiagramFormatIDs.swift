import Foundation

/// Stable identifiers for the diagram family. They are persisted in file-type choices, so they
/// never change with branding or wording.
public extension FormatID {
    /// Mermaid source (`.mmd`, `.mermaid`). The renderer draws supported diagram types natively.
    static let mermaid = FormatID(rawValue: "text.mermaid")
    /// diagrams.net / draw.io documents (`.drawio`, `.dio`), compressed or plain `mxfile` XML.
    static let drawio = FormatID(rawValue: "data.drawio")
}

import Foundation

/// Stable identifiers for the markup-document family. They are persisted in preference
/// overrides, so the raw values never change with the display name or the suffix list.
public extension FormatID {
    static let latex = FormatID(rawValue: "text.latex")
    static let bibtex = FormatID(rawValue: "text.bibtex")
    static let asciidoc = FormatID(rawValue: "text.asciidoc")
    static let restructuredText = FormatID(rawValue: "text.restructuredtext")
    static let org = FormatID(rawValue: "text.org")
    static let fountain = FormatID(rawValue: "text.fountain")
}

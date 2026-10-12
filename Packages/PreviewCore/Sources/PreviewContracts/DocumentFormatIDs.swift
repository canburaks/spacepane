import Foundation

/// Stable identifiers for the ebook, comic and web-archive formats. They are persisted in
/// preferences, so their spelling never changes with the product's display name.
public extension FormatID {
    /// ZIP-packaged comic pages (`.cbz`).
    static let comicBook = FormatID(rawValue: "archive.comic-book")
    /// EPUB 2 and EPUB 3 packages.
    static let epub = FormatID(rawValue: "document.epub")
    /// FictionBook 2 XML (`.fb2`).
    static let fictionBook = FormatID(rawValue: "document.fictionbook")
    /// MIME HTML saved pages (`.mht`, `.mhtml`).
    static let webArchive = FormatID(rawValue: "document.web-archive")
}

import Foundation
import PreviewContracts

extension SafeMarkdownDocument {
    /// Native inert Markdown subset: headings (ATX and setext), nested ordered/bullet/task lists,
    /// quotes and GitHub alerts, thematic breaks, pipe tables, fenced code, footnotes, front matter,
    /// math (approximated in Unicode) and inline emphasis, code and links/images shown as text.
    /// HTML is literal; destinations never acquire link attributes and images never trigger
    /// file or network I/O. Returns nil beyond the input, output or decoration bounds.
    static func render(_ safeSource: String, maximumUTF16Units: Int = 262_144,
                       frontMatter: MarkdownFrontMatterStyle = .verbatim) -> Self? {
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max else { return nil }
        var limits = MarkupBuilder.Limits()
        limits.maximumUTF16Units = maximumUTF16Units
        return MarkdownRenderer.render(safeSource, limits: limits, frontMatter: frontMatter)
    }

    /// The Rendered document of a Markdown presentation. The format decides how the leading metadata block is
    /// shown: a file's own front matter as written, but the metadata that an ebook, FictionBook or web-archive
    /// adapter generated with localized labels and without its machine flags.
    static func render(_ presentation: TextPresentation, maximumUTF16Units: Int = 262_144) -> Self? {
        render(presentation.text, maximumUTF16Units: maximumUTF16Units,
               frontMatter: MarkdownFrontMatterStyle(formatID: presentation.formatID))
    }
}

extension MarkdownFrontMatterStyle {
    /// The style for the Markdown a format's presentation carries.
    init(formatID: FormatID) {
        self = DocumentPresentationNotices.documentFormats.contains(formatID) ? .generated : .verbatim
    }
}

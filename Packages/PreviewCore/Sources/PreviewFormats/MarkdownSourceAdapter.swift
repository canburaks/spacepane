import Foundation
import PreviewContracts

/// Markdown and its close relatives (`.mdx`, `.rmd`, `.qmd` and other suffixes) share this adapter.
/// Beyond the shared configuration rules, a leading YAML or TOML front-matter block is planned
/// on its own with the YAML/TOML rules, so block scalars and quoted keys in metadata are concealed
/// exactly as they would be in a configuration file without hiding the document that follows.
/// Embedded code, scripts and chunks are never run.
public struct MarkdownSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try MarkupPrivacyRanges.markdown(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .markdown)
    }
}

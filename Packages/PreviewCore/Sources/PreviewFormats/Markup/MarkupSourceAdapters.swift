import PreviewContracts

/// Adapters for the markup-document family. Each validates the shared input and line bounds,
/// plans syntax-specific concealment on top of the shared privacy stage and returns the text
/// unchanged with a syntax hint. The Rendered, Contents and References views are derived later
/// from the concealed text, so no adapter parses document structure and none follows
/// references (`\input`, `include::`, `.. include::`, `#+INCLUDE`) to other files.
///
/// The Markdown adapter itself stays in `MarkdownSourceAdapter.swift`, which also serves the
/// extra Markdown suffixes.

public struct LaTeXSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try ConfigurationPrivacyRanges.ranges(in: input.text, syntax: .environment, context: context)
            + MarkupPrivacyRanges.latex(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .latex)
    }
}

public struct BibTeXSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        // Field assignments (`name = {value}`) follow the configuration rules; comments between
        // entries fall to the shared assignment and credential-value policy.
        let ranges = try ConfigurationPrivacyRanges.ranges(in: input.text, syntax: .environment, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .bibtex)
    }
}

public struct AsciiDocSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try MarkupPrivacyRanges.asciidocComments(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .asciidoc)
    }
}

public struct ReStructuredTextSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try MarkupPrivacyRanges.restructuredText(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .restructuredText)
    }
}

public struct OrgSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try MarkupPrivacyRanges.org(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .orgMode)
    }
}

public struct FountainSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let ranges = try MarkupPrivacyRanges.fountainTitlePage(in: input.text, context: context)
        return ParsedTextDocument(text: input.text, sensitiveRanges: ranges, syntax: .fountain)
    }
}

/// One explicit registration per markup format; `StandardFormatAdapters` appends this list.
public enum MarkupFormatAdapters {
    public static let registrations: [AdapterRegistration] = [
        AdapterRegistration(formatID: .latex) { LaTeXSourceAdapter() },
        AdapterRegistration(formatID: .bibtex) { BibTeXSourceAdapter() },
        AdapterRegistration(formatID: .asciidoc) { AsciiDocSourceAdapter() },
        AdapterRegistration(formatID: .restructuredText) { ReStructuredTextSourceAdapter() },
        AdapterRegistration(formatID: .org) { OrgSourceAdapter() },
        AdapterRegistration(formatID: .fountain) { FountainSourceAdapter() }
    ]
}

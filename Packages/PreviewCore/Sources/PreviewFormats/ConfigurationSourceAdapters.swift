import PreviewContracts

/// Complex configuration syntax remains available as concealed source. The renderer offers
/// a node view only for its documented subset; no YAML alias expansion or TOML evaluation occurs.
public struct YAMLSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: try ConfigurationPrivacyRanges.ranges(in: input.text, syntax: .yaml, context: context),
                                  syntax: .yaml)
    }
}

public struct TOMLSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: try ConfigurationPrivacyRanges.ranges(in: input.text, syntax: .toml, context: context),
                                  syntax: .toml)
    }
}

public struct EnvironmentSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        // Generic assignment privacy deliberately handles ambiguous multiline values.
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: try ConfigurationPrivacyRanges.ranges(in: input.text, syntax: .environment, context: context),
                                  syntax: .environment)
    }
}

public struct DiffSourceAdapter: FormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        return ParsedTextDocument(text: input.text,
                                  sensitiveRanges: try ConfigurationPrivacyRanges.ranges(in: input.text, syntax: .diff, context: context),
                                  syntax: .diff)
    }
}

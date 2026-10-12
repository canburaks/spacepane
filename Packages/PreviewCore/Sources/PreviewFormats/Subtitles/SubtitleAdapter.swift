import PreviewContracts

/// Timed-caption source adapter for SubRip (`.srt`) and WebVTT (`.vtt`).
///
/// The adapter validates the file's block structure and then returns the exact decoded
/// source text. It never rewrites, normalizes or interprets cue text: markup tags, ASS
/// override blocks, STYLE sheets, REGION definitions and cue settings are inert characters.
/// The grammar and the malformed-document policy are documented on `SubtitleParser`.
///
/// Privacy: `usesStructuredPrivacy` stays `false`, so the shared heuristic also conceals the
/// remainder of any `key:`/`key=` assignment whose key names a secret, in cue text, headers
/// and timing lines alike. WebVTT `NOTE` comments are free text outside any field grammar, so
/// a comment block that contains such an assignment is concealed as a whole, matching how the
/// configuration adapters treat comments. This only adds concealment to the shared policy.
public struct SubtitleAdapter: FormatAdapter, TextInputPolicyProviding {
    public enum Variant: Sendable { case subRip, webVTT }
    let variant: Variant
    public init(variant: Variant) { self.variant = variant }
    /// Cues are blank-line separated blocks, so a file over the input budget ends after a complete block.
    public var textInputPolicy: TextInputPolicy { .leadingRecords(.blankLine) }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let outline = try SubtitleParser(bytes: Array(input.text.utf8), variant: variant, context: context).parse()
        try context.checkpoint()
        return ParsedTextDocument(text: input.text, sensitiveRanges: outline.commentRanges,
                                  usesStructuredPrivacy: false,
                                  syntax: variant == .subRip ? .subRip : .webVTT,
                                  sourceRecordCount: outline.cueCount)
    }
}

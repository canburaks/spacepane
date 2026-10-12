import PreviewContracts

/// CSV (RFC 4180) and TSV (IANA `text/tab-separated-values`) records with header-aware privacy.
///
/// The adapter validates source structure with the shared `DelimitedRecords` grammar and returns the
/// exact decoded characters plus precise sensitive cell ranges. It never evaluates formulas, follows
/// links, coerces numbers/dates or resolves anything: every cell keeps its source spelling. A
/// structural failure (unterminated quote, stray quote, data after a closing quote) throws
/// `PreviewFailure.malformedDocument`; column-based concealment cannot be trusted on a guessed
/// structure, so there is deliberately no fallback to unconcealed source.
///
/// Bounds come from the request budget: records <= `maxTextLines`, fields per record and concealed
/// cells <= `maxJSONNodes` (the same ceiling the privacy filter applies to ranges), one field's raw
/// span <= `maxLineUTF8Bytes`, plus the shared input/output/line checks and cooperative checkpoints.
public struct DelimitedTextAdapter: FormatAdapter {
    public typealias Dialect = DelimitedRecords.Dialect
    let dialect: Dialect
    public init(dialect: Dialect) { self.dialect = dialect }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        let bytes = Array(input.text.utf8)
        let limits = DelimitedRecords.Limits(maxRecords: context.budget.maxTextLines,
                                             maxFieldsPerRecord: context.budget.maxJSONNodes,
                                             maxFieldBytes: context.budget.maxLineUTF8Bytes)
        var planner = try DelimitedPrivacyPlanner(bytes: bytes, maxRanges: context.budget.maxJSONNodes, context: context)
        var recordCount = 0
        var columnCount = 0
        _ = try DelimitedRecords.scan(bytes, dialect: dialect, limits: limits,
                                      checkpoint: { try context.checkpoint() }) { record, fields in
            try planner.consume(record: record, fields: fields)
            let (next, overflow) = recordCount.addingReportingOverflow(1)
            guard !overflow else { throw PreviewFailure.tooManyLines }
            recordCount = next
            columnCount = max(columnCount, fields.count)
            return .proceed
        }
        try context.checkpoint()
        return ParsedTextDocument(text: input.text, sensitiveRanges: planner.ranges, usesStructuredPrivacy: true,
                                  syntax: dialect == .comma ? .commaSeparated : .tabSeparated,
                                  facts: columnCount == 0 ? .none : PresentationFacts([
                                    .grid(rows: max(0, recordCount - 1), columns: columnCount, rowsAreLowerBound: false)
                                  ]))
    }
}

import PreviewContracts

/// Strict source validation by default; optional record recovery conceals damaged records completely.
/// UTF-8, LF/CRLF and an optional final newline are supported; blank records and BOMs are not.
public struct JSONLinesAdapter: FormatAdapter, TextInputPolicyProviding {
    private let allowsMalformedRecords: Bool
    public init(allowsMalformedRecords: Bool = false) { self.allowsMalformedRecords = allowsMalformedRecords }
    /// Records are independent lines, so a file over the input budget shows its leading complete records.
    public var textInputPolicy: TextInputPolicy { .leadingRecords(.line) }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.encoding == .utf8 else { throw PreviewFailure.unsupportedEncoding }
        guard !input.hasByteOrderMark, input.text.unicodeScalars.first?.value != 0xFEFF else {
            throw PreviewFailure.malformedDocument
        }
        let count = input.text.utf8.count
        guard input.byteCount <= context.budget.maxInputBytes, count <= context.budget.maxInputBytes else {
            throw PreviewFailure.inputTooLarge
        }
        guard count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        guard count > 0 else { throw PreviewFailure.malformedDocument }
        let bytes = Array(input.text.utf8)
        var scanner = JSONScanner(bytes: bytes, context: context)
        var start = 0
        var records = 0
        var invalidRecordLines: [Int] = []
        while start < bytes.count {
            try context.checkpoint()
            records += 1
            guard records <= context.budget.maxTextLines else { throw PreviewFailure.tooManyLines }
            var end = start
            while end < bytes.count, bytes[end] != 10 {
                if (end - start).isMultiple(of: 512) { try context.checkpoint() }
                end += 1
            }
            let contentEnd = end > start && bytes[end - 1] == 13 ? end - 1 : end
            guard contentEnd - start <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
            do { try scanner.scan(start..<end) }
            catch PreviewFailure.malformedDocument {
                guard allowsMalformedRecords else { throw PreviewFailure.malformedDocument }
                // A damaged record can contain escaped sensitive keys. Conceal the entire
                // record, instead of relying on a best-effort assignment regex.
                scanner.sensitiveRanges.append(.init(utf8Range: start..<contentEnd))
                invalidRecordLines.append(records)
            }
            start = end < bytes.count ? end + 1 : end
        }
        try context.checkpoint()
        return ParsedTextDocument(text: input.text, sensitiveRanges: scanner.sensitiveRanges,
                                  usesStructuredPrivacy: true, syntax: .json, invalidRecordLines: invalidRecordLines, sourceRecordCount: records)
    }
}

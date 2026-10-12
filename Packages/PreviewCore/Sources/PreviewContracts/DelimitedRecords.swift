/// One pure, bounded and cancellable record/field scanner for delimiter-separated text.
///
/// The format adapter scans raw source to decide what to conceal; the renderer scans the
/// already-concealed safe text to build its table. Both must agree on record and column
/// boundaries, otherwise a concealed column could shift in the view. They therefore share
/// this single grammar instead of two look-alike parsers.
///
/// Grammar (UTF-8 bytes; delimiters, quotes and terminators are all ASCII):
/// - A record ends at LF, CRLF or a bare CR outside quotes. A terminator right before the end
///   of input does not start another record; a blank line in the middle is one empty field.
/// - **Comma** follows RFC 4180: a field is quoted only when its first byte is `"`. Inside, `""`
///   is one literal quote and delimiters, CR and LF are data. The closing quote must be followed
///   by a delimiter, a record terminator or the end of input. A quote inside an unquoted field
///   (RFC 4180 section 2, rule 5), data after a closing quote and an unterminated quoted field
///   are all malformed. Column-based concealment needs reliable field boundaries, so a
///   structural error throws instead of guessing.
/// - **Tab** follows IANA `text/tab-separated-values`: one record per line and no quoting, so
///   quotes are literal data. Spreadsheet exporters sometimes add RFC-style quotes around fields
///   with embedded tabs or line breaks, which that registration does not define. A field that
///   begins with `"` and holds an odd number of quotes can be the first piece of such a field,
///   so it is rejected as malformed rather than split into misaligned columns.
/// - A leading U+FEFF is an encoding mark, never data; offsets still index the original bytes.
/// - Spellings are exact: no trimming, number/date conversion or formula evaluation.
public enum DelimitedRecords {
    public enum Dialect: Sendable, Equatable {
        case comma, tab

        public var delimiter: UInt8 { self == .comma ? 0x2C : 0x09 }
    }

    /// Hard bounds enforced while scanning, before any per-field storage grows.
    public struct Limits: Sendable, Equatable {
        public var maxRecords: Int
        public var maxFieldsPerRecord: Int
        /// Raw field span in bytes, including enclosing quotes and embedded line breaks.
        public var maxFieldBytes: Int
        public init(maxRecords: Int, maxFieldsPerRecord: Int, maxFieldBytes: Int) {
            self.maxRecords = maxRecords
            self.maxFieldsPerRecord = maxFieldsPerRecord
            self.maxFieldBytes = maxFieldBytes
        }
    }

    public struct Field: Sendable, Equatable {
        public let column: Int
        /// Byte range including enclosing quotes. Replacing exactly this range keeps the shape.
        public let raw: Range<Int>
        /// Bytes between the enclosing quotes (or the whole field). Doubled quotes are not collapsed.
        public let content: Range<Int>
        public let isQuoted: Bool
        public let hasEscapedQuotes: Bool
    }

    public enum Control: Sendable { case proceed, stop }

    public struct Summary: Sendable, Equatable {
        public let recordCount: Int
        /// True when the visitor stopped while input remained unscanned.
        public let stoppedEarly: Bool
    }

    private static let quote: UInt8 = 0x22
    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
    private static let checkpointInterval = 1_024

    /// Visits each record with its fields. The field array is reused between records; copy what
    /// must outlive the callback. Throws `PreviewFailure` for structure/limit failures and rethrows
    /// whatever `checkpoint` throws (cancellation or an expired deadline).
    public static func scan(_ bytes: [UInt8], dialect: Dialect, limits: Limits,
                            checkpoint: () throws -> Void,
                            visit: (_ record: Int, _ fields: [Field]) throws -> Control) throws -> Summary {
        try checkpoint()
        let count = bytes.count
        let delimiter = dialect.delimiter
        var index = count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0
        guard index < count else { return Summary(recordCount: 0, stoppedEarly: false) }
        var fields: [Field] = []
        var record = 0
        var checkpointIndex = index
        while true {
            guard record < limits.maxRecords else { throw PreviewFailure.tooManyLines }
            fields.removeAll(keepingCapacity: true)
            var reachedEnd = false
            fieldLoop: while true {
                guard fields.count < limits.maxFieldsPerRecord else { throw PreviewFailure.tooManyNodes }
                let start = index
                let content: Range<Int>
                var isQuoted = false
                var hasEscapedQuotes = false
                if dialect == .comma, index < count, bytes[index] == quote {
                    isQuoted = true
                    index += 1
                    let contentStart = index
                    while true {
                        guard index < count else { throw PreviewFailure.malformedDocument }
                        if index &- start > limits.maxFieldBytes { throw PreviewFailure.lineTooLong }
                        if index &- checkpointIndex >= checkpointInterval { try checkpoint(); checkpointIndex = index }
                        if bytes[index] == quote {
                            if index + 1 < count, bytes[index + 1] == quote {
                                hasEscapedQuotes = true
                                index += 2
                            } else { break }
                        } else { index += 1 }
                    }
                    content = contentStart..<index
                    index += 1 // closing quote
                    if index < count, bytes[index] != delimiter, bytes[index] != lineFeed, bytes[index] != carriageReturn {
                        throw PreviewFailure.malformedDocument
                    }
                } else {
                    var quotes = 0
                    while index < count {
                        let byte = bytes[index]
                        if byte == delimiter || byte == lineFeed || byte == carriageReturn { break }
                        if byte == quote {
                            // Comma: a quote may not appear in an unquoted field.
                            if dialect == .comma { throw PreviewFailure.malformedDocument }
                            quotes += 1
                        }
                        index += 1
                        if index &- start > limits.maxFieldBytes { throw PreviewFailure.lineTooLong }
                        if index &- checkpointIndex >= checkpointInterval { try checkpoint(); checkpointIndex = index }
                    }
                    if dialect == .tab, index > start, bytes[start] == quote, !quotes.isMultiple(of: 2) {
                        throw PreviewFailure.malformedDocument
                    }
                    content = start..<index
                }
                if index &- start > limits.maxFieldBytes { throw PreviewFailure.lineTooLong }
                fields.append(Field(column: fields.count, raw: start..<index, content: content,
                                    isQuoted: isQuoted, hasEscapedQuotes: hasEscapedQuotes))
                guard index < count else { reachedEnd = true; break fieldLoop }
                let terminator = bytes[index]
                index += 1
                if terminator == delimiter { continue fieldLoop }
                if terminator == carriageReturn, index < count, bytes[index] == lineFeed { index += 1 }
                break fieldLoop
            }
            let control = try visit(record, fields)
            record += 1
            if control == .stop {
                return Summary(recordCount: record, stoppedEarly: !reachedEnd && index < count)
            }
            if reachedEnd || index >= count { break }
        }
        try checkpoint()
        return Summary(recordCount: record, stoppedEarly: false)
    }

    /// The decoded value: enclosing quotes removed and doubled quotes collapsed.
    public static func text(of field: Field, in bytes: [UInt8]) -> String {
        let slice = bytes[field.content]
        guard field.hasEscapedQuotes else { return String(decoding: slice, as: UTF8.self) }
        var decoded: [UInt8] = []
        decoded.reserveCapacity(slice.count)
        var index = slice.startIndex
        while index < slice.endIndex {
            let byte = slice[index]
            decoded.append(byte)
            // The scan guarantees every quote inside a quoted field is the first of a pair.
            index += byte == quote ? 2 : 1
        }
        return String(decoding: decoded, as: UTF8.self)
    }
}

import Foundation
import PreviewContracts

/// Validates bounded JSON syntax without converting numbers or deduplicating keys.
/// Privacy annotations are applied before the renderer can build a safe source outline.
///
/// A document with a line longer than the line budget (minified JSON) is not refused: after the same
/// strict validation it is shown pretty-printed from its token stream (`JSONReformatter`), with key
/// order, number lexemes, string escapes and structural concealment unchanged, and the presentation is
/// marked as reformatted. Documents whose lines already fit are shown exactly as written. The adapter
/// declares `allowsLongLines` so the shared decoder leaves that decision to it; the budget is still
/// applied to the formatted text, so a single over-long string value still fails with `lineTooLong`.
public struct JSONSourceAdapter: FormatAdapter, TextInputPolicyProviding {
    public init() {}
    public var textInputPolicy: TextInputPolicy { TextInputPolicy(allowsLongLines: true) }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        var needsFormatting = false
        do { try ExpandedTextLimits.validate(input, context: context) }
        catch PreviewFailure.lineTooLong { needsFormatting = true }
        let bytes = Array(input.text.utf8)
        var scanner = JSONScanner(bytes: bytes, context: context, tracksRootRecordFacts: true)
        try scanner.scan()
        guard needsFormatting else {
            return ParsedTextDocument(text: input.text, sensitiveRanges: scanner.sensitiveRanges,
                                      usesStructuredPrivacy: true, syntax: .json, facts: scanner.recordFacts)
        }
        let formatted = try JSONReformatter.format(bytes, sensitiveRanges: scanner.sensitiveRanges, context: context)
        try Self.validateFormattedLines(formatted.text, context: context)
        return ParsedTextDocument(text: formatted.text, sensitiveRanges: formatted.sensitiveRanges,
                                  usesStructuredPrivacy: true, syntax: .json, isReformatted: true, origin: .reformatted,
                                  facts: scanner.recordFacts)
    }

    /// The input checks of `ExpandedTextLimits`, for text that is legitimately larger than the input
    /// budget: only the line count and line length apply (output size is checked while formatting).
    private static func validateFormattedLines(_ text: String, context: RequestContext) throws {
        var lines = 1
        var lineBytes = 0
        var previousCR = false
        for (index, byte) in text.utf8.enumerated() {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            if byte == 10 || byte == 13 {
                if byte != 10 || !previousCR { lines += 1 }
                guard lines <= context.budget.maxTextLines else { throw PreviewFailure.tooManyLines }
                lineBytes = 0
            } else {
                lineBytes += 1
                guard lineBytes <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
            }
            previousCR = byte == 13
        }
        try context.checkpoint()
    }
}

/// Shared request-local scanner. Record ranges retain absolute source offsets and
/// one cumulative node count; no per-record parse can reset the work budget.
struct JSONScanner {
    let bytes: [UInt8]
    let context: RequestContext
    var position = 0
    private var limit = 0
    private var checkpointPosition = 0
    var nodes = 0
    var sensitiveRanges: [SensitiveRange] = []
    private var sensitiveOffsets: Set<Range<Int>> = []
    private var rootRecords: JSONRootRecordFacts?

    init(bytes: [UInt8], context: RequestContext, tracksRootRecordFacts: Bool = false) {
        self.bytes = bytes
        self.context = context
        limit = bytes.count
        rootRecords = tracksRootRecordFacts ? JSONRootRecordFacts() : nil
    }

    var recordFacts: PresentationFacts { rootRecords?.facts ?? .none }

    mutating func scan(_ range: Range<Int>? = nil) throws {
        try context.checkpoint()
        if rootRecords != nil { rootRecords = JSONRootRecordFacts() }
        let range = range ?? 0..<bytes.count
        position = range.lowerBound
        limit = range.upperBound
        checkpointPosition = position
        try skipWhitespace()
        try value(depth: 1)
        try skipWhitespace()
        guard position == limit else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
    }

    private mutating func addSensitive(_ range: Range<Int>) throws {
        if sensitiveOffsets.contains(range) { return }
        guard sensitiveRanges.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        sensitiveOffsets.insert(range)
        sensitiveRanges.append(.init(utf8Range: range))
    }

    @discardableResult
    mutating func value(depth: Int, decodeString: Bool = false) throws -> String? {
        try context.checkpoint()
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        nodes += 1
        guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        guard let byte = current else { throw PreviewFailure.malformedDocument }
        switch byte {
        case 123: try object(depth: depth)
        case 91: try array(depth: depth)
        case 34: return try string(decodeKey: false, decodeValue: decodeString)
        case 116: try literal([116, 114, 117, 101])
        case 102: try literal([102, 97, 108, 115, 101])
        case 110: try literal([110, 117, 108, 108])
        case 45, 48...57: try number()
        default: throw PreviewFailure.malformedDocument
        }
        return nil
    }

    mutating func object(depth: Int) throws {
        position += 1
        try skipWhitespace()
        if take(125) { return }
        let isTrackedRecord = depth == 2 && rootRecords?.acceptsKeys == true
        var keysInRecord: Set<[UInt16]>? = isTrackedRecord ? [] : nil
        var hasSensitiveName = false
        var namedValues: [Range<Int>] = []
        while true {
            let key = try string(decodeKey: true) ?? ""
            if isTrackedRecord, rootRecords?.acceptsKeys == true {
                // Swift String equality coalesces canonically equivalent spellings. JSON keys
                // must instead match the exact decoded code units, including escaped duplicates.
                let units = Array(key.utf16)
                if keysInRecord?.contains(units) != false || keysInRecord?.count == JSONRootRecordFacts.maximumKeys {
                    rootRecords?.discardColumns()
                } else {
                    keysInRecord?.insert(units)
                    rootRecords?.includeKey(units)
                }
                if rootRecords?.acceptsKeys != true { keysInRecord = nil }
            }
            try skipWhitespace()
            guard take(58) else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
            let start = position
            let role = SecretFieldPolicy.namedValueRole(key)
            let decoded = try value(depth: depth + 1, decodeString: role == .name)
            if role == .name, let decoded, SecretFieldPolicy.isSensitive(decoded) { hasSensitiveName = true }
            if role == .value { namedValues.append(start..<position) }
            if SecretFieldPolicy.isSensitive(key) {
                try addSensitive(start..<position)
            }
            try skipWhitespace()
            if take(125) { break }
            guard take(44) else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
        }
        if hasSensitiveName { for range in namedValues { try addSensitive(range) } }
    }

    mutating func array(depth: Int) throws {
        let isTrackedRoot = depth == 1 && rootRecords != nil
        if isTrackedRoot { rootRecords?.beginRootArray() }
        position += 1
        try skipWhitespace()
        if take(93) { return }
        while true {
            if isTrackedRoot {
                if current == 123 { try rootRecords?.appendRecord() }
                else { rootRecords?.invalidateRecordArray() }
            }
            try value(depth: depth + 1)
            try skipWhitespace()
            if take(93) { return }
            guard take(44) else { throw PreviewFailure.malformedDocument }
            try skipWhitespace()
        }
    }

    mutating func string(decodeKey: Bool, decodeValue: Bool = false) throws -> String? {
        let start = position
        var escapedValue = false
        guard take(34) else { throw PreviewFailure.malformedDocument }
        while let byte = current {
            try checkpointProgress()
            if byte == 34 {
                position += 1
                if !decodeKey && !decodeValue && !escapedValue { return nil }
                guard let decoded = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<position])) else {
                    throw PreviewFailure.malformedDocument
                }
                if !decodeKey, escapedValue, try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded, originalText: String(decoding: bytes[start..<position], as: UTF8.self), context: context) {
                    try addSensitive(start..<position)
                }
                return decodeKey || decodeValue ? decoded : nil
            }
            guard byte >= 32 else { throw PreviewFailure.malformedDocument }
            position += 1
            if byte == 92 {
                escapedValue = true
                guard let escaped = current else { throw PreviewFailure.malformedDocument }
                position += 1
                switch escaped {
                case 34, 92, 47, 98, 102, 110, 114, 116: break
                case 117:
                    let unit = try unicodeUnit()
                    if (0xD800...0xDBFF).contains(unit) {
                        guard take(92), take(117) else { throw PreviewFailure.malformedDocument }
                        let low = try unicodeUnit()
                        guard (0xDC00...0xDFFF).contains(low) else { throw PreviewFailure.malformedDocument }
                    } else if (0xDC00...0xDFFF).contains(unit) { throw PreviewFailure.malformedDocument }
                default: throw PreviewFailure.malformedDocument
                }
            }
        }
        throw PreviewFailure.malformedDocument
    }

    mutating func unicodeUnit() throws -> UInt16 {
        var result: UInt16 = 0
        for _ in 0..<4 {
            guard let byte = current else { throw PreviewFailure.malformedDocument }
            let digit: UInt16
            switch byte {
            case 48...57: digit = UInt16(byte - 48)
            case 65...70: digit = UInt16(byte - 55)
            case 97...102: digit = UInt16(byte - 87)
            default: throw PreviewFailure.malformedDocument
            }
            result = result * 16 + digit
            position += 1
        }
        return result
    }

    mutating func number() throws {
        _ = take(45)
        if !take(48) {
            guard let byte = current, (49...57).contains(byte) else { throw PreviewFailure.malformedDocument }
            position += 1
            try consumeDigits()
        }
        if take(46) {
            guard let byte = current, (48...57).contains(byte) else { throw PreviewFailure.malformedDocument }
            try consumeDigits()
        }
        if take(101) || take(69) {
            if !take(43) { _ = take(45) }
            guard let byte = current, (48...57).contains(byte) else { throw PreviewFailure.malformedDocument }
            try consumeDigits()
        }
    }

    mutating func literal(_ expected: [UInt8]) throws {
        guard limit - position >= expected.count,
              Array(bytes[position..<(position + expected.count)]) == expected else { throw PreviewFailure.malformedDocument }
        position += expected.count
    }

    mutating func consumeDigits() throws {
        while let byte = current, (48...57).contains(byte) {
            try checkpointProgress()
            position += 1
        }
    }
    mutating func skipWhitespace() throws {
        while let byte = current, [9, 10, 13, 32].contains(byte) {
            try checkpointProgress()
            position += 1
        }
    }
    private mutating func checkpointProgress() throws {
        if position - checkpointPosition >= 512 {
            try context.checkpoint()
            checkpointPosition = position
        }
    }
    mutating func take(_ byte: UInt8) -> Bool {
        guard current == byte else { return false }
        position += 1
        return true
    }
    var current: UInt8? { position < limit ? bytes[position] : nil }
}

/// Request-local accounting from the existing grammar scan. It keeps no values or exported key
/// strings, retains at most 256 exact decoded keys, and never turns an ambiguous schema into a grid.
private struct JSONRootRecordFacts {
    static let maximumKeys = 256
    private var isRootArray = false
    private var isRecordArray = true
    private var records = 0
    private var columns: Set<[UInt16]>? = []

    var acceptsKeys: Bool { isRootArray && isRecordArray && columns != nil }

    mutating func beginRootArray() { isRootArray = true }

    mutating func appendRecord() throws {
        guard isRecordArray else { return }
        let (count, overflow) = records.addingReportingOverflow(1)
        guard !overflow else { throw PreviewFailure.tooManyNodes }
        records = count
    }

    mutating func includeKey(_ key: [UInt16]) {
        guard let count = columns?.count else { return }
        if columns?.contains(key) == true { return }
        guard count < Self.maximumKeys else { discardColumns(); return }
        columns?.insert(key)
    }

    mutating func discardColumns() { columns = nil }

    mutating func invalidateRecordArray() {
        isRecordArray = false
        discardColumns()
    }

    var facts: PresentationFacts {
        guard isRootArray, isRecordArray, records > 0 else { return .none }
        guard let count = columns?.count, count > 0 else { return PresentationFacts([.records(records, .records)]) }
        return PresentationFacts([.grid(rows: records, columns: count, rowsAreLowerBound: false)])
    }
}

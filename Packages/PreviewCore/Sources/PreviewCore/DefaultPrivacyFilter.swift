import Foundation
import PreviewContracts

public struct DefaultPrivacyFilter: PreviewPrivacyFiltering {
    public init() {}

    /// Progress callbacks arrive once per candidate start position. Reading the clock on each
    /// one dominated the scan, so cancellation and the deadline are rechecked every 1,024th
    /// progress event and on every match. Per-pattern and per-offset checkpoints are unchanged.
    private static let progressCheckpointMask = 0x3FF

    /// The range merge and the forward concealment pass recheck cancellation and the deadline every 256th
    /// range, so a file made of very many short secrets stays interruptible at the cost of one clock read
    /// per 256 replacements.
    private static let rangeCheckpointMask = 0xFF

    /// What produced a concealed range, for the inventory of kinds. Declaration order is precedence:
    /// when ranges merge, the most specific source names the merged range. Never carries a value.
    private enum RangeSource: Int, CaseIterable, Comparable {
        case sensitiveField, authorizationHeader, webToken, apiKey, codeHostingToken, cloudAccessKey, privateKey

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

        init?(findingKind: PreviewFindingKind) {
            switch findingKind {
            case .secretSensitiveField: self = .sensitiveField
            case .secretAuthorizationHeader: self = .authorizationHeader
            case .secretWebToken: self = .webToken
            case .secretAPIKey: self = .apiKey
            case .secretCodeHostingToken: self = .codeHostingToken
            case .secretCloudAccessKey: self = .cloudAccessKey
            case .secretPrivateKey: self = .privateKey
            default: return nil
            }
        }

        var findingKind: PreviewFindingKind {
            switch self {
            case .sensitiveField: .secretSensitiveField
            case .authorizationHeader: .secretAuthorizationHeader
            case .webToken: .secretWebToken
            case .apiKey: .secretAPIKey
            case .codeHostingToken: .secretCodeHostingToken
            case .cloudAccessKey: .secretCloudAccessKey
            case .privateKey: .secretPrivateKey
            }
        }
    }

    private struct SourcedRange {
        var range: NSRange
        var source: RangeSource
    }

    /// Counts the filter's own matches (assignment tails and value patterns) against the request's node budget,
    /// as an adapter's ranges are counted. The match that exceeds the budget ends the scan that found it, and the
    /// caller then conceals the whole text, the safe answer the adapters give for the same case. An adapter's own
    /// ranges are not counted here; `filter` already refuses more of those than the budget allows.
    private struct OwnMatchLimit {
        let maximum: Int
        private var count = 0

        init(maximum: Int) { self.maximum = maximum }

        var isExceeded: Bool { count > maximum }
        var remaining: Int { max(0, maximum - count) }

        /// Records one match; false once the budget is exceeded, which stops the scan that found it.
        mutating func accept() -> Bool {
            count += 1
            return count <= maximum
        }
    }


    /// Replaces each concealed range. Its UTF-16 length also locates replacements in the safe text.
    private static let concealmentToken = SecretFieldPolicy.concealmentToken
    private static let concealmentTokenUnits = Array(SecretFieldPolicy.concealmentToken.utf16)

    /// The safe text is built in one forward, cancellable pass over UTF-16 code units and is a native Swift
    /// string, so the later passes over it (line counting, validation, the hidden-content scan, the gutter's
    /// index) read contiguous UTF-8. What is concealed, the count and the findings do not depend on how the text
    /// is assembled; `PrivacyFilterReference` is the oracle for that.
    public func filter(_ document: ParsedTextDocument, context: RequestContext) throws -> SafeText {
        try context.checkpoint()
        let source = document.text
        guard document.sensitiveRanges.count <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        // Convert all required UTF-8 offsets to UTF-16 in one scalar pass; repeated
        // String.Index walks would make documents with many sensitive fields quadratic.
        // Offsets only increase, so a sorted cursor replaces a hash lookup per scalar.
        // Requested offsets inside a scalar are never recorded and later fail as malformed.
        let requestedOffsets = Set(document.sensitiveRanges.flatMap { [$0.utf8Range.lowerBound, $0.utf8Range.upperBound] })
        var offsets: [Int: Int] = [:]
        if !requestedOffsets.isEmpty {
            let targets = requestedOffsets.sorted()
            var cursor = 0
            var utf8Offset = 0
            var utf16Offset = 0
            for (index, scalar) in source.unicodeScalars.enumerated() {
                if index.isMultiple(of: 1024) { try context.checkpoint() }
                while cursor < targets.count, targets[cursor] < utf8Offset { cursor += 1 }
                if cursor < targets.count, targets[cursor] == utf8Offset {
                    offsets[utf8Offset] = utf16Offset
                    cursor += 1
                }
                utf8Offset += scalar.utf8.count
                utf16Offset += scalar.value > 0xFFFF ? 2 : 1
            }
            if requestedOffsets.contains(utf8Offset) { offsets[utf8Offset] = utf16Offset }
        }
        var ranges: [SourcedRange] = try document.sensitiveRanges.map { span in
            try context.checkpoint()
            guard let start = offsets[span.utf8Range.lowerBound], let end = offsets[span.utf8Range.upperBound], end >= start else {
                throw PreviewFailure.malformedDocument
            }
            return SourcedRange(range: NSRange(location: start, length: end - start), source: .sensitiveField)
        }
        // One contiguous UTF-16 copy serves every pass; ICU then reads code units directly
        // rather than transcoding the Swift string for each search. The concealment pass below
        // slices the same code units.
        let units = Array(source.utf16)
        let nsSource = Self.nsString(from: units)
        // The filter's own matches are limited like an adapter's ranges: past the node budget the scans stop
        // and the whole text is concealed instead of the filter growing without bound.
        var ownMatches = OwnMatchLimit(maximum: context.budget.maxJSONNodes)
        if !document.usesStructuredPrivacy {
            // Redact the rest of a secret assignment's line, including malformed/unterminated quotes.
            // Identifier boundary prevents repeated greedy retries along one long token.
            let keys = try NSRegularExpression(pattern: SecretFieldPolicy.assignmentPattern)
            try enumerateMatches(keys, in: nsSource, context: context) { match in
                if SecretFieldPolicy.isSensitive(nsSource.substring(with: match.range(at: 1))) {
                    let start = NSMaxRange(match.range)
                    let remaining = NSRange(location: start, length: nsSource.length - start)
                    let newline = nsSource.rangeOfCharacter(from: .newlines, options: [], range: remaining)
                    let lineEnd = newline.location == NSNotFound ? nsSource.length : newline.location
                    let lineValue = nsSource.substring(with: NSRange(location: start, length: lineEnd - start))
                    // Plain text has no grammar for multiline values. Conceal the remainder
                    // when a value is ambiguous rather than exposing continuation lines.
                    let end = mayContinueBeyondLine(lineValue, hasFollowingLine: lineEnd < nsSource.length)
                        ? nsSource.length : lineEnd
                    if end > start {
                        ranges.append(SourcedRange(range: NSRange(location: start, length: end - start), source: .sensitiveField))
                        return ownMatches.accept()
                    }
                }
                return true
            }
        }
        // The same value policy is used for decoded adapter values and the displayed source.
        var ownLimitExceeded = ownMatches.isExceeded
        if !ownLimitExceeded {
            switch try RecognizableSecretPolicy.recognizedRanges(in: source, context: context, maximumMatches: ownMatches.remaining) {
            case .matchLimitExceeded: ownLimitExceeded = true
            case .matches(let matches):
                for match in matches {
                    guard let source = RangeSource(findingKind: match.kind) else { throw PreviewFailure.malformedDocument }
                    ranges.append(SourcedRange(range: NSRange(location: match.utf16Range.lowerBound, length: match.utf16Range.count), source: source))
                }
            }
        }
        // Merge overlaps before replacing, keeping no raw alternate representation. A merged range
        // keeps the most specific source among its parts, so the inventory names what was concealed.
        let merged: [SourcedRange]
        if ownLimitExceeded {
            merged = [SourcedRange(range: NSRange(location: 0, length: units.count), source: .sensitiveField)]
        } else {
            merged = try Self.mergeRanges(ranges, context: context)
        }
        let safe: String
        if merged.isEmpty {
            safe = source
        } else {
            safe = try Self.concealed(units, ranges: merged.map(\.range), context: context)
        }
        guard safe.utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        try context.checkpoint()
        let findings = try Self.inventory(of: merged, in: safe, context: context)
        return SafeText(text: safe, redactionCount: merged.count, syntax: document.syntax, findings: findings)
    }

    /// One finding per kind of concealed range; counts sum to the redaction count. Lines are where each
    /// replacement starts in the safe text, counted by the gutter's own definition of a logical line, so
    /// they stay correct after a multiline value collapses. No key name, pattern or value is carried.
    private static func inventory(of merged: [SourcedRange], in safe: String, context: RequestContext) throws -> [PreviewFinding] {
        guard !merged.isEmpty else { return [] }
        // Ranges are ascending and disjoint, so each replacement starts at its source offset less
        // what the earlier replacements removed.
        let tokenLength = concealmentToken.utf16.count
        var starts: [Int] = []
        starts.reserveCapacity(merged.count)
        var removed = 0
        for item in merged {
            starts.append(item.range.location - removed)
            removed += item.range.length - tokenLength
        }
        try context.checkpoint()
        // The only extra pass over the text, bounded by the output budget. Offsets are in range by
        // construction; if that ever failed, counts would still be reported without positions.
        let lineNumbers = LogicalLines.lineNumbers(forUTF16Offsets: starts, in: safe)
        let hasLines = lineNumbers.count == merged.count
        try context.checkpoint()
        var counts = [Int](repeating: 0, count: RangeSource.allCases.count)
        var lines = [[Int]](repeating: [], count: RangeSource.allCases.count)
        for (index, item) in merged.enumerated() {
            let slot = item.source.rawValue
            counts[slot] += 1
            // Lines never decrease, so the first distinct ones are the ones a finding keeps.
            if hasLines, lines[slot].count < PreviewFinding.maximumLines, lines[slot].last != lineNumbers[index] {
                lines[slot].append(lineNumbers[index])
            }
        }
        return RangeSource.allCases.reversed().compactMap { source in
            counts[source.rawValue] > 0
                ? PreviewFinding(kind: source.findingKind, count: counts[source.rawValue], lines: lines[source.rawValue])
                : nil
        }
    }

    private static func nsString(from units: [UInt16]) -> NSString {
        units.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { NSString(characters: $0, length: buffer.count) } ?? NSString()
        }
    }

    /// The concealed ranges in ascending order, none overlapping or touching: ranges that overlap or touch are
    /// joined into one that spans them, and a joined range keeps the most specific source among its parts.
    /// Empty ranges are dropped. Linear after the sort, and it checks cancellation between batches of ranges.
    private static func mergeRanges(_ ranges: [SourcedRange], context: RequestContext) throws -> [SourcedRange] {
        try context.checkpoint()
        let sorted = ranges.filter { $0.range.length > 0 }.sorted { $0.range.location < $1.range.location }
        try context.checkpoint()
        var merged: [SourcedRange] = []
        for (index, item) in sorted.enumerated() {
            if index & Self.rangeCheckpointMask == 0 { try context.checkpoint() }
            if let last = merged.last, NSMaxRange(last.range) >= item.range.location {
                merged[merged.count - 1] = SourcedRange(range: NSUnionRange(last.range, item.range),
                                                        source: max(last.source, item.source))
            } else { merged.append(item) }
        }
        return merged
    }

    /// `units` with every range replaced by the concealment token, built in one forward pass: the text between
    /// ranges and the token are appended in order, then decoded once into a native Swift string. The work is
    /// linear in the text and the ranges. Replacing ranges one by one in a mutable string moved the whole
    /// tail for each replacement, took time proportional to the text times the ranges, and could not be
    /// interrupted. Cancellation and the deadline are checked every 256th range.
    ///
    /// `ranges` must be ascending, must not overlap and must lie inside `units`, at scalar boundaries; the merge
    /// step guarantees that. A range that breaks the contract is `malformedDocument` rather than a trap.
    static func concealed(_ units: [UInt16], ranges: [NSRange], context: RequestContext) throws -> String {
        var output: [UInt16] = []
        output.reserveCapacity(units.count)
        var copied = 0
        for (index, range) in ranges.enumerated() {
            if index & Self.rangeCheckpointMask == 0 { try context.checkpoint() }
            guard range.location >= copied, range.length >= 0, NSMaxRange(range) <= units.count else {
                throw PreviewFailure.malformedDocument
            }
            output.append(contentsOf: units[copied..<range.location])
            output.append(contentsOf: Self.concealmentTokenUnits)
            copied = NSMaxRange(range)
        }
        output.append(contentsOf: units[copied...])
        try context.checkpoint()
        return String(decoding: output, as: UTF16.self)
    }

    /// `body` returns false to end the scan early, as the own-match limit does.
    private func enumerateMatches(_ regex: NSRegularExpression, in text: NSString, context: RequestContext,
                                  body: (NSTextCheckingResult) -> Bool) throws {
        var failure: (any Error)?
        var progressEvents = 0
        regex.enumerateMatches(in: text as String, options: [.reportProgress],
                               range: NSRange(location: 0, length: text.length)) { match, _, stop in
            if match == nil {
                progressEvents &+= 1
                guard progressEvents & Self.progressCheckpointMask == 0 else { return }
            }
            do { try context.checkpoint() }
            catch { failure = error; stop.pointee = true; return }
            if let match, !body(match) { stop.pointee = true }
        }
        if let failure { throw failure }
    }

    private func mayContinueBeyondLine(_ value: String, hasFollowingLine: Bool) -> Bool {
        guard hasFollowingLine else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return true }
        // A value that is only a comment is an empty value: the block under the key follows it.
        if first == "#" { return true }
        if first == "{" || first == "[" || trimmed.hasSuffix("\\") { return true }
        guard first == "\"" || first == "'" else { return false }
        if trimmed.hasPrefix(String(repeating: String(first), count: 3)) { return true }
        var escaped = false
        for character in trimmed.dropFirst() {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == first { return false }
        }
        return true
    }
}

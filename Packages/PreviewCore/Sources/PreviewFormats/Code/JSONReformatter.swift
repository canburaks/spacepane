import Foundation
import PreviewContracts

/// Pretty-prints a JSON document that `JSONScanner` has already validated, for sources whose lines are
/// too long to show (minified JSON). It is a token-level rewrite, not a re-serialization: key order,
/// duplicate keys, number lexemes and string escapes are copied byte for byte; only the whitespace
/// between tokens changes. The caller's sensitive source ranges (each spans exactly one value) are
/// carried across by tracking where those values start and end in the output, so structural
/// concealment is identical to the unformatted document.
///
/// Layout: two spaces per level, `key: value`, one member or element per line, empty containers as
/// `{}` and `[]`, and an array of scalars that fits in 100 source bytes on a single line. One linear
/// pass; output size is checked against the request's output budget as it grows.
struct JSONReformatter {
    struct Result {
        let text: String
        let sensitiveRanges: [SensitiveRange]
    }

    private static let inlineArrayLimit = 100
    private static let indentUnit: [UInt8] = [32, 32]

    static func format(_ bytes: [UInt8], sensitiveRanges: [SensitiveRange], context: RequestContext) throws -> Result {
        var formatter = JSONReformatter(bytes: bytes, context: context)
        formatter.pendingStarts = Dictionary(sensitiveRanges.map { ($0.utf8Range.lowerBound, $0.utf8Range.upperBound) },
                                             uniquingKeysWith: max)
        try formatter.run()
        return Result(text: String(decoding: formatter.output, as: UTF8.self), sensitiveRanges: formatter.outputRanges)
    }

    private let bytes: [UInt8]
    private let context: RequestContext
    private var index = 0
    private var depth = 0
    private var output: [UInt8] = []
    private var pendingStarts: [Int: Int] = [:]
    private var open: [(sourceEnd: Int, outputStart: Int)] = []
    private var outputRanges: [SensitiveRange] = []

    private init(bytes: [UInt8], context: RequestContext) {
        self.bytes = bytes
        self.context = context
        output.reserveCapacity(bytes.count * 2)
    }

    private mutating func run() throws {
        while index < bytes.count {
            if index.isMultiple(of: 512) {
                try context.checkpoint()
                guard output.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
            }
            let byte = bytes[index]
            switch byte {
            case 9, 10, 13, 32:
                index += 1
            case 123, 91:
                beginValue()
                if let closer = emptyContainerCloser() {
                    output.append(byte)
                    output.append(bytes[closer])
                    index = closer + 1
                    endValue()
                } else if byte == 91, let end = inlineArrayEnd() {
                    try writeInlineArray(through: end)
                } else {
                    output.append(byte)
                    index += 1
                    depth += 1
                    newline()
                }
            case 125, 93:
                depth -= 1
                newline()
                output.append(byte)
                index += 1
                endValue()
            case 44:
                output.append(44)
                index += 1
                newline()
            case 58:
                output.append(58)
                output.append(32)
                index += 1
            case 34:
                beginValue()
                copyString()
                endValue()
            default:
                beginValue()
                while index < bytes.count, ![9, 10, 13, 32, 44, 58, 93, 125].contains(bytes[index]) {
                    output.append(bytes[index])
                    index += 1
                }
                endValue()
            }
        }
        try context.checkpoint()
        guard output.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
    }

    // MARK: Sensitive ranges

    /// A sensitive value begins here; remember where it begins in the output.
    private mutating func beginValue() {
        if let end = pendingStarts[index] { open.append((end, output.count)) }
    }

    /// The token that just ended closes every sensitive value that ends at this source offset.
    private mutating func endValue() {
        while let last = open.last, last.sourceEnd == index {
            open.removeLast()
            outputRanges.append(SensitiveRange(utf8Range: last.outputStart..<output.count))
        }
    }

    // MARK: Layout

    private mutating func newline() {
        output.append(10)
        for _ in 0..<max(depth, 0) { output.append(contentsOf: Self.indentUnit) }
    }

    /// The offset of the closing bracket when the container at `index` has no members.
    private func emptyContainerCloser() -> Int? {
        var next = index + 1
        while next < bytes.count, [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
        guard next < bytes.count else { return nil }
        return bytes[next] == (bytes[index] == 123 ? 125 : 93) ? next : nil
    }

    private mutating func copyString() {
        output.append(bytes[index])
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            output.append(byte)
            index += 1
            if byte == 92, index < bytes.count {
                output.append(bytes[index])
                index += 1
            } else if byte == 34 {
                return
            }
        }
    }

    /// The offset just past `]` when the array at `index` holds only scalars and fits on one line.
    private func inlineArrayEnd() -> Int? {
        var position = index + 1
        let limit = min(bytes.count, index + Self.inlineArrayLimit)
        while position < limit {
            switch bytes[position] {
            case 93: return position + 1
            case 91, 123: return nil
            case 34:
                position += 1
                while position < limit, bytes[position] != 34 {
                    position += bytes[position] == 92 ? 2 : 1
                }
                position += 1
            default:
                position += 1
            }
        }
        return nil
    }

    private mutating func writeInlineArray(through end: Int) throws {
        output.append(91)
        index += 1
        while index < end - 1 {
            let byte = bytes[index]
            switch byte {
            case 9, 10, 13, 32:
                index += 1
            case 44:
                output.append(44)
                output.append(32)
                index += 1
            case 34:
                copyString()
            default:
                while index < end - 1, ![9, 10, 13, 32, 44].contains(bytes[index]) {
                    output.append(bytes[index])
                    index += 1
                }
            }
        }
        output.append(93)
        index = end
        endValue()
    }
}

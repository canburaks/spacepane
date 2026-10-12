import Foundation
import PreviewContracts

/// Omits only image MIME value strings/arrays from notebook output data. Keys, whitespace,
/// escaped spelling and every other source code unit stay exact. `null` is an inert JSON placeholder;
/// the renderer supplies localized provenance rather than embedding translated text into source.
enum NotebookImageSource {
    struct Result {
        let text: String
        let sensitiveRanges: [SensitiveRange]
        let changed: Bool
    }

    private struct Replacement {
        let source: Range<Int>
        let output: Range<Int>
        let deltaAfter: Int
    }

    static func transform(_ bytes: [UInt8], root: NotebookJSONValue, sensitiveRanges: [SensitiveRange],
                          context: RequestContext) throws -> Result {
        let spans = try imageSpans(root, context: context).sorted { $0.lowerBound < $1.lowerBound }
        guard !spans.isEmpty else {
            guard bytes.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
            return Result(text: String(decoding: bytes, as: UTF8.self), sensitiveRanges: sensitiveRanges, changed: false)
        }
        var replacements: [Replacement] = []
        var outputCount = bytes.count
        var previousEnd = 0
        var delta = 0
        for span in spans {
            try context.checkpoint()
            guard span.lowerBound >= previousEnd, span.upperBound <= bytes.count else { throw PreviewFailure.malformedDocument }
            let start = span.lowerBound + delta
            delta += 4 - span.count
            replacements.append(Replacement(source: span, output: start..<start + 4, deltaAfter: delta))
            outputCount += 4 - span.count
            previousEnd = span.upperBound
        }
        guard outputCount <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        var output: [UInt8] = []
        output.reserveCapacity(outputCount)
        var cursor = 0
        for replacement in replacements {
            try context.checkpoint()
            output.append(contentsOf: bytes[cursor..<replacement.source.lowerBound])
            output.append(contentsOf: "null".utf8)
            cursor = replacement.source.upperBound
        }
        output.append(contentsOf: bytes[cursor...])
        var mapped: [SensitiveRange] = []
        for range in sensitiveRanges {
            try context.checkpoint()
            // These bytes are already omitted. Concealing their inert null placeholder would make safe
            // notebook JSON invalid; a range extending outside this image must still be remapped below.
            if let replacement = replacement(atOrBefore: range.utf8Range.lowerBound, in: replacements),
               range.utf8Range.upperBound <= replacement.source.upperBound { continue }
            let lower = offset(range.utf8Range.lowerBound, end: false, replacements: replacements)
            let upper = offset(range.utf8Range.upperBound, end: true, replacements: replacements)
            if lower < upper { mapped.append(SensitiveRange(utf8Range: lower..<upper)) }
        }
        return Result(text: String(decoding: output, as: UTF8.self),
                      sensitiveRanges: NotebookPrivacyRanges.merged(mapped), changed: true)
    }

    private static func imageSpans(_ root: NotebookJSONValue, context: RequestContext) throws -> [Range<Int>] {
        guard case .array(let cells)? = try root.member("cells") else { return [] }
        var spans: [Range<Int>] = []
        for cell in cells {
            try context.checkpoint()
            guard case .array(let outputs)? = try cell.member("outputs") else { continue }
            for output in outputs {
                try context.checkpoint()
                guard case .object(let data)? = try output.member("data") else { continue }
                for member in data where member.key.value.hasPrefix("image/") {
                    try context.checkpoint()
                    switch member.value {
                    case .string, .array: spans.append(member.valueRange)
                    default: break
                    }
                }
            }
        }
        return spans
    }

    /// Boundary offsets within a removed value expand to its complete replacement, so an original
    /// privacy range intersecting a payload never becomes a partly exposed placeholder or sibling.
    private static func offset(_ source: Int, end: Bool, replacements: [Replacement]) -> Int {
        guard let replacement = replacement(atOrBefore: source, in: replacements) else { return source }
        if source == replacement.source.lowerBound { return replacement.output.lowerBound }
        if source < replacement.source.upperBound {
            return end ? replacement.output.upperBound : replacement.output.lowerBound
        }
        return source + replacement.deltaAfter
    }

    /// The last image starting at or before this byte offset, found without scanning earlier images.
    private static func replacement(atOrBefore source: Int, in replacements: [Replacement]) -> Replacement? {
        var lower = 0
        var upper = replacements.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if replacements[middle].source.lowerBound <= source { lower = middle + 1 }
            else { upper = middle }
        }
        return lower > 0 ? replacements[lower - 1] : nil
    }
}

import Foundation
import PreviewContracts

/// Summarizes a safetensors model file (`.safetensors`): tensor count, exact parameter count, the mix of
/// data types, a shard position taken from the file name, LoRA and GPTQ/AWQ hints taken from tensor
/// names, the `__metadata__` map, and a bounded tensor list.
///
/// Only the 8-byte length and the JSON header are read. The header is parsed by a strict scanner built
/// for this one schema, with a 16 MiB cap on its size, 200,000 tensors and four levels of nesting.
/// Tensor data is never read. `model.incomplete` fires when the header describes more data than the
/// file holds (a download cut short); `model.inconsistentLayout` fires for overlapping or missing
/// ranges, bytes after the last tensor and tensors whose size disagrees with their dtype and shape.
public struct SafetensorsAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let maximumHeaderBytes: UInt64 = 16 * 1_048_576
    private static let readChunk = 1_048_576

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let fileSize = source.byteCount
        guard fileSize >= 8 else { throw PreviewFailure.malformedDocument }
        let prefix = try source.read(offset: 0, count: 8, context: context)
        let headerLength = prefix.reversed().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard headerLength > 0, headerLength <= UInt64(fileSize - 8) else { throw PreviewFailure.malformedDocument }
        guard headerLength <= Self.maximumHeaderBytes, headerLength <= UInt64(max(0, context.budget.maxInputBytes - 8)) else {
            throw PreviewFailure.inputTooLarge
        }

        var headerBytes = [UInt8]()
        headerBytes.reserveCapacity(Int(headerLength))
        while headerBytes.count < Int(headerLength) {
            let count = min(Self.readChunk, Int(headerLength) - headerBytes.count)
            headerBytes.append(contentsOf: try source.read(offset: 8 + Int64(headerBytes.count), count: count, context: context))
        }
        var scanner = SafetensorsHeaderScanner(bytes: headerBytes, context: context)
        let header = try scanner.scan()

        let available = UInt64(fileSize) - 8 - headerLength
        let analysis = try SafetensorsAnalysis(tensors: header.tensors, availableBytes: available, context: context)
        var findings: [PreviewFinding] = []
        if analysis.tensorsBeyondFile > 0 { findings.append(PreviewFinding(kind: .modelIncomplete, count: analysis.tensorsBeyondFile)) }
        if analysis.inconsistentEntries > 0 {
            findings.append(PreviewFinding(kind: .modelInconsistentLayout, count: analysis.inconsistentEntries))
        }
        var hidden = ModelHiddenText()
        let fields = try Self.summary(header: header, analysis: analysis, headerLength: headerLength,
                                      fileName: context.nameHint?.filename, hidden: &hidden, context: context)
        return try PackageSummary.document(fields.value, context: context, findings: findings + hidden.findings)
    }
}

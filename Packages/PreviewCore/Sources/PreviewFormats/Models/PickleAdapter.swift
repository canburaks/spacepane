import Foundation
import PreviewContracts

/// Scans Python pickles and PyTorch checkpoints for what loading them would import (decision 030): `.pt`,
/// `.pth`, `.ckpt`, `.pickle` and `.joblib`.
///
/// Nothing is loaded. The scan walks pickle opcodes, keeps a memo of strings only to resolve `STACK_GLOBAL`,
/// builds no objects and imports nothing. Tensor storages are counted from a ZIP's directory and never read.
/// The result is a summary of what was found, with findings by class of import; it never says that a file is
/// safe, because a static look at imports cannot know that.
///
/// The file's content decides the route, not its suffix:
/// - a ZIP is a PyTorch checkpoint when it holds `.pkl` members (`PyTorchArchiveScanner`);
/// - a PROTO opcode, or an opcode that opens a protocol 0 or 1 pickle, is a raw pickle, and consecutive
///   pickles are scanned, which is what legacy `torch.save` files hold;
/// - zlib, gzip, bzip2 and xz streams are joblib files and are decompressed within bounds first;
/// - 7z, GGUF, safetensors and other recognizable files are summarized as what they are and flagged as
///   mismatched content, and are not opened;
/// - a `.pth` file that is UTF-8 text is a Python path file and is shown as text.
public struct PickleAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    /// A raw pickle file is read this far; legacy PyTorch files put raw tensor data after their pickles.
    static let maximumRawBytes = 8_388_608
    static let maximumTextBytes = 1_048_576
    static let maximumDecodedBytes = 33_554_432

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = source.byteCount
        guard size > 0 else { throw PreviewFailure.malformedDocument }
        let head = try source.read(offset: 0, count: Int(min(size, Int64(PickleSniffer.headLength))), context: context)
        switch PickleSniffer.kind(of: head, size: size) {
        case .zip:
            return try archive(source, context: context)
        case .foreign(let name):
            return try PickleSummary.document(PickleScanReport(container: name), scanned: false, mismatch: true, context: context)
        case .compressed(let compression):
            return try compressed(compression, source: source, size: size, headLength: head.count, context: context)
        case .unsupportedCompression:
            throw PreviewFailure.unsupportedVariant
        case .other:
            return try raw(source, size: size, context: context)
        }
    }

    private func archive(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        var report = PickleScanReport(container: "PyTorch ZIP")
        try PyTorchArchiveScanner.scan(source, context: context, report: &report)
        guard report.pickles > 0 else {
            // A ZIP with no pickle member is not a checkpoint, whatever its name says.
            var other = PickleScanReport(container: "ZIP")
            other.nativeMembers = report.nativeMembers
            return try PickleSummary.document(other, scanned: false, mismatch: true, context: context)
        }
        return try PickleSummary.document(report, context: context)
    }

    private func compressed(_ compression: PickleSniffer.Compression, source: any PreviewByteSource, size: Int64,
                            headLength: Int, context: RequestContext) throws -> ParsedTextDocument {
        guard size <= Int64(context.budget.maxInputBytes - headLength) else { throw PreviewFailure.inputTooLarge }
        let packed = try source.read(offset: 0, count: Int(size), context: context)
        let decoded: Data
        switch compression {
        case .zlib: decoded = try BoundedDecompression.zlibWrapped(packed, context: context, maximum: Self.maximumDecodedBytes)
        case .gzip: decoded = try BoundedDecompression.gzip(packed, context: context, maximum: Self.maximumDecodedBytes)
        case .bzip2: decoded = try BoundedDecompression.bzip2(packed, context: context, maximum: Self.maximumDecodedBytes)
        case .xz: decoded = try BoundedDecompression.xz(packed, context: context, maximum: Self.maximumDecodedBytes)
        }
        var report = PickleScanReport(container: "joblib (\(compression.rawValue))")
        guard try PickleStreamScanner.scan(decoded, isWindow: false, single: false, report: &report, context: context) == .scanned else {
            throw PreviewFailure.unsupportedFormat
        }
        return try PickleSummary.document(report, context: context)
    }

    private func raw(_ source: any PreviewByteSource, size: Int64, context: RequestContext) throws -> ParsedTextDocument {
        let isPathFileName = context.nameHint?.suffix == "pth"
        var data: Data?
        if isPathFileName, size <= Int64(Self.maximumTextBytes) {
            let all = try source.read(offset: 0, count: Int(size), context: context)
            data = all
            if let text = PickleSniffer.utf8Text(all) {
                // Text is a path file, unless the whole text is a complete pickle that names imports, which
                // is what a protocol 0 pickle saved under this name looks like.
                var report = PickleScanReport(container: "Pickle")
                if try PickleStreamScanner.scan(all, isWindow: false, single: false, report: &report, context: context) == .scanned,
                   report.pickles > 0, !report.isBroken, !report.isPartial, !report.tally.isEmpty {
                    return try PickleSummary.document(report, context: context)
                }
                return ParsedTextDocument(text: text, decodedEncoding: .utf8)
            }
        }
        let bytes = try data ?? source.read(offset: 0, count: Int(min(size, Int64(Self.maximumRawBytes))), context: context)
        var report = PickleScanReport(container: PickleStreamScanner.isLegacyPyTorch(bytes) ? "PyTorch legacy" : "Pickle")
        guard try PickleStreamScanner.scan(bytes, isWindow: size > Int64(bytes.count), single: false, report: &report, context: context) == .scanned else {
            throw PreviewFailure.unsupportedFormat
        }
        return try PickleSummary.document(report, context: context)
    }
}

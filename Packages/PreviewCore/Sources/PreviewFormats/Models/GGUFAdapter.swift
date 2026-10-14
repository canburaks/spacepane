import Foundation
import PreviewContracts

/// Summarizes a GGUF model file (`.gguf`): its name, architecture, parameter count, quantization,
/// context length, vocabulary size, licence, provenance and chat template, plus a bounded tensor list.
///
/// Only the header is read: the key/value section and the tensor infos. Tensor data is never read, so
/// nothing proportional to the weights is fetched. Vocabularies and merge lists are counted, not kept.
/// Format versions 2 and 3 are read, in either byte order; version 1 is reported as unsupported.
/// If the request's read budget ends before the tensor infos do, the summary is marked partial and
/// carries the metadata read so far but no totals. The chat template is shown as inert text.
public struct GGUFAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    static let magic: [UInt8] = [0x47, 0x47, 0x55, 0x46]
    static let maximumAlignment: UInt64 = 1 << 30

    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(DataByteSource(input.data), context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        var reader = GGUFByteReader(source: source, context: context)
        let preamble = try Self.readPreamble(&reader)

        var metadataParser = GGUFMetadataParser(context: context)
        var table = GGUFTensorTable()
        var hidden = ModelHiddenText()
        var isPartial = false
        do {
            try metadataParser.parse(count: preamble.metadataCount, reader: &reader)
            try table.parse(count: preamble.tensorCount, listingCapacity: PackageSummary.listingCapacity(context),
                            reader: &reader, hidden: &hidden, context: context)
        } catch is GGUFByteReader.BudgetExhausted {
            isPartial = true
        }
        let metadata = metadataParser.finished()
        guard (1...Self.maximumAlignment).contains(metadata.alignment), metadata.alignment.nonzeroBitCount == 1 else {
            throw PreviewFailure.malformedDocument
        }

        var findings: [PreviewFinding] = []
        var layout: GGUFLayoutReport?
        if !isPartial {
            let dataStart = Self.aligned(UInt64(reader.position), to: metadata.alignment)
            let report = try GGUFLayoutReport(records: table.records, alignment: metadata.alignment, dataStart: dataStart,
                                              fileSize: UInt64(reader.fileSize), context: context)
            if report.tensorsBeyondFile > 0 { findings.append(PreviewFinding(kind: .modelIncomplete, count: report.tensorsBeyondFile)) }
            if report.inconsistentTensors > 0 {
                findings.append(PreviewFinding(kind: .modelInconsistentLayout, count: report.inconsistentTensors))
            }
            layout = report
        }
        hidden.merge(metadataParser.hidden)
        let fields = try Self.summary(preamble: preamble, metadata: metadata, table: table, layout: layout,
                                      isPartial: isPartial, hidden: &hidden, context: context)
        return try PackageSummary.document(fields.value, context: context, findings: findings + hidden.findings)
    }

    // MARK: Header

    struct Preamble {
        let version: UInt32
        let tensorCount: Int
        let metadataCount: Int
    }

    /// Magic, version and the two counts. A version whose low half is zero is a big-endian file: its
    /// version number 3 read as little-endian is 0x03000000.
    static func readPreamble(_ reader: inout GGUFByteReader) throws -> Preamble {
        do {
            guard try reader.bytes(4) == magic else { throw PreviewFailure.malformedDocument }
            var version = try reader.uint32()
            if version != 0, version & 0xFFFF == 0 {
                reader.useBigEndian()
                version = version.byteSwapped
            }
            switch version {
            case 0: throw PreviewFailure.malformedDocument
            case 2, 3: break
            default: throw PreviewFailure.unsupportedVariant
            }
            let tensors = try reader.uint64()
            let entries = try reader.uint64()
            guard tensors <= UInt64(GGUFTensorTable.maximumTensors),
                  entries <= UInt64(GGUFMetadataParser.maximumEntries) else { throw PreviewFailure.tooManyNodes }
            // Every entry and tensor takes at least this many bytes, so counts beyond the file are truncation.
            let (entryBytes, entryOverflow) = entries.multipliedReportingOverflow(by: 13)
            let tensorBytes = tensors * GGUFTensorTable.minimumInfoBytes
            guard !entryOverflow, entryBytes + tensorBytes <= UInt64(max(0, reader.remaining)) else {
                throw PreviewFailure.malformedDocument
            }
            return Preamble(version: version, tensorCount: Int(tensors), metadataCount: Int(entries))
        } catch is GGUFByteReader.BudgetExhausted {
            throw PreviewFailure.inputTooLarge
        }
    }

    static func aligned(_ offset: UInt64, to alignment: UInt64) -> UInt64 {
        let remainder = offset % alignment
        return remainder == 0 ? offset : offset + (alignment - remainder)
    }
}

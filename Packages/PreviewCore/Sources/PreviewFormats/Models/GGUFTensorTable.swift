import Foundation
import PreviewContracts

/// What a tensor info says about one tensor; the name is kept only for the tensors a summary lists.
struct GGUFTensorRecord {
    let typeCode: UInt32
    let elements: UInt64
    let firstDimension: UInt64
    /// Bytes from the start of the data section, as the file states it.
    let offset: UInt64

    var byteCount: UInt64? {
        GGUFTypeTable.byteCount(code: typeCode, elements: elements, firstDimension: firstDimension)
    }
}

struct GGUFListedTensor {
    let name: String
    let typeCode: UInt32
    let shape: [UInt64]
    let elements: UInt64
}

/// Reads the tensor infos that follow the key/value section. Only names, shapes and offsets are read;
/// tensor data lies beyond the infos and is never touched.
struct GGUFTensorTable {
    static let maximumTensors = 100_000
    static let maximumDimensions = 4
    static let maximumNameBytes = 65_536
    static let listedNameBytes = 256
    /// Smallest encoded tensor info: an empty name, one dimension, a type and an offset.
    static let minimumInfoBytes: UInt64 = 8 + 4 + 8 + 4 + 8

    private(set) var records: [GGUFTensorRecord] = []
    private(set) var listed: [GGUFListedTensor] = []
    private(set) var parameters: UInt64 = 0

    mutating func parse(count: Int, listingCapacity: Int, reader: inout GGUFByteReader,
                        hidden: inout ModelHiddenText, context: RequestContext) throws {
        records.reserveCapacity(min(count, Self.maximumTensors))
        for index in 0..<count {
            if index.isMultiple(of: 256) { try context.checkpoint() }
            let nameLength = try reader.uint64()
            guard nameLength <= UInt64(Self.maximumNameBytes), nameLength <= UInt64(max(0, reader.remaining)) else {
                throw PreviewFailure.malformedDocument
            }
            let name: String?
            if index < listingCapacity {
                name = String(decoding: try reader.bytes(Int(nameLength)), as: UTF8.self)
            } else {
                try reader.skip(nameLength)
                name = nil
            }
            let dimensionCount = try reader.uint32()
            guard (1...UInt32(Self.maximumDimensions)).contains(dimensionCount) else { throw PreviewFailure.malformedDocument }
            var shape: [UInt64] = []
            var elements: UInt64 = 1
            for _ in 0..<dimensionCount {
                let dimension = try reader.uint64()
                let (product, overflow) = elements.multipliedReportingOverflow(by: dimension)
                guard !overflow else { throw PreviewFailure.malformedDocument }
                elements = product
                shape.append(dimension)
            }
            let typeCode = try reader.uint32()
            let offset = try reader.uint64()
            let (total, overflow) = parameters.addingReportingOverflow(elements)
            guard !overflow, total <= UInt64(Int64.max) else { throw PreviewFailure.malformedDocument }
            parameters = total
            records.append(GGUFTensorRecord(typeCode: typeCode, elements: elements, firstDimension: shape[0], offset: offset))
            if let name {
                try hidden.scan(name, context: context)
                listed.append(GGUFListedTensor(name: PackageSummary.clipped(name, limit: Self.listedNameBytes),
                                               typeCode: typeCode, shape: shape, elements: elements))
            }
        }
    }
}

/// What the tensor infos imply about the file around them: how much data they expect, and whether
/// their ranges are laid out the way ggml writes them.
struct GGUFLayoutReport {
    /// Tensors whose stated range ends beyond the file's last byte.
    var tensorsBeyondFile = 0
    /// Tensors whose offset is not a multiple of the alignment, whose first dimension is not a whole
    /// number of blocks, or whose range overlaps an earlier one.
    var inconsistentTensors = 0
    /// Total bytes of all tensors, when every tensor's type is known.
    var totalBytes: UInt64?
    /// Number of tensors of each ggml type code.
    var typeCounts: [UInt32: Int] = [:]

    init(records: [GGUFTensorRecord], alignment: UInt64, dataStart: UInt64, fileSize: UInt64,
         context: RequestContext) throws {
        var flagged = [Bool](repeating: false, count: records.count)
        var ranges: [(index: Int, start: UInt64, end: UInt64)] = []
        var total: UInt64? = 0
        for (index, record) in records.enumerated() {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            typeCounts[record.typeCode, default: 0] += 1
            if record.offset % alignment != 0 { flagged[index] = true }
            if GGUFTypeTable.hasPartialBlocks(code: record.typeCode, firstDimension: record.firstDimension) {
                flagged[index] = true
            }
            guard let bytes = record.byteCount else { total = nil; continue }
            if let running = total {
                let (sum, summed) = running.addingReportingOverflow(bytes)
                total = summed ? nil : sum
            }
            guard bytes > 0 else { continue }
            let (end, overflow) = record.offset.addingReportingOverflow(bytes)
            let (absoluteEnd, absoluteOverflow) = dataStart.addingReportingOverflow(end)
            if overflow || absoluteOverflow || absoluteEnd > fileSize { tensorsBeyondFile += 1 }
            ranges.append((index, record.offset, overflow ? .max : end))
        }
        totalBytes = total
        try context.checkpoint()
        ranges.sort { $0.start < $1.start }
        try context.checkpoint()
        var coveredUntil: UInt64 = 0
        for range in ranges {
            if range.start < coveredUntil { flagged[range.index] = true }
            coveredUntil = max(coveredUntil, range.end)
        }
        inconsistentTensors = flagged.lazy.filter { $0 }.count
    }
}

import Foundation
import PreviewContracts

/// The first rows of a Parquet file's first row group, from the leading data pages of each column.
///
/// Supported: columns without repeated ancestors (one entry per row), PLAIN values and dictionary
/// pages with RLE_DICTIONARY / PLAIN_DICTIONARY indices, data page versions 1 and 2, and the
/// UNCOMPRESSED, SNAPPY and GZIP codecs. A column using anything else (delta encodings, other
/// codecs, nested repetition) is left out of the sample, never guessed. At most `maximumRows` rows
/// and `maximumColumns` columns are decoded, at most `maximumPages` pages per column, and the bytes
/// read are held below a share of the request's input budget so the sample can never turn an
/// otherwise good preview into `inputTooLarge`. Statistics, indexes and the rest of the file are not read.
enum ParquetRowSampler {
    static let maximumRows = 100
    static let maximumColumns = 20
    static let maximumPages = 8
    static let maximumPageBytes = 4_194_304

    struct Sample {
        var columns: [String] = []
        var rows: [[DataCell]] = []
        /// Columns left out because their encoding or codec is not supported.
        var skippedColumns = 0
    }

    /// `dataEnd` is where the footer begins: no page can lie beyond it, and no read crosses it.
    static func sample(_ footer: ParquetFooter, source: any PreviewByteSource, dataEnd: Int64, readAllowance: Int,
                       context: RequestContext) throws -> Sample? {
        guard let group = footer.rowGroups.first, let leaves = ParquetLeaf.leaves(of: footer.schema), !leaves.isEmpty,
              let rowCount = group.rows, rowCount > 0 else { return nil }
        var allowance = readAllowance
        var columns: [(name: String, cells: [DataCell])] = []
        var skipped = 0
        for (index, leaf) in leaves.enumerated() where index < group.chunks.count {
            try context.checkpoint()
            if columns.count >= maximumColumns { break }
            guard let cells = try column(leaf, chunk: group.chunks[index], rowCount: Int(min(rowCount, Int64(maximumRows))),
                                         source: source, dataEnd: dataEnd, allowance: &allowance, context: context) else {
                skipped += 1
                continue
            }
            columns.append((leaf.name, cells))
        }
        guard let shortest = columns.map(\.cells.count).min(), shortest > 0 else { return nil }
        var result = Sample(skippedColumns: skipped)
        result.columns = columns.map(\.name)
        result.rows = (0..<min(shortest, maximumRows)).map { row in columns.map { $0.cells[row] } }
        return result
    }

    // MARK: One column

    /// The first cells of one column chunk, or nil when it cannot be decoded.
    private static func column(_ leaf: ParquetLeaf, chunk: ParquetFooter.ColumnChunk, rowCount: Int,
                               source: any PreviewByteSource, dataEnd: Int64, allowance: inout Int,
                               context: RequestContext) throws -> [DataCell]? {
        guard leaf.maximumRepetition == 0, let codec = chunk.codec, [0, 1, 2].contains(codec),
              let physical = leaf.element.physicalType,
              let dataOffset = chunk.dataPageOffset, dataOffset >= 4 else { return nil }
        var start = dataOffset
        if let dictionary = chunk.dictionaryPageOffset, dictionary >= 4, dictionary < start { start = dictionary }
        // A chunk's own size bounds where its pages can be; without one, the footer does.
        let chunkEnd = min(dataEnd, chunk.compressedBytes.map { start + $0 } ?? dataEnd)
        var offset = start
        var dictionary: [ParquetRaw]?
        var cells: [DataCell] = []
        var pages = 0
        while cells.count < rowCount, pages < maximumPages, offset < chunkEnd {
            try context.checkpoint()
            pages += 1
            let window = Int(min(Int64(2_048), chunkEnd - offset))
            guard window > 0, window <= allowance else { break }
            allowance -= window
            let header: ParquetPageHeader
            do {
                header = try ParquetPageHeader.decode([UInt8](try source.read(offset: offset, count: window, context: context)),
                                                      context: context)
            } catch let failure as PreviewFailure where failure == .malformedDocument { return cells.isEmpty ? nil : cells }
            let payloadStart = offset + Int64(header.length)
            guard header.compressedSize <= maximumPageBytes, header.uncompressedSize <= maximumPageBytes,
                  Int64(header.compressedSize) <= chunkEnd - payloadStart,
                  header.compressedSize <= allowance else { break }
            allowance -= header.compressedSize
            let payload = [UInt8](try source.read(offset: payloadStart, count: header.compressedSize, context: context))
            offset = payloadStart + Int64(header.compressedSize)
            guard let kind = header.kind else { return cells.isEmpty ? nil : cells }
            switch kind {
            case .index: continue
            case .dictionary:
                guard [0, 2].contains(header.encoding) else { return nil }
                let page = try decompress(payload, codec: codec, expected: header.uncompressedSize, context: context)
                dictionary = try ParquetPlain.decode(type: physical, typeLength: leaf.element.typeLength, page[...],
                                                    count: min(header.valueCount, 65_536), context: context)
            case .data, .dataV2:
                guard let page = try dataPage(header, payload: payload, leaf: leaf, codec: codec, dictionary: dictionary,
                                              rowsNeeded: rowCount - cells.count, context: context) else { return nil }
                cells += page
            }
        }
        return cells.isEmpty ? nil : cells
    }

    // MARK: Data pages

    private static func dataPage(_ header: ParquetPageHeader, payload: [UInt8], leaf: ParquetLeaf, codec: Int,
                                 dictionary: [ParquetRaw]?, rowsNeeded: Int, context: RequestContext) throws -> [DataCell]? {
        let isV2 = header.kind == .dataV2
        guard let physical = leaf.element.physicalType else { return nil }
        // Version 1 compresses the whole page; version 2 leaves the level bytes uncompressed.
        var body: [UInt8]
        var levels: ArraySlice<UInt8>?
        if isV2 {
            guard header.repetitionLevelBytes == 0, header.definitionLevelBytes <= payload.count else { return nil }
            levels = payload[0..<header.definitionLevelBytes]
            let values = Array(payload[header.definitionLevelBytes...])
            body = header.isCompressed && codec != 0
                ? try decompress(values, codec: codec, expected: header.uncompressedSize - header.definitionLevelBytes, context: context)
                : values
        } else {
            guard header.definitionLevelEncoding == 3 || leaf.maximumDefinition == 0 else { return nil }
            body = try decompress(payload, codec: codec, expected: header.uncompressedSize, context: context)
        }
        let entries = min(header.valueCount, rowsNeeded)
        guard entries > 0 else { return [] }
        var position = 0
        var definitions: [Int] = []
        if leaf.maximumDefinition > 0 {
            let width = ParquetHybrid.bitWidth(forMaximum: leaf.maximumDefinition)
            if isV2 {
                definitions = try ParquetHybrid.decode(levels ?? [], bitWidth: width, count: entries, context: context)
            } else {
                // Version 1 prefixes the level run with its byte length.
                guard body.count >= 4 else { throw PreviewFailure.malformedDocument }
                let length = Int(body[0]) | Int(body[1]) << 8 | Int(body[2]) << 16 | Int(body[3]) << 24
                guard length >= 0, length <= body.count - 4 else { throw PreviewFailure.malformedDocument }
                definitions = try ParquetHybrid.decode(body[4..<(4 + length)], bitWidth: width, count: entries, context: context)
                position = 4 + length
            }
        } else {
            definitions = Array(repeating: 0, count: entries)
        }
        let present = definitions.filter { $0 == leaf.maximumDefinition }.count
        let valueBytes = body[position...]
        let raws: [ParquetRaw]
        switch header.encoding {
        case 0:
            raws = try ParquetPlain.decode(type: physical, typeLength: leaf.element.typeLength, valueBytes, count: present, context: context)
        case 2, 8:
            guard let dictionary, let widthByte = valueBytes.first else { return nil }
            let indices = try ParquetHybrid.decode(valueBytes.dropFirst(), bitWidth: Int(widthByte), count: present, context: context)
            raws = try indices.map { index in
                guard dictionary.indices.contains(index) else { throw PreviewFailure.malformedDocument }
                return dictionary[index]
            }
        default:
            return nil
        }
        var next = raws.makeIterator()
        return definitions.map { level in
            guard level == leaf.maximumDefinition, let raw = next.next() else { return .null }
            return ParquetCells.cell(raw, leaf: leaf)
        }
    }

    private static func decompress(_ bytes: [UInt8], codec: Int, expected: Int, context: RequestContext) throws -> [UInt8] {
        guard expected >= 0, expected <= maximumPageBytes else { throw PreviewFailure.outputTooLarge }
        let output: [UInt8]
        switch codec {
        case 0: output = bytes
        case 1: output = try SnappyDecoder.decode(bytes, maximum: expected, context: context)
        case 2: output = [UInt8](try BoundedDecompression.gzip(Data(bytes), context: context, maximum: expected))
        default: throw PreviewFailure.unsupportedFormat
        }
        guard output.count == expected else { throw PreviewFailure.malformedDocument }
        return output
    }
}

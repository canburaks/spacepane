import Foundation
import zlib
import PreviewContracts

/// NumPy `.npy` arrays: header, data type, shape and a values table, without loading the array.
///
/// The header dictionary is a Python literal parsed by `NumPyLiteralParser`; nothing is evaluated
/// or unpickled. Arrays of dtype `object` (pickled Python objects) and structured records are
/// described but their data is never read. For numeric arrays of at most two dimensions the first
/// 100 rows and 20 columns are read from exactly the bytes they occupy.
public struct NumPyAdapter: RandomAccessFormatAdapter {
    public init() {}

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let size = Int(clamping: source.byteCount)
        let header = try NumPyHeader.parse(available: size, context: context) { offset, count in
            [UInt8](try source.read(offset: Int64(offset), count: count, context: context))
        }
        if let bytes = header.dataByteCount {
            // A file shorter than its shape implies is truncated; never read past it.
            guard header.dataOffset <= size, bytes <= size - header.dataOffset else { throw PreviewFailure.malformedDocument }
        }
        let table = try NumPyTable.build(header, context: context) { offset, count in
            guard offset >= 0, count >= 0, offset <= size, count <= size - offset else { return nil }
            return [UInt8](try source.read(offset: Int64(offset), count: count, context: context))
        }
        try context.checkpoint()
        var members: [(String, SummaryValue)] = [("dataFormat", .string("NumPy")), ("formatVersion", .string(header.version))]
        members += NumPyArrays.description(of: header)
        if let table { members.append((DataSummaryKeys.table, table.summary)) }
        return try DataDocument.make(members, context: context, facts: NumPyArrays.facts(of: header))
    }
}

/// Shared description members of one array: type, shape, element count, storage order and, for
/// record types, the field names and types.
enum NumPyArrays {
    /// Validated printable array counts, unaffected by clipped samples. Metadata-only dtypes
    /// and higher-dimensional arrays cannot establish this values-grid capability.
    static func facts(of header: NumPyHeader) -> PresentationFacts {
        guard header.dtype.hasPrintableValues, header.dataByteCount != nil, header.shape.count <= 2 else { return .none }
        let rows = header.shape.first ?? 1
        let columns = header.shape.count == 2 ? header.shape[1] : 1
        return PresentationFacts([.grid(rows: rows, columns: columns, rowsAreLowerBound: false)])
    }

    static func description(of header: NumPyHeader) -> [(String, SummaryValue)] {
        var members: [(String, SummaryValue)] = [
            ("dtype", .string(DataTable.clip(header.dtype.display, to: 120).0)),
            ("shape", .string(header.shapeDescription))
        ]
        if let count = header.elementCount { members.append(("elementCount", .integer(count))) }
        members.append(("fortranOrder", .boolean(header.fortranOrder)))
        if header.dtype.kind == .structured {
            members.append(("fields", .array(header.dtype.fields.prefix(50).map {
                .object([("name", .string($0.name)), ("dtype", .string(DataTable.clip($0.dtype, to: 120).0))])
            })))
        }
        return members
    }
}

/// NumPy `.npz` archives (`savez`, `savez_compressed`): the arrays in the archive and the values of
/// the first printable one.
///
/// The ZIP directory is read by the shared bounded `ZIPArchiveReader`. Each member's header is
/// taken from its first bytes: stored members are read directly at their offset, deflated members
/// through a prefix inflater that stops after a small output cap, so no member is ever expanded
/// beyond that cap. Members are not CRC-checked because only their beginnings are read. Arrays
/// whose archive name looks secret contribute no values.
public struct NumPyArchiveAdapter: RandomAccessFormatAdapter {
    public init() {}

    private static let maximumListed = 100
    private static let headerPrefixBytes = 2_048
    private static let widerHeaderPrefixBytes = 32_768
    private static let valuesPrefixBytes = 49_152
    private static let inflatedHeaderBytes = 8_192
    private static let inflatedValuesBytes = 131_072

    private struct Listed {
        let entry: ZIPEntry
        let name: String
        var header: NumPyHeader?
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let archive = try ZIPArchiveReader.read(source, context: context)
        let members = archive.entries.filter { $0.kind == "file" && $0.path.lowercased().hasSuffix(".npy") }
        guard !members.isEmpty else { throw PreviewFailure.malformedDocument }
        var listed: [Listed] = []
        for entry in members.prefix(Self.maximumListed) {
            try context.checkpoint()
            let name = String(entry.path.dropLast(4))
            listed.append(Listed(entry: entry, name: name, header: try Self.header(of: entry, source: source, context: context)))
        }
        var table: DataTable?
        var shown: String?
        var facts = PresentationFacts.none
        if let chosen = listed.first(where: {
            guard let header = $0.header else { return false }
            return header.dtype.hasPrintableValues && !SecretFieldPolicy.isSensitive($0.name)
        }), let header = chosen.header {
            table = try Self.values(of: header, entry: chosen.entry, source: source, context: context)
            if table != nil { shown = chosen.name; facts = NumPyArrays.facts(of: header) }
        }
        try context.checkpoint()
        var summary: [(String, SummaryValue)] = [
            ("dataFormat", .string("NumPy archive")),
            ("arrayCount", .integer(members.count)),
            ("arrays", .array(listed.map { item in
                var fields: [(String, SummaryValue)] = [("name", .string(DataTable.clip(item.name, to: 200).0))]
                if let header = item.header {
                    fields.append(("dtype", .string(DataTable.clip(header.dtype.display, to: 120).0)))
                    fields.append(("shape", .string(header.shapeDescription)))
                }
                return .object(fields)
            }))
        ]
        if members.count > listed.count { summary.append(("partial", .boolean(true))) }
        if let shown { summary.append(("shownArray", .string(DataTable.clip(shown, to: 200).0))) }
        if let table { summary.append((DataSummaryKeys.table, table.summary)) }
        return try DataDocument.make(summary, context: context, facts: facts)
    }

    // MARK: Members

    /// The header of one member, or nil when it cannot be read from the member's beginning.
    private static func header(of entry: ZIPEntry, source: any PreviewByteSource, context: RequestContext) throws -> NumPyHeader? {
        guard !entry.isEncrypted, entry.method == 0 || entry.method == 8 else { return nil }
        do {
            if entry.method == 0 { return try storedHeader(entry, source: source, context: context) }
            for prefix in [headerPrefixBytes, widerHeaderPrefixBytes] {
                let bytes = try inflatedPrefix(entry, source: source, compressed: prefix, output: inflatedHeaderBytes, context: context)
                let parsed: NumPyHeader?
                do { parsed = try NumPyHeader.parse(available: entry.uncompressedSize, context: context, read: reader(bytes)) }
                catch let failure as PreviewFailure where failure == .malformedDocument { parsed = nil }
                if let parsed { return validated(parsed, in: entry) }
                if entry.compressedSize <= prefix { break }
            }
            return nil
        } catch let failure as PreviewFailure where failure == .malformedDocument || failure == .unsupportedFormat {
            return nil
        }
    }

    private static func storedHeader(_ entry: ZIPEntry, source: any PreviewByteSource,
                                     context: RequestContext) throws -> NumPyHeader? {
        let header = try NumPyHeader.parse(available: entry.uncompressedSize, context: context) { offset, count in
            guard offset >= 0, count >= 0, offset + count <= entry.uncompressedSize else { throw PreviewFailure.malformedDocument }
            return [UInt8](try source.read(offset: Int64(entry.payloadOffset + offset), count: count, context: context))
        }
        return validated(header, in: entry)
    }

    /// A member whose data would run past its declared size is treated as having no usable header.
    private static func validated(_ header: NumPyHeader, in entry: ZIPEntry) -> NumPyHeader? {
        if let bytes = header.dataByteCount {
            guard header.dataOffset <= entry.uncompressedSize, bytes <= entry.uncompressedSize - header.dataOffset else { return nil }
        }
        return header
    }

    private static func values(of header: NumPyHeader, entry: ZIPEntry, source: any PreviewByteSource,
                               context: RequestContext) throws -> DataTable? {
        if entry.method == 0 {
            return try NumPyTable.build(header, context: context) { offset, count in
                guard offset >= 0, count >= 0, offset + count <= entry.uncompressedSize else { return nil }
                return [UInt8](try source.read(offset: Int64(entry.payloadOffset + offset), count: count, context: context))
            }
        }
        guard entry.method == 8 else { return nil }
        let bytes = try inflatedPrefix(entry, source: source, compressed: valuesPrefixBytes, output: inflatedValuesBytes, context: context)
        return try NumPyTable.build(header, context: context) { offset, count in
            guard offset >= 0, count >= 0, offset + count <= bytes.count else { return nil }
            return Array(bytes[offset..<(offset + count)])
        }
    }

    private static func reader(_ bytes: [UInt8]) -> (Int, Int) throws -> [UInt8] {
        { offset, count in
            guard offset >= 0, count >= 0, offset + count <= bytes.count else { throw PreviewFailure.malformedDocument }
            return Array(bytes[offset..<(offset + count)])
        }
    }

    private static func inflatedPrefix(_ entry: ZIPEntry, source: any PreviewByteSource, compressed: Int,
                                       output: Int, context: RequestContext) throws -> [UInt8] {
        let count = min(entry.compressedSize, compressed)
        let data = try source.read(offset: Int64(entry.payloadOffset), count: count, context: context)
        return try PrefixInflater.inflate(data, maximumOutput: min(output, entry.uncompressedSize), context: context)
    }
}

/// Inflates the beginning of a raw DEFLATE stream. The input may be cut anywhere, so running out of
/// input is not an error; the output is capped, so the cost is bounded by the cap, not the stream.
enum PrefixInflater {
    static func inflate(_ data: Data, maximumOutput: Int, context: RequestContext) throws -> [UInt8] {
        guard maximumOutput > 0, !data.isEmpty else { return [] }
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw PreviewFailure.unavailableContent
        }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            guard let base = input.bindMemory(to: UInt8.self).baseAddress else { return [] }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            var output: [UInt8] = []
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while output.count < maximumOutput {
                try context.checkpoint()
                let capacity = min(buffer.count, maximumOutput - output.count)
                let status = buffer.withUnsafeMutableBufferPointer { target -> Int32 in
                    stream.next_out = target.baseAddress
                    stream.avail_out = uInt(capacity)
                    return zlib.inflate(&stream, Z_SYNC_FLUSH)
                }
                let produced = capacity - Int(stream.avail_out)
                output.append(contentsOf: buffer.prefix(produced))
                if status == Z_STREAM_END { break }
                // Z_BUF_ERROR with no progress means the cut input is exhausted.
                if status == Z_BUF_ERROR || (status == Z_OK && produced == 0 && stream.avail_in == 0) { break }
                guard status == Z_OK else { throw PreviewFailure.malformedDocument }
            }
            return output
        }
    }
}

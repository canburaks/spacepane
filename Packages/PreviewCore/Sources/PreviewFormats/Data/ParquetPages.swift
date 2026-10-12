import Foundation
import PreviewContracts

/// A leaf column of the Parquet schema with the levels its values carry. Only a column without
/// repeated ancestors (maximum repetition level 0) has exactly one entry per row.
struct ParquetLeaf {
    let path: [String]
    let element: ParquetFooter.SchemaElement
    let maximumDefinition: Int
    let maximumRepetition: Int

    var name: String { path.joined(separator: ".") }

    /// Leaves in file order, from the preorder schema list; nil when the list is inconsistent.
    static func leaves(of schema: [ParquetFooter.SchemaElement]) -> [ParquetLeaf]? {
        guard schema.count > 1 else { return [] }
        struct Frame { var remaining: Int; var path: [String]; var definition: Int; var repetition: Int }
        var frames = [Frame(remaining: schema[0].childCount, path: [], definition: 0, repetition: 0)]
        var result: [ParquetLeaf] = []
        for element in schema.dropFirst() {
            while let top = frames.last, top.remaining == 0 { frames.removeLast() }
            guard let last = frames.indices.last else { return nil }
            frames[last].remaining -= 1
            let frame = frames[last]
            let path = frame.path + [element.name]
            // OPTIONAL adds a definition level; REPEATED adds both a definition and a repetition level.
            let definition = frame.definition + (element.repetition == 1 || element.repetition == 2 ? 1 : 0)
            let repetition = frame.repetition + (element.repetition == 2 ? 1 : 0)
            if element.childCount > 0 {
                frames.append(Frame(remaining: element.childCount, path: path, definition: definition, repetition: repetition))
            } else {
                result.append(ParquetLeaf(path: path, element: element, maximumDefinition: definition, maximumRepetition: repetition))
            }
        }
        return result
    }
}

/// A Thrift `PageHeader`, reduced to what decoding needs.
struct ParquetPageHeader {
    enum Kind: Int { case data = 0, index = 1, dictionary = 2, dataV2 = 3 }

    var kind: Kind?
    var uncompressedSize = 0
    var compressedSize = 0
    var valueCount = 0
    var encoding = 0
    var definitionLevelEncoding = 3
    var definitionLevelBytes = 0
    var repetitionLevelBytes = 0
    var isCompressed = true
    /// Bytes the header itself occupies.
    var length = 0

    static func decode(_ bytes: [UInt8], context: RequestContext) throws -> ParquetPageHeader {
        var reader = ThriftCompactReader(bytes: bytes, context: context)
        var header = ParquetPageHeader()
        try reader.structure(depth: 1) { id, type, reader in
            switch (id, type) {
            case (1, .i32): header.kind = Kind(rawValue: Int(try reader.zigzag32()))
            case (2, .i32): header.uncompressedSize = Int(try reader.zigzag32())
            case (3, .i32): header.compressedSize = Int(try reader.zigzag32())
            case (5, .structure):
                try reader.structure(depth: 2) { field, type, reader in
                    switch (field, type) {
                    case (1, .i32): header.valueCount = Int(try reader.zigzag32())
                    case (2, .i32): header.encoding = Int(try reader.zigzag32())
                    case (3, .i32): header.definitionLevelEncoding = Int(try reader.zigzag32())
                    default: return false
                    }
                    return true
                }
            case (7, .structure):
                try reader.structure(depth: 2) { field, type, reader in
                    switch (field, type) {
                    case (1, .i32): header.valueCount = Int(try reader.zigzag32())
                    case (2, .i32): header.encoding = Int(try reader.zigzag32())
                    default: return false
                    }
                    return true
                }
            case (8, .structure):
                try reader.structure(depth: 2) { field, type, reader in
                    switch (field, type) {
                    case (1, .i32): header.valueCount = Int(try reader.zigzag32())
                    case (4, .i32): header.encoding = Int(try reader.zigzag32())
                    case (5, .i32): header.definitionLevelBytes = Int(try reader.zigzag32())
                    case (6, .i32): header.repetitionLevelBytes = Int(try reader.zigzag32())
                    case (7, .booleanTrue): header.isCompressed = true
                    case (7, .booleanFalse): header.isCompressed = false
                    default: return false
                    }
                    return true
                }
            default: return false
            }
            return true
        }
        header.length = reader.position
        guard header.uncompressedSize >= 0, header.compressedSize >= 0, header.valueCount >= 0,
              header.definitionLevelBytes >= 0, header.repetitionLevelBytes >= 0 else { throw PreviewFailure.malformedDocument }
        return header
    }
}

/// Parquet's RLE / bit-packed hybrid, used for definition levels and dictionary indices. Only the
/// first `count` values are produced, and every read is checked against the bytes available.
enum ParquetHybrid {
    static func decode(_ bytes: ArraySlice<UInt8>, bitWidth: Int, count: Int, context: RequestContext) throws -> [Int] {
        guard (0...32).contains(bitWidth), count >= 0 else { throw PreviewFailure.malformedDocument }
        var values: [Int] = []
        values.reserveCapacity(min(count, 4_096))
        var position = bytes.startIndex
        let end = bytes.endIndex
        var runs = 0
        while values.count < count {
            runs += 1
            if runs.isMultiple(of: 256) { try context.checkpoint() }
            // Run header: a varint whose low bit chooses bit-packed (1) or repeated (0).
            var header: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard position < end, shift < 35 else { throw PreviewFailure.malformedDocument }
                let byte = bytes[position]
                position += 1
                header |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            if header & 1 == 0 {
                let length = Int(min(header >> 1, UInt64(Int32.max)))
                let width = (bitWidth + 7) / 8
                guard width <= end - position else { throw PreviewFailure.malformedDocument }
                var value = 0
                for index in 0..<width { value |= Int(bytes[position + index]) << (index * 8) }
                position += width
                guard length > 0 else { throw PreviewFailure.malformedDocument }
                values.append(contentsOf: repeatElement(value, count: min(length, count - values.count)))
            } else {
                let groups = Int(min(header >> 1, UInt64(Int32.max)))
                guard groups > 0 else { throw PreviewFailure.malformedDocument }
                let byteCount = groups.multipliedReportingOverflow(by: bitWidth)
                guard !byteCount.overflow, byteCount.partialValue <= end - position else { throw PreviewFailure.malformedDocument }
                let total = groups * 8
                for index in 0..<min(total, count - values.count) {
                    var value = 0
                    var bit = index * bitWidth
                    for part in 0..<bitWidth {
                        let source = bytes[position + bit >> 3]
                        value |= Int((source >> UInt8(bit & 7)) & 1) << part
                        bit += 1
                    }
                    values.append(value)
                }
                position += byteCount.partialValue
            }
        }
        return values
    }

    /// Bits needed for values `0...maximum`.
    static func bitWidth(forMaximum maximum: Int) -> Int {
        maximum <= 0 ? 0 : Int.bitWidth - maximum.leadingZeroBitCount
    }
}

/// One value of a column chunk before display conversion.
enum ParquetRaw {
    case boolean(Bool)
    case int32(Int32)
    case int64(Int64)
    case int96(julianDay: Int32, nanosecondsOfDay: Int64)
    case float(Float)
    case double(Double)
    /// A byte array or fixed-length array: its first bytes (for text) and its full length.
    case bytes(prefix: [UInt8], length: Int)
}

/// PLAIN-encoded values, from the public encoding description.
enum ParquetPlain {
    static let maximumRetainedBytes = 512

    /// Decodes up to `count` values; running out of bytes first is malformed.
    static func decode(type: Int, typeLength: Int?, _ bytes: ArraySlice<UInt8>, count: Int,
                       context: RequestContext) throws -> [ParquetRaw] {
        var values: [ParquetRaw] = []
        values.reserveCapacity(min(count, 4_096))
        var position = bytes.startIndex
        let end = bytes.endIndex
        func take(_ width: Int) throws -> ArraySlice<UInt8> {
            guard width >= 0, width <= end - position else { throw PreviewFailure.malformedDocument }
            defer { position += width }
            return bytes[position..<(position + width)]
        }
        func little(_ slice: ArraySlice<UInt8>) -> UInt64 {
            slice.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) }
        }
        for index in 0..<count {
            if index.isMultiple(of: 1_024) { try context.checkpoint() }
            switch type {
            case 0:
                // Booleans are packed eight to a byte, least significant bit first.
                let byte = index / 8 < end - bytes.startIndex ? bytes[bytes.startIndex + index / 8] : nil
                guard let byte else { throw PreviewFailure.malformedDocument }
                values.append(.boolean((byte >> UInt8(index % 8)) & 1 == 1))
            case 1: values.append(.int32(Int32(truncatingIfNeeded: little(try take(4)))))
            case 2: values.append(.int64(Int64(bitPattern: little(try take(8)))))
            case 3:
                let raw = try take(12)
                values.append(.int96(julianDay: Int32(truncatingIfNeeded: little(raw.dropFirst(8))),
                                     nanosecondsOfDay: Int64(bitPattern: little(raw.prefix(8)))))
            case 4: values.append(.float(Float(bitPattern: UInt32(truncatingIfNeeded: little(try take(4))))))
            case 5: values.append(.double(Double(bitPattern: little(try take(8)))))
            case 6:
                let length = Int(little(try take(4)))
                let value = try take(length)
                values.append(.bytes(prefix: Array(value.prefix(maximumRetainedBytes)), length: length))
            case 7:
                guard let width = typeLength, width > 0 else { throw PreviewFailure.malformedDocument }
                let value = try take(width)
                values.append(.bytes(prefix: Array(value.prefix(maximumRetainedBytes)), length: width))
            default:
                throw PreviewFailure.unsupportedFormat
            }
        }
        return values
    }
}

/// Turns raw values into table cells using the schema's converted and logical annotations.
enum ParquetCells {
    static func cell(_ raw: ParquetRaw, leaf: ParquetLeaf) -> DataCell {
        let element = leaf.element
        let logical = element.logicalType ?? ""
        let converted = element.convertedType
        switch raw {
        case .boolean(let flag): return .text(flag ? "true" : "false")
        case .float(let value): return .text(value.description)
        case .double(let value): return .text(value.description)
        case .int32(let value):
            if converted == 6 || logical == "DATE" { return .text(date(daysSinceEpoch: Int(value))) }
            if let scale = decimalScale(element) { return .text(decimal(Int64(value), scale: scale)) }
            if let converted, (11...13).contains(converted) { return .text(String(UInt32(bitPattern: value))) }
            return .text(String(value))
        case .int64(let value):
            if let scale = decimalScale(element) { return .text(decimal(value, scale: scale)) }
            if converted == 9 || logical.hasPrefix("TIMESTAMP(MILLIS") { return .text(timestamp(value, perSecond: 1_000)) }
            if converted == 10 || logical.hasPrefix("TIMESTAMP(MICROS") { return .text(timestamp(value, perSecond: 1_000_000)) }
            if logical.hasPrefix("TIMESTAMP(NANOS") { return .text(timestamp(value, perSecond: 1_000_000_000)) }
            if converted == 14 { return .text(String(UInt64(bitPattern: value))) }
            return .text(String(value))
        case .int96(let day, let nanoseconds):
            // The legacy timestamp: a Julian day number and nanoseconds within the day.
            let epochDays = Int(day) - 2_440_588
            return .text(timestamp(Int64(epochDays) * 86_400_000_000_000 + nanoseconds, perSecond: 1_000_000_000))
        case .bytes(let prefix, let length):
            let isText = [0, 4, 19].contains(converted ?? -1) || ["STRING", "ENUM", "JSON"].contains(logical)
            if isText {
                var kept = prefix
                if length > prefix.count { trimIncompleteScalar(&kept) }
                let text = String(decoding: kept, as: UTF8.self)
                return .text(length > prefix.count ? text + "…" : text)
            }
            return .binary(byteCount: length)
        }
    }

    /// The scale of a DECIMAL annotation, from the footer's `DECIMAL(precision, scale)` spelling or the
    /// converted type with its explicit scale.
    private static func decimalScale(_ element: ParquetFooter.SchemaElement) -> Int? {
        if element.convertedType == 5 { return element.scale ?? 0 }
        guard let logical = element.logicalType, logical.hasPrefix("DECIMAL("),
              let close = logical.firstIndex(of: ")") else { return nil }
        let parts = logical[logical.index(logical.startIndex, offsetBy: 8)..<close].split(separator: ",")
        return parts.count == 2 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
    }

    private static func decimal(_ unscaled: Int64, scale: Int) -> String {
        guard scale > 0, scale < 19 else { return String(unscaled) }
        var digits = String(unscaled.magnitude)
        if digits.count <= scale { digits = String(repeating: "0", count: scale - digits.count + 1) + digits }
        digits.insert(".", at: digits.index(digits.endIndex, offsetBy: -scale))
        return (unscaled < 0 ? "-" : "") + digits
    }

    private static func date(daysSinceEpoch days: Int) -> String {
        let (year, month, day) = GeoTime.civilFromDays(days)
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// `YYYY-MM-DDThh:mm:ss[.fraction]Z` for a count of ticks since the epoch.
    private static func timestamp(_ ticks: Int64, perSecond: Int64) -> String {
        let seconds = ticks >= 0 ? ticks / perSecond : -((-ticks + perSecond - 1) / perSecond)
        let remainder = ticks - seconds * perSecond
        var text = GeoTime.format(Double(seconds))
        if remainder != 0 {
            let width = String(perSecond - 1).count
            var fraction = String(remainder)
            fraction = String(repeating: "0", count: max(0, width - fraction.count)) + fraction
            while fraction.hasSuffix("0") { fraction.removeLast() }
            text.removeLast()
            text += "." + fraction + "Z"
        }
        return text
    }

    private static func trimIncompleteScalar(_ bytes: inout [UInt8]) {
        var index = bytes.count - 1
        var continuation = 0
        while index >= 0, bytes[index] & 0xC0 == 0x80, continuation < 3 {
            index -= 1
            continuation += 1
        }
        guard index >= 0 else { return }
        let lead = bytes[index]
        let expected = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
        if expected > continuation + 1 { bytes.removeSubrange(index...) }
    }
}

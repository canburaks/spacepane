import Foundation
import PreviewContracts

/// Builds the values table of a 0-, 1- or 2-dimensional numeric array: the first 100 rows and 20
/// columns, with every number printed exactly (shortest round-trip spelling, no locale).
///
/// Only the bytes of the shown cells are read, at offsets computed from the shape and storage
/// order, so a huge array costs a few kilobytes. `read` returns nil when those bytes are not
/// available (a truncated prefix of a compressed archive member); the table is then omitted.
enum NumPyTable {
    static let maximumRows = 100
    static let maximumColumns = 20

    static func build(_ header: NumPyHeader, context: RequestContext,
                      read: (_ offset: Int, _ count: Int) throws -> [UInt8]?) throws -> DataTable? {
        let dtype = header.dtype
        guard dtype.hasPrintableValues, header.shape.count <= 2, header.shape.allSatisfy({ $0 > 0 }),
              header.dataByteCount != nil else { return nil }
        let item = dtype.itemSize
        let start = header.dataOffset
        switch header.shape.count {
        case 0:
            guard let bytes = try read(start, item), bytes.count == item else { return nil }
            var table = DataTable(kind: .identifiers, columns: ["value"])
            table.append([.text(NumPyValue.format(bytes[...], dtype: dtype))])
            return table
        case 1:
            let length = header.shape[0]
            let rows = min(length, maximumRows)
            guard let bytes = try read(start, rows * item), bytes.count == rows * item else { return nil }
            var table = DataTable(kind: .identifiers, columns: ["#", "value"],
                                  alreadyTruncated: length > rows)
            for row in 0..<rows {
                if row.isMultiple(of: 64) { try context.checkpoint() }
                table.append([.text(String(row)), .text(NumPyValue.format(bytes[(row * item)..<((row + 1) * item)], dtype: dtype))])
            }
            return table
        default:
            let rowCount = header.shape[0]
            let columnCount = header.shape[1]
            let rows = min(rowCount, maximumRows)
            let columns = min(columnCount, maximumColumns)
            var cells = [[String]](repeating: [String](repeating: "", count: columns), count: rows)
            if header.fortranOrder {
                // Element (i, j) sits at j * rowCount + i, so each shown column is contiguous.
                for column in 0..<columns {
                    try context.checkpoint()
                    guard let bytes = try read(start + column * rowCount * item, rows * item),
                          bytes.count == rows * item else { return nil }
                    for row in 0..<rows {
                        cells[row][column] = NumPyValue.format(bytes[(row * item)..<((row + 1) * item)], dtype: dtype)
                    }
                }
            } else {
                for row in 0..<rows {
                    try context.checkpoint()
                    guard let bytes = try read(start + row * columnCount * item, columns * item),
                          bytes.count == columns * item else { return nil }
                    for column in 0..<columns {
                        cells[row][column] = NumPyValue.format(bytes[(column * item)..<((column + 1) * item)], dtype: dtype)
                    }
                }
            }
            // The row-number column is in addition to the shown value columns.
            var table = DataTable(kind: .identifiers, columns: ["#"] + (0..<columns).map(String.init),
                                  limits: .init(maximumColumns: maximumColumns + 1),
                                  alreadyTruncated: rowCount > rows || columnCount > columns)
            for (row, values) in cells.enumerated() {
                table.append([.text(String(row))] + values.map { .text($0) })
            }
            return table
        }
    }
}

/// Exact textual forms of NumPy scalars. Booleans and complex numbers use Python's spelling.
enum NumPyValue {
    static func format(_ bytes: ArraySlice<UInt8>, dtype: NumPyDType) -> String {
        let little = dtype.byteOrder != .big
        func unsigned(_ range: Range<Int>) -> UInt64 {
            let slice = Array(bytes[(bytes.startIndex + range.lowerBound)..<(bytes.startIndex + range.upperBound)])
            let ordered = little ? slice : slice.reversed()
            return ordered.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << UInt64($1.offset * 8) }
        }
        let size = dtype.itemSize
        switch dtype.kind {
        case .bool:
            return unsigned(0..<1) == 0 ? "False" : "True"
        case .unsigned:
            return String(unsigned(0..<size))
        case .signed:
            let raw = unsigned(0..<size)
            let shift = UInt64(64 - size * 8)
            return String(Int64(bitPattern: raw << shift) >> Int64(shift))
        case .float:
            return spelling(unsigned(0..<size), size: size)
        case .complex:
            let half = size / 2
            let realBits = unsigned(0..<half)
            let imaginaryBits = unsigned(half..<size)
            let negative = imaginaryBits >> UInt64(half * 8 - 1) & 1 == 1
            let magnitude = imaginaryBits & ~(1 << UInt64(half * 8 - 1))
            return "\(spelling(realBits, size: half))\(negative ? "-" : "+")\(spelling(magnitude, size: half))j"
        default:
            return ""
        }
    }

    /// The shortest spelling that reads back as the same IEEE 754 value of that width, as NumPy prints.
    private static func spelling(_ bits: UInt64, size: Int) -> String {
        switch size {
        case 2:
            #if arch(arm64)
            return Float16(bitPattern: UInt16(truncatingIfNeeded: bits)).description
            #else
            return halfPrecision(UInt16(truncatingIfNeeded: bits)).description
            #endif
        case 4: return Float(bitPattern: UInt32(truncatingIfNeeded: bits)).description
        default: return Double(bitPattern: bits).description
        }
    }

    /// Widening of binary16 where the `Float16` type is unavailable.
    static func halfPrecision(_ bits: UInt16) -> Float {
        let sign: FloatingPointSign = bits & 0x8000 == 0 ? .plus : .minus
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Float(bits & 0x03FF)
        switch exponent {
        case 0: return Float(sign: sign, exponent: -24, significand: fraction)
        case 31: return fraction == 0 ? Float(sign: sign, exponentBitPattern: 0xFF, significandBitPattern: 0) : Float.nan
        default: return Float(sign: sign, exponent: exponent - 15, significand: 1 + fraction / 1024)
        }
    }
}

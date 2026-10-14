import Foundation

/// Every opcode of pickle protocols 0 to 5, written from the opcode tables in Python's documentation
/// of the `pickle` and `pickletools` modules (decision 030). The scanner walks these opcodes and
/// never builds, imports or calls anything.
enum PickleOpcode: UInt8 {
    // Protocol 0 and 1
    case mark = 0x28            // (
    case stop = 0x2E            // .
    case pop = 0x30             // 0
    case popMark = 0x31         // 1
    case dup = 0x32             // 2
    case float = 0x46           // F  decimal line
    case binFloat = 0x47        // G  8 bytes, big endian
    case int = 0x49             // I  decimal line
    case binInt = 0x4A          // J  4 bytes
    case binInt1 = 0x4B         // K  1 byte
    case long = 0x4C            // L  decimal line
    case binInt2 = 0x4D         // M  2 bytes
    case noneValue = 0x4E       // N
    case persID = 0x50          // P  line
    case binPersID = 0x51       // Q
    case reduce = 0x52          // R
    case string = 0x53          // S  quoted line
    case binString = 0x54       // T  4-byte length
    case shortBinString = 0x55  // U  1-byte length
    case unicode = 0x56         // V  raw-unicode-escape line
    case binUnicode = 0x58      // X  4-byte length
    case append = 0x61          // a
    case build = 0x62           // b
    case global = 0x63          // c  two lines
    case dict = 0x64            // d
    case appends = 0x65         // e
    case get = 0x67             // g  decimal line
    case binGet = 0x68          // h  1 byte
    case inst = 0x69            // i  two lines
    case longBinGet = 0x6A      // j  4 bytes
    case list = 0x6C            // l
    case obj = 0x6F             // o
    case put = 0x70             // p  decimal line
    case binPut = 0x71          // q  1 byte
    case longBinPut = 0x72      // r  4 bytes
    case setItem = 0x73         // s
    case tuple = 0x74           // t
    case setItems = 0x75        // u
    case emptyTuple = 0x29      // )
    case emptyList = 0x5D       // ]
    case emptyDict = 0x7D       // }
    // Protocol 2
    case proto = 0x80           // 1-byte version
    case newObj = 0x81
    case ext1 = 0x82            // 1-byte extension code
    case ext2 = 0x83            // 2 bytes
    case ext4 = 0x84            // 4 bytes
    case tuple1 = 0x85
    case tuple2 = 0x86
    case tuple3 = 0x87
    case newTrue = 0x88
    case newFalse = 0x89
    case long1 = 0x8A           // 1-byte length
    case long4 = 0x8B           // 4-byte length
    // Protocol 3
    case binBytes = 0x42        // B  4-byte length
    case shortBinBytes = 0x43   // C  1-byte length
    // Protocol 4
    case shortBinUnicode = 0x8C // 1-byte length
    case binUnicode8 = 0x8D     // 8-byte length
    case binBytes8 = 0x8E       // 8-byte length
    case emptySet = 0x8F
    case addItems = 0x90
    case frozenSet = 0x91
    case newObjEx = 0x92
    case stackGlobal = 0x93
    case memoize = 0x94
    case frame = 0x95           // 8-byte frame length
    // Protocol 5
    case byteArray8 = 0x96      // 8-byte length
    case nextBuffer = 0x97
    case readonlyBuffer = 0x98

    /// The protocol that introduced the opcode, as `pickletools` lists it.
    var protocolVersion: Int {
        switch self {
        case .mark, .stop, .pop, .dup, .float, .int, .long, .noneValue, .persID, .reduce, .string, .unicode,
             .append, .build, .global, .dict, .get, .inst, .list, .put, .setItem, .tuple:
            0
        case .popMark, .binFloat, .binInt, .binInt1, .binInt2, .binPersID, .binString, .shortBinString, .binUnicode,
             .appends, .binGet, .longBinGet, .obj, .binPut, .longBinPut, .setItems, .emptyTuple, .emptyList, .emptyDict:
            1
        case .proto, .newObj, .ext1, .ext2, .ext4, .tuple1, .tuple2, .tuple3, .newTrue, .newFalse, .long1, .long4:
            2
        case .binBytes, .shortBinBytes:
            3
        case .shortBinUnicode, .binUnicode8, .binBytes8, .emptySet, .addItems, .frozenSet, .newObjEx,
             .stackGlobal, .memoize, .frame:
            4
        case .byteArray8, .nextBuffer, .readonlyBuffer:
            5
        }
    }
}

typealias PickleBytes = Slice<UnsafeBufferPointer<UInt8>>

/// Reads the arguments of opcodes from a bounded byte range. A read past the end throws `PickleBreak`;
/// the walker decides whether that is a broken stream or the end of a window onto a larger file.
struct PickleReader {
    let bytes: UnsafeBufferPointer<UInt8>
    var position: Int

    var remaining: Int { bytes.count - position }

    mutating func byte() throws -> UInt8 {
        guard position < bytes.count else { throw PickleBreak.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    /// A little-endian unsigned integer of 1 to 8 bytes.
    mutating func littleEndian(_ width: Int) throws -> UInt64 {
        guard width <= remaining else { throw PickleBreak.truncated }
        var value: UInt64 = 0
        for index in 0..<width { value |= UInt64(bytes[position + index]) << UInt64(8 * index) }
        position += width
        return value
    }

    /// Skips `count` bytes and returns their range; `count` is checked against what is left before any
    /// arithmetic, so a length field of any size is safe.
    mutating func skip(_ count: UInt64) throws -> Range<Int> {
        guard count <= UInt64(remaining) else { throw PickleBreak.truncated }
        let start = position
        position += Int(count)
        return start..<position
    }

    /// The bytes up to the next line feed, which is consumed. Truncated when no line feed follows.
    mutating func line() throws -> Range<Int> {
        var cursor = position
        while cursor < bytes.count, bytes[cursor] != 0x0A { cursor += 1 }
        guard cursor < bytes.count else { throw PickleBreak.truncated }
        defer { position = cursor + 1 }
        return position..<cursor
    }

    /// A decimal memo index from a `GET` or `PUT` line.
    mutating func decimalLine() throws -> Int {
        let range = try line()
        guard !range.isEmpty, range.count <= 18 else { throw PickleBreak.invalid }
        var value = 0
        for index in range {
            let digit = bytes[index] &- 0x30
            guard digit < 10 else { throw PickleBreak.invalid }
            value = value * 10 + Int(digit)
        }
        return value
    }

    func text(_ range: Range<Int>, limit: Int = PickleText.maximumBytes) -> String {
        String(decoding: UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<min(range.upperBound, range.lowerBound + limit)]),
               as: UTF8.self)
    }
}

/// Why a walk stopped before STOP. `truncated` is a read past the end of the available bytes.
enum PickleBreak: Error {
    case truncated, invalid, limit
}

/// Decoding of the string-like opcodes whose values can name a module or an attribute for `STACK_GLOBAL`.
/// Python 3 accepts any `str` there, and `STRING`, `BINSTRING`, `SHORT_BINSTRING` and `UNICODE` all
/// produce `str`, so each one is decoded the way the unpickler decodes it.
enum PickleText {
    /// A string kept for resolving a name is clipped here; a longer one cannot be a module or attribute name.
    static let maximumBytes = 4_096

    /// `STRING`: a quoted Python string literal with backslash escapes. Returns nil when it is not quoted.
    static func quoted(_ line: PickleBytes) -> String? {
        guard line.count >= 2, let first = line.first, first == line.last, first == 0x27 || first == 0x22 else { return nil }
        var output: [UInt8] = []
        var index = line.startIndex + 1
        let end = line.endIndex - 1
        while index < end, output.count < maximumBytes {
            let byte = line[index]
            index += 1
            guard byte == 0x5C, index < end else { output.append(byte); continue }
            let next = line[index]
            index += 1
            switch next {
            case 0x6E: output.append(0x0A)
            case 0x72: output.append(0x0D)
            case 0x74: output.append(0x09)
            case 0x61: output.append(0x07)
            case 0x62: output.append(0x08)
            case 0x66: output.append(0x0C)
            case 0x76: output.append(0x0B)
            case 0x78:
                if index + 1 < end, let high = hexValue(line[index]), let low = hexValue(line[index + 1]) {
                    output.append(high << 4 | low)
                    index += 2
                } else { output.append(0x5C); output.append(next) }
            case 0x30...0x37:
                var value = Int(next - 0x30)
                var digits = 1
                while digits < 3, index < end, (0x30...0x37).contains(line[index]) {
                    value = value * 8 + Int(line[index] - 0x30)
                    index += 1
                    digits += 1
                }
                output.append(UInt8(truncatingIfNeeded: value))
            case 0x5C, 0x27, 0x22: output.append(next)
            default: output.append(0x5C); output.append(next)
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// `UNICODE`: raw-unicode-escape, where only `\uXXXX` and `\UXXXXXXXX` are escapes and other bytes are Latin-1.
    static func rawUnicodeEscape(_ line: PickleBytes) -> String {
        var scalars = String.UnicodeScalarView()
        var kept = 0
        var index = line.startIndex
        while index < line.endIndex, kept < maximumBytes {
            kept += 1
            let byte = line[index]
            if byte == 0x5C, index + 1 < line.endIndex, line[index + 1] == 0x75 || line[index + 1] == 0x55 {
                let digits = line[index + 1] == 0x75 ? 4 : 8
                if index + 2 + digits <= line.endIndex,
                   let value = hexNumber(line[(index + 2)..<(index + 2 + digits)]), let scalar = Unicode.Scalar(value) {
                    scalars.append(scalar)
                    index += 2 + digits
                    continue
                }
            }
            scalars.append(Unicode.Scalar(byte))
            index += 1
        }
        return String(scalars)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private static func hexNumber(_ digits: PickleBytes) -> UInt32? {
        var value: UInt32 = 0
        for digit in digits {
            guard let part = hexValue(digit) else { return nil }
            value = value << 4 | UInt32(part)
        }
        return value
    }
}

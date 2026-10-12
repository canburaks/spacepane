import Foundation
import PreviewContracts

enum TextDecoder {
    /// `enforcesLineLength` is false only for adapters that declare `TextInputPolicy.allowsLongLines`
    /// and apply the line budget to their own output; every other limit and the binary check still apply.
    static func decode(_ file: FileBytes, context: RequestContext, enforcesLineLength: Bool = true) throws -> DecodedText {
        try context.checkpoint()
        let bytes = file.data
        let text: String
        let encoding: TextEncoding
        let hasByteOrderMark: Bool
        if bytes.starts(with: [0xFF, 0xFE]) {
            encoding = .utf16LittleEndian
            hasByteOrderMark = true
            text = try decodeUTF16(bytes.dropFirst(2), littleEndian: true)
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            encoding = .utf16BigEndian
            hasByteOrderMark = true
            text = try decodeUTF16(bytes.dropFirst(2), littleEndian: false)
        } else {
            encoding = .utf8
            hasByteOrderMark = bytes.starts(with: [0xEF, 0xBB, 0xBF])
            let content = hasByteOrderMark ? bytes.dropFirst(3) : bytes[...]
            guard let decoded = String(data: content, encoding: .utf8) else { throw PreviewFailure.unsupportedEncoding }
            text = decoded
        }
        _ = try TextMetrics.validate(text, context: context, enforcesLineLength: enforcesLineLength)
        guard text.utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        try context.checkpoint()
        return DecodedText(text: text, encoding: encoding, byteCount: bytes.count, hasByteOrderMark: hasByteOrderMark)
    }

    private static func decodeUTF16(_ bytes: Data.SubSequence, littleEndian: Bool) throws -> String {
        guard bytes.count.isMultiple(of: 2) else { throw PreviewFailure.unsupportedEncoding }
        let raw = Array(bytes)
        var units: [UInt16] = []
        units.reserveCapacity(raw.count / 2)
        for index in stride(from: 0, to: raw.count, by: 2) {
            let unit = littleEndian ? UInt16(raw[index]) | UInt16(raw[index + 1]) << 8
                : UInt16(raw[index]) << 8 | UInt16(raw[index + 1])
            units.append(unit)
        }
        var index = 0
        while index < units.count {
            let unit = units[index]
            if (0xD800...0xDBFF).contains(unit) {
                guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else {
                    throw PreviewFailure.unsupportedEncoding
                }
                index += 2
            } else {
                guard !(0xDC00...0xDFFF).contains(unit) else { throw PreviewFailure.unsupportedEncoding }
                index += 1
            }
        }
        return String(decoding: units, as: UTF16.self)
    }
}

/// Count the visual line separators accepted by the native text system. CRLF is one
/// break; CR, LF, NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR are independent breaks.
/// The same pass enforces per-line bytes and rejects binary control characters.
enum TextMetrics {
    static func validate(_ text: String, context: RequestContext, enforcesLineLength: Bool = true) throws -> Int {
        guard !text.isEmpty else { return 0 }
        var lines = 1
        var lineBytes = 0
        var previousWasCR = false
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index.isMultiple(of: 1024) { try context.checkpoint() }
            switch scalar.value {
            case 10:
                if !previousWasCR { lines += 1 }
                lineBytes = 0
                previousWasCR = false
            case 13, 0x85, 0x2028, 0x2029:
                lines += 1
                lineBytes = 0
                previousWasCR = scalar.value == 13
            default:
                previousWasCR = false
                lineBytes += scalar.utf8.count
                if (scalar.value < 32 && scalar.value != 9) || scalar.value == 127 {
                    throw PreviewFailure.binaryContent
                }
            }
            guard lines <= context.budget.maxTextLines else { throw PreviewFailure.tooManyLines }
            guard !enforcesLineLength || lineBytes <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
        }
        try context.checkpoint()
        return lines
    }
}

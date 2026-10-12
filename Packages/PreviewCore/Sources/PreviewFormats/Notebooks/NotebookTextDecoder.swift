import Foundation
import PreviewContracts

/// Strict notebook decoding before JSON validation. Image payloads may exceed displayed-text limits;
/// those limits apply only after their exact spans have been replaced. Source bytes remain bounded.
enum NotebookTextDecoder {
    static func decode(_ input: FileBytes, context: RequestContext) throws -> DecodedText {
        try context.checkpoint()
        let data = input.data
        guard data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let encoding: TextEncoding
        let text: String
        let hasBOM: Bool
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            let littleEndian = data.starts(with: [0xFF, 0xFE])
            encoding = littleEndian ? .utf16LittleEndian : .utf16BigEndian
            hasBOM = true
            let raw = Array(data.dropFirst(2))
            guard raw.count.isMultiple(of: 2) else { throw PreviewFailure.unsupportedEncoding }
            var units: [UInt16] = []
            units.reserveCapacity(raw.count / 2)
            for index in stride(from: 0, to: raw.count, by: 2) {
                if index.isMultiple(of: 2_048) { try context.checkpoint() }
                units.append(littleEndian ? UInt16(raw[index]) | UInt16(raw[index + 1]) << 8
                             : UInt16(raw[index]) << 8 | UInt16(raw[index + 1]))
            }
            var index = 0
            var checkpointIndex = 0
            while index < units.count {
                if index - checkpointIndex >= 1_024 {
                    try context.checkpoint()
                    checkpointIndex = index
                }
                if (0xD800...0xDBFF).contains(units[index]) {
                    guard index + 1 < units.count, (0xDC00...0xDFFF).contains(units[index + 1]) else {
                        throw PreviewFailure.unsupportedEncoding
                    }
                    index += 2
                } else {
                    guard !(0xDC00...0xDFFF).contains(units[index]) else { throw PreviewFailure.unsupportedEncoding }
                    index += 1
                }
            }
            text = String(decoding: units, as: UTF16.self)
        } else {
            encoding = .utf8
            hasBOM = data.starts(with: [0xEF, 0xBB, 0xBF])
            let bytes = hasBOM ? data.dropFirst(3) : data[...]
            guard let decoded = String(data: bytes, encoding: .utf8) else { throw PreviewFailure.unsupportedEncoding }
            text = decoded
        }
        guard text.utf8.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        try context.checkpoint()
        return DecodedText(text: text, encoding: encoding, byteCount: data.count, hasByteOrderMark: hasBOM)
    }
}

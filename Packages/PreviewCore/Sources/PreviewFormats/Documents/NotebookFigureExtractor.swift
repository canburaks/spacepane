import Foundation
import PreviewContracts

/// Saved PNG/JPEG in display_data/execute_result outputs only. No pixels, rich-output rendering or
/// execution. Alphabet, padding and cumulative decoded size are checked across every array piece
/// before a joined payload or decoded-byte allocation; images use the shared bounded collector.
enum NotebookFigureExtractor {
    static let mimeTypes = ["image/png", "image/jpeg"]

    static func figures(in root: NotebookJSONValue, context: RequestContext) throws -> [PreviewImage] {
        var collector = ImageCollector(limits: DocumentLimits(context: context))
        guard case .array(let cells)? = try root.member("cells") else { return [] }
        for cell in cells {
            try context.checkpoint()
            guard case .string(let cellType)? = try cell.member("cell_type"), cellType.value == "code",
                  case .array(let outputs)? = try cell.member("outputs") else { continue }
            for output in outputs {
                try context.checkpoint()
                guard case .string(let type)? = try output.member("output_type"),
                      ["display_data", "execute_result"].contains(type.value),
                      let data = try output.member("data"), case .object = data else { continue }
                for mime in mimeTypes {
                    try context.checkpoint()
                    guard !collector.isFull else { return collector.images }
                    guard let value = try? data.member(mime),
                          let payload = try Base64Payload.inspect(value, context: context) else { continue }
                    // No normalized base64 or decoded bytes exist yet. Aggregate ceilings bind first.
                    guard collector.canAccept(encodedBytes: payload.decodedByteCount) else { return collector.images }
                    guard let decoded = try payload.decode(context: context),
                          EmbeddedImageValidator.sniff(decoded) == (mime == "image/png" ? .png : .jpeg) else { continue }
                    if let figure = try EmbeddedImageValidator.validate(decoded, role: .figure, context: context) {
                        collector.append(figure)
                    }
                }
            }
        }
        return collector.images
    }

    private struct Base64Payload {
        let pieces: [String]
        let characterCount: Int
        let decodedByteCount: Int

        static func inspect(_ value: NotebookJSONValue, context: RequestContext) throws -> Self? {
            let pieces: [String]
            switch value {
            case .string(let token): pieces = [token.value]
            case .array(let values):
                var strings: [String] = []
                for value in values {
                    try context.checkpoint()
                    guard case .string(let token) = value else { return nil }
                    strings.append(token.value)
                }
                pieces = strings
            default: return nil
            }
            let maximumCharacters = (DocumentLimits.maximumEncodedImageBytes + 2) / 3 * 4
            var characters = 0
            var padding = 0
            var lastSextet: UInt8 = 0
            var scanned = 0
            for piece in pieces {
                for byte in piece.utf8 {
                    scanned += 1
                    if scanned.isMultiple(of: 1_024) { try context.checkpoint() }
                    if whitespace(byte) { continue }
                    characters += 1
                    guard characters <= maximumCharacters else { return nil }
                    if byte == 61 {
                        padding += 1
                        guard padding <= 2 else { return nil }
                    } else {
                        guard padding == 0, let sextet = sextet(byte) else { return nil }
                        lastSextet = sextet
                    }
                }
            }
            guard characters > 0, characters.isMultiple(of: 4) else { return nil }
            // Unused tail bits must be zero; padding is terminal and at most two characters.
            guard padding != 1 || lastSextet & 3 == 0,
                  padding != 2 || lastSextet & 15 == 0 else { return nil }
            let decodedBytes = characters / 4 * 3 - padding
            guard decodedBytes > 0, decodedBytes <= DocumentLimits.maximumEncodedImageBytes else { return nil }
            try context.checkpoint()
            return Self(pieces: pieces, characterCount: characters, decodedByteCount: decodedBytes)
        }

        func decode(context: RequestContext) throws -> Data? {
            var normalized: [UInt8] = []
            normalized.reserveCapacity(characterCount)
            var scanned = 0
            for piece in pieces {
                for byte in piece.utf8 {
                    scanned += 1
                    if scanned.isMultiple(of: 1_024) { try context.checkpoint() }
                    if !Self.whitespace(byte) { normalized.append(byte) }
                }
            }
            try context.checkpoint()
            guard let decoded = Data(base64Encoded: Data(normalized)), decoded.count == decodedByteCount else { return nil }
            try context.checkpoint()
            return decoded
        }

        private static func whitespace(_ byte: UInt8) -> Bool { byte == 9 || byte == 10 || byte == 13 || byte == 32 }

        private static func sextet(_ byte: UInt8) -> UInt8? {
            switch byte {
            case 65...90: byte - 65
            case 97...122: byte - 71
            case 48...57: byte + 4
            case 43: 62
            case 47: 63
            default: nil
            }
        }
    }
}

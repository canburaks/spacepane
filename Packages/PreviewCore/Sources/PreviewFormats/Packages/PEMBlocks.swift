import Foundation
import PreviewContracts

/// One encapsulated block of a PEM (RFC 7468) text: its label and the byte range of its body lines.
struct PEMBlock: Equatable {
    let label: String
    /// Bytes between the BEGIN and END lines. For a block without an END line this runs to the end of the input.
    let body: Range<Int>
    let isTerminated: Bool

    /// Private key material in any encoding or armor: such blocks are only counted, never decoded or shown.
    var isPrivateKey: Bool { label.contains("PRIVATE KEY") }
    var isCertificate: Bool { ["CERTIFICATE", "X509 CERTIFICATE", "TRUSTED CERTIFICATE"].contains(label) }
}

enum PEMScanner {
    private static let beginPrefix = Array("-----BEGIN ".utf8)
    private static let endPrefix = Array("-----END ".utf8)
    private static let dashes = Array("-----".utf8)
    static let maximumLabelBytes = 64

    /// Finds up to `maximumBlocks` blocks. `truncated` reports blocks left unread past that limit.
    /// Block bodies are located but not interpreted here; a private-key body is never decoded.
    static func scan(_ bytes: [UInt8], maximumBlocks: Int, context: RequestContext) throws -> (blocks: [PEMBlock], truncated: Bool) {
        var blocks: [PEMBlock] = []
        var position = 0
        var truncated = false
        while position < bytes.count {
            try context.checkpoint()
            let (lineEnd, next) = lineBounds(bytes, from: position)
            if let label = beginLabel(bytes[position..<lineEnd]) {
                if blocks.count == maximumBlocks { truncated = true; break }
                let bodyStart = next
                var cursor = next
                var terminated = false
                var bodyEnd = bytes.count
                var resume = bytes.count
                var linesRead = 0
                while cursor < bytes.count {
                    linesRead += 1
                    if linesRead.isMultiple(of: 4_096) { try context.checkpoint() }
                    let (end, following) = lineBounds(bytes, from: cursor)
                    if isEnd(bytes[cursor..<end], label: label) {
                        terminated = true
                        bodyEnd = cursor
                        resume = following
                        break
                    }
                    cursor = following
                }
                blocks.append(PEMBlock(label: label, body: bodyStart..<min(bodyEnd, bytes.count), isTerminated: terminated))
                position = resume
            } else {
                position = next
            }
        }
        return (blocks, truncated)
    }

    /// Decodes a base64 body. Whitespace is dropped; any other character outside the alphabet is rejected.
    static func decodeBase64(_ bytes: ArraySlice<UInt8>, maximumDecodedBytes: Int) -> Data? {
        var filtered: [UInt8] = []
        filtered.reserveCapacity(bytes.count)
        for byte in bytes {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: continue
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="):
                filtered.append(byte)
            default: return nil
            }
        }
        guard !filtered.isEmpty, filtered.count / 4 * 3 <= maximumDecodedBytes + 3 else { return nil }
        guard let data = Data(base64Encoded: Data(filtered)), data.count <= maximumDecodedBytes else { return nil }
        return data
    }

    private static func lineBounds(_ bytes: [UInt8], from start: Int) -> (end: Int, next: Int) {
        var end = start
        while end < bytes.count, bytes[end] != 0x0A { end += 1 }
        let next = min(end + 1, bytes.count)
        if end > start, bytes[end - 1] == 0x0D { end -= 1 }
        return (end, max(next, start + 1))
    }

    private static func beginLabel(_ line: ArraySlice<UInt8>) -> String? {
        guard line.count > beginPrefix.count + dashes.count, line.starts(with: beginPrefix),
              line.suffix(dashes.count).elementsEqual(dashes) else { return nil }
        let label = line.dropFirst(beginPrefix.count).dropLast(dashes.count)
        guard label.count <= maximumLabelBytes, !label.isEmpty,
              label.allSatisfy({ ($0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z")) || ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9")) || $0 == 0x20 }) else { return nil }
        return String(decoding: label, as: UTF8.self)
    }

    private static func isEnd(_ line: ArraySlice<UInt8>, label: String) -> Bool {
        let expected = endPrefix + Array(label.utf8) + dashes
        return line.elementsEqual(expected)
    }
}

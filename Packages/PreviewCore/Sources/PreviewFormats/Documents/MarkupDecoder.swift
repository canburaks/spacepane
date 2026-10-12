import Foundation
import CoreFoundation
import PreviewContracts

/// Turns the bytes of an XML, XHTML, HTML or MIME text part into a String. A byte order mark wins, then an
/// explicit charset (a MIME header or the document's own declaration), then UTF-8. Bytes that do not fit the
/// chosen encoding are shown as replacement characters instead of failing the whole document: a single bad
/// chapter must not hide the rest of a book.
enum MarkupDecoder {
    /// Declarations are only searched in the first bytes, as the XML and HTML specifications require.
    static let declarationWindow = 1_024

    static func decode(_ data: Data, declaredCharset: String? = nil, context: RequestContext) throws -> String {
        try context.checkpoint()
        let bytes = [UInt8](data)
        let text: String
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            text = String(decoding: bytes.dropFirst(3), as: UTF8.self)
        } else if bytes.starts(with: [0xFF, 0xFE]) {
            text = String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) ?? lossy(bytes)
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            text = String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) ?? lossy(bytes)
        } else if let encoding = (declaredCharset.flatMap(encoding(named:)) ?? sniffedEncoding(bytes)),
                  encoding != .utf8 {
            text = String(data: data, encoding: encoding) ?? lossy(bytes)
        } else {
            text = lossy(bytes)
        }
        try context.checkpoint()
        return text
    }

    /// Foundation encoding for an IANA charset name such as `windows-1251` or `shift_jis`, or `nil`.
    static func encoding(named name: String) -> String.Encoding? {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
        guard !trimmed.isEmpty, trimmed.utf8.count <= 64 else { return nil }
        let converted = CFStringConvertIANACharSetNameToEncoding(trimmed as CFString)
        guard converted != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(converted))
    }

    private static func lossy(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    /// `encoding="…"` in an XML declaration, or `charset=…` in an HTML `<meta>` element, within the first bytes.
    private static func sniffedEncoding(_ bytes: [UInt8]) -> String.Encoding? {
        let head = String(decoding: bytes.prefix(declarationWindow), as: UTF8.self)
        for key in ["encoding", "charset"] {
            var search = head.startIndex..<head.endIndex
            while let found = head.range(of: key, options: .caseInsensitive, range: search) {
                var rest = head[found.upperBound...].drop { $0 == " " }
                if rest.first == "=" {
                    rest = rest.dropFirst().drop { $0 == " " || $0 == "\"" || $0 == "'" }
                    let name = rest.prefix { $0.isLetter || $0.isNumber || "-_:.".contains($0) }
                    if !name.isEmpty, let encoding = encoding(named: String(name)) { return encoding }
                }
                search = found.upperBound..<head.endIndex
            }
        }
        return nil
    }
}

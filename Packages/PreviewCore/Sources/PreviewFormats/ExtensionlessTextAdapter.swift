import Foundation
import PreviewContracts

/// A file whose name has no extension can hold anything, so this adapter receives the
/// bounded bytes and decides whether they are text. Bytes that are not valid UTF-8, or
/// UTF-16 with a byte-order mark, are reported as binary content and never displayed;
/// the shared metrics pass also rejects text that carries binary control characters.
///
/// Text is then styled by its first line: a script that names its interpreter is
/// source code, anything else is plain text. The interpreter also names the language hint
/// (`#!/usr/bin/env python3` is Python). Well-known names are catalog aliases of the
/// source-code format instead.
public struct ExtensionlessTextAdapter: BinaryFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let decoded = try Self.decode(input.data)
        guard decoded.text.utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        let isScript = decoded.text.hasPrefix(Self.interpreterMarker)
        let document = isScript
            ? try SourceCodeAdapter().parse(decoded, context: context)
            : try TextAdapter().parse(decoded, context: context)
        let credentialRanges = try CredentialFilePrivacyRanges.ranges(in: decoded.text, filename: context.nameHint?.filename, context: context)
        // The interpreter named on the first line chooses the language when the name cannot.
        let language = isScript
            ? document.sourceLanguage ?? SourceLanguageDetector.language(forInterpreterLine: decoded.text.prefix(while: { $0 != "\n" && $0 != "\r" }))
            : nil
        return ParsedTextDocument(text: document.text,
                                  sensitiveRanges: SecretRangeBudget.capped(document.sensitiveRanges + (credentialRanges ?? []), byteCount: document.text.utf8.count, context: context),
                                  usesStructuredPrivacy: document.usesStructuredPrivacy || credentialRanges != nil, syntax: document.syntax,
                                  decodedEncoding: decoded.encoding, sourceLanguage: language)
    }

    private static let interpreterMarker = "#!"
    private static let utf8Mark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LittleEndianMark: [UInt8] = [0xFF, 0xFE]
    private static let utf16BigEndianMark: [UInt8] = [0xFE, 0xFF]

    private static func decode(_ data: Data) throws -> DecodedText {
        let bytes = [UInt8](data)
        let text: String?
        let encoding: TextEncoding
        let mark: Int
        if bytes.starts(with: utf16LittleEndianMark) || bytes.starts(with: utf16BigEndianMark) {
            let littleEndian = bytes.starts(with: utf16LittleEndianMark)
            (encoding, mark) = (littleEndian ? .utf16LittleEndian : .utf16BigEndian, 2)
            let body = bytes.dropFirst(mark)
            // Strict decoding: an odd length or an unpaired surrogate is not text.
            guard body.count.isMultiple(of: 2) else { throw PreviewFailure.binaryContent }
            let units = stride(from: body.startIndex, to: body.endIndex, by: 2).map { index in
                littleEndian ? UInt16(body[index]) | UInt16(body[index + 1]) << 8
                             : UInt16(body[index]) << 8 | UInt16(body[index + 1])
            }
            text = String(validating: units, as: UTF16.self)
        } else {
            (encoding, mark) = (.utf8, bytes.starts(with: utf8Mark) ? utf8Mark.count : 0)
            text = String(validating: bytes.dropFirst(mark), as: UTF8.self)
        }
        // A NUL never occurs in text; rejecting it here also covers unmarked UTF-16 and most binaries.
        guard let text, !text.unicodeScalars.contains(where: { $0.value == 0 }) else { throw PreviewFailure.binaryContent }
        return DecodedText(text: text, encoding: encoding, byteCount: bytes.count, hasByteOrderMark: mark > 0)
    }
}

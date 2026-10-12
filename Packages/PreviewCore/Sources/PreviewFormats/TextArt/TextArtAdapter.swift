import PreviewContracts

/// Binary adapter for scene-style `.nfo`/`.diz` text art, which is usually IBM code page 437.
///
/// Decoding policy (all input is untrusted, nothing is interpreted):
/// 1. Input above `maxInputBytes` is rejected before any scan.
/// 2. A trailing run of Ctrl-Z (0x1A), the DOS end-of-file marker that many NFO/DIZ files end
///    with, is dropped. Any other occurrence is a control byte.
/// 3. Binary signals fail with `binaryContent`: a NUL byte anywhere (which also rejects
///    UTF-16 and most real binaries), every other C0 control except TAB, LF and CR, and DEL.
///    This matches the shared text path, which treats the same bytes as binary, and it
///    means no glyph guessing for ESC (ANSI art), BEL or form feed. The conventional
///    glyphs for 0x01...0x1F and 0x7F are deliberately not applied.
/// 4. Valid UTF-8, with an optional BOM that is dropped, decodes as UTF-8. Pure ASCII is
///    therefore reported as UTF-8. Any other byte sequence decodes as code page 437 using the
///    complete 0x80...0xFF table in `CodePage437`; a BOM-like prefix on that path is data.
/// 5. Decoded output is bounded by `maxOutputUTF8Bytes` while decoding, since box-drawing
///    bytes expand to three UTF-8 bytes each, then by `maxTextLines` and `maxLineUTF8Bytes`.
///
/// The text is returned exactly as decoded (no line-ending or whitespace normalization) with
/// plain syntax, and the encoding actually used is reported via `decodedEncoding`.
/// `usesStructuredPrivacy` stays `false` so the shared assignment heuristic applies.
public struct TextArtAdapter: BinaryFormatAdapter {
    public init() {}

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let bytes = [UInt8](input.data)
        var end = bytes.count
        while end > 0, bytes[end - 1] == Self.endOfFile { end -= 1 }
        let body = bytes[..<end]
        try rejectBinarySignals(body, context: context)
        let text: String
        let encoding: TextEncoding
        let withoutBOM = body.starts(with: [0xEF, 0xBB, 0xBF]) ? body.dropFirst(3) : body
        if let utf8 = String(validating: withoutBOM, as: UTF8.self) {
            text = utf8
            encoding = .utf8
        } else {
            text = try decodeCodePage437(body, context: context)
            encoding = .codePage437
        }
        try validateLimits(text, context: context)
        return ParsedTextDocument(text: text, usesStructuredPrivacy: false, syntax: .plain, decodedEncoding: encoding)
    }

    private static let endOfFile: UInt8 = 0x1A

    private func rejectBinarySignals(_ body: ArraySlice<UInt8>, context: RequestContext) throws {
        for (offset, byte) in body.enumerated() {
            if offset.isMultiple(of: 4096) { try context.checkpoint() }
            if (byte < 0x20 && byte != 9 && byte != 10 && byte != 13) || byte == 0x7F { throw PreviewFailure.binaryContent }
        }
        try context.checkpoint()
    }

    private func decodeCodePage437(_ body: ArraySlice<UInt8>, context: RequestContext) throws -> String {
        var scalars = String.UnicodeScalarView()
        var outputBytes = 0
        for (offset, byte) in body.enumerated() {
            if offset.isMultiple(of: 4096) { try context.checkpoint() }
            let scalar: Unicode.Scalar
            if byte < 0x80 {
                scalar = Unicode.Scalar(byte)
            } else if let mapped = Unicode.Scalar(UInt32(CodePage437.upperHalf[Int(byte) - 0x80])) {
                scalar = mapped
            } else {
                throw PreviewFailure.unsupportedEncoding
            }
            outputBytes += scalar.utf8.count
            guard outputBytes <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Same accounting as the shared text limits: CRLF is one break, LF and CR are breaks.
    private func validateLimits(_ text: String, context: RequestContext) throws {
        let utf8 = text.utf8
        guard utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        var lines = 1
        var lineBytes = 0
        var previousCR = false
        for (index, byte) in utf8.enumerated() {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            if byte == 10 || byte == 13 {
                if byte != 10 || !previousCR { lines += 1 }
                guard lines <= context.budget.maxTextLines else { throw PreviewFailure.tooManyLines }
                lineBytes = 0
            } else {
                lineBytes += 1
                guard lineBytes <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
            }
            previousCR = byte == 13
        }
        try context.checkpoint()
    }
}

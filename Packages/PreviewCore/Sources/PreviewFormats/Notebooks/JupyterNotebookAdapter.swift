import Foundation
import PreviewContracts

/// Read-only Jupyter notebook (nbformat 4) adapter.
///
/// The adapter validates and annotates; it never executes, imports, evaluates widgets, invokes
/// nbconvert or interprets HTML/JavaScript/SVG outputs. Cell code is only ever text.
///
/// - Input: strict UTF-8/UTF-16 byte decoding with an adapter-owned input budget. Raw JSON grammar,
///   depth and nodes are validated before figures; displayed text keeps the standard output/line
///   ceilings after image output strings/arrays become inert JSON `null` placeholders.
/// - Syntax: bounded JSON validation with `JSONScanner` (depth, node count, checkpoints).
/// - Variants: `nbformat` 4 (any `nbformat_minor`) is supported. Any other integer version,
///   including nbformat 3 (`worksheets`), is `PreviewFailure.unsupportedFormat`, never an
///   approximate rendering. JSON that is not a notebook (no numeric `nbformat`, no `cells` array,
///   unknown `cell_type`, ill-typed `source`/`outputs`) is `PreviewFailure.malformedDocument`.
/// - Text: exact decoded source outside replaced image values, syntax `.json`. Replacement reports
///   `.converted` provenance; a notebook without replacements remains `.source`.
/// - Privacy: structured JSON privacy only. Ranges are the shared key-based JSON ranges plus every
///   string token whose decoded content holds a sensitive assignment (`NotebookPrivacyRanges`).
/// - Figures: `image/png` and `image/jpeg` outputs are validated and returned as `PreviewImage`s with the
///   `figure` role (header dimensions only, never decoded here); see `NotebookFigureExtractor`. Every other
///   image or rich output is still never rendered or decoded.
/// - Findings: `NotebookHealth` reads the same validated tree for execution order, gaps, cells that
///   never ran and saved errors. It reports structural integers only and never changes the text,
///   the ranges or the failures above.
public struct JupyterNotebookAdapter: FormatAdapter, BinaryFormatAdapter {
    public init() {}

    public static let defaultBudget = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 5_000)

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(NotebookTextDecoder.decode(input, context: context), context: context)
    }

    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard input.byteCount <= context.budget.maxInputBytes,
              input.text.utf8.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let bytes = Array(input.text.utf8)
        var scanner = JSONScanner(bytes: bytes, context: context)
        try scanner.scan()
        var builder = NotebookJSONTreeBuilder(bytes: bytes, context: context)
        let root = try builder.build()
        try NotebookShape.validate(root, bytes: bytes, context: context)
        let ranges = NotebookPrivacyRanges.merged(
            scanner.sensitiveRanges + (try NotebookPrivacyRanges.ranges(in: root, context: context)))
        let findings = try NotebookHealth.findings(in: root, bytes: bytes, context: context)
        let source = try NotebookImageSource.transform(bytes, root: root, sensitiveRanges: ranges, context: context)
        try ExpandedTextLimits.validate(DecodedText(text: source.text, encoding: input.encoding,
                                                   byteCount: input.byteCount), context: context)
        try context.checkpoint()
        // Saved PNG/JPEG figures are the only pictures taken from a notebook; see `NotebookFigureExtractor`.
        let figures = try NotebookFigureExtractor.figures(in: root, context: context)
        return ParsedTextDocument(text: source.text, sensitiveRanges: source.sensitiveRanges, usesStructuredPrivacy: true,
                                  syntax: .json, decodedEncoding: input.encoding, images: figures, findings: findings,
                                  origin: source.changed ? .converted : .source)
    }
}

/// What this preview commits to display. Only fields the safe notebook view reads are typed;
/// everything else (metadata, attachments, widget state) is permitted but never interpreted.
enum NotebookShape {
    static func validate(_ root: NotebookJSONValue, bytes: [UInt8], context: RequestContext) throws {
        guard case .object = root else { throw PreviewFailure.malformedDocument }
        guard case .number(let version)? = try root.member("nbformat") else { throw PreviewFailure.malformedDocument }
        guard bytes[version].elementsEqual("4".utf8) else { throw PreviewFailure.unsupportedFormat }
        if let minor = try root.member("nbformat_minor") {
            guard case .number(let range) = minor, isNonNegativeInteger(bytes[range]) else {
                throw PreviewFailure.malformedDocument
            }
        }
        guard case .array(let cells)? = try root.member("cells") else { throw PreviewFailure.malformedDocument }
        for cell in cells {
            try context.checkpoint()
            try validateCell(cell, context: context)
        }
    }

    private static func validateCell(_ cell: NotebookJSONValue, context: RequestContext) throws {
        guard case .object = cell, case .string(let type)? = try cell.member("cell_type") else {
            throw PreviewFailure.malformedDocument
        }
        guard ["markdown", "code", "raw"].contains(where: { type.value.utf8.elementsEqual($0.utf8) }) else {
            throw PreviewFailure.malformedDocument
        }
        guard let source = try cell.member("source"), isMultilineText(source) else { throw PreviewFailure.malformedDocument }
        guard let outputs = try cell.member("outputs") else { return }
        guard case .array(let items) = outputs else { throw PreviewFailure.malformedDocument }
        for output in items {
            try context.checkpoint()
            try validateOutput(output)
        }
    }

    private static func validateOutput(_ output: NotebookJSONValue) throws {
        guard case .object = output, case .string(let type)? = try output.member("output_type") else {
            throw PreviewFailure.malformedDocument
        }
        switch type.value {
        case "stream":
            if let text = try output.member("text"), !isMultilineText(text) { throw PreviewFailure.malformedDocument }
        case "execute_result", "display_data":
            if let data = try output.member("data") {
                guard case .object = data else { throw PreviewFailure.malformedDocument }
            }
        case "error":
            for field in ["ename", "evalue"] {
                if let value = try output.member(field), !isString(value) { throw PreviewFailure.malformedDocument }
            }
            if let traceback = try output.member("traceback") {
                guard case .array(let lines) = traceback, lines.allSatisfy(isString) else {
                    throw PreviewFailure.malformedDocument
                }
            }
        default:
            break   // Unknown output types are shown only as an inert placeholder.
        }
    }

    /// nbformat "multiline string": one string, or an array of strings joined without separator.
    private static func isMultilineText(_ value: NotebookJSONValue) -> Bool {
        switch value {
        case .string: true
        case .array(let lines): lines.allSatisfy(isString)
        default: false
        }
    }

    private static func isString(_ value: NotebookJSONValue) -> Bool {
        if case .string = value { true } else { false }
    }

    private static func isNonNegativeInteger(_ lexeme: ArraySlice<UInt8>) -> Bool {
        guard (1...9).contains(lexeme.count), lexeme.allSatisfy({ (48...57).contains($0) }) else { return false }
        return lexeme.count == 1 || lexeme.first != 48
    }
}

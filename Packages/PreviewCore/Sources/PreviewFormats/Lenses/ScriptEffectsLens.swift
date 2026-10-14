import Foundation
import PreviewContracts

/// Script effects lens: what a shell, AppleScript, PowerShell or batch script would do when run.
/// Decision 029. Workstream `sl2-script` owns this file.
///
/// It reads the displayed (concealed) text of source code and extension-free text whose language is
/// shell-family, fish, PowerShell, batch or AppleScript, and reports nine kinds of effect as typed
/// findings with a count and the lines where each occurrence starts. It follows the rules of decision 029:
///
/// - Facts, not verdicts, and conservative: commands are recognized as commands (at command position,
///   through wrappers such as `sudo`), never as words in a message or a variable name. A missed detection
///   is acceptable; a false alarm on an ordinary script is a defect.
/// - Comments do not count, and neither does text a here-document merely writes to a file.
/// - Nothing is run, expanded or decoded. A decode-and-run finding says only that the script decodes
///   text and runs the result.
/// - Work is linear in the text, checks the request's checkpoint at least every 256 lines, and looks at
///   no more than the first 64 KiB of a line.
/// - Findings carry kinds, counts and lines, never a URL, a path or any other source value.
public struct ScriptEffectsLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        guard let dialect = ScriptDialect(request: request, text: text) else { return [] }
        try context.checkpoint()
        var contiguous = text
        contiguous.makeContiguousUTF8()
        let tally = try contiguous.utf8.withContiguousStorageIfAvailable { bytes in
            try Self.scan(bytes, dialect: dialect, context: context)
        } ?? Array(contiguous.utf8).withUnsafeBufferPointer { bytes in
            try Self.scan(bytes, dialect: dialect, context: context)
        }
        return tally.findings()
    }

    private static func scan(_ bytes: UnsafeBufferPointer<UInt8>, dialect: ScriptDialect, context: RequestContext) throws -> ScriptEffectsTally {
        func analyze(_ buffer: UnsafeBufferPointer<UInt8>) throws -> ScriptEffectsTally {
            let analyzer = ScriptEffectsAnalyzer(bytes: buffer, context: context)
            try analyzer.analyzeAll(dialect)
            return analyzer.tally
        }
        // A byte-order mark is not part of the first command.
        let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? UnsafeBufferPointer(rebasing: bytes[3...]) : bytes
        // Lines longer than the limit are cut once, up front, so every lexer sees bounded lines.
        if let limited = ScriptBytes.limitingLines(of: body) {
            return try limited.withUnsafeBufferPointer(analyze)
        }
        return try analyze(body)
    }
}

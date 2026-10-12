import Foundation
import PreviewContracts

/// Notebook code, prose and output live inside JSON string values, where the key-based JSON
/// policy cannot see a line such as `password = "..."`. This pass decodes every string token
/// and conceals the whole token, quotes included, when the decoded content contains a
/// sensitive assignment. Whole tokens keep the safe JSON syntactically valid, so structured
/// views can still be derived from it. Nothing here executes, imports or evaluates content.
enum NotebookPrivacyRanges {
    /// Token spans to conceal: every string (value or key) whose decoded content is sensitive, plus
    /// continuation lines of the same array (see `Collector.visit`).
    static func ranges(in root: NotebookJSONValue, context: RequestContext) throws -> [SensitiveRange] {
        var collector = Collector(context: context)
        try collector.visit(root, depth: 1)
        return collector.ranges
    }

    /// Orders ranges and drops any contained in another one, so each concealed JSON value
    /// appears once and the range count never exceeds the node count the scanner enforced.
    static func merged(_ ranges: [SensitiveRange]) -> [SensitiveRange] {
        let ordered = ranges.sorted {
            $0.utf8Range.lowerBound != $1.utf8Range.lowerBound
                ? $0.utf8Range.lowerBound < $1.utf8Range.lowerBound
                : $0.utf8Range.upperBound > $1.utf8Range.upperBound
        }
        var result: [SensitiveRange] = []
        for range in ordered {
            if let last = result.last, range.utf8Range.upperBound <= last.utf8Range.upperBound { continue }
            result.append(range)
        }
        return result
    }

    private struct Collector {
        let context: RequestContext
        var ranges: [SensitiveRange] = []

        mutating func visit(_ value: NotebookJSONValue, depth: Int) throws {
            try context.checkpoint()
            switch value {
            case .object(let members):
                for member in members {
                    // A concealed key leaves the safe JSON unparsable for structured views, which then
                    // fall back to the concealed source. That is the intended fail-closed behavior.
                    if try NotebookSecretHeuristics.verdict(for: member.key.value, context: context).isSensitive {
                        ranges.append(SensitiveRange(utf8Range: member.key.range))
                    }
                    try visit(member.value, depth: depth + 1)
                }
            case .array(let elements):
                // Cell source, stream text and tracebacks are arrays of lines. A secret whose value
                // continues past its line (open quote, bracket, triple quote, PEM block) could hide
                // in the following lines, so those sibling strings are concealed too.
                var concealRemainingStrings = false
                for element in elements {
                    guard case .string(let token) = element else {
                        concealRemainingStrings = false
                        try visit(element, depth: depth + 1)
                        continue
                    }
                    if concealRemainingStrings {
                        if !token.value.isEmpty { ranges.append(SensitiveRange(utf8Range: token.range)) }
                        continue
                    }
                    let verdict = try NotebookSecretHeuristics.verdict(for: token.value, context: context)
                    if verdict.isSensitive {
                        ranges.append(SensitiveRange(utf8Range: token.range))
                        concealRemainingStrings = verdict.continuesBeyondLine
                    }
                }
            case .string(let token):
                if try NotebookSecretHeuristics.verdict(for: token.value, context: context).isSensitive {
                    ranges.append(SensitiveRange(utf8Range: token.range))
                }
            case .number, .literal:
                break
            }
        }
    }
}

struct NotebookSecretVerdict: Equatable {
    var isSensitive = false
    var continuesBeyondLine = false
}

/// Decoded-content heuristics. They extend the shared assignment heuristic (identifier, optional
/// quotes, optional closing bracket, then `:` or `=`; key judged by `SecretFieldPolicy`) in the
/// conservative direction only: `--password=...` command flags and `environ["KEY"] = ...` subscripts
/// are also recognized, and terminal color escapes cannot separate a key from its delimiter.
enum NotebookSecretHeuristics {
    private static let assignment = try? NSRegularExpression(
        pattern: #"(?i)(?<![a-z0-9_.\#(SecretFieldPolicy.invisibleKeyCharacterClass)])[\"']?([a-z_\#(SecretFieldPolicy.invisibleKeyCharacterClass)][a-z0-9_.\#(SecretFieldPolicy.invisibleKeyCharacterClass)-]*)[\"']?\]?[\t ]*[:=]"#)
    private static let privateKeyHeader = try? NSRegularExpression(
        pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#)

    /// Classifies decoded string content. When it holds terminal escapes, the stripped text is also
    /// classified and the verdicts are combined, so stripping can never hide a visible assignment.
    static func verdict(for decoded: String, context: RequestContext) throws -> NotebookSecretVerdict {
        guard !decoded.isEmpty else { return NotebookSecretVerdict() }
        let first = try classify(decoded, context: context)
        let stripped = strippingTerminalEscapes(decoded)
        guard stripped != decoded else { return first }
        let second = try classify(stripped, context: context)
        return NotebookSecretVerdict(isSensitive: first.isSensitive || second.isSensitive,
                                     continuesBeyondLine: first.continuesBeyondLine || second.continuesBeyondLine)
    }

    private static func classify(_ text: String, context: RequestContext) throws -> NotebookSecretVerdict {
        var verdict = NotebookSecretVerdict()
        try context.checkpoint()
        let nsText = text as NSString
        let whole = NSRange(location: 0, length: nsText.length)
        // An unterminated PEM block makes the shared filter conceal to the end of the document, so
        // the block is concealed here as a token and its continuation is also treated as concealed.
        if text.contains("PRIVATE KEY-----"), let privateKeyHeader,
           let header = privateKeyHeader.firstMatch(in: text, range: whole) {
            verdict.isSensitive = true
            let tail = nsText.substring(from: NSMaxRange(header.range))
            verdict.continuesBeyondLine = !tail.contains("-----END")
        }
        guard text.utf8.contains(where: { $0 == 58 || $0 == 61 }) else { return verdict }
        guard let assignment else {
            // Unreachable for the constant pattern; fail closed if compilation ever changes.
            return NotebookSecretVerdict(isSensitive: true, continuesBeyondLine: true)
        }
        var failure: (any Error)?
        assignment.enumerateMatches(in: text, options: [.reportProgress], range: whole) { match, _, stop in
            do { try context.checkpoint() } catch { failure = error; stop.pointee = true; return }
            guard let match, SecretFieldPolicy.isSensitive(nsText.substring(with: match.range(at: 1))) else { return }
            verdict.isSensitive = true
            let valueStart = NSMaxRange(match.range)
            let remaining = NSRange(location: valueStart, length: nsText.length - valueStart)
            let newline = nsText.rangeOfCharacter(from: .newlines, options: [], range: remaining)
            let lineEnd = newline.location == NSNotFound ? nsText.length : newline.location
            if mayContinue(nsText.substring(with: NSRange(location: valueStart, length: lineEnd - valueStart))) {
                verdict.continuesBeyondLine = true
                stop.pointee = true
            }
        }
        if let failure { throw failure }
        return verdict
    }

    /// Empty values and values opening a bracket, parenthesis, continuation or unbalanced quote
    /// may span several array elements.
    private static func mayContinue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return true }
        if first == "{" || first == "[" || first == "(" || trimmed.hasSuffix("\\") { return true }
        guard first == "\"" || first == "'" else { return false }
        if trimmed.hasPrefix(String(repeating: String(first), count: 3)) { return true }
        var escaped = false
        for character in trimmed.dropFirst() {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if character == first { return false }
        }
        return true
    }

    /// Removes CSI, OSC and other escape sequences, as IPython tracebacks interleave them between an
    /// assignment's key, delimiter and value. Malformed sequences consume only well-formed prefixes
    /// and never a line break. Used for classification only.
    static func strippingTerminalEscapes(_ text: String) -> String {
        guard text.utf8.contains(0x1B) else { return text }
        var output = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            guard scalar.value == 0x1B else { output.append(scalar); continue }
            guard index < scalars.count else { break }
            let introducer = scalars[index].value
            index += 1
            switch introducer {
            case 0x5B:   // CSI
                while index < scalars.count, (0x20...0x3F).contains(scalars[index].value) { index += 1 }
                if index < scalars.count, (0x40...0x7E).contains(scalars[index].value) { index += 1 }
            case 0x5D:   // OSC, ended by BEL or ESC \
                while index < scalars.count, scalars[index].value != 0x0A {
                    let next = scalars[index].value
                    index += 1
                    if next == 0x07 { break }
                    if next == 0x1B, index < scalars.count, scalars[index].value == 0x5C { index += 1; break }
                }
            case 0x20...0x2F:
                while index < scalars.count, (0x20...0x2F).contains(scalars[index].value) { index += 1 }
                if index < scalars.count, (0x30...0x7E).contains(scalars[index].value) { index += 1 }
            case 0x30...0x7E:
                break
            default:
                index -= 1   // A bare ESC drops only itself.
            }
        }
        return String(output)
    }
}

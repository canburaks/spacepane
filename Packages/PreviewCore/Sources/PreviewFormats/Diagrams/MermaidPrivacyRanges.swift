import Foundation
import PreviewContracts

/// Concealment ranges for Mermaid source that keep the diagram's structure.
///
/// The shared filter conceals the whole rest of a line after `password:`; in a flowchart that would
/// also remove the edge and the nodes that follow a label such as `A[Token: JWT] --> B`, leaving a
/// silently incomplete diagram. Here a secret-like assignment inside a bracketed, quoted or
/// pipe-delimited label is concealed only up to the delimiter that ends that label, which is where
/// Mermaid itself ends the label text, so the secret cannot extend past it. Everywhere else
/// (comments, directives, front matter, sequence messages, notes, descriptions) the value runs to the
/// end of the line, and a value that may continue on later lines conceals the rest of the file,
/// exactly as the shared policy does.
enum MermaidPrivacyRanges {
    static func ranges(in text: String, context: RequestContext) throws -> [SensitiveRange] {
        let scalars = Array(text.unicodeScalars)
        // UTF-8 offset of every scalar boundary, so ranges convert without rescanning.
        var offsets = [Int](repeating: 0, count: scalars.count + 1)
        for (index, scalar) in scalars.enumerated() { offsets[index + 1] = offsets[index] + scalar.utf8.count }
        var ranges: [SensitiveRange] = []
        var lineStart = 0
        var inFrontMatter = false
        var seenContent = false
        while lineStart < scalars.count {
            try context.checkpoint()
            var lineEnd = lineStart
            while lineEnd < scalars.count, scalars[lineEnd] != "\n", scalars[lineEnd] != "\r" { lineEnd += 1 }
            let line = String(String.UnicodeScalarView(scalars[lineStart..<lineEnd]))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---", !seenContent || inFrontMatter {
                inFrontMatter.toggle()
                seenContent = true
            } else if !trimmed.isEmpty {
                seenContent = true
            }
            let freeText = inFrontMatter || trimmed.hasPrefix("%%")
            let spans = try DiagramLabelPrivacy.spans(in: line, context: context)
            for span in spans {
                var start = lineStart + span.lowerBound
                var end = lineStart + span.upperBound
                let delimiter = delimiterIndex(before: span.lowerBound, in: Array(line.unicodeScalars))
                if !freeText, let delimiter, let terminator = labelTerminator(in: Array(line.unicodeScalars), delimiter: delimiter) {
                    end = min(end, lineStart + terminator)
                } else if continues(scalars, valueStart: start, lineEnd: lineEnd) {
                    end = scalars.count
                }
                start = min(start, end)
                if end > start { ranges.append(SensitiveRange(utf8Range: offsets[start]..<offsets[end])) }
                guard ranges.count <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            }
            // An assignment with an empty value, such as `password:` before nested lines, hides what follows.
            if let hidden = try emptyValueContinuation(line: line, lineStart: lineStart, scalars: scalars) {
                ranges.append(SensitiveRange(utf8Range: offsets[hidden]..<offsets[scalars.count]))
            }
            lineStart = lineEnd
            while lineStart < scalars.count, scalars[lineStart] == "\n" || scalars[lineStart] == "\r" { lineStart += 1 }
        }
        return merged(ranges)
    }

    /// Scalar index of the `:` or `=` that introduced the value starting at `valueStart`.
    private static func delimiterIndex(before valueStart: Int, in line: [Unicode.Scalar]) -> Int? {
        var index = valueStart - 1
        while index >= 0, line[index] == " " || line[index] == "\t" { index -= 1 }
        guard index >= 0, line[index] == ":" || line[index] == "=" else { return nil }
        return index
    }

    /// Where the label around `delimiter` ends (a scalar index within the line), or nil when the
    /// delimiter is not inside a bracketed, quoted or pipe-delimited label.
    private static func labelTerminator(in line: [Unicode.Scalar], delimiter: Int) -> Int? {
        var inQuotes = false
        var inPipe = false
        var stack: [Unicode.Scalar] = []
        for index in 0..<delimiter {
            let scalar = line[index]
            if inQuotes { if scalar == "\"" { inQuotes = false }; continue }
            switch scalar {
            case "\"": inQuotes = true
            case "[", "(", "{": stack.append(scalar)
            case "]", ")", "}":
                if let top = stack.last, closer(of: top) == scalar { stack.removeLast() }
            case "|": if stack.isEmpty { inPipe.toggle() }
            default: break
            }
        }
        let terminator: Unicode.Scalar
        if inQuotes { terminator = "\"" }
        else if let top = stack.last { terminator = closer(of: top) }
        else if inPipe { terminator = "|" }
        else { return nil }
        var index = delimiter + 1
        while index < line.count, line[index] != terminator { index += 1 }
        return index
    }

    private static func closer(of opener: Unicode.Scalar) -> Unicode.Scalar {
        switch opener {
        case "[": "]"
        case "(": ")"
        default: "}"
        }
    }

    /// A value that may continue on following lines: opening braces or brackets, a quote that does
    /// not close on this line, a block indicator, or a trailing backslash.
    private static func continues(_ scalars: [Unicode.Scalar], valueStart: Int, lineEnd: Int) -> Bool {
        guard lineEnd < scalars.count else { return false }
        let value = String(String.UnicodeScalarView(scalars[min(valueStart, lineEnd)..<lineEnd])).trimmingCharacters(in: .whitespaces)
        guard let first = value.first else { return false }
        if first == "{" || first == "[" || first == "|" || first == ">" || value.hasSuffix("\\") { return true }
        guard first == "\"" || first == "'" else { return false }
        if value.hasPrefix(String(repeating: String(first), count: 3)) { return true }
        return !value.dropFirst().contains(first)
    }

    /// For `key:` with nothing after the delimiter on a free-text line, the scalar index where the
    /// following lines begin; nil when the key is not secret-like or has a value.
    private static func emptyValueContinuation(line: String, lineStart: Int, scalars: [Unicode.Scalar]) throws -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(":") || trimmed.hasSuffix("=") else { return nil }
        let key = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains("["), !key.contains("("), !key.contains("|"),
              SecretFieldPolicy.isSensitive(key.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }) else { return nil }
        let end = lineStart + line.unicodeScalars.count
        return end < scalars.count ? end : nil
    }

    private static func merged(_ ranges: [SensitiveRange]) -> [SensitiveRange] {
        var result: [SensitiveRange] = []
        for range in ranges.sorted(by: { $0.utf8Range.lowerBound < $1.utf8Range.lowerBound }) {
            if let last = result.last, last.utf8Range.upperBound >= range.utf8Range.lowerBound {
                result[result.count - 1] = SensitiveRange(utf8Range: last.utf8Range.lowerBound..<max(last.utf8Range.upperBound, range.utf8Range.upperBound))
            } else { result.append(range) }
        }
        return result
    }
}

import Foundation
import PreviewContracts

/// Conservative annotations complement the shared recognisable-value policy. Quoted/dotted
/// keys are decoded at this syntax boundary; uncertain key escapes and complex sensitive
/// continuations are concealed rather than relying on a regex that sees only raw spelling.
enum ConfigurationPrivacyRanges {
    static func ranges(in source: String, syntax: TextSyntax, context: RequestContext) throws -> [SensitiveRange] {
        let bytes = Array(source.utf8)
        var ranges = syntax == .yaml ? try YAMLFlowPrivacyRanges.ranges(in: bytes, context: context) : []
        var lineStart = 0
        var containsComplexYAML = false
        var containsSensitiveKey = !ranges.isEmpty
        var namedItems: [NamedItem] = []
        var bindingValues = 0
        // This bounded lexical pass also sees quoted keys inside unsupported flow/inline
        // tables and table headers. It never constructs or expands those grammars.
        if try hasUncertainOrSensitiveEscapedKey(bytes, context: context) {
            return [.init(utf8Range: 0..<bytes.count)]
        }
        while lineStart < bytes.count {
            try context.checkpoint()
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 10, bytes[lineEnd] != 13 {
                if (lineEnd - lineStart).isMultiple(of: 512) { try context.checkpoint() }
                lineEnd += 1
            }
            let line = String(decoding: bytes[lineStart..<lineEnd], as: UTF8.self)
            let separator: Character = syntax == .yaml ? ":" : "="
            let split = try delimiter(separator, in: line, context: context)
            if syntax == .toml {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                    let header = String(trimmed.drop(while: { $0 == "[" }).reversed().drop(while: { $0 == "]" }).reversed())
                    let classification = classify(header, dotted: true)
                    if classification.sensitive || classification.uncertain { return [.init(utf8Range: 0..<bytes.count)] }
                }
            }
            if syntax == .yaml, line.range(of: #"(?:^|[\s:\[,])[&*!][A-Za-z0-9_!-]"#, options: .regularExpression) != nil { containsComplexYAML = true }
            if let split {
                var rawKey = String(line[..<split]).trimmingCharacters(in: .whitespaces)
                if rawKey.hasPrefix("- ") { rawKey = String(rawKey.dropFirst(2)) }
                if rawKey.hasPrefix("export ") { rawKey = String(rawKey.dropFirst(7)) }
                let valueIndex = line.index(after: split)
                let rawValue = String(line[valueIndex...]).trimmingCharacters(in: .whitespaces)
                let valueStart = lineStart + line[..<valueIndex].utf8.count
                if rawValue.hasPrefix("\""), rawValue.contains("\\"), let decoded = simpleScalar(rawValue),
                   try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded, originalText: rawValue, context: context) {
                    ranges.append(.init(utf8Range: valueStart..<lineEnd))
                }
                if syntax == .yaml {
                    let indentation = line.prefix(while: { $0 == " " || $0 == "\t" }).utf8.count
                    let sequenceItem = line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("- ")
                    let itemIndent = indentation + (sequenceItem ? 2 : 0)
                    while let item = namedItems.last, item.indent > itemIndent || (sequenceItem && item.indent >= itemIndent) {
                        if !finish(namedItems.removeLast(), into: &ranges, maximum: context.budget.maxJSONNodes) { return [.init(utf8Range: 0..<bytes.count)] }
                    }
                    if namedItems.last?.indent != itemIndent {
                        guard namedItems.count < context.budget.maxJSONDepth else { return [.init(utf8Range: 0..<bytes.count)] }
                        namedItems.append(NamedItem(indent: itemIndent))
                    }
                    let item = namedItems.count - 1
                    switch SecretFieldPolicy.namedValueRole(rawKey) {
                    case .name:
                        if let name = simpleScalar(rawValue) {
                            namedItems[item].sensitive = namedItems[item].sensitive || SecretFieldPolicy.isSensitive(name)
                        } else { namedItems[item].sensitive = true }
                        containsSensitiveKey = containsSensitiveKey || namedItems[item].sensitive
                    case .value:
                        guard bindingValues < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                        bindingValues += 1
                        let end = try continuationEnd(in: bytes, after: lineEnd, indentation: itemIndent, context: context)
                        if valueStart < end { namedItems[item].values.append(valueStart..<end) }
                    case nil: break
                    }
                }
                let classified = classify(rawKey, dotted: syntax == .toml)
                if classified.sensitive || classified.uncertain {
                    containsSensitiveKey = true
                    let valueIndex = line.index(after: split)
                    let value = String(line[valueIndex...]).trimmingCharacters(in: .whitespaces)
                    let start = classified.uncertain ? lineStart : lineStart + line[..<valueIndex].utf8.count
                    let continues = classified.uncertain || value.isEmpty || value.hasPrefix("|") || value.hasPrefix(">")
                        || value.hasPrefix("!") || value.hasPrefix("&") || value.hasPrefix("{") || value.hasPrefix("[")
                        || value.hasPrefix("\"\"\"") || value.hasPrefix("'''") || value.hasSuffix("\\")
                        || (value.hasPrefix("\"") && !value.hasSuffix("\"")) || (value.hasPrefix("'") && !value.hasSuffix("'"))
                    if start < (continues ? bytes.count : lineEnd) { ranges.append(.init(utf8Range: start..<(continues ? bytes.count : lineEnd))) }
                }
            } else if line.contains("\\"), line.trimmingCharacters(in: .whitespaces).hasPrefix("\"") {
                // A malformed escaped key can hide its delimiter from a best-effort scanner.
                containsSensitiveKey = true
                ranges.append(.init(utf8Range: lineStart..<bytes.count))
            }
            if ranges.count > context.budget.maxJSONNodes { return [.init(utf8Range: 0..<bytes.count)] }
            lineStart = lineEnd < bytes.count ? lineEnd + 1 : lineEnd
        }
        while let item = namedItems.popLast() {
            if !finish(item, into: &ranges, maximum: context.budget.maxJSONNodes) { return [.init(utf8Range: 0..<bytes.count)] }
        }
        if syntax == .yaml, containsComplexYAML, containsSensitiveKey { return [.init(utf8Range: 0..<bytes.count)] }
        return ranges
    }
    private struct NamedItem {
        let indent: Int
        var sensitive = false
        var values: [Range<Int>] = []
    }

    private static func finish(_ item: NamedItem, into ranges: inout [SensitiveRange], maximum: Int) -> Bool {
        guard item.sensitive else { return true }
        guard ranges.count <= maximum, item.values.count <= maximum - ranges.count else { return false }
        ranges += item.values.map { SensitiveRange(utf8Range: $0) }
        return true
    }

    /// A named YAML value owns its more-indented continuation, whether it is a block scalar,
    /// nested mapping or sequence. Stop before the next same-level item/member so deferred
    /// value-first bindings can conceal the complete value without consuming a neighbor.
    private static func continuationEnd(in bytes: [UInt8], after lineEnd: Int, indentation: Int,
                                        context: RequestContext) throws -> Int {
        var cursor = lineEnd
        var end = lineEnd
        while cursor < bytes.count {
            try context.checkpoint()
            if bytes[cursor] == 13 { cursor += 1 }
            if cursor < bytes.count, bytes[cursor] == 10 { cursor += 1 }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] == 32 || bytes[cursor] == 9 {
                if cursor.isMultiple(of: 512) { try context.checkpoint() }
                cursor += 1
            }
            let indent = cursor - start
            if cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13, indent <= indentation { return end }
            while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13 {
                if cursor.isMultiple(of: 512) { try context.checkpoint() }
                cursor += 1
            }
            end = cursor
        }
        return end
    }

    /// Decode a bounded scalar at this configuration boundary, retaining source offsets separately.
    /// Complex values are not constructed or evaluated; unsupported quoted names remain uncertain.
    private static func simpleScalar(_ raw: String) -> String? {
        if raw.hasPrefix("\"") {
            var escaped = false
            for index in raw.indices.dropFirst() {
                let character = raw[index]
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == "\"" {
                    return try? JSONDecoder().decode(String.self, from: Data(raw[...index].utf8))
                }
            }
            return nil
        }
        if raw.hasPrefix("'") {
            // YAML doubles apostrophes; the same spelling without doubling covers TOML literals.
            var index = raw.index(after: raw.startIndex)
            var result = ""
            while index < raw.endIndex {
                if raw[index] == "'" {
                    let next = raw.index(after: index)
                    if next < raw.endIndex, raw[next] == "'" { result.append("'"); index = raw.index(after: next); continue }
                    return result
                }
                result.append(raw[index]); index = raw.index(after: index)
            }
            return nil
        }
        return raw.components(separatedBy: " #")[0].trimmingCharacters(in: .whitespaces)
    }

    private static func hasUncertainOrSensitiveEscapedKey(_ bytes: [UInt8], context: RequestContext) throws -> Bool {
        var index = 0
        var checkpointOffset = 0
        while index < bytes.count {
            if index - checkpointOffset >= 512 { try context.checkpoint(); checkpointOffset = index }
            guard bytes[index] == 34 else { index += 1; continue }
            let start = index; index += 1
            var escaped = false
            var closed = false
            while index < bytes.count {
                if index - checkpointOffset >= 512 { try context.checkpoint(); checkpointOffset = index }
                let byte = bytes[index]; index += 1
                if byte == 92 { escaped = true; if index < bytes.count { index += 1 } }
                else if byte == 34 { closed = true; break }
            }
            guard closed else { return escaped }
            var following = index
            while following < bytes.count, [9, 32].contains(bytes[following]) { following += 1 }
            guard following < bytes.count, [58, 61, 93].contains(bytes[following]), escaped else { continue }
            guard let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else { return true }
            if SecretFieldPolicy.isSensitive(key) { return true }
        }
        return false
    }
    private static func classify(_ raw: String, dotted: Bool) -> (sensitive: Bool, uncertain: Bool) {
        var parts: [String] = []
        var start = raw.startIndex
        var quote: Character?
        var escaped = false
        for index in raw.indices {
            let character = raw[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if let current = quote { if character == current { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character; continue }
            if dotted, character == "." {
                guard parts.count < 64 else { return (false, true) }
                parts.append(String(raw[start..<index])); start = raw.index(after: index)
            }
        }
        parts.append(String(raw[start...]))
        var sensitive = false
        for part in parts {
            let key = part.trimmingCharacters(in: .whitespaces)
            let decoded: String
            if key.hasPrefix("\"") {
                guard let result = try? JSONDecoder().decode(String.self, from: Data(key.utf8)) else { return (sensitive, true) }
                decoded = result
            } else if key.hasPrefix("'"), key.hasSuffix("'"), key.count >= 2 { decoded = String(key.dropFirst().dropLast()) }
            else { decoded = key }
            sensitive = sensitive || SecretFieldPolicy.isSensitive(decoded)
        }
        return (sensitive, false)
    }
    private static func delimiter(_ needle: Character, in text: String, context: RequestContext) throws -> String.Index? {
        var quote: Character?
        var escaped = false
        var visited = 0
        for index in text.indices {
            visited += 1
            if visited.isMultiple(of: 512) { try context.checkpoint() }
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if let current = quote { if character == current { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character; continue }
            if character == "#" { return nil }
            if character == needle { return index }
        }
        return nil
    }
}

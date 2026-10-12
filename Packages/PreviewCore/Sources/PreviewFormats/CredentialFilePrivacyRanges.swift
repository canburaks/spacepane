import Foundation
import PreviewContracts

/// Metadata-selected credential grammars. This annotates supplied, bounded UTF-8 only: no home
/// directory lookup, sibling access, permission changes, macro execution or connection attempts.
enum CredentialFilePrivacyRanges {
    static func ranges(in text: String, filename: String?, context: RequestContext) throws -> [SensitiveRange]? {
        guard filename == ".netrc" || filename == ".pgpass" else { return nil }
        let bytes = Array(text.utf8)
        return filename == ".netrc" ? try netrc(bytes, context: context) : try pgpass(bytes, context: context)
    }

    private static func pgpass(_ bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var ranges: [SensitiveRange] = []
        var start = 0
        while start < bytes.count {
            try context.checkpoint()
            var end = start
            while end < bytes.count, bytes[end] != 10, bytes[end] != 13 {
                if (end - start).isMultiple(of: 512) { try context.checkpoint() }
                end += 1
            }
            if start < end, bytes[start] == 35 {
                if let comment = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: (start + 1)..<end, context: context) {
                    guard ranges.count < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                    ranges.append(comment)
                }
            } else if bytes[start..<end].contains(where: { $0 != 32 && $0 != 9 }) {
                var separators = 0
                var escaped = false
                var passwordStart: Int?
                for index in start..<end {
                    if (index - start).isMultiple(of: 512) { try context.checkpoint() }
                    if escaped { escaped = false; continue }
                    if bytes[index] == 92 { escaped = true; continue }
                    if bytes[index] == 58 {
                        separators += 1
                        if separators == 4 { passwordStart = index + 1; break }
                    }
                }
                // Malformed entries in an explicitly selected password file are concealed whole;
                // guessing which unescaped field contains a password could expose missing delimiters.
                let valueStart = passwordStart ?? start
                if valueStart < end {
                    guard ranges.count < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                    ranges.append(.init(utf8Range: valueStart..<end))
                }
            }
            start = end < bytes.count ? end + 1 : end
        }
        return ranges
    }

    private static func netrc(_ bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var lexer = NetrcLexer(bytes: bytes, context: context)
        var ranges: [SensitiveRange] = []
        while let token = try lexer.next(comments: &ranges) {
            let keyword = token.count <= 32 ? String(decoding: bytes[token], as: UTF8.self).lowercased() : ""
            switch keyword {
            case "password", "account":
                if let value = try lexer.next(comments: &ranges) {
                    guard ranges.count < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                    ranges.append(.init(utf8Range: value))
                }
            case "machine", "login": _ = try lexer.next(comments: &ranges)
            case "macdef":
                _ = try lexer.next(comments: &ranges)
                if let body = try lexer.macroBody() {
                    guard ranges.count < context.budget.maxJSONNodes else { return [.init(utf8Range: 0..<bytes.count)] }
                    // Macro text may hold FTP credentials without a password keyword. Keep it inert
                    // and concealed through the terminating blank line, preserving the next machine.
                    ranges.append(.init(utf8Range: body))
                }
            default: break
            }
            if ranges.count > context.budget.maxJSONNodes { return [.init(utf8Range: 0..<bytes.count)] }
        }
        return ranges
    }

    private struct NetrcLexer {
        let bytes: [UInt8]
        let context: RequestContext
        var index = 0

        mutating func next(comments: inout [SensitiveRange]) throws -> Range<Int>? {
            try context.checkpoint()
            while index < bytes.count {
                if index.isMultiple(of: 512) { try context.checkpoint() }
                if Self.space(bytes[index]) { index += 1; continue }
                if bytes[index] == 35 {
                    let start = index + 1
                    while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                        if index.isMultiple(of: 512) { try context.checkpoint() }
                        index += 1
                    }
                    if let comment = try CommentPrivacyRanges.sensitiveRange(in: bytes, content: start..<index, context: context) {
                        guard comments.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                        comments.append(comment)
                    }
                    continue
                }
                let start = index
                if bytes[index] == 34 {
                    index += 1
                    var checkpointAt = index
                    while index < bytes.count {
                        if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
                        if bytes[index] == 92 { index = min(bytes.count, index + 2); continue }
                        if bytes[index] == 34 { index += 1; break }
                        index += 1
                    }
                } else {
                    while index < bytes.count, !Self.space(bytes[index]) {
                        if index.isMultiple(of: 512) { try context.checkpoint() }
                        index += 1
                    }
                }
                return start..<index
            }
            return nil
        }

        mutating func macroBody() throws -> Range<Int>? {
            while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                if index.isMultiple(of: 512) { try context.checkpoint() }
                index += 1
            }
            if index < bytes.count, bytes[index] == 13 { index += 1 }
            if index < bytes.count, bytes[index] == 10 { index += 1 }
            let start = index
            while index < bytes.count {
                try context.checkpoint()
                let lineStart = index
                while index < bytes.count, bytes[index] != 10, bytes[index] != 13 {
                    if index.isMultiple(of: 512) { try context.checkpoint() }
                    index += 1
                }
                let blank = bytes[lineStart..<index].allSatisfy { $0 == 32 || $0 == 9 }
                let lineEnd = index
                if index < bytes.count, bytes[index] == 13 { index += 1 }
                if index < bytes.count, bytes[index] == 10 { index += 1 }
                if blank { return start < lineStart ? start..<lineStart : nil }
                if lineEnd == bytes.count { break }
            }
            return start < index ? start..<index : nil
        }

        private static func space(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
    }
}

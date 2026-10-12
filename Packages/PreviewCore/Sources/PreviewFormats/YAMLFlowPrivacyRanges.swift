import Foundation
import PreviewContracts

/// Bounded lexical privacy annotations for YAML flow collections. This does not build YAML values,
/// validate all YAML syntax, resolve aliases/tags or expand documents. The caller already validated
/// the supplied UTF-8 input. Only original byte spans leave this boundary.
enum YAMLFlowPrivacyRanges {
    static func ranges(in bytes: [UInt8], context: RequestContext) throws -> [SensitiveRange] {
        var scanner = Scanner(bytes: bytes, context: context)
        try scanner.scan()
        return scanner.ranges
    }

    private struct Scalar {
        let range: Range<Int>
        let decoded: String?
    }

    private struct Scanner {
        let bytes: [UInt8]
        let context: RequestContext
        var index = 0
        var nodes = 0
        var ranges: [SensitiveRange] = []
        private var checkpointAt = 0

        init(bytes: [UInt8], context: RequestContext) { self.bytes = bytes; self.context = context }

        mutating func scan() throws {
            try context.checkpoint()
            var scalarParentIndent: Int?
            while index < bytes.count {
                try progress()
                let lineStart = index
                let end = try lineEnd(from: lineStart)
                while index < end, bytes[index] == 32 || bytes[index] == 9 { try progress(); index += 1 }
                let indent = index - lineStart
                if index == end || bytes[index] == 35 { advance(after: end); continue }
                if let parent = scalarParentIndent, indent > parent { advance(after: end); continue }
                scalarParentIndent = nil
                // A flow collection starts a block node/value. Brackets later in a plain scalar,
                // or in the indented contents of |/> block scalars, are ordinary prose.
                if index + 3 <= end, bytes[index..<(index + 3)].elementsEqual("---".utf8),
                   index + 3 == end || [9, 32].contains(bytes[index + 3]) { index += 3 }
                try lineSpaces(until: end)
                if index < end, bytes[index] == 45, index + 1 == end || [9, 32].contains(bytes[index + 1]) {
                    index += 1
                    try lineSpaces(until: end)
                }
                guard index < end else { advance(after: end); continue }
                let memberIndent = index - lineStart
                var isMapping = false
                try inertPrefixes(until: end)
                guard index < end else { advance(after: end); continue }
                if bytes[index] != 123, bytes[index] != 91, let colon = try mappingColon(from: index, until: end) {
                    isMapping = true
                    index = colon + 1
                    try lineSpaces(until: end)
                }
                // Inspect collection syntax after an inert anchor/tag without resolving it. The
                // caller retains its whole-source fallback if sensitive complex YAML is found.
                try inertPrefixes(until: end)
                guard index < end else { advance(after: end); continue }
                if bytes[index] == 123 || bytes[index] == 91 {
                    _ = try value(depth: 1)
                    advance(after: try lineEnd(from: index))
                } else if bytes[index] == 34 || bytes[index] == 39 {
                    let quoted = try scalar(key: false)
                    try annotateDecodedValue(quoted)
                    advance(after: try lineEnd(from: index))
                } else {
                    // Both block-scalar content and multiline plain scalars belong to this node's
                    // more-indented continuation. Do not parse that prose as flow collections.
                    scalarParentIndent = isMapping ? memberIndent : indent
                    advance(after: end)
                }
            }
            try context.checkpoint()
        }

        private func lineEnd(from start: Int) throws -> Int {
            var cursor = start
            while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13 {
                if (cursor - start).isMultiple(of: 512) { try context.checkpoint() }
                cursor += 1
            }
            return cursor
        }

        private mutating func advance(after end: Int) {
            index = end
            if index < bytes.count, bytes[index] == 13 { index += 1 }
            if index < bytes.count, bytes[index] == 10 { index += 1 }
        }

        private mutating func lineSpaces(until end: Int) throws {
            while index < end, bytes[index] == 9 || bytes[index] == 32 { try progress(); index += 1 }
        }

        private mutating func inertPrefixes(until end: Int) throws {
            while index < end, bytes[index] == 38 || bytes[index] == 33 {
                while index < end, ![9, 32].contains(bytes[index]) { try progress(); index += 1 }
                try lineSpaces(until: end)
            }
        }

        private func mappingColon(from start: Int, until end: Int) throws -> Int? {
            var cursor = start
            var quote: UInt8?
            var checkpointAt = start
            while cursor < end {
                if cursor >= checkpointAt { try context.checkpoint(); checkpointAt = cursor + 512 }
                let byte = bytes[cursor]
                if let current = quote {
                    if current == 34, byte == 92 { cursor = min(end, cursor + 2); continue }
                    if byte == current { quote = nil }
                } else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 58, cursor + 1 == end || [9, 32].contains(bytes[cursor + 1]) { return cursor }
                else if byte == 35, cursor == start || [9, 32].contains(bytes[cursor - 1]) { return nil }
                cursor += 1
            }
            return nil
        }

        private mutating func progress() throws {
            if index >= checkpointAt { try context.checkpoint(); checkpointAt = index + 512 }
        }

        private mutating func node() throws {
            nodes += 1
            guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        }

        private mutating func add(_ range: Range<Int>) throws {
            guard !range.isEmpty else { return }
            guard ranges.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            ranges.append(.init(utf8Range: range))
        }

        private mutating func trivia() throws {
            while index < bytes.count {
                try progress()
                if [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
                else if bytes[index] == 35 { try comment() }
                else { return }
            }
        }

        private mutating func comment() throws {
            while index < bytes.count, bytes[index] != 10, bytes[index] != 13 { try progress(); index += 1 }
        }

        private mutating func value(depth: Int) throws -> Scalar {
            try node()
            guard depth <= min(context.budget.maxJSONDepth, 128) else { throw PreviewFailure.structureTooDeep }
            try trivia()
            let start = index
            guard index < bytes.count else { return Scalar(range: start..<start, decoded: nil) }
            if bytes[index] == 123 { try object(depth: depth); return Scalar(range: start..<index, decoded: nil) }
            if bytes[index] == 91 {
                index += 1
                while index < bytes.count {
                    try trivia()
                    guard index < bytes.count else { break }
                    if bytes[index] == 93 { index += 1; break }
                    let before = index
                    _ = try value(depth: depth + 1)
                    try trivia()
                    if index < bytes.count, bytes[index] == 44 { index += 1 }
                    else if index == before { index += 1 }
                }
                return Scalar(range: start..<index, decoded: nil)
            }
            let item = try scalar(key: false)
            try annotateDecodedValue(item)
            return item
        }

        private mutating func annotateDecodedValue(_ scalar: Scalar) throws {
            if let decoded = scalar.decoded, bytes[scalar.range].contains(92),
               try RecognizableSecretPolicy.requiresDecodedConcealment(in: decoded,
                   originalText: String(decoding: bytes[scalar.range], as: UTF8.self), context: context) {
                try add(scalar.range)
            }
        }

        private mutating func object(depth: Int) throws {
            let start = index
            index += 1
            var sensitiveName = false
            var namedValues: [Range<Int>] = []
            var uncertain = false
            var directSensitive = false
            var closed = false
            while index < bytes.count {
                try trivia()
                guard index < bytes.count else { break }
                if bytes[index] == 125 { index += 1; closed = true; break }
                if index < bytes.count, bytes[index] == 44 { index += 1; continue }
                try node()
                let before = index
                let key = try scalar(key: true)
                try trivia()
                guard index < bytes.count, bytes[index] == 58 else {
                    // Unsupported/malformed entries remain source. If this record already identified
                    // a sensitive binding, conceal its entire uncertain extent instead of guessing.
                    uncertain = true
                    if index == before { index += 1 }
                    continue
                }
                index += 1
                let member = try value(depth: depth + 1)
                if let decodedKey = key.decoded {
                    if SecretFieldPolicy.isSensitive(decodedKey) { try add(member.range); directSensitive = true }
                    switch SecretFieldPolicy.namedValueRole(decodedKey) {
                    case .name: sensitiveName = sensitiveName || (member.decoded.map(SecretFieldPolicy.isSensitive) ?? true)
                    case .value: namedValues.append(member.range)
                    case nil: break
                    }
                } else { try add(member.range); directSensitive = true }
                try trivia()
                if index < bytes.count, bytes[index] == 44 { index += 1 }
                else if index < bytes.count, bytes[index] != 125 { uncertain = true }
            }
            if (!closed || uncertain), sensitiveName || directSensitive { try add(start..<index) }
            else if sensitiveName { for range in namedValues { try add(range) } }
        }

        private mutating func scalar(key: Bool) throws -> Scalar {
            let start = index
            guard index < bytes.count else { return Scalar(range: start..<start, decoded: nil) }
            let quote = bytes[index]
            if quote == 34 || quote == 39 {
                index += 1
                var closed = false
                while index < bytes.count {
                    try progress()
                    if quote == 34, bytes[index] == 92 { index = min(bytes.count, index + 2); continue }
                    if bytes[index] == quote {
                        index += 1
                        if quote == 39, index < bytes.count, bytes[index] == quote { index += 1; continue }
                        closed = true; break
                    }
                    index += 1
                }
                let decoded: String?
                if !closed { decoded = nil }
                else if quote == 34 { decoded = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                else { decoded = String(decoding: bytes[(start + 1)..<(index - 1)], as: UTF8.self).replacingOccurrences(of: "''", with: "'") }
                return Scalar(range: start..<index, decoded: decoded)
            }
            while index < bytes.count {
                try progress()
                let byte = bytes[index]
                if [44, 125, 93, 123, 91, 35].contains(byte) || (key && byte == 58) { break }
                index += 1
            }
            let decoded = String(decoding: bytes[start..<index], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            // Aliases and tags are intentionally not interpreted. An uncertain named field triggers
            // the caller's existing whole-source complex-YAML fallback after its value is annotated.
            let uncertain = decoded.hasPrefix("*") || decoded.hasPrefix("!") || decoded.hasPrefix("&")
            return Scalar(range: start..<index, decoded: uncertain ? nil : decoded)
        }
    }
}

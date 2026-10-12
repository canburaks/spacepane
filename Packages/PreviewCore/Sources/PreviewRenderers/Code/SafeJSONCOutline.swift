import Foundation
import PreviewContracts

/// Derives the outline of a JSON-with-comments document from concealed text. Its only input is the
/// privacy-filtered presentation, and it reads the same lenient grammar as the adapter (comments,
/// trailing commas, unquoted and single-quoted keys, JSON5 numbers) using the shared `JSON5Lexicon`, so
/// both sides agree on every token boundary. Like the strict JSON outline it treats the inert
/// concealment token as a scalar, because replacing a whole secret value need not leave valid JSON.
/// Scalars keep their source spelling; strings show their decoded characters. A document the lenient
/// grammar rejects, or one over the limits, returns `nil` and the safe source stays on screen.
enum SafeJSONCOutline {
    static func nodes(_ source: String, maximumUTF16Units: Int = 262_144, maximumNodes: Int = 20_000,
                      maximumDepth: Int = 64) -> [SafeOutlineNode]? {
        guard source.utf16.prefix(maximumUTF16Units + 1).count <= maximumUTF16Units else { return nil }
        var scanner = Scanner(bytes: Array(source.utf8), maximumNodes: maximumNodes, maximumDepth: maximumDepth)
        return try? [scanner.document()]
    }

    private struct Invalid: Error {}

    private struct Scanner {
        let bytes: [UInt8]
        let maximumNodes: Int
        let maximumDepth: Int
        var index = 0
        var nextID = 0

        init(bytes: [UInt8], maximumNodes: Int, maximumDepth: Int) {
            self.bytes = bytes
            self.maximumNodes = maximumNodes
            self.maximumDepth = maximumDepth
        }

        mutating func document() throws -> SafeOutlineNode {
            try trivia()
            let root = try value(name: "$", depth: 1)
            try trivia()
            guard index == bytes.count else { throw Invalid() }
            return root
        }

        mutating func value(name: String, depth: Int) throws -> SafeOutlineNode {
            guard depth <= maximumDepth, nextID < maximumNodes, index < bytes.count else { throw Invalid() }
            let id = nextID
            nextID += 1
            let byte = bytes[index]
            if byte == 123 || byte == 91 {
                let isObject = byte == 123
                let closing: UInt8 = isObject ? 125 : 93
                index += 1
                try trivia()
                var children: [SafeOutlineNode] = []
                while true {
                    if take(closing) { break }
                    let childName: String
                    if isObject {
                        childName = try key()
                        try trivia()
                        guard take(58) else { throw Invalid() }
                        try trivia()
                    } else {
                        childName = "[\(children.count)]"
                    }
                    children.append(try value(name: childName, depth: depth + 1))
                    try trivia()
                    if take(closing) { break }
                    guard take(44) else { throw Invalid() }
                    try trivia()
                }
                if isObject {
                    var counts: [String: Int] = [:]
                    for child in children { counts[child.name, default: 0] += 1 }
                    children = children.map {
                        SafeOutlineNode(id: $0.id, name: $0.name, value: $0.value, children: $0.children,
                                        isDuplicateKey: counts[$0.name, default: 0] > 1)
                    }
                }
                return SafeOutlineNode(id: id, name: name, value: isObject ? "{…}" : "[…]", children: children)
            }
            if byte == 34 || byte == 39 { return SafeOutlineNode(id: id, name: name, value: try quoted()) }
            let start = index
            while index < bytes.count, !isDelimiter(bytes[index]) { index += 1 }
            guard index > start else { throw Invalid() }
            let token = bytes[start..<index]
            let text = String(decoding: token, as: UTF8.self)
            guard text == "••••" || JSON5Lexicon.literals.contains(text) || JSON5Lexicon.isNumber(token) else { throw Invalid() }
            return SafeOutlineNode(id: id, name: name, value: text)
        }

        mutating func key() throws -> String {
            guard index < bytes.count else { throw Invalid() }
            if bytes[index] == 34 || bytes[index] == 39 { return try quoted() }
            guard JSON5Lexicon.isIdentifierStart(bytes[index]) else { throw Invalid() }
            let start = index
            while index < bytes.count, JSON5Lexicon.isIdentifierPart(bytes[index]) { index += 1 }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        mutating func quoted() throws -> String {
            let quote = bytes[index]
            index += 1
            let start = index
            while index < bytes.count {
                let byte = bytes[index]
                if byte == quote {
                    let content = bytes[start..<index]
                    index += 1
                    guard let decoded = JSON5Lexicon.decodeString(content) else { throw Invalid() }
                    return decoded
                }
                if byte == 10 || byte == 13 { throw Invalid() }
                index += 1
                if byte == 92 {
                    guard index < bytes.count else { throw Invalid() }
                    let escaped = bytes[index]
                    index += 1
                    if escaped == 13, index < bytes.count, bytes[index] == 10 { index += 1 }
                }
            }
            throw Invalid()
        }

        /// Whitespace and comments. An unterminated block comment is invalid.
        mutating func trivia() throws {
            while index < bytes.count {
                let byte = bytes[index]
                if JSON5Lexicon.isWhitespace(byte) { index += 1; continue }
                guard byte == 47, index + 1 < bytes.count else { return }
                if bytes[index + 1] == 47 {
                    index += 2
                    while index < bytes.count, bytes[index] != 10, bytes[index] != 13 { index += 1 }
                } else if bytes[index + 1] == 42 {
                    index += 2
                    var closed = false
                    while index + 1 < bytes.count {
                        if bytes[index] == 42, bytes[index + 1] == 47 { closed = true; break }
                        index += 1
                    }
                    guard closed else { throw Invalid() }
                    index += 2
                } else {
                    return
                }
            }
        }

        func isDelimiter(_ byte: UInt8) -> Bool {
            JSON5Lexicon.isWhitespace(byte) || [44, 93, 125, 58, 47, 123, 91, 34, 39].contains(byte)
        }

        mutating func take(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }
    }
}

import Foundation
import PreviewContracts

struct SafeOutlineNode: Equatable, Sendable {
    let id: Int
    let name: String
    let value: String
    let children: [SafeOutlineNode]
    let isDuplicateKey: Bool
    let isIssue: Bool
    init(id: Int, name: String, value: String, children: [SafeOutlineNode] = [],
         isDuplicateKey: Bool = false, isIssue: Bool = false) {
        self.id = id; self.name = name; self.value = value; self.children = children
        self.isDuplicateKey = isDuplicateKey; self.isIssue = isIssue
    }

    // Outline invalidation must preserve exact source spellings, including Unicode
    // sequences that Swift's canonically equivalent String comparison treats as equal.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.isDuplicateKey == rhs.isDuplicateKey && lhs.isIssue == rhs.isIssue
            && lhs.name.utf8.elementsEqual(rhs.name.utf8)
            && lhs.value.utf8.elementsEqual(rhs.value.utf8)
            && lhs.children == rhs.children
    }
}

/// A bounded presentation parser. Its only input is already privacy-filtered characters.
/// It deliberately recognizes the inert concealment token as a scalar, since replacing a
/// complete secret JSON value removes its quotes/braces and need not leave valid JSON.
enum SafeStructuredText {
    static func json(_ source: String, maximumUTF16Units: Int = 262_144,
                     maximumNodes: Int = 20_000, maximumDepth: Int = 64) -> [SafeOutlineNode]? {
        guard maximumUTF16Units > 0, maximumUTF16Units < Int.max, maximumNodes > 0, maximumDepth > 0,
              source.utf16.prefix(maximumUTF16Units + 1).count <= maximumUTF16Units else { return nil }
        var scanner = SafeJSONOutlineScanner(bytes: Array(source.utf8), maximumNodes: maximumNodes, maximumDepth: maximumDepth)
        return try? [scanner.document()]
    }
    static func configuration(_ source: String, syntax: TextSyntax) -> [SafeOutlineNode]? {
        SafeConfigurationOutline.nodes(source, syntax: syntax)
    }
}

private enum SafeOutlineParseError: Error { case invalid }

private struct SafeJSONOutlineScanner {
    let bytes: [UInt8]
    let maximumNodes: Int
    let maximumDepth: Int
    var index = 0
    var nextID = 0
    mutating func document() throws -> SafeOutlineNode {
        whitespace()
        let root = try value(name: "$", depth: 1)
        whitespace()
        guard index == bytes.count else { throw SafeOutlineParseError.invalid }
        return root
    }
    mutating func value(name: String, depth: Int) throws -> SafeOutlineNode {
        guard depth <= maximumDepth, nextID < maximumNodes, index < bytes.count else { throw SafeOutlineParseError.invalid }
        let id = nextID; nextID += 1
        if bytes[index] == 123 || bytes[index] == 91 {
            let object = bytes[index] == 123
            let closing: UInt8 = object ? 125 : 93
            index += 1; whitespace()
            var children: [SafeOutlineNode] = []
            if !take(closing) {
                while true {
                    let childName: String
                    if object {
                        childName = try string()
                        whitespace()
                        guard take(58) else { throw SafeOutlineParseError.invalid }
                        whitespace()
                    } else { childName = "[\(children.count)]" }
                    children.append(try value(name: childName, depth: depth + 1))
                    whitespace()
                    if take(closing) { break }
                    guard take(44) else { throw SafeOutlineParseError.invalid }
                    whitespace()
                }
            }
            if object {
                var counts: [String: Int] = [:]
                for child in children { counts[child.name, default: 0] += 1 }
                children = children.map { child in
                    .init(id: child.id, name: child.name, value: child.value, children: child.children,
                          isDuplicateKey: counts[child.name, default: 0] > 1)
                }
            }
            return .init(id: id, name: name, value: object ? "{…}" : "[…]", children: children)
        }
        if bytes[index] == 34 { return .init(id: id, name: name, value: try string()) }
        let start = index
        while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        guard start < index else { throw SafeOutlineParseError.invalid }
        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        let literal = ["true", "false", "null", SecretFieldPolicy.concealmentToken].contains(token)
        let number = token.range(of: #"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
        guard literal || number else { throw SafeOutlineParseError.invalid }
        return .init(id: id, name: name, value: token)
    }
    mutating func string() throws -> String {
        let start = index
        guard take(34) else { throw SafeOutlineParseError.invalid }
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 {
                guard let value = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) else { throw SafeOutlineParseError.invalid }
                return value
            }
            if byte == 92 {
                guard index < bytes.count else { throw SafeOutlineParseError.invalid }
                index += 1
            }
        }
        throw SafeOutlineParseError.invalid
    }
    mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ value: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == value else { return false }
        index += 1; return true
    }
}

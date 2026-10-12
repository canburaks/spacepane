import PreviewContracts

/// A short outline of concealed JSON: keys with scalar values inline, nested containers indented
/// to a small depth and collapsed beyond it. Minified documents, which have no line structure of their
/// own, read as an outline instead of one clipped line. Scanning stops as soon as the page is full.
enum ThumbnailJSONOutline {
    /// True when the text's own line structure would waste the page: a few very long lines.
    static func prefersOutline(text: String, lineCount: Int, columns: Int) -> Bool {
        guard lineCount > 0 else { return false }
        if lineCount <= 2 { return text.utf8.count > columns }
        let firstLine = text.unicodeScalars.prefix(while: { $0.value != 10 && $0.value != 13 })
        return ThumbnailCells.width(of: firstLine) > columns
    }

    /// Returns nil when the text is not exactly one well-formed JSON value (JSON Lines, for example).
    static func page(from text: String, metrics: ThumbnailMetrics) -> ThumbnailTextPage? {
        var scanner = Scanner(bytes: Array(text.utf8), capacity: metrics.rows, columns: metrics.columns)
        guard scanner.scan(), !scanner.lines.isEmpty else { return nil }
        return ThumbnailTextPage(lines: scanner.lines)
    }

    private struct Scanner {
        static let maximumDepth = 3
        static let maximumRetainedStringBytes = 512
        static let quote = UInt8(ascii: "\"")
        static let backslash = UInt8(ascii: "\\")

        let bytes: [UInt8]
        let capacity: Int
        let columns: Int
        var index = 0
        var lines: [ThumbnailLine] = []

        init(bytes: [UInt8], capacity: Int, columns: Int) {
            self.bytes = bytes
            self.capacity = capacity
            self.columns = columns
        }

        private var isFull: Bool { lines.count >= capacity }

        mutating func scan() -> Bool {
            skipWhitespace()
            guard emit(label: nil, indent: 0, depth: 0, dash: false) else { return false }
            skipWhitespace()
            return isFull || index >= bytes.count
        }

        // MARK: Values

        /// Emits one value; false means the input is malformed.
        private mutating func emit(label: String?, indent: Int, depth: Int, dash: Bool) -> Bool {
            if isFull { return true }
            skipWhitespace()
            guard index < bytes.count else { return false }
            let byte = bytes[index]
            guard byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") else {
                guard let value = scalar() else { return false }
                add(indent: indent, dash: dash, label: label, value: value)
                return true
            }
            let isObject = byte == UInt8(ascii: "{")
            let closer = isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")
            let start = index
            index += 1
            skipWhitespace()
            guard index < bytes.count else { return false }
            if bytes[index] == closer {
                index += 1
                add(indent: indent, dash: dash, label: label, value: [ThumbnailRun(isObject ? "{}" : "[]")])
                return true
            }
            if depth >= Self.maximumDepth {
                index = start
                guard skipContainer() else { return false }
                add(indent: indent, dash: dash, label: label, value: [ThumbnailRun(isObject ? "{…}" : "[…]", tone: .muted)])
                return true
            }
            var childIndent = indent
            var inlineDashIndent: Int?
            if label != nil {
                add(indent: indent, dash: dash, label: label, value: [])
                childIndent = indent + (dash ? 4 : 2)
            } else if dash {
                // An object element carries its dash on its first member's line.
                childIndent = indent + 2
                inlineDashIndent = isObject ? indent : nil
            }
            return isObject
                ? members(childIndent: childIndent, dashIndent: inlineDashIndent, depth: depth)
                : elements(childIndent: childIndent, depth: depth)
        }

        private mutating func members(childIndent: Int, dashIndent: Int?, depth: Int) -> Bool {
            var pendingDash = dashIndent
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == Self.quote, let key = string() else { return false }
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return false }
                index += 1
                let ok: Bool
                if let dashAt = pendingDash {
                    pendingDash = nil
                    ok = emit(label: key, indent: dashAt, depth: depth + 1, dash: true)
                } else {
                    ok = emit(label: key, indent: childIndent, depth: depth + 1, dash: false)
                }
                guard ok else { return false }
                if isFull { return true }
                skipWhitespace()
                guard index < bytes.count else { return false }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return true }
                return false
            }
        }

        private mutating func elements(childIndent: Int, depth: Int) -> Bool {
            while true {
                guard emit(label: nil, indent: childIndent, depth: depth + 1, dash: true) else { return false }
                if isFull { return true }
                skipWhitespace()
                guard index < bytes.count else { return false }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return true }
                return false
            }
        }

        /// A string, number or literal as drawn runs; nil when malformed.
        private mutating func scalar() -> [ThumbnailRun]? {
            let byte = bytes[index]
            if byte == Self.quote {
                guard let value = string() else { return nil }
                return [ThumbnailRun("\"" + value + "\"", tone: .string)]
            }
            let start = index
            while index < bytes.count, !Self.isDelimiter(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            if token == "true" || token == "false" || token == "null" { return [ThumbnailRun(token, tone: .literal)] }
            guard !token.isEmpty, token.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 43 || $0 == 46 || $0 == 101 || $0 == 69 }) else {
                return nil
            }
            return [ThumbnailRun(token, tone: .number)]
        }

        private static func isDelimiter(_ byte: UInt8) -> Bool {
            byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]")
                || byte == 32 || byte == 9 || byte == 10 || byte == 13
        }

        /// Decodes the string at `index` (an opening quote). Escapes that would break a one-line
        /// summary become spaces; only a bounded prefix is kept. nil when unterminated.
        private mutating func string() -> String? {
            guard index < bytes.count, bytes[index] == Self.quote else { return nil }
            index += 1
            var kept: [UInt8] = []
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == Self.quote { return String(decoding: kept, as: UTF8.self) }
                var decoded = byte
                if byte == Self.backslash {
                    guard index < bytes.count else { return nil }
                    let escape = bytes[index]
                    index += 1
                    switch escape {
                    case UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"), UInt8(ascii: "b"), UInt8(ascii: "f"):
                        decoded = 32
                    case UInt8(ascii: "u"):
                        // \uXXXX: keep BMP scalars, drop the four digits otherwise.
                        guard index + 4 <= bytes.count else { return nil }
                        let digits = String(decoding: bytes[index..<(index + 4)], as: UTF8.self)
                        index += 4
                        if let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                            if kept.count < Self.maximumRetainedStringBytes { kept.append(contentsOf: Array(String(Character(scalar)).utf8)) }
                        }
                        continue
                    default:
                        decoded = escape
                    }
                }
                if kept.count < Self.maximumRetainedStringBytes { kept.append(decoded) }
            }
            return nil
        }

        /// Skips the container that starts at `index`, honoring strings. False when unterminated.
        private mutating func skipContainer() -> Bool {
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if byte == Self.quote {
                    guard string() != nil else { return false }
                    continue
                }
                index += 1
                if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { depth += 1 }
                else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                    depth -= 1
                    if depth == 0 { return true }
                }
            }
            return false
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, bytes[index] == 32 || bytes[index] == 9 || bytes[index] == 10 || bytes[index] == 13 { index += 1 }
        }

        // MARK: Lines

        private mutating func add(indent: Int, dash: Bool, label: String?, value: [ThumbnailRun]) {
            guard !isFull else { return }
            var runs: [ThumbnailRun] = []
            if dash { runs.append(ThumbnailRun("- ", tone: .muted)) }
            if let label {
                runs.append(ThumbnailRun(label, tone: .key))
                runs.append(ThumbnailRun(value.isEmpty ? ":" : ": "))
            }
            runs.append(contentsOf: value)
            let clampedIndent = min(indent, max(0, columns - 4))
            lines.append(ThumbnailLine(indent: clampedIndent, runs: Self.fit(runs, cells: columns - clampedIndent)))
        }

        /// Clips runs to a cell budget, ending a clipped line with an ellipsis.
        static func fit(_ runs: [ThumbnailRun], cells: Int) -> [ThumbnailRun] {
            guard cells > 0 else { return [] }
            var remaining = cells
            var result: [ThumbnailRun] = []
            for run in runs {
                let scalars = Array(run.text.unicodeScalars)
                let width = ThumbnailCells.width(of: scalars)
                if width <= remaining {
                    result.append(run)
                    remaining -= width
                    continue
                }
                let head = ThumbnailCells.prefix(scalars, cells: max(0, remaining - 1))
                result.append(ThumbnailRun(ThumbnailCells.string(head) + "…", tone: run.tone))
                return result
            }
            return result
        }
    }
}

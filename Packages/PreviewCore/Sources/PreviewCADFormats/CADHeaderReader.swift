import Foundation
import PreviewContracts

/// Reads a few non-personal facts from the first bytes of a STEP or IGES file.
///
/// Scope and privacy: the scan is bounded to the first 64 KiB, never fails a preview and returns nothing
/// instead of guessing. Only the exchange schema and the system named by the file are read. Author,
/// organization, file name, product identifiers and timestamps are never decoded; the readers below skip
/// those parameters structurally. The caller already holds the opt-in CAD file's bytes, so no extra I/O occurs.
enum CADHeaderReader {
    static let scanLimit = 64 * 1_024

    static func facts(kind: CADFileKind, data: Data) -> CADHeaderFacts? {
        let bytes = [UInt8](data.prefix(scanLimit))
        let facts: CADHeaderFacts?
        switch kind {
        case .step: facts = StepHeaderReader.read(bytes)
        case .iges: facts = IGESHeaderReader.read(bytes)
        }
        guard let facts, !facts.isEmpty else { return nil }
        return facts
    }

    /// Placeholder values that exporters write when a field is unknown. They name nothing.
    fileprivate static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty || trimmed == "unknown" || trimmed == "none" || trimmed == "n/a" || trimmed == "$"
    }

    /// Chooses the system name from the primary field, or from the fallback only when the primary field is
    /// blank. A primary field that is present but unreadable yields nothing: an unsafe name is omitted, never
    /// silently replaced by a different field.
    fileprivate static func originatingSystem(primary: ArraySlice<UInt8>?, fallback: ArraySlice<UInt8>?) -> String? {
        func decode(_ slice: ArraySlice<UInt8>?) -> (text: String?, isBlank: Bool) {
            guard let slice else { return (nil, true) }
            guard let text = asciiText(slice) else { return (nil, false) }
            return (text, isPlaceholder(text))
        }
        let first = decode(primary)
        if !first.isBlank { return first.text }
        let second = decode(fallback)
        return second.isBlank ? nil : second.text
    }

    /// Printable ASCII only. Exchange-file escapes (`\X2\`, `\S\`) and raw high bytes decline to decode.
    fileprivate static func asciiText(_ bytes: ArraySlice<UInt8>, maximumLength: Int = 256) -> String? {
        guard bytes.count <= maximumLength, bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }
}

// MARK: - STEP (ISO 10303-21)

private enum StepHeaderReader {
    /// `FILE_SCHEMA` and `FILE_NAME` are the only entities consulted, and a bounded count of header
    /// entities is processed so a malformed header cannot make the scan expensive.
    private static let maximumEntities = 32

    static func read(_ bytes: [UInt8]) -> CADHeaderFacts? {
        var lexer = ExchangeLexer(bytes: bytes)
        guard lexer.skipToHeaderSection() else { return nil }
        var schema: CADSchema?
        var originatingSystem: String?
        var readName = false
        var consumedEntities = 0
        entities: while consumedEntities < maximumEntities, let token = lexer.next() {
            guard case .word(let range) = token else { continue }
            consumedEntities += 1
            let keyword = String(decoding: bytes[range].prefix(32), as: UTF8.self).uppercased()
            if keyword == "ENDSEC" { break }
            switch lexer.next() {
            case .open?: break
            case .semicolon?: continue entities
            default: break entities
            }
            switch keyword {
            case "FILE_SCHEMA":
                // Argument 0 is the schema-name list. Take the first identifier we recognize.
                guard let arguments = lexer.arguments(retaining: [0]) else { break entities }
                if case .strings(let ranges)? = arguments[0] {
                    schema = schema ?? ranges.lazy.compactMap { stepSchema(named: CADHeaderReader.asciiText(bytes[$0])) }.first
                }
            case "FILE_NAME":
                // Arguments 4 and 5 are preprocessor_version and originating_system. Name, time stamp,
                // author, organization and authorisation (0-3, 6) are structurally skipped, never decoded.
                guard let arguments = lexer.arguments(retaining: [4, 5]) else { break entities }
                func slice(_ index: Int) -> ArraySlice<UInt8>? {
                    guard case .string(let range)? = arguments[index] else { return nil }
                    return bytes[range]
                }
                // The sixth argument names the originating CAD system (ISO 10303-21 `originating_system`);
                // the fifth names the translator. Use the translator only when the system is blank.
                if !readName {
                    originatingSystem = CADHeaderReader.originatingSystem(primary: slice(5), fallback: slice(4))
                    readName = true
                }
            default:
                guard lexer.arguments(retaining: []) != nil else { break entities }
            }
        }
        return CADHeaderFacts(schema: schema, originatingSystem: originatingSystem)
    }

    /// Identifiers may be followed by an object identifier such as `{ 1 0 10303 214 1 1 1 1 }`.
    static func stepSchema(named identifier: String?) -> CADSchema? {
        guard let identifier else { return nil }
        let name = identifier.uppercased().prefix { $0 != "{" && $0 != " " }
        switch name {
        case "CONFIG_CONTROL_DESIGN": return .stepAP203
        case "AUTOMOTIVE_DESIGN", "AUTOMOTIVE_DESIGN_CC2": return .stepAP214
        default:
            if name.hasPrefix("AP203_CONFIGURATION_CONTROLLED_3D_DESIGN") { return .stepAP203Edition2 }
            if name.hasPrefix("AP242_MANAGED_MODEL_BASED_3D_ENGINEERING") { return .stepAP242 }
            return nil
        }
    }
}

/// Minimal Part 21 lexer: strings with doubled-apostrophe escapes, `/* */` comments, delimiters and
/// opaque words. Tokens carry byte ranges so skipped text is never copied or decoded.
private struct ExchangeLexer {
    enum Token: Equatable { case word(Range<Int>), string(Range<Int>), open, close, comma, semicolon }
    enum Argument: Equatable { case string(Range<Int>), strings([Range<Int>]) }
    private static let maximumNesting = 16
    private static let maximumListStrings = 8

    let bytes: [UInt8]
    private var position = 0
    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func next() -> Token? {
        while position < bytes.count {
            switch bytes[position] {
            case 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C: position += 1
            case UInt8(ascii: "("): position += 1; return .open
            case UInt8(ascii: ")"): position += 1; return .close
            case UInt8(ascii: ","): position += 1; return .comma
            case UInt8(ascii: ";"): position += 1; return .semicolon
            case UInt8(ascii: "'"): return string()
            case UInt8(ascii: "/") where startsComment(at: position):
                guard let end = commentEnd(from: position + 2) else { position = bytes.count; return nil }
                position = end
            default: return word()
            }
        }
        return nil
    }

    /// Advances past `HEADER ;`. Returns false when the section does not start in the scanned bytes.
    mutating func skipToHeaderSection() -> Bool {
        while let token = next() {
            guard case .word(let range) = token,
                  String(decoding: bytes[range].prefix(8), as: UTF8.self).uppercased() == "HEADER" else { continue }
            if next() == .semicolon { return true }
        }
        return false
    }

    /// Consumes an entity's argument list (the opening parenthesis is already consumed) through its matching
    /// closing parenthesis. Only top-level arguments named in `retained` keep their string content: a string
    /// argument, or the strings of a one-level list. Everything else is skipped by structure alone.
    /// Returns nil for truncated or malformed input.
    mutating func arguments(retaining retained: Set<Int>) -> [Int: Argument]? {
        var result: [Int: Argument] = [:]
        var index = 0, depth = 1
        var list: [Range<Int>]?
        while let token = next() {
            switch token {
            case .open:
                depth += 1
                guard depth <= Self.maximumNesting else { return nil }
                if depth == 2, retained.contains(index) { list = [] }
            case .close:
                depth -= 1
                if depth == 1, let collected = list { result[index] = .strings(collected); list = nil }
                if depth == 0 { return result }
            case .comma:
                if depth == 1 { index += 1 }
            case .string(let range):
                if depth == 1, retained.contains(index) { result[index] = .string(range) }
                else if depth == 2, list != nil, list!.count < Self.maximumListStrings { list!.append(range) }
            case .semicolon:
                return nil
            case .word:
                break
            }
        }
        return nil
    }

    private func startsComment(at index: Int) -> Bool {
        index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "*")
    }

    private func commentEnd(from start: Int) -> Int? {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == UInt8(ascii: "*"), bytes[index + 1] == UInt8(ascii: "/") { return index + 2 }
            index += 1
        }
        return nil
    }

    private mutating func string() -> Token? {
        let start = position + 1
        var index = start
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "'") {
                if index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "'") { index += 2; continue }
                position = index + 1
                return .string(start..<index)
            }
            index += 1
        }
        position = bytes.count // Unterminated: the scanned prefix ended inside a string.
        return nil
    }

    private mutating func word() -> Token {
        let start = position
        position += 1
        while position < bytes.count {
            switch bytes[position] {
            case 0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C, UInt8(ascii: "("), UInt8(ascii: ")"),
                 UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "'"):
                return .word(start..<position)
            case UInt8(ascii: "/") where startsComment(at: position):
                return .word(start..<position)
            default: position += 1
            }
        }
        return .word(start..<position)
    }
}

// MARK: - IGES

/// Reads Global-section parameters. Fixed 80-column records carry the section letter in column 73;
/// Hollerith strings (`nH...`) and custom delimiters are honored.
private enum IGESHeaderReader {
    private static let recordLength = 80
    private static let sectionColumn = 72
    private static let maximumGlobalBytes = 8 * 1_024
    private static let lastParameter = 23

    static func read(_ bytes: [UInt8]) -> CADHeaderFacts? {
        guard let global = globalSectionText(bytes), var reader = GlobalParameterReader(bytes: global),
              reader.readDelimiters() else { return nil }
        var native: Range<Int>?, preprocessor: Range<Int>?, unitName: String?
        var unitFlag: Int?, revisionFlag: Int?
        var index = 3
        while index <= lastParameter, let parameter = reader.next() {
            switch (index, parameter) {
            case (5, .text(let range)): native = range
            case (6, .text(let range)): preprocessor = range
            case (14, .raw(let range)): unitFlag = integer(global[range])
            case (15, .text(let range)): unitName = CADHeaderReader.asciiText(global[range])
            case (23, .raw(let range)): revisionFlag = integer(global[range])
            default: break // Product ID, file name, dates, author and organization are skipped unread.
            }
            index += 1
        }
        // Parameter 5 is the native system ID; parameter 6 is the translator, used only when 5 is blank.
        let system = CADHeaderReader.originatingSystem(primary: native.map { global[$0] }, fallback: preprocessor.map { global[$0] })
        let schema = revisionFlag.flatMap(IGESRevision.init(rawValue:)).map(CADSchema.iges)
        return CADHeaderFacts(schema: schema, originatingSystem: system, sourceUnit: unit(flag: unitFlag, name: unitName))
    }

    /// Flag 3 means "see the unit name"; other flags are the standard's fixed set.
    private static func unit(flag: Int?, name: String?) -> String? {
        switch flag {
        case 1: "IN"
        case 2: "MM"
        case 4: "FT"
        case 5: "MI"
        case 6: "M"
        case 7: "KM"
        case 8: "MIL"
        case 9: "UM"
        case 10: "CM"
        case 11: "UIN"
        default: name.flatMap { CADHeaderReader.isPlaceholder($0) ? nil : $0 }
        }
    }

    private static func integer(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard !bytes.isEmpty, bytes.count <= 4, bytes.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return bytes.reduce(0) { $0 * 10 + Int($1 - 0x30) }
    }

    /// Concatenates columns 1-72 of the contiguous `G` records. Handles newline-terminated files and
    /// bare 80-byte records. Skips records before the section and stops at the first other record after it.
    private static func globalSectionText(_ bytes: [UInt8]) -> [UInt8]? {
        let hasLineBreaks = bytes.prefix(2 * recordLength).contains { $0 == 0x0A || $0 == 0x0D }
        var text = [UInt8]()
        var began = false
        func accept(_ record: ArraySlice<UInt8>) -> Bool {
            guard record.count > sectionColumn else { return !began }
            let section = record[record.startIndex + sectionColumn]
            if section == UInt8(ascii: "G") {
                began = true
                text.append(contentsOf: record.prefix(sectionColumn))
                return text.count < maximumGlobalBytes
            }
            // Before the Global section, unrecognized records (Start section, stray bytes) are skipped.
            return !began
        }
        if hasLineBreaks {
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != 0x0A, bytes[end] != 0x0D { end += 1 }
                if end > start, !accept(bytes[start..<end]) { break }
                start = end + 1
            }
        } else {
            var start = 0
            while start < bytes.count {
                if !accept(bytes[start..<min(start + recordLength, bytes.count)]) { break }
                start += recordLength
            }
        }
        return began ? text : nil
    }
}

/// Sequential reader over the concatenated Global section text.
private struct GlobalParameterReader {
    enum Parameter { case text(Range<Int>), raw(Range<Int>), empty }
    private enum Hollerith { case none, value(Range<Int>), malformed }

    let bytes: [UInt8]
    private var position = 0
    private var parameterDelimiter = UInt8(ascii: ",")
    private var recordDelimiter = UInt8(ascii: ";")
    private var finished = false

    init?(bytes: [UInt8]) {
        guard !bytes.isEmpty else { return nil }
        self.bytes = bytes
    }

    /// Parameters 1 and 2: delimiter definitions, each either empty (default) or `1Hc`.
    mutating func readDelimiters() -> Bool {
        for slot in 0..<2 {
            skipSpaces()
            guard position < bytes.count else { return false }
            switch hollerith() {
            case .value(let range):
                guard range.count == 1 else { return false }
                if slot == 0 { parameterDelimiter = bytes[range.lowerBound] } else { recordDelimiter = bytes[range.lowerBound] }
                skipSpaces()
                // The terminator is the default comma or the delimiter just declared.
                if position < bytes.count, bytes[position] == UInt8(ascii: ",") || bytes[position] == parameterDelimiter {
                    position += 1
                }
            case .malformed: return false
            case .none:
                guard bytes[position] == parameterDelimiter else { return false }
                position += 1
            }
        }
        return true
    }

    /// Returns the next parameter, or nil at the record delimiter, the end of the section or malformed text.
    mutating func next() -> Parameter? {
        guard !finished else { return nil }
        skipSpaces()
        guard position < bytes.count else { return nil }
        let byte = bytes[position]
        if byte == recordDelimiter { finished = true; return nil }
        if byte == parameterDelimiter { position += 1; return .empty }
        switch hollerith() {
        case .value(let range):
            skipSpaces()
            if position < bytes.count {
                if bytes[position] == parameterDelimiter { position += 1 }
                else if bytes[position] == recordDelimiter { finished = true }
            }
            return .text(range)
        case .malformed:
            finished = true
            return nil
        case .none:
            let start = position
            while position < bytes.count, bytes[position] != parameterDelimiter, bytes[position] != recordDelimiter {
                position += 1
            }
            var end = position
            while end > start, bytes[end - 1] == 0x20 { end -= 1 }
            if position < bytes.count {
                if bytes[position] == recordDelimiter { finished = true } else { position += 1 }
            }
            return .raw(start..<end)
        }
    }

    private mutating func skipSpaces() {
        while position < bytes.count, bytes[position] == 0x20 { position += 1 }
    }

    /// `nHxxxx`: one to three digits, `H`, then exactly n bytes (delimiters inside are data).
    private mutating func hollerith() -> Hollerith {
        var index = position, length = 0, digits = 0
        while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
            length = length * 10 + Int(bytes[index] - 0x30)
            digits += 1; index += 1
            if digits > 3 { return .none }
        }
        guard digits > 0, index < bytes.count, bytes[index] == UInt8(ascii: "H") || bytes[index] == UInt8(ascii: "h") else {
            return .none
        }
        let start = index + 1
        guard start + length <= bytes.count else { return .malformed }
        position = start + length
        return .value(start..<(start + length))
    }
}

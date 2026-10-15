import Foundation
import PreviewContracts

/// XML and binary property lists become a normalized JSON source/tree using the same privacy
/// scanner. Data payloads are represented by byte counts, never decoded or exposed as base64.
public struct PropertyListSourceAdapter: FormatAdapter, BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: DecodedText, context: RequestContext) throws -> ParsedTextDocument {
        try ExpandedTextLimits.validate(input, context: context)
        return try parse(data: Data(input.text.utf8), context: context)
    }
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try parse(data: input.data, context: context)
    }
    public func parse(data: Data, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        guard data.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        let input: Data
        // XML property lists report their actual encoding; binary property lists have none to report.
        // Both produce converted text, which receives the hidden-content scan after concealment.
        var decodedEncoding: TextEncoding?
        if data.starts(with: Data("bplist00".utf8)) {
            var preflight = BinaryPropertyListPreflight(bytes: Array(data), context: context)
            try preflight.validate()
            input = data
        } else {
            let encoding: String.Encoding = data.starts(with: [0xFF, 0xFE]) ? .utf16LittleEndian
                : data.starts(with: [0xFE, 0xFF]) ? .utf16BigEndian : .utf8
            guard var source = String(data: data, encoding: encoding) else { throw PreviewFailure.unsupportedEncoding }
            decodedEncoding = encoding == .utf16LittleEndian ? .utf16LittleEndian : encoding == .utf16BigEndian ? .utf16BigEndian : .utf8
            if source.unicodeScalars.first?.value == 0xFEFF { source.removeFirst() }
            if source.hasPrefix("<?xml"), let end = source.range(of: "?>") { source.removeSubrange(source.startIndex..<end.upperBound) }
            // The one standard Apple DTD declaration is inert metadata, removed before parsing.
            let declaration = #"<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">"#
            source = source.replacingOccurrences(of: declaration, with: "")
            var scanner = XMLSourceScanner(bytes: Array(source.utf8), context: context)
            try scanner.scan()
            input = Data(source.utf8)
        }
        let value: Any
        do { value = try PropertyListSerialization.propertyList(from: input, options: [], format: nil) }
        catch { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        var normalizer = PropertyListNormalizer(context: context)
        let normalized = try normalizer.value(value, depth: 1)
        let json: Data
        do { json = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys, .prettyPrinted, .fragmentsAllowed, .withoutEscapingSlashes]) }
        catch { throw PreviewFailure.malformedDocument }
        guard json.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        let source = String(decoding: json, as: UTF8.self)
        var scanner = JSONScanner(bytes: Array(json), context: context)
        try scanner.scan()
        return ParsedTextDocument(text: source, sensitiveRanges: scanner.sensitiveRanges,
                                  usesStructuredPrivacy: true, syntax: .json, decodedEncoding: decodedEncoding,
                                  origin: .converted)
    }
}

/// Reserve a conservative escaped JSON/pretty-print bound while expanding native values.
/// Binary references spend this budget on every use, before adding a normalized child or
/// asking Foundation to serialize the full graph. The final byte check remains a backstop.
struct PropertyListNormalizer {
    let context: RequestContext
    var nodes = 0
    private(set) var outputBound = 0
    mutating func value(_ object: Any, depth: Int) throws -> Any {
        try context.checkpoint()
        nodes += 1
        guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        if let values = object as? [String: Any] {
            try container(depth: depth)
            var result: [String: Any] = [:]
            for (key, child) in values {
                try item(depth: depth)
                try string(key)
                try reserve(3) // Pretty-printed key/value separator, including spaces.
                result[key] = try value(child, depth: depth + 1)
            }
            return result
        }
        if let values = object as? [Any] {
            try container(depth: depth)
            var result: [Any] = []
            for child in values {
                try item(depth: depth)
                result.append(try value(child, depth: depth + 1))
            }
            return result
        }
        if let data = object as? Data {
            try container(depth: depth)
            try item(depth: depth)
            try string("$dataBytes")
            try reserve(3)
            try number(NSNumber(value: data.count))
            return ["$dataBytes": data.count]
        }
        if let date = object as? Date {
            let text = ISO8601DateFormatter().string(from: date)
            try string(text)
            return text
        }
        if let text = object as? String { try string(text); return text }
        if let scalar = object as? NSNumber { try number(scalar); return scalar }
        throw PreviewFailure.malformedDocument
    }

    private mutating func container(depth: Int) throws {
        // Opening/closing delimiters, line breaks and closing indentation. Empty
        // containers are deliberately charged the same conservative overhead.
        try reserve(4 + 2 * (depth - 1))
    }
    private mutating func item(depth: Int) throws {
        // Leading line break, indentation and a possible comma.
        try reserve(2 + 2 * depth)
    }
    private mutating func string(_ text: String) throws {
        try reserve(2) // Quotes.
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            let cost: Int
            switch scalar.value {
            case 0..<32: cost = 6 // A possible \uXXXX control escape.
            case 34, 47, 92: cost = 2 // Quote, slash or backslash.
            case 32..<128: cost = 1
            case 128...0xFFFF: cost = 6 // Covers either UTF-8 or an escaped BMP scalar.
            default: cost = 12 // Covers an escaped UTF-16 surrogate pair.
            }
            try reserve(cost)
        }
    }
    private mutating func number(_ value: NSNumber) throws {
        // A native plist number is a fixed-size scalar. Serialize only this bounded
        // scalar to count Foundation's exact spelling, including booleans/exponents.
        let data: Data
        do { data = try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) }
        catch { throw PreviewFailure.malformedDocument }
        try reserve(data.count)
    }
    private mutating func reserve(_ bytes: Int) throws {
        guard bytes >= 0, bytes <= context.budget.maxOutputUTF8Bytes - outputBound else {
            throw PreviewFailure.outputTooLarge
        }
        outputBound += bytes
    }
}

/// Header/trailer, all referenced collection sizes, cycles and expanded graph depth are checked
/// before Foundation allocates a property-list graph. Repeated references spend the node budget.
private struct BinaryPropertyListPreflight {
    let bytes: [UInt8]
    let context: RequestContext
    var offsets: [Int] = []
    var referenceWidth = 0
    var tableStart = 0
    var visits = 0

    mutating func validate() throws {
        guard bytes.count >= 40 else { throw PreviewFailure.malformedDocument }
        let trailer = bytes.count - 32
        let offsetWidth = Int(bytes[trailer + 6])
        referenceWidth = Int(bytes[trailer + 7])
        guard (1...8).contains(offsetWidth), (1...8).contains(referenceWidth) else { throw PreviewFailure.malformedDocument }
        let count = try integer(at: trailer + 8, width: 8)
        let root = try integer(at: trailer + 16, width: 8)
        tableStart = try integer(at: trailer + 24, width: 8)
        guard count > 0, count <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        guard root < count, tableStart >= 8, tableStart <= trailer,
              count <= (trailer - tableStart) / offsetWidth else { throw PreviewFailure.malformedDocument }
        for index in 0..<count {
            try context.checkpoint()
            let offset = try integer(at: tableStart + index * offsetWidth, width: offsetWidth)
            guard (8..<tableStart).contains(offset) else { throw PreviewFailure.malformedDocument }
            offsets.append(offset)
        }
        var path: Set<Int> = []
        try visit(root, depth: 1, path: &path)
    }
    mutating func visit(_ reference: Int, depth: Int, path: inout Set<Int>) throws {
        try context.checkpoint()
        visits += 1
        guard visits <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
        guard depth <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
        guard offsets.indices.contains(reference), !path.contains(reference) else { throw PreviewFailure.malformedDocument }
        path.insert(reference)
        defer { path.remove(reference) }
        let offset = offsets[reference]
        let marker = bytes[offset]
        let kind = marker >> 4
        var position = offset + 1
        var count = Int(marker & 15)
        if [4, 5, 6, 10, 13].contains(kind), count == 15 {
            guard position < tableStart, bytes[position] >> 4 == 1 else { throw PreviewFailure.malformedDocument }
            let power = Int(bytes[position] & 15)
            guard power <= 3 else { throw PreviewFailure.malformedDocument }
            let width = 1 << power
            position += 1
            count = try integer(at: position, width: width)
            position += width
        }
        let width: Int
        switch kind {
        case 0: guard [0, 8, 9, 15].contains(marker & 15) else { throw PreviewFailure.malformedDocument }; return
        case 1, 2: guard marker & 15 <= 4 else { throw PreviewFailure.malformedDocument }; width = 1 << Int(marker & 15)
        case 3: guard marker == 0x33 else { throw PreviewFailure.malformedDocument }; width = 8
        case 4, 5: width = count
        case 6: guard count <= (tableStart - position) / 2 else { throw PreviewFailure.malformedDocument }; width = count * 2
        case 10, 13:
            let multiplier = kind == 13 ? 2 : 1
            guard count <= context.budget.maxJSONNodes, count <= (tableStart - position) / referenceWidth / multiplier else { throw PreviewFailure.tooManyNodes }
            for child in 0..<(count * multiplier) {
                let value = try integer(at: position + child * referenceWidth, width: referenceWidth)
                try visit(value, depth: depth + 1, path: &path)
            }
            return
        default: throw PreviewFailure.malformedDocument
        }
        guard width >= 0, position <= tableStart, width <= tableStart - position else { throw PreviewFailure.malformedDocument }
    }
    func integer(at start: Int, width: Int) throws -> Int {
        guard start >= 0, width > 0, start <= bytes.count, width <= bytes.count - start else { throw PreviewFailure.malformedDocument }
        var result: UInt64 = 0
        for byte in bytes[start..<(start + width)] { result = (result << 8) | UInt64(byte) }
        guard result <= UInt64(Int.max) else { throw PreviewFailure.malformedDocument }
        return Int(result)
    }
}

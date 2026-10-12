import Foundation
import PreviewContracts

/// The manifest facts shown for an Android package.
struct AndroidManifestSummary: Equatable {
    var packageName: String?
    var versionCode: Int?
    var versionName: String?
    var minimumSDK: String?
    var targetSDK: String?
    var compileSDK: String?
    var applicationLabel: String?
    var isDebuggable: Bool?
    var permissions: [String] = []
    var activities = 0
    var services = 0
    var receivers = 0
    var providers = 0
}

/// A manifest attribute's value, as either compiled XML (typed) or protobuf XML (always text) supplies it.
enum AndroidAttributeValue: Equatable {
    case text(String), integer(Int), boolean(Bool)
    var text: String? {
        switch self {
        case .text(let value): value
        case .integer(let value): String(value)
        case .boolean: nil
        }
    }
    var integer: Int? {
        switch self {
        case .integer(let value): value
        case .text(let value): Int(value)
        case .boolean: nil
        }
    }
    var boolean: Bool? {
        switch self {
        case .boolean(let value): value
        case .integer(let value): value != 0
        case .text(let value): ["true", "1"].contains(value.lowercased()) ? true : (["false", "0"].contains(value.lowercased()) ? false : nil)
        }
    }
}

extension AndroidManifestSummary {
    static let maximumStoredPermissions = 512

    /// Applies one element's attributes. The same rules serve both manifest encodings.
    mutating func record(element: String, parent: String?, attributes: [String: AndroidAttributeValue], isRoot: Bool) {
        switch (element, parent) {
        case ("manifest", nil) where isRoot:
            packageName = attributes["package"]?.text
            versionCode = attributes["versionCode"]?.integer
            versionName = attributes["versionName"]?.text
            compileSDK = attributes["compileSdkVersion"]?.text
        case ("uses-sdk", "manifest"):
            minimumSDK = attributes["minSdkVersion"]?.text
            targetSDK = attributes["targetSdkVersion"]?.text
        case ("uses-permission", "manifest"), ("uses-permission-sdk-23", "manifest"):
            if let name = attributes["name"]?.text, !name.isEmpty, permissions.count < Self.maximumStoredPermissions,
               !permissions.contains(name) {
                permissions.append(name)
            }
        case ("application", "manifest"):
            isDebuggable = attributes["debuggable"]?.boolean
            // A label that is a resource reference is not resolved; only a literal string is shown.
            applicationLabel = attributes["label"]?.text
        case ("activity", "application"), ("activity-alias", "application"): activities += 1
        case ("service", "application"): services += 1
        case ("receiver", "application"): receivers += 1
        case ("provider", "application"): providers += 1
        default: break
        }
    }
}

/// A bounded reader for Android's compiled ("binary") XML, as found in `AndroidManifest.xml` inside
/// an APK. The format is a chunk stream: a string pool, an optional resource-id map and element
/// chunks whose attributes carry typed values. Only the manifest facts above are interpreted; resource
/// references are not resolved (the resource table is never read), and nothing is executed or loaded.
enum AndroidBinaryXML {
    private enum Chunk {
        static let document: UInt16 = 0x0003
        static let stringPool: UInt16 = 0x0001
        static let resourceMap: UInt16 = 0x0180
        static let startElement: UInt16 = 0x0102
        static let endElement: UInt16 = 0x0103
    }
    private enum ValueType {
        static let string: UInt8 = 0x03
        static let decimal: UInt8 = 0x10
        static let hexadecimal: UInt8 = 0x11
        static let boolean: UInt8 = 0x12
    }
    /// Framework attribute resource identifiers, used when a packer stripped an attribute's name string.
    private static let attributeByResourceID: [UInt32: String] = [
        0x0101_0003: "name", 0x0101_0001: "label", 0x0101_000F: "debuggable", 0x0101_020C: "minSdkVersion",
        0x0101_021B: "versionCode", 0x0101_021C: "versionName", 0x0101_0270: "targetSdkVersion",
        0x0101_0572: "compileSdkVersion"
    ]
    private static let noIndex: UInt32 = 0xFFFF_FFFF
    private static let attributeLength = 20
    private static let maximumStringCharacters = 32_768

    static func parseManifest(_ data: Data, context: RequestContext) throws -> AndroidManifestSummary {
        try context.checkpoint()
        let reader = Reader(bytes: [UInt8](data))
        guard reader.bytes.count >= 8, try reader.u16(0) == Chunk.document, try reader.u16(2) == 8 else {
            throw PreviewFailure.unsupportedFormat
        }
        let declared = Int(try reader.u32(4))
        guard declared >= 8, declared <= reader.bytes.count else { throw PreviewFailure.malformedDocument }
        let end = declared
        var offset = 8
        var pool: StringPool?
        var resourceIDs: [UInt32] = []
        var summary = AndroidManifestSummary()
        var path: [String] = []
        var sawManifest = false
        var elements = 0
        var chunks = 0
        while offset + 8 <= end {
            chunks += 1
            if chunks.isMultiple(of: 256) { try context.checkpoint() }
            let type = try reader.u16(offset)
            let headerSize = Int(try reader.u16(offset + 2))
            let size = Int(try reader.u32(offset + 4))
            guard headerSize >= 8, size >= headerSize, size <= end - offset else { throw PreviewFailure.malformedDocument }
            switch type {
            case Chunk.stringPool:
                guard pool == nil else { throw PreviewFailure.malformedDocument }
                pool = try StringPool(reader: reader, start: offset, headerSize: headerSize, size: size)
            case Chunk.resourceMap:
                let count = (size - headerSize) / 4
                guard count <= context.budget.maxJSONNodes * 4 else { throw PreviewFailure.tooManyNodes }
                resourceIDs = try (0..<count).map { try reader.u32(offset + headerSize + $0 * 4) }
            case Chunk.startElement:
                guard let pool else { throw PreviewFailure.malformedDocument }
                elements += 1
                guard elements <= context.budget.maxJSONNodes, path.count < min(context.budget.maxJSONDepth, 64) else {
                    throw PreviewFailure.tooManyNodes
                }
                let name = pool.string(try reader.u32(offset + 20)) ?? ""
                let attributes = try attributeList(reader, chunk: offset, headerSize: headerSize, size: size, pool: pool, resourceIDs: resourceIDs)
                summary.record(element: name, parent: path.last, attributes: attributes, isRoot: path.isEmpty)
                if path.isEmpty, name == "manifest" { sawManifest = true }
                path.append(name)
            case Chunk.endElement:
                guard !path.isEmpty else { throw PreviewFailure.malformedDocument }
                path.removeLast()
            default:
                break
            }
            offset += size
        }
        guard sawManifest, path.isEmpty else { throw PreviewFailure.malformedDocument }
        return summary
    }

    // MARK: Attributes

    private static func attributeList(_ reader: Reader, chunk: Int, headerSize: Int, size: Int, pool: StringPool,
                                      resourceIDs: [UInt32]) throws -> [String: AndroidAttributeValue] {
        // The extension header follows the 16-byte node header: namespace, name, then the attribute table layout.
        guard headerSize == 16, size >= 36 else { throw PreviewFailure.malformedDocument }
        let start = Int(try reader.u16(chunk + 24))
        let stride = Int(try reader.u16(chunk + 26))
        let count = Int(try reader.u16(chunk + 28))
        // Attributes cannot overlap the 20-byte extension header that precedes them.
        guard stride == attributeLength, start >= 20 else { throw PreviewFailure.unsupportedFormat }
        let first = chunk + 16 + start
        guard count >= 0, first >= chunk + 16, first + count * attributeLength <= chunk + size else { throw PreviewFailure.malformedDocument }
        var result: [String: AndroidAttributeValue] = [:]
        for index in 0..<count {
            let base = first + index * attributeLength
            let nameIndex = try reader.u32(base + 4)
            let raw = try reader.u32(base + 8)
            let dataType = try reader.u8(base + 15)
            let data = try reader.u32(base + 16)
            var name = pool.string(nameIndex) ?? ""
            if name.isEmpty, Int(nameIndex) < resourceIDs.count { name = attributeByResourceID[resourceIDs[Int(nameIndex)]] ?? "" }
            guard !name.isEmpty, result[name] == nil else { continue }
            switch dataType {
            case ValueType.string: if let text = pool.string(data) { result[name] = .text(text) }
            case ValueType.decimal, ValueType.hexadecimal: result[name] = .integer(Int(Int32(bitPattern: data)))
            case ValueType.boolean: result[name] = .boolean(data != 0)
            default: if let text = pool.string(raw) { result[name] = .text(text) }
            }
        }
        return result
    }

    // MARK: Bounded little-endian reads

    private struct Reader {
        let bytes: [UInt8]
        func u8(_ offset: Int) throws -> UInt8 {
            guard offset >= 0, offset < bytes.count else { throw PreviewFailure.malformedDocument }
            return bytes[offset]
        }
        func u16(_ offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= bytes.count else { throw PreviewFailure.malformedDocument }
            return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= bytes.count else { throw PreviewFailure.malformedDocument }
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
        }
    }

    // MARK: String pool

    private struct StringPool {
        let reader: Reader
        let chunkEnd: Int
        let count: Int
        let isUTF8: Bool
        let offsetsStart: Int
        let stringsStart: Int

        init(reader: Reader, start: Int, headerSize: Int, size: Int) throws {
            guard headerSize >= 28 else { throw PreviewFailure.malformedDocument }
            let count = Int(try reader.u32(start + 8))
            let flags = try reader.u32(start + 16)
            let strings = Int(try reader.u32(start + 20))
            guard count <= (size - headerSize) / 4, strings <= size else { throw PreviewFailure.malformedDocument }
            self.reader = reader
            self.chunkEnd = start + size
            self.count = count
            self.isUTF8 = flags & 0x100 != 0
            self.offsetsStart = start + headerSize
            self.stringsStart = start + strings
        }

        func string(_ index: UInt32) -> String? {
            guard index != AndroidBinaryXML.noIndex, Int(index) < count,
                  let relative = try? reader.u32(offsetsStart + Int(index) * 4) else { return nil }
            var position = stringsStart + Int(relative)
            guard position >= stringsStart, position < chunkEnd else { return nil }
            do {
                if isUTF8 {
                    var first = Int(try reader.u8(position))
                    position += 1
                    if first & 0x80 != 0 { first = ((first & 0x7F) << 8) | Int(try reader.u8(position)); position += 1 }
                    _ = first // The character count is informative only; the byte length bounds the read.
                    var length = Int(try reader.u8(position))
                    position += 1
                    if length & 0x80 != 0 { length = ((length & 0x7F) << 8) | Int(try reader.u8(position)); position += 1 }
                    guard length <= AndroidBinaryXML.maximumStringCharacters * 2, position + length <= chunkEnd else { return nil }
                    return String(decoding: reader.bytes[position..<(position + length)], as: UTF8.self)
                }
                var length = Int(try reader.u16(position))
                position += 2
                if length & 0x8000 != 0 { length = ((length & 0x7FFF) << 16) | Int(try reader.u16(position)); position += 2 }
                guard length <= AndroidBinaryXML.maximumStringCharacters, position + length * 2 <= chunkEnd else { return nil }
                let units = try (0..<length).map { try reader.u16(position + $0 * 2) }
                return String(decoding: units, as: UTF16.self)
            } catch { return nil }
        }
    }
}

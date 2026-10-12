import Foundation
import PreviewContracts

public struct TARListingAdapter: BinaryFormatAdapter, RandomAccessFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try ContainerLimits(context: context).validateInput(input.data)
        return try parseDecoded(input.data, context: context)
    }

    public func parse(_ source: any PreviewByteSource, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let limits = ContainerLimits(context: context)
        var position: Int64 = 0
        var readBytes = 0
        var metadataBytes = 0
        var entries: [ContainerEntry] = []
        var longName: String?
        var longLink: String?
        var localPAX: [String: String] = [:]
        var globalPAX: [String: String] = [:]
        var partial = false
        var ended = false
        while position < source.byteCount {
            try context.checkpoint()
            if position >= Int64(limits.maxDecodedBytes) || context.budget.maxInputBytes - readBytes < 512 ||
                entries.count >= ArchiveListing.maxEntries(context) { partial = true; break }
            guard source.byteCount - position >= 512 else { throw PreviewFailure.malformedDocument }
            let header = Array(try source.read(offset: position, count: 512, context: context))
            position += 512
            readBytes += 512
            if header.allSatisfy({ $0 == 0 }) {
                guard source.byteCount - position >= 512 else { throw PreviewFailure.malformedDocument }
                if context.budget.maxInputBytes - readBytes < 512 { partial = true; break }
                guard try source.read(offset: position, count: 512, context: context).allSatisfy({ $0 == 0 }) else { throw PreviewFailure.malformedDocument }
                position += 512
                readBytes += 512
                let remaining = source.byteCount - position
                if remaining > Int64(context.budget.maxInputBytes - readBytes) { partial = true }
                else if remaining > 0 {
                    guard try source.read(offset: position, count: Int(remaining), context: context).allSatisfy({ $0 == 0 }) else { throw PreviewFailure.malformedDocument }
                }
                ended = true
                break
            }
            let checksum = try tarNumber(header[148..<156])
            let actual = header.enumerated().reduce(0) { $0 + ((148..<156).contains($1.offset) ? 32 : Int($1.element)) }
            guard checksum == actual else { throw PreviewFailure.malformedDocument }
            let type = header[156]
            guard type != 83 else { throw PreviewFailure.unsupportedFormat }
            var size = try tarNumber(header[124..<136])
            var path = try tarString(header[0..<100])
            let magic = String(decoding: header[257..<263], as: UTF8.self)
            if magic.hasPrefix("ustar") {
                let prefix = try tarString(header[345..<500])
                if !prefix.isEmpty { path = prefix + "/" + path }
            } else if !header[257..<263].allSatisfy({ $0 == 0 }) { throw PreviewFailure.unsupportedFormat }
            if type == 120 || type == 103 || type == 76 || type == 75 {
                guard size <= limits.maxMetadataBytes - metadataBytes, size <= context.budget.maxInputBytes - readBytes,
                      Int64(size) <= source.byteCount - position else { throw PreviewFailure.outputTooLarge }
                let payload = ArraySlice(try source.read(offset: position, count: size, context: context))
                readBytes += size
                metadataBytes += size
                if type == 120 || type == 103 {
                    let fields = try paxFields(payload, context: context)
                    if type == 103 { globalPAX.merge(fields) { _, new in new } } else { localPAX = fields }
                } else if type == 76 { longName = try tarString(payload) }
                else if type == 75 { longLink = try tarString(payload) }
            } else {
                let fields = globalPAX.merging(localPAX) { _, new in new }
                if let value = fields["size"] {
                    guard let number = Int(value), number >= 0 else { throw PreviewFailure.malformedDocument }
                    size = number
                }
                path = fields["path"] ?? longName ?? path
                let target = fields["linkpath"] ?? longLink
                localPAX = [:]
                longName = nil
                longLink = nil
                metadataBytes += path.utf8.count
                guard metadataBytes <= limits.maxMetadataBytes else { throw PreviewFailure.outputTooLarge }
                entries.append(try entry(path: path, type: type, size: size, header: header, linkTarget: target,
                                         modified: tarModified(header, fields: fields)))
            }
            guard Int64(size) <= source.byteCount - position else { throw PreviewFailure.malformedDocument }
            position += Int64(size)
            let padding = Int64((512 - size % 512) % 512)
            guard padding <= source.byteCount - position else { throw PreviewFailure.malformedDocument }
            position += padding
        }
        guard partial || (ended && longName == nil && localPAX.isEmpty) else { throw PreviewFailure.malformedDocument }
        return try listingDocument(format: "TAR", entries: entries, context: context, partial: partial, assessRisks: true)
    }

    func parseDecoded(_ data: Data, context: RequestContext) throws -> ParsedTextDocument {
        let limits = ContainerLimits(context: context)
        guard data.count <= limits.maxDecodedBytes else { throw PreviewFailure.inputTooLarge }
        var cursor = BinaryCursor(data)
        var entries: [ContainerEntry] = []
        var metadataBytes = 0
        var longName: String?
        var longLink: String?
        var localPAX: [String: String] = [:]
        var globalPAX: [String: String] = [:]
        var ended = false
        while cursor.remaining >= 512 {
            try context.checkpoint()
            let header = Array(try cursor.read(512))
            if header.allSatisfy({ $0 == 0 }) {
                guard cursor.remaining >= 512, try cursor.read(512).allSatisfy({ $0 == 0 }),
                      cursor.bytes[cursor.offset...].allSatisfy({ $0 == 0 }) else { throw PreviewFailure.malformedDocument }
                ended = true
                break
            }
            let checksum = try tarNumber(header[148..<156])
            let actual = header.enumerated().reduce(0) { $0 + ((148..<156).contains($1.offset) ? 32 : Int($1.element)) }
            guard checksum == actual else { throw PreviewFailure.malformedDocument }
            let rawType = header[156]
            guard rawType != 83 else { throw PreviewFailure.unsupportedFormat } // GNU sparse.
            var size = try tarNumber(header[124..<136])
            var path = try tarString(header[0..<100])
            let magic = String(decoding: header[257..<263], as: UTF8.self)
            if magic.hasPrefix("ustar") {
                let prefix = try tarString(header[345..<500])
                if !prefix.isEmpty { path = prefix + "/" + path }
            } else if !header[257..<263].allSatisfy({ $0 == 0 }) { throw PreviewFailure.unsupportedFormat }
            if rawType == 120 || rawType == 103 || rawType == 76 || rawType == 75 {
                guard size <= limits.maxMetadataBytes - metadataBytes else { throw PreviewFailure.outputTooLarge }
                let payload = try cursor.read(size)
                metadataBytes += size
                try skipPadding(size, cursor: &cursor)
                if rawType == 120 || rawType == 103 {
                    let fields = try paxFields(payload, context: context)
                    if rawType == 103 { globalPAX.merge(fields) { _, new in new } }
                    else { localPAX = fields }
                } else if rawType == 76 { longName = try tarString(payload) }
                else if rawType == 75 { longLink = try tarString(payload) }
                continue
            }
            let fields = globalPAX.merging(localPAX) { _, new in new }
            if let paxSize = fields["size"] {
                guard let value = Int(paxSize), value >= 0 else { throw PreviewFailure.malformedDocument }
                size = value
            }
            path = fields["path"] ?? longName ?? path
            let target = fields["linkpath"] ?? longLink
            longName = nil
            longLink = nil
            localPAX = [:]
            metadataBytes += path.utf8.count
            guard metadataBytes <= limits.maxMetadataBytes else { throw PreviewFailure.outputTooLarge }
            guard entries.count < ArchiveListing.maxEntries(context) else { throw PreviewFailure.tooManyNodes }
            entries.append(try entry(path: path, type: rawType, size: size, header: header, linkTarget: target,
                                     modified: tarModified(header, fields: fields)))
            // Scanned/skipped payloads count towards the decoded budget too.
            _ = try cursor.read(size)
            try skipPadding(size, cursor: &cursor)
        }
        guard ended, longName == nil, localPAX.isEmpty else { throw PreviewFailure.malformedDocument }
        return try listingDocument(format: "TAR", entries: entries, context: context, assessRisks: true)
    }

    /// One listed member. The mode and a link's target are facts for the risk analyzer: the target comes
    /// from a PAX `linkpath`, a GNU long link record or the header's link name, in that order.
    private func entry(path: String, type: UInt8, size: Int, header: [UInt8], linkTarget: String?,
                       modified: Date?) throws -> ContainerEntry {
        let kind: ContainerEntryKind
        switch type {
        case 0, 48, 55: kind = .file
        case 53: kind = .directory
        case 49: kind = .hardlink
        case 50: kind = .symlink
        case 51, 52, 54: kind = .special
        default: throw PreviewFailure.unsupportedFormat
        }
        let isLink = kind == .hardlink || kind == .symlink
        // Neither field is validated by this listing, so a malformed value costs the fact, not the archive.
        let target = isLink ? linkTarget ?? (try? tarString(header[157..<257])) : nil
        let mode = (try? tarNumber(header[100..<108])).map { UInt32(truncatingIfNeeded: $0) }
        return ContainerEntry(path: try listableArchivePath(path), kind: kind, size: size, mode: mode, linkTarget: target,
                              modified: modified)
    }

    /// Modification time from a PAX `mtime` record (decimal seconds, possibly fractional) when present,
    /// otherwise the header field. A blank or unparsable field means the writer stored no time.
    private func tarModified(_ header: [UInt8], fields: [String: String]) -> Date? {
        if let value = fields["mtime"], let seconds = Double(value), seconds.isFinite {
            return ArchiveListing.date(unixSeconds: seconds)
        }
        let field = header[136..<148]
        guard !field.allSatisfy({ $0 == 0 || $0 == 32 }), let seconds = try? tarNumber(field) else { return nil }
        return ArchiveListing.date(unixSeconds: Double(seconds))
    }

    private func tarNumber(_ bytes: ArraySlice<UInt8>) throws -> Int {
        guard let first = bytes.first else { throw PreviewFailure.malformedDocument }
        if first & 0x80 != 0 {
            guard first == 0x80, bytes.count <= 12 else { throw PreviewFailure.unsupportedFormat }
            var value: UInt64 = 0
            for byte in bytes.dropFirst() {
                guard value <= UInt64(Int.max) >> 8 else { throw PreviewFailure.malformedDocument }
                value = value << 8 | UInt64(byte)
            }
            return try boundedInt(value)
        }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
        if value.isEmpty { return 0 }
        guard value.allSatisfy({ ("0"..."7").contains(String($0)) }), let number = Int(value, radix: 8) else { throw PreviewFailure.malformedDocument }
        return number
    }
    private func tarString(_ bytes: ArraySlice<UInt8>) throws -> String {
        let part = bytes.prefix(while: { $0 != 0 })
        guard let string = String(data: Data(part), encoding: .utf8) else { throw PreviewFailure.unsupportedEncoding }
        return string
    }
    private func skipPadding(_ size: Int, cursor: inout BinaryCursor) throws {
        _ = try cursor.read((512 - (size % 512)) % 512)
    }
    private func paxFields(_ bytes: ArraySlice<UInt8>, context: RequestContext) throws -> [String: String] {
        var cursor = BinaryCursor(Data(bytes))
        var fields: [String: String] = [:]
        while cursor.remaining > 0 {
            try context.checkpoint()
            let start = cursor.offset
            var digits = ""
            while cursor.remaining > 0 {
                let byte = try cursor.integer(1)
                if byte == 32 { break }
                guard (48...57).contains(byte), digits.count < 10 else { throw PreviewFailure.malformedDocument }
                digits.append(Character(UnicodeScalar(UInt8(byte))))
            }
            guard let length = Int(digits), length > cursor.offset - start,
                  length <= cursor.bytes.count - start else { throw PreviewFailure.malformedDocument }
            let record = try cursor.read(length - (cursor.offset - start))
            guard record.last == 10, let value = String(data: Data(record.dropLast()), encoding: .utf8),
                  let delimiter = value.firstIndex(of: "=") else { throw PreviewFailure.malformedDocument }
            let key = String(value[..<delimiter])
            guard !key.hasPrefix("GNU.sparse"), key != "SCHILY.realsize", key != "SCHILY.filetype" else { throw PreviewFailure.unsupportedFormat }
            guard fields.count < context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
            fields[key] = String(value[value.index(after: delimiter)...])
        }
        return fields
    }
}

public struct GZIPPreviewAdapter: BinaryFormatAdapter {
    public init() {}
    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        let limits = ContainerLimits(context: context)
        try limits.validateInput(input.data)
        let decoded = try BoundedDecompression.gzip(input.data, context: context, maximum: limits.maxDecodedBytes)
        return try CompressedStreamPayload.document(decoded, streamName: "GZIP", context: context)
    }
}

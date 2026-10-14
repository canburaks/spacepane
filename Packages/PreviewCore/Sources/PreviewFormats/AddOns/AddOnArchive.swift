import Foundation
import zlib
import PreviewContracts

/// Byte and member limits of the add-on readers. They bound the work a package can cause: the manifest
/// is one capped member, scripts are read as capped prefixes, and a content probe reads one header.
enum AddOnLimits {
    static let manifestBytes = 1_048_576
    /// Script members scanned for invisible characters, the bytes read from each, and the bytes in all.
    static let scriptMembers = 20
    static let scriptMemberBytes = 262_144
    static let scriptTotalBytes = 2_097_152
    /// Members whose leading bytes are checked for machine code, and the smallest one worth checking.
    static let contentProbes = 512
    static let smallestProbedMember = 16
    /// Items kept from a manifest list. A summary reserves 512 nodes for its descriptive fields, so the
    /// lists and settings together stay well inside that.
    static let listItems = 32
}

/// A package archive opened for an add-on summary: the central directory, and bounded access to a few
/// members. Nothing is extracted, nested archives are never opened and no member is ever run.
struct AddOnArchive {
    let source: any PreviewByteSource
    let archive: ZIPArchive
    let context: RequestContext

    init(source: any PreviewByteSource, context: RequestContext) throws {
        self.source = source
        self.context = context
        archive = try ZIPArchiveReader.read(source, context: context)
    }

    /// The manifest at `path` as a tolerant JSON tree (comments and trailing commas are accepted, as old
    /// Chrome manifests have them). A missing, oversized, unreadable or non-object manifest fails the
    /// preview; the size cap is checked before any payload byte is read.
    func manifest(at path: String) throws -> LensJSONNode {
        guard let entry = archive.entry(at: path), entry.kind == "file" else { throw PreviewFailure.malformedDocument }
        let data = try ZIPArchiveReader.readMember(entry, from: source, maximumBytes: AddOnLimits.manifestBytes, context: context)
        guard let text = String(data: data, encoding: .utf8),
              let root = try LensJSON.parse(text, context: context), root.members != nil else {
            throw PreviewFailure.malformedDocument
        }
        return root
    }

    /// Adds the standard archive listing, in the budget the summary's descriptive fields leave.
    func addListing(to fields: inout SummaryFields) {
        let capacity = PackageSummary.listingCapacity(context)
        let entries = archive.entries.prefix(capacity).map {
            ContainerEntry(path: $0.path, kind: $0.kind, size: $0.uncompressedSize, modified: $0.modified, isEncrypted: $0.isEncrypted)
        }
        fields.listing(format: archive.isZip64 ? "ZIP64" : "ZIP", entries: Array(entries), partial: archive.entries.count > capacity)
    }

    /// Runs an optional read: a bounded-reader refusal or a malformed member omits that part of the
    /// summary instead of failing it. Cancellation and an expired deadline still propagate.
    static func optional<T>(_ body: () throws -> T?) throws -> T? {
        do { return try body() }
        catch PreviewFailure.deadlineExceeded { throw PreviewFailure.deadlineExceeded }
        catch is PreviewFailure { return nil }
    }

    /// The first `limit` bytes of a member, reading no more of the archive than they need. Stored members
    /// are read directly; deflated ones are inflated in chunks that stop when enough has come out, so a
    /// multi-megabyte bundle costs a few hundred kilobytes at most. The member's checksum is not
    /// verified, because that needs every byte. Members that are encrypted, not regular files or
    /// compressed with another method read as empty.
    func prefix(of entry: ZIPEntry, limit: Int) throws -> Data {
        try context.checkpoint()
        guard entry.kind == "file", !entry.isEncrypted else { return Data() }
        let wanted = min(limit, entry.uncompressedSize)
        guard wanted > 0 else { return Data() }
        switch entry.method {
        case 0:
            guard entry.compressedSize == entry.uncompressedSize else { throw PreviewFailure.malformedDocument }
            return try source.read(offset: Int64(entry.payloadOffset), count: wanted, context: context)
        case 8: return try inflatedPrefix(of: entry, wanted: wanted)
        default: return Data()
        }
    }

    private func inflatedPrefix(of entry: ZIPEntry, wanted: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw PreviewFailure.unavailableContent
        }
        defer { inflateEnd(&stream) }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 32_768)
        var consumed = 0
        var finished = false
        while !finished, output.count < wanted, consumed < entry.compressedSize {
            try context.checkpoint()
            let take = min(65_536, entry.compressedSize - consumed)
            let chunk = try source.read(offset: Int64(entry.payloadOffset + consumed), count: take, context: context)
            consumed += take
            chunk.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { finished = true; return }
                stream.next_in = UnsafeMutablePointer(mutating: base)
                stream.avail_in = uInt(chunk.count)
                while stream.avail_in > 0, output.count < wanted {
                    let capacity = min(buffer.count, wanted - output.count)
                    var status: Int32 = Z_OK
                    buffer.withUnsafeMutableBufferPointer { target in
                        stream.next_out = target.baseAddress
                        stream.avail_out = uInt(capacity)
                        status = zlib.inflate(&stream, Z_NO_FLUSH)
                    }
                    output.append(contentsOf: buffer.prefix(capacity - Int(stream.avail_out)))
                    // The end of the stream, or a stream that stops making sense: keep what came out.
                    if status != Z_OK { finished = true; break }
                }
            }
        }
        return output
    }
}

import Foundation
import PreviewContracts

/// The wrapper in front of a Chrome extension's ZIP archive (`.crx`). CRX3 is `Cr24`, the version 3, the
/// length of a protobuf header and that header; CRX2 is `Cr24`, the version 2, the lengths of a public key
/// and a signature, and both. The archive follows. Only the lengths are read: the header and signature
/// are never parsed, and nothing is said about whether the package is signed or by whom.
enum CRXContainer {
    static let magic = Data("Cr24".utf8)
    /// The most a header may declare, as Chromium itself enforces for CRX3.
    static let maximumHeaderBytes: UInt64 = 262_144

    struct Layout {
        /// 2 or 3.
        let version: Int
        /// Where the ZIP archive starts.
        let archiveOffset: Int64
    }

    /// The archive's position in a CRX2 or CRX3 file, or `nil` when the source does not start with the
    /// magic, which is how a plain ZIP behaves. Other versions are a known format with no reader here;
    /// a header that overruns the file or exceeds its limit is malformed.
    static func layout(of source: any PreviewByteSource, context: RequestContext) throws -> Layout? {
        guard source.byteCount >= 4, try source.read(offset: 0, count: 4, context: context) == magic else { return nil }
        guard source.byteCount >= 12 else { throw PreviewFailure.malformedDocument }
        let fixed = BinaryCursor(try source.read(offset: 0, count: Int(min(source.byteCount, 16)), context: context))
        let version = try fixed.integer(at: 4, width: 4, littleEndian: true)
        let archiveOffset: UInt64
        switch version {
        case 3:
            let headerLength = try fixed.integer(at: 8, width: 4, littleEndian: true)
            guard headerLength <= maximumHeaderBytes else { throw PreviewFailure.malformedDocument }
            archiveOffset = 12 + headerLength
        case 2:
            let keyLength = try fixed.integer(at: 8, width: 4, littleEndian: true)
            let signatureLength = try fixed.integer(at: 12, width: 4, littleEndian: true)
            guard keyLength <= maximumHeaderBytes, signatureLength <= maximumHeaderBytes else { throw PreviewFailure.malformedDocument }
            archiveOffset = 16 + keyLength + signatureLength
        default:
            throw PreviewFailure.unsupportedVariant
        }
        // The smallest archive is an empty end-of-directory record of 22 bytes.
        guard archiveOffset + 22 <= UInt64(source.byteCount) else { throw PreviewFailure.malformedDocument }
        return Layout(version: Int(version), archiveOffset: Int64(archiveOffset))
    }
}

/// A byte source that starts `offset` bytes into another, so the ZIP reader sees the archive inside a CRX
/// as a file of its own. Reads are charged to the underlying source.
struct OffsetByteSource: PreviewByteSource {
    let base: any PreviewByteSource
    let offset: Int64

    var byteCount: Int64 { base.byteCount - offset }

    func read(offset position: Int64, count: Int, context: RequestContext) throws -> Data {
        guard position >= 0, count >= 0, position <= byteCount, Int64(count) <= byteCount - position else {
            throw PreviewFailure.malformedDocument
        }
        return try base.read(offset: offset + position, count: count, context: context)
    }
}

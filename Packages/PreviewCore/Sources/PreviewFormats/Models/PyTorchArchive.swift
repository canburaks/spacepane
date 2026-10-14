import Foundation
import zlib
import PreviewContracts

/// Scans a PyTorch checkpoint in the ZIP layout (PyTorch 1.6 and later): the pickles are the members whose
/// names end in `.pkl`, usually `archive/data.pkl`, and the tensors are the members under `data/`.
///
/// Only the pickle members are read. Tensor storages are counted and sized from the central directory and
/// are never read. A pickle member whose checksum does not match is still scanned and the mismatch is
/// counted, because PyTorch reads such a member too; stopping would let a damaged checksum hide the imports.
enum PyTorchArchiveScanner {
    static let maximumPickleMembers = 8
    static let maximumMemberBytes = 8_388_608

    static func scan(_ source: any PreviewByteSource, context: RequestContext, report: inout PickleScanReport) throws {
        let archive = try ZIPArchiveReader.read(source, context: context, encryptedEntries: .list, paths: .listing)
        var storages = 0
        var storageBytes = 0
        var members: [ZIPEntry] = []
        for entry in archive.entries where entry.kind == "file" {
            if isStorage(entry.path) {
                storages += 1
                storageBytes = storageBytes.addingReportingOverflow(entry.uncompressedSize).partialValue
            }
            if NativeCodeSignature.hasNativeSuffix(entry.path) { report.nativeMembers += 1 }
            if entry.path.lowercased().hasSuffix(".pkl") { members.append(entry) }
        }
        report.storages = storages
        report.storageBytes = storageBytes
        guard !members.isEmpty else { return }
        if members.count > maximumPickleMembers { report.isPartial = true }
        var budgetSpent = false
        for entry in members.prefix(maximumPickleMembers) {
            try context.checkpoint()
            guard !entry.isEncrypted, entry.method == 0 || entry.method == 8, entry.uncompressedSize <= maximumMemberBytes else {
                report.isPartial = true
                continue
            }
            let member: (data: Data, matches: Bool)
            do { member = try read(entry, from: source, context: context) }
            catch PreviewFailure.inputTooLarge {
                // The request's read budget is spent; whatever is scanned so far is all there will be.
                report.isPartial = true
                budgetSpent = true
                break
            } catch PreviewFailure.malformedDocument {
                report.isPartial = true
                continue
            } catch PreviewFailure.outputTooLarge {
                report.isPartial = true
                continue
            }
            if !member.matches { report.checksumErrors += 1 }
            do {
                if try PickleStreamScanner.scan(member.data, isWindow: false, single: true, report: &report, context: context) == .notAPickle {
                    report.isPartial = true
                }
            } catch PreviewFailure.malformedDocument {
                report.isPartial = true
            }
        }
        // A ZIP with pickle members of which none could be scanned has nothing to show but a failure.
        if report.pickles == 0 { throw budgetSpent ? PreviewFailure.inputTooLarge : PreviewFailure.malformedDocument }
    }

    /// A tensor storage: any file below a folder named `data` (`archive/data/0`).
    static func isStorage(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).dropLast().contains("data")
    }

    /// Reads one member, stored or deflated, without stopping at a checksum mismatch. The result says whether
    /// the checksum and the declared size matched. Encryption and other methods are the caller's to refuse.
    static func read(_ entry: ZIPEntry, from source: any PreviewByteSource, context: RequestContext) throws -> (data: Data, matches: Bool) {
        let payload = try source.read(offset: Int64(entry.payloadOffset), count: entry.compressedSize, context: context)
        let data: Data
        if entry.method == 0 {
            guard entry.compressedSize == entry.uncompressedSize else { throw PreviewFailure.malformedDocument }
            data = payload
        } else {
            data = try BoundedDecompression.rawDeflate(payload, context: context, maximum: entry.uncompressedSize)
        }
        try context.checkpoint()
        return (data, data.count == entry.uncompressedSize && checksum(data) == entry.crc32)
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.bindMemory(to: Bytef.self).baseAddress else { return UInt32(zlib.crc32(0, nil, 0)) }
            return UInt32(zlib.crc32(0, base, uInt(buffer.count)))
        }
    }
}

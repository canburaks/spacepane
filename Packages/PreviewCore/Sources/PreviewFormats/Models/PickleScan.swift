import Foundation
import PreviewContracts

/// What one scan of a file found, before it is written as a summary (decision 030). Nothing here holds a
/// value from the file other than import names, which the summary shows as the file's content.
struct PickleScanReport: Sendable {
    /// The container's name as the summary shows it: "PyTorch ZIP", "PyTorch legacy", "Pickle", "joblib (zlib)".
    var container: String
    var tally = PickleImportTally()
    /// The highest protocol over the pickles scanned.
    var protocolVersion: Int?
    var pickles = 0
    var persistentIDs = 0
    /// Tensor storages and their bytes, counted from a ZIP's central directory only. Nil outside ZIP files.
    var storages: Int?
    var storageBytes = 0
    /// Pickle members whose checksum or size did not match their header; the scan used them anyway.
    var checksumErrors = 0
    var nativeMembers = 0
    /// A pickle ended in the middle after naming at least one import: the shape of a stream built to slip past scanners.
    var isBroken = false
    /// Something was not scanned: a cap, a window, a member that could not be read, imports beyond the list's room.
    var isPartial = false
    /// Opcodes left in the scan's shared cap.
    var opcodeBudget = PickleWalker.maximumOpcodes

    init(container: String) { self.container = container }

    mutating func absorb(_ outcome: PickleWalkOutcome, tally walked: PickleImportTally) {
        tally = walked
        pickles += 1
        persistentIDs += outcome.persistentIDs
        protocolVersion = max(protocolVersion ?? 0, outcome.protocolVersion)
    }
}

/// Walks the pickles in a buffer. A file can hold several: legacy `torch.save` writes a magic number, a
/// protocol number, system information, the object and the storage keys as separate pickles, followed by
/// raw storage bytes, so the scan continues while the next bytes begin a protocol 2 or later pickle.
enum PickleStreamScanner {
    static let maximumPickles = 8

    enum Result: Equatable {
        case scanned
        /// The very first bytes are not a pickle.
        case notAPickle
    }

    /// Bytes that can open a pickle without a PROTO header (protocols 0 and 1).
    private static let headerlessOpeners: Set<UInt8> = Set("(c]})NILFSVXUTKMJG".utf8)

    /// The magic-number pickle that opens a legacy PyTorch file: PROTO 2, LONG1 of 0x1950a86a20f9469cfc6c, STOP.
    private static let legacyMagic: [UInt8] = [0x80, 0x02, 0x8A, 0x0A, 0x6C, 0xFC, 0x9C, 0x46, 0xF9, 0x20, 0x6A, 0xA8, 0x50, 0x19, 0x2E]

    static func isLegacyPyTorch(_ data: Data) -> Bool { data.starts(with: legacyMagic) }

    /// - Parameters:
    ///   - isWindow: `data` is only the start of a larger file, so running out is not a broken stream.
    ///   - single: scan one pickle only, as for a ZIP member; bytes after STOP are never read as a pickle.
    static func scan(_ data: Data, isWindow: Bool, single: Bool, report: inout PickleScanReport,
                     context: RequestContext) throws -> Result {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> Result in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard startsPickle(bytes, at: 0, requireHeader: false) else { return .notAPickle }
            var offset = 0
            var index = 0
            while offset < bytes.count {
                if index >= (single ? 1 : maximumPickles) {
                    if !single, startsPickle(bytes, at: offset, requireHeader: true) { report.isPartial = true }
                    break
                }
                if index > 0, !startsPickle(bytes, at: offset, requireHeader: true) { break }
                var walker = PickleWalker(bytes: bytes, start: offset, isWindow: isWindow, tally: report.tally)
                let outcome = try walker.run(opcodeBudget: &report.opcodeBudget, context: context)
                switch outcome.ending {
                case .complete:
                    report.absorb(outcome, tally: walker.tally)
                    offset = outcome.endOffset
                case .limited, .windowEnd:
                    report.absorb(outcome, tally: walker.tally)
                    report.isPartial = true
                    return .scanned
                case .broken:
                    if outcome.sawJoblibArray {
                        // joblib writes an array's raw bytes between opcodes; what follows is data, not a stream.
                        report.absorb(outcome, tally: walker.tally)
                        report.isPartial = true
                    } else if outcome.imports > 0, outcome.hasProtoHeader || outcome.plausibleImports == outcome.imports {
                        report.absorb(outcome, tally: walker.tally)
                        report.isBroken = true
                    } else if index == 0 {
                        // A header says it was a pickle; without imports there is nothing to report from it.
                        if outcome.hasProtoHeader { throw PreviewFailure.malformedDocument }
                        return .notAPickle
                    }
                    // After the first pickle, bytes that do not walk are the raw data that follows.
                    return .scanned
                }
                index += 1
            }
            return .scanned
        }
    }

    /// Whether a pickle can begin at `offset`: a PROTO opcode with a version from 2 to 5, or, unless the
    /// caller requires a header, one of the opcodes that open protocol 0 and 1 pickles.
    private static func startsPickle(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int, requireHeader: Bool) -> Bool {
        guard offset < bytes.count else { return false }
        if bytes[offset] == 0x80 { return offset + 1 < bytes.count && (2...5).contains(bytes[offset + 1]) }
        return !requireHeader && headerlessOpeners.contains(bytes[offset])
    }
}

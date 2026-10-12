import Foundation
import Synchronization
import PreviewContracts

/// Read-only synthetic bytes and the accepted ranges a parser read. Shared by adapter and pipeline tests;
/// cancellation, deadlines and physical bounds are checked before logging or converting an offset to Int.
/// Aggregate input accounting remains the responsibility of the parser or request's input ledger.
public final class RecordingByteSource: PreviewByteSource {
    public let data: Data
    private let log = Mutex<[Range<Int>]>([])

    public init(_ data: Data) { self.data = data }

    public var byteCount: Int64 { Int64(data.count) }
    public var reads: [Range<Int>] { log.withLock { $0 } }

    public func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        guard offset >= 0, count >= 0, offset <= byteCount,
              Int64(count) <= byteCount - offset else { throw PreviewFailure.malformedDocument }
        let range = Int(offset)..<(Int(offset) + count)
        log.withLock { $0.append(range) }
        return data.subdata(in: range)
    }

    /// Empty probes do not count as touching a source range.
    public func touches(_ range: Range<Int>) -> Bool {
        reads.contains { !$0.isEmpty && $0.overlaps(range) }
    }
}

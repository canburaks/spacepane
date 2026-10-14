import Foundation
import PreviewContracts

/// Sequential, buffered reader over a random-access source for GGUF headers.
///
/// Every byte it fetches goes through `PreviewByteSource.read`, so the request budget is charged for
/// all of it. Windows start small and grow to 1 MiB while the reader moves forward, and a jump over
/// bytes (an array of numbers, a string that is not kept) is a seek that fetches nothing. The reader
/// never looks for tensor data; a window can extend at most one window length past the last header
/// byte, and those bytes are discarded unparsed.
struct GGUFByteReader {
    /// Thrown when the request's read budget cannot cover the next bytes. The adapter turns it into a
    /// partial summary; every other problem is a `PreviewFailure`.
    struct BudgetExhausted: Error {}

    static let firstWindow = 65_536
    static let largestWindow = 1_048_576

    let fileSize: Int64
    private(set) var isBigEndian = false

    private let source: any PreviewByteSource
    private let context: RequestContext
    private var window: [UInt8] = []
    private var windowStart: Int64 = 0
    private var head = 0
    private var requestedBytes = 0
    private var nextWindow = GGUFByteReader.firstWindow

    init(source: any PreviewByteSource, context: RequestContext) {
        self.source = source
        self.context = context
        fileSize = source.byteCount
    }

    /// Offset of the next unread byte.
    var position: Int64 { windowStart + Int64(head) }
    var remaining: Int64 { fileSize - position }

    mutating func useBigEndian() { isBigEndian = true }

    // MARK: Scalars

    mutating func uint8() throws -> UInt8 { UInt8(truncatingIfNeeded: try integer(width: 1)) }
    mutating func uint32() throws -> UInt32 { UInt32(truncatingIfNeeded: try integer(width: 4)) }
    mutating func uint64() throws -> UInt64 { try integer(width: 8) }

    /// Reads a 1 to 8 byte integer in the file's byte order.
    mutating func integer(width: Int) throws -> UInt64 {
        try ensure(width)
        var value: UInt64 = 0
        for index in 0..<width {
            let byte = UInt64(window[head + (isBigEndian ? index : width - 1 - index)])
            value = (value << 8) | byte
        }
        head += width
        return value
    }

    // MARK: Byte runs

    /// The next `count` bytes. Callers bound `count` before asking.
    mutating func bytes(_ count: Int) throws -> [UInt8] {
        try ensure(count)
        defer { head += count }
        return Array(window[head..<(head + count)])
    }

    /// Moves forward without fetching. A distance beyond the end of the file is a truncated file.
    mutating func skip(_ count: UInt64) throws {
        guard count <= UInt64(max(0, remaining)) else { throw PreviewFailure.malformedDocument }
        let distance = Int(count)
        if distance <= window.count - head {
            head += distance
            return
        }
        windowStart = position + Int64(distance)
        window = []
        head = 0
        nextWindow = Self.firstWindow
    }

    // MARK: Buffering

    private mutating func ensure(_ count: Int) throws {
        let buffered = window.count - head
        if buffered >= count { return }
        guard Int64(count) <= remaining else { throw PreviewFailure.malformedDocument }
        try context.checkpoint()
        let needed = count - buffered
        let budgetLeft = context.budget.maxInputBytes - requestedBytes
        guard needed <= budgetLeft else { throw BudgetExhausted() }
        let readOffset = windowStart + Int64(window.count)
        let wanted = Int(min(Int64(max(nextWindow, needed)), fileSize - readOffset, Int64(budgetLeft)))
        let fetched: Data
        do { fetched = try source.read(offset: readOffset, count: wanted, context: context) }
        catch PreviewFailure.inputTooLarge { throw BudgetExhausted() }
        guard fetched.count == wanted else { throw PreviewFailure.unreadableFile }
        requestedBytes += wanted
        let carried = window[head...]
        let start = position
        var next = [UInt8]()
        next.reserveCapacity(carried.count + wanted)
        next.append(contentsOf: carried)
        next.append(contentsOf: fetched)
        window = next
        windowStart = start
        head = 0
        nextWindow = min(nextWindow * 4, Self.largestWindow)
    }
}

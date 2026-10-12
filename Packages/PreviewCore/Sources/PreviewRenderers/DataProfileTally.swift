import Foundation

/// Counts how often each exact spelling occurs in one column, remembering the row of its first
/// occurrence so equally common values keep a stable order.
///
/// Spellings are compared by UTF-8 code units. Swift's own `String` equality folds canonically
/// equivalent text, which would count two different cells as one value.
///
/// Open addressing over a power-of-two slot array keeps the hot path allocation-free for repeated
/// values. The hash is seeded randomly for each process, so a crafted file cannot arrange collisions to
/// stretch probe runs; the number of tracked spellings is also capped, which bounds memory and work.
struct DataProfileTally {
    struct Entry {
        let text: String
        let hash: UInt32
        var count: Int
        /// Row of the first occurrence.
        let first: Int
    }

    private(set) var entries: [Entry] = []
    /// Set once a new spelling arrived while `maximumDistinct` were already tracked. Tracked spellings
    /// keep counting exactly; later new ones are not tracked.
    private(set) var reachedLimit = false
    private var slots = [Int32](repeating: -1, count: 64)
    private let maximumDistinct: Int

    init(maximumDistinct: Int) {
        // Slot indexes are Int32, and the load factor needs room for twice the entries.
        self.maximumDistinct = max(0, min(maximumDistinct, Int(Int32.max) / 4))
    }

    var distinctCount: Int { entries.count }

    /// `bytes` must be the UTF-8 code units of `text`; they are passed separately so the caller reads them once.
    mutating func record(_ text: String, bytes: UnsafeBufferPointer<UInt8>, row: Int) {
        let hash = Self.hash(bytes)
        let mask = slots.count - 1
        var index = Int(hash) & mask
        while true {
            let slot = Int(slots[index])
            if slot < 0 { break }
            if entries[slot].hash == hash, Self.isEqual(entries[slot].text, bytes) {
                entries[slot].count += 1
                return
            }
            index = (index + 1) & mask
        }
        guard entries.count < maximumDistinct else {
            reachedLimit = true
            return
        }
        entries.append(Entry(text: text, hash: hash, count: 1, first: row))
        slots[index] = Int32(entries.count - 1)
        if entries.count * 2 > slots.count { grow() }
    }

    /// The `limit` most frequent spellings, most frequent first. Equal counts keep the spelling that
    /// appeared first, so the result never depends on storage order.
    func mostFrequent(_ limit: Int) -> [Entry] {
        func ranks(_ lhs: Entry, above rhs: Entry) -> Bool {
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs.first < rhs.first
        }
        var top: [Entry] = []
        guard limit > 0 else { return top }
        for entry in entries {
            guard top.count < limit || ranks(entry, above: top[top.count - 1]) else { continue }
            top.insert(entry, at: top.firstIndex { ranks(entry, above: $0) } ?? top.count)
            if top.count > limit { top.removeLast() }
        }
        return top
    }

    private mutating func grow() {
        var larger = [Int32](repeating: -1, count: slots.count * 2)
        let mask = larger.count - 1
        for (position, entry) in entries.enumerated() {
            var index = Int(entry.hash) & mask
            while larger[index] >= 0 { index = (index + 1) & mask }
            larger[index] = Int32(position)
        }
        slots = larger
    }

    private static let seed = UInt64.random(in: .min ... .max)

    /// Eight bytes per step with a multiply-and-fold mix, finished with an avalanche so the low bits that
    /// choose a slot depend on every input byte.
    private static func hash(_ bytes: UnsafeBufferPointer<UInt8>) -> UInt32 {
        let raw = UnsafeRawBufferPointer(bytes)
        var state = seed ^ UInt64(truncatingIfNeeded: raw.count) &* 0x9E37_79B9_7F4A_7C15
        var offset = 0
        while offset + 8 <= raw.count {
            state = (state ^ raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) &* 0xFF51_AFD7_ED55_8CCD
            state ^= state >> 32
            offset += 8
        }
        var tail: UInt64 = 0
        var shift: UInt64 = 0
        while offset < raw.count {
            tail |= UInt64(raw[offset]) << shift
            shift += 8
            offset += 1
        }
        state = (state ^ tail) &* 0xC4CE_B9FE_1A85_EC53
        state ^= state >> 33
        state = state &* 0xFF51_AFD7_ED55_8CCD
        state ^= state >> 33
        return UInt32(truncatingIfNeeded: state)
    }

    private static func isEqual(_ stored: String, _ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        withUTF8Bytes(of: stored) { other in
            other.count == bytes.count && (bytes.count == 0 || memcmp(other.baseAddress!, bytes.baseAddress!, bytes.count) == 0)
        }
    }
}

/// Text compared and hashed by UTF-8 code units, for the few table-level checks that need a key.
struct ExactText: Hashable, Sendable {
    let text: String

    init(_ text: String) { self.text = text }

    static func == (lhs: Self, rhs: Self) -> Bool {
        withUTF8Bytes(of: lhs.text) { left in
            withUTF8Bytes(of: rhs.text) { right in
                left.count == right.count && (left.count == 0 || memcmp(left.baseAddress!, right.baseAddress!, left.count) == 0)
            }
        }
    }

    func hash(into hasher: inout Hasher) {
        withUTF8Bytes(of: text) { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
    }
}

/// Runs `body` over the UTF-8 code units of `text`. Native strings expose them in place; a bridged
/// string is copied once.
@inline(__always)
func withUTF8Bytes<Result>(of text: String, _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
    if let result = text.utf8.withContiguousStorageIfAvailable(body) { return result }
    return Array(text.utf8).withUnsafeBufferPointer(body)
}

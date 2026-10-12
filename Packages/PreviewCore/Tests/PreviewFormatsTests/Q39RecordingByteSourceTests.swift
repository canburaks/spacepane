import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport

@Suite("Shared recording byte source")
struct Q39RecordingByteSourceTests {
    private var context: RequestContext { RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)) }

    @Test func acceptedReadsRetainExactBytesAndOrder() throws {
        let original = Data([0x00, 0x7F, 0x80, 0xFF])
        let source = RecordingByteSource(original)
        #expect(source.byteCount == 4 && source.reads.isEmpty)
        #expect(try source.read(offset: 1, count: 2, context: context) == Data([0x7F, 0x80]))
        #expect(try source.read(offset: 0, count: 4, context: context) == original)
        #expect(try source.read(offset: 4, count: 0, context: context).isEmpty)
        #expect(source.reads == [1..<3, 0..<4, 4..<4])
        #expect(source.data == original)
        #expect(source.touches(2..<3) && !source.touches(4..<5) && !source.touches(1..<1))
    }

    @Test func emptyProbesDoNotCountAsTouchingBytes() throws {
        let source = RecordingByteSource(Data([1, 2, 3]))
        #expect(try source.read(offset: 1, count: 0, context: context).isEmpty)
        #expect(source.reads == [1..<1] && !source.touches(0..<3))
        let empty = RecordingByteSource(Data())
        #expect(try empty.read(offset: 0, count: 0, context: context).isEmpty)
        #expect(empty.byteCount == 0 && empty.reads == [0..<0] && !empty.touches(0..<1))
    }

    @Test func invalidAndOverflowingReadsFailWithoutBeingRecorded() {
        let source = RecordingByteSource(Data([1, 2, 3]))
        let invalid: [(offset: Int64, count: Int)] = [
            (-1, 1), (0, -1), (3, 1), (4, 0), (1, Int.max), (Int64.max, 1), (Int64.max, Int.max),
        ]
        for read in invalid {
            #expect(throws: PreviewFailure.malformedDocument) {
                try source.read(offset: read.offset, count: read.count, context: context)
            }
        }
        #expect(source.reads.isEmpty && source.data == Data([1, 2, 3]))
    }

    @Test func anExpiredBudgetStopsBeforeReadingOrRecording() {
        let source = RecordingByteSource(Data([1, 2, 3]))
        let expired = RequestContext(budget: PreviewBudget(maxMilliseconds: 0))
        #expect(throws: PreviewFailure.deadlineExceeded) { try source.read(offset: 0, count: 1, context: expired) }
        #expect(source.reads.isEmpty)
    }

    @Test func cancellationStopsBeforeReadingOrRecording() async {
        let source = RecordingByteSource(Data([1, 2, 3]))
        let cancelled = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try source.read(offset: 0, count: 1,
                                    context: RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000)))
                return false
            } catch is CancellationError { return true }
            catch { Issue.record("Expected CancellationError, received \(error)"); return false }
        }
        #expect(await cancelled.value)
        #expect(source.reads.isEmpty)
    }

    @Test func concurrentReadsAreEachRecordedOnce() async throws {
        let original = Data((0..<64).map(UInt8.init))
        let source = RecordingByteSource(original)
        let results = try await withThrowingTaskGroup(of: (Int, Data).self, returning: [(Int, Data)].self) { group in
            for index in 0..<64 {
                group.addTask {
                    let context = RequestContext(budget: PreviewBudget(maxMilliseconds: 30_000))
                    return (index, try source.read(offset: Int64(index), count: 1, context: context))
                }
            }
            var answers: [(Int, Data)] = []
            for try await answer in group { answers.append(answer) }
            return answers
        }
        #expect(results.count == 64)
        for (index, bytes) in results { #expect(bytes == Data([UInt8(index)])) }
        let reads = source.reads
        #expect(reads.count == 64 && reads.map(\.lowerBound).sorted() == Array(0..<64))
        #expect(reads.allSatisfy { $0.count == 1 } && source.data == original)
    }
}

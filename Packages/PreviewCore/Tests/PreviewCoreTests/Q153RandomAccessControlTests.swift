import Foundation
import Darwin
import Testing
import PreviewContracts
@testable import PreviewCore

@Suite("Q153 random source cancellation and mutation controls")
struct Q153RandomAccessControlTests {
    @Test func cancellationPrecedesConstructionAndRangeAdmission() async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), construction = Q153ReadProbe(), range = Q153ReadProbe(), url = fixture.url
        let initial = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) {
                try BoundedFileReader(policy: construction, probe: construction)
                    .openRandomAccess(url: url, context: q153Context())
            }
        }
        await initial.value
        #expect(construction.snapshot.entries == 0 && construction.snapshot.operations.isEmpty)
        let later = Task.detached {
            var source: (any PreviewByteSource)? = try BoundedFileReader(policy: range, probe: range)
                .openRandomAccess(url: url, context: q153Context(limit: 4))
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try source?.read(offset: 0, count: 4, context: q153Context(limit: 4)) }
            source = nil // Release inside the task before completion, avoiding scheduler cleanup races.
        }
        try await later.value
        #expect(range.snapshot.entries == 1 && range.attempts(.metadata(.beforeRangeRead)) == 0 && range.attempts(.pread) == 0)
        construction.expectNoLeaks(); range.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func cancellationAfterPreadNeverPublishesBytesAndRestoresScope() async throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let before = try fixture.snapshot(), probe = Q153ReadProbe(), url = fixture.url
        let task = Task.detached {
            var context = q153Context(limit: 4)
            context.checkpointObserver = {
                if probe.attempts(.pread) > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
                .openRandomAccess(url: url, context: context)
            #expect(throws: CancellationError.self) { try source?.read(offset: 0, count: 4, context: context) }
            source = nil
        }
        try await task.value
        #expect(probe.snapshot.entries == 2 && probe.snapshot.restores == 2)
        #expect(probe.attempts(.pread) == 1 && probe.attempts(.metadata(.finalRead)) == 0)
        probe.expectNoLeaks(); try fixture.expectUnchanged(before)
    }

    @Test func sameSizeMutationRejectsBeforePreadAndReaderDoesNotChangeTheReplacement() throws {
        let fixture = try Q153ReadFixture(); defer { fixture.remove() }
        let probe = Q153ReadProbe(), context = q153Context(limit: 4)
        var source: (any PreviewByteSource)? = try BoundedFileReader(policy: probe, probe: probe)
            .openRandomAccess(url: fixture.url, context: context)
        // Only the test writer mutates synthetic input; force a distinct timestamp without waiting.
        let writer = try FileHandle(forWritingTo: fixture.url)
        try writer.write(contentsOf: Data([8, 7, 6, 5, 4, 3, 2, 1])); try writer.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: fixture.url.path)
        let afterWriter = try fixture.snapshot()
        #expect(throws: PreviewFailure.unavailableContent) { try source?.read(offset: 0, count: 1, context: context) }
        #expect(probe.snapshot.entries == 2 && probe.attempts(.metadata(.beforeRangeRead)) == 1 && probe.attempts(.pread) == 0)
        source = nil
        probe.expectNoLeaks(); try fixture.expectUnchanged(afterWriter)
    }
}

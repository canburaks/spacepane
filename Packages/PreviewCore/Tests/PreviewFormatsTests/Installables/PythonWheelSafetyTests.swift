import Foundation
import Testing
import PreviewContracts
import PreviewTestSupport
@testable import PreviewFormats

@Suite("Python wheel native code, bounds and failures")
struct PythonWheelSafetyTests {
    private typealias Fixtures = InstallFixtures

    private func summary(_ members: [(path: String, data: Data)], deflate: Bool = true,
                         context: RequestContext = Fixtures.context) throws -> ([String: Any], ParsedTextDocument) {
        let document = try PythonWheelAdapter().parse(FileBytes(data: Fixtures.zip(members, deflate: deflate)), context: context)
        return (PackageTestSupport.object(document), document)
    }

    // MARK: Native code

    @Test func nativeModulesAreCountedByNameAndByLeadingBytesAtInfoLevel() throws {
        let elf = Data([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0] + [UInt8](repeating: 0, count: 64))
        let members = Fixtures.wheelMembers(extra: [
            ("example/_speed.cpython-312-darwin.so", Data("x".utf8)), ("example/lib.dylib", Data("x".utf8)),
            ("example/mod.pyd", Data("x".utf8)), ("example/helper.dll", Data("x".utf8)),
            ("example/disguised.txt", elf), ("example/plain.py", Data("VALUE = 2\n".utf8))
        ])
        for deflate in [false, true] {
            let (summary, document) = try summary(members, deflate: deflate)
            #expect(summary["nativeModules"] as? Int == 5)
            #expect(document.findings == [PreviewFinding(kind: .artifactNativeCode, severity: .info, count: 5)])
        }
    }

    @Test func aBudgetThatRunsOutDuringTheNativeCheckStillGivesTheSummary() throws {
        let elf = Data([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0] + [UInt8](repeating: 0, count: 2_000))
        let members = Fixtures.wheelMembers(extra: [("example/a.so", Data("x".utf8)), ("example/b.bin", elf), ("example/c.bin", elf)])
        let data = Fixtures.zip(members, deflate: false)
        final class Limited: PreviewByteSource {
            let inner: RecordingByteSource
            init(_ data: Data) { inner = RecordingByteSource(data) }
            var byteCount: Int64 { inner.byteCount }
            func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
                // The leading-bytes check asks for exactly this many bytes of a stored member.
                if count == NativeCodeSignature.prefixLength { throw PreviewFailure.inputTooLarge }
                return try inner.read(offset: offset, count: count, context: context)
            }
        }
        let document = try PythonWheelAdapter().parse(Limited(data), context: Fixtures.context)
        #expect(PackageTestSupport.object(document)["name"] as? String == "example")
        #expect(document.findings == [PreviewFinding(kind: .artifactNativeCode, severity: .info, count: 1)])
    }

    @Test func largeMembersAreNeverReadBeyondTheirLeadingBytes() throws {
        var state: UInt64 = 7
        var noise = Data()
        for _ in 0..<400_000 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            noise.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        let source = RecordingByteSource(Fixtures.zip(Fixtures.wheelMembers(extra: [("example/blob.bin", noise)]), deflate: true))
        _ = try PythonWheelAdapter().parse(source, context: Fixtures.context)
        let archive = try ZIPArchiveReader.read(source, context: Fixtures.context)
        let entry = try #require(archive.entry(at: "example/blob.bin"))
        #expect(entry.compressedSize > 300_000)
        // Leave out the last 64 KiB of the file, which the ZIP reader reads to find the end record.
        let interior = (entry.payloadOffset + 6_000)..<(entry.payloadOffset + entry.compressedSize - 70_000)
        #expect(!source.touches(interior))
    }

    // MARK: Malformed input

    @Test func inputThatIsNotAValidWheelFailsWithAPreviewFailure() throws {
        let good = Fixtures.zip(Fixtures.wheelMembers())
        let noInfo = Fixtures.zip([("example/__init__.py", Data("x".utf8))])
        let twoInfos = Fixtures.zip(Fixtures.wheelMembers(extra: [("other-1.0.dist-info/METADATA", Data("Name: other\n".utf8))]))
        let noMetadata = Fixtures.zip(Fixtures.wheelMembers(metadata: nil))
        let inputs: [(String, Data)] = [
            ("empty", Data()), ("text", Data("not a zip".utf8)), ("truncated", good.prefix(good.count / 2)),
            ("no tail", good.dropLast(10)), ("no dist-info", noInfo), ("two dist-info", twoInfos), ("no METADATA", noMetadata)
        ]
        for (label, data) in inputs {
            do {
                _ = try PythonWheelAdapter().parse(FileBytes(data: data), context: Fixtures.context)
                Issue.record("\(label): expected a failure")
            } catch is PreviewFailure {
            } catch { Issue.record("\(label): unexpected error \(error)") }
        }
    }

    @Test func unsafeMemberNamesAreRefusedAsMalformed() throws {
        let data = Fixtures.zip(Fixtures.wheelMembers(extra: [("../escape.txt", Data("x".utf8))]))
        #expect(throws: PreviewFailure.malformedDocument) {
            try PythonWheelAdapter().parse(FileBytes(data: data), context: Fixtures.context)
        }
    }

    @Test func corruptMemberStreamsDoNotFailTheSummary() throws {
        var data = Fixtures.zip(Fixtures.wheelMembers(), deflate: true)
        let archive = try ZIPArchiveReader.read(DataByteSource(data), context: Fixtures.context)
        let entry = try #require(archive.entry(at: "example-1.0.dist-info/WHEEL"))
        for offset in entry.payloadOffset..<(entry.payloadOffset + entry.compressedSize) { data[offset] = 0xFF }
        let document = try PythonWheelAdapter().parse(FileBytes(data: data), context: Fixtures.context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["name"] as? String == "example")
        #expect(summary["wheelVersion"] == nil)
    }

    // MARK: Privacy

    @Test func aTokenLikeValueInMetadataIsConcealedAndAnUnshownHeaderIsNotRead() throws {
        let secret = PackageFixtures.secret
        let metadata = Fixtures.defaultMetadata
            .replacingOccurrences(of: "Summary: A tiny example", with: "Summary: api_key=\(secret)")
            .replacingOccurrences(of: "License-Expression: MIT", with: "License-Expression: MIT\nHome-page: https://example.invalid/?token=\(secret)")
        let (_, document) = try summary(Fixtures.wheelMembers(metadata: metadata))
        // Only the Summary value is shown, and the writer marks it sensitive; the Home-page header never is.
        #expect(document.text.components(separatedBy: secret).count == 2)
        #expect(!PackageTestSupport.concealedText(document).contains(secret))
        #expect(!document.sensitiveRanges.isEmpty)
    }

    // MARK: Registration and cancellation

    @Test func theRegistrationIsARandomAccessContainerScan() throws {
        let registration = try #require(InstallableFormatAdapters.registrations.first)
        #expect(InstallableFormatAdapters.registrations.count == 1)
        #expect(registration.formatID == .pythonWheel)
        #expect(registration.defaultBudget == .containerScan)
        guard case .randomAccess(let make) = registration.inputPath else { Issue.record("expected a random-access adapter"); return }
        #expect(make() is PythonWheelAdapter)
    }

    @Test func cancellationStopsAnActiveWheelParse() async throws {
        let files = (0..<1_500).map { ("example/module\($0).py", Data("VALUE = \($0)\n".utf8)) }
        let data = Fixtures.zip(Fixtures.wheelMembers(extra: files + [Fixtures.wheelFile("import os\n", at: "boot.pth")]))
        let budget = PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)
        try await CancellationTest.expectStopsActiveParse(budget: budget) { context in
            try PythonWheelAdapter().parse(FileBytes(data: data), context: context)
        }
    }
}

import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("PyTorch ZIP checkpoints")
struct PyTorchArchiveTests {
    private typealias S = PickleStream
    private let secret = "synthetic-secret-value"

    private func scan(_ archive: Data, context: RequestContext = PackageTestSupport.context) throws -> PickleResult {
        PickleResult(try PickleAdapter().parse(DataByteSource(archive), context: context))
    }

    @Test func anOrdinaryCheckpointListsExpectedImportsAndNoFindings() throws {
        let result = try scan(PyTorchZip.checkpoint(pickle: S.torchCheckpoint()))
        #expect(result.container == "PyTorch ZIP")
        #expect(result.protocolVersion == 2)
        #expect(result.json["pickles"] as? Int == 1 && result.json["persistentIDs"] as? Int == 1)
        #expect(result.json["storages"] as? Int == 1 && result.json["storageBytes"] as? Int == 16)
        #expect(result.json["checksumErrors"] == nil)
        #expect(result.json["checked"] as? String == "importsOnly" && result.json["partial"] as? Bool == false)
        #expect(result.importNames == ["collections.OrderedDict", "torch.FloatStorage", "torch._utils._rebuild_tensor_v2"])
        #expect(result.imports.compactMap { $0["kind"] as? String } == ["expected", "expected", "expected"])
        #expect(result.imports.first?["count"] as? Int == 2)
        #expect(result.document.findings.isEmpty)
        #expect(result.document.origin == .summary)
    }

    @Test func aSecretInsideTheCheckpointNeverReachesTheSummary() throws {
        let result = try scan(PyTorchZip.checkpoint(pickle: S.torchCheckpoint(extraEntry: ("api_key", secret))))
        #expect(!result.document.text.contains(secret) && !result.document.text.contains("api_key"))
        #expect(result.importNames.count == 3)
    }

    @Test func importsThatRunCodeReachTheNetworkOrAreUncommonEachGetAFinding() throws {
        let pairs = [("os", "system"), ("posix", "system"), ("socket", "socket"), ("sklearn.tree", "DecisionTreeClassifier"),
                     ("torch.nn.modules.linear", "Linear"), ("collections", "OrderedDict")]
        let result = try scan(PyTorchZip.checkpoint(pickle: S.imports(pairs)))
        #expect(result.findings == [.pickleRunsCode, .pickleNetworkOrFiles, .pickleUncommonImports])
        #expect(result.count(of: .pickleRunsCode) == 2)
        #expect(result.count(of: .pickleNetworkOrFiles) == 1)
        #expect(result.count(of: .pickleUncommonImports) == 2)
        #expect(result.kind(of: "os.system") == "code" && result.kind(of: "socket.socket") == "networkOrFiles")
        // Most serious first, expected last.
        #expect(result.importNames == ["os.system", "posix.system", "socket.socket", "sklearn.tree.DecisionTreeClassifier",
                                       "torch.nn.modules.linear.Linear", "collections.OrderedDict"])
        #expect(result.document.findings.allSatisfy { $0.lines.isEmpty && $0.detail == .none })
    }

    @Test func aChecksumMismatchDoesNotStopTheScan() throws {
        let pickle = S.call("os", "system")
        let archive = PyTorchZip.build([.init("archive/data.pkl", pickle, crc: 0xDEAD_BEEF)])
        let result = try scan(archive)
        #expect(result.json["checksumErrors"] as? Int == 1)
        #expect(result.kind(of: "os.system") == "code")
        #expect(result.count(of: .pickleRunsCode) == 1)
    }

    @Test func deflatedMembersAreScannedToo() throws {
        let archive = PyTorchZip.build([.init("archive/data.pkl", S.torchCheckpoint(), deflated: true)])
        let result = try scan(archive)
        #expect(result.importNames.count == 3 && result.json["checksumErrors"] == nil)
    }

    @Test func everyPickleMemberIsScannedUpToEight() throws {
        let members = (0..<10).map { PyTorchZip.Member("archive/part\($0).pkl", S.call("os", "system\($0)")) }
        let result = try scan(PyTorchZip.build(members))
        #expect(result.json["pickles"] as? Int == 8)
        #expect(result.json["partial"] as? Bool == true)
        #expect(result.count(of: .pickleRunsCode) == 8)
        let fewer = try scan(PyTorchZip.build(Array(members.prefix(2))))
        #expect(fewer.json["pickles"] as? Int == 2 && fewer.json["partial"] as? Bool == false)
    }

    @Test func aMemberAboveTheSizeCapIsSkippedAndTheScanIsPartial() throws {
        let big = Data(count: PyTorchArchiveScanner.maximumMemberBytes + 1)
        let archive = PyTorchZip.build([.init("archive/data.pkl", S.call("os", "system")), .init("archive/big.pkl", big, deflated: true)])
        let result = try scan(archive)
        #expect(result.json["pickles"] as? Int == 1 && result.json["partial"] as? Bool == true)
        #expect(result.count(of: .pickleRunsCode) == 1)
    }

    @Test func encryptedMembersAreSkippedNotDecrypted() throws {
        let archive = PyTorchZip.build([.init("archive/data.pkl", S.call("os", "system")),
                                        .init("archive/secret.pkl", S.call("socket", "socket"), flags: 1)])
        let result = try scan(archive)
        #expect(result.json["partial"] as? Bool == true)
        #expect(result.importNames == ["os.system"])
    }

    @Test func aBrokenStreamAfterImportsIsReportedAsTheEvasionShape() throws {
        let nullifAI = Array(S.call("os", "system").dropLast()) + [0x7F]
        let result = try scan(PyTorchZip.checkpoint(pickle: nullifAI))
        #expect(result.findings == [.pickleRunsCode, .pickleBrokenStream])
        #expect(result.kind(of: "os.system") == "code")
    }

    @Test func storagesAreCountedFromTheDirectoryAndNeverRead() throws {
        // Stored storages come first and are larger than the 64 KiB tail the directory search reads.
        let storage = Data(repeating: 7, count: 100_000)
        let archive = PyTorchZip.build([.init("archive/data/0", storage), .init("archive/data/1", storage),
                                        .init("archive/data.pkl", S.torchCheckpoint()), .init("archive/notes.txt", Array("x".utf8))])
        let source = PickleRecordingSource(archive)
        let result = PickleResult(try PickleAdapter().parse(source, context: PackageTestSupport.context))
        #expect(result.json["storages"] as? Int == 2 && result.json["storageBytes"] as? Int == 200_000)
        #expect(result.importNames.count == 3)
        let first = try #require(archive.range(of: Data("archive/data/0".utf8))).upperBound
        // Only the 64 bytes of the sniffed head fall inside the first storage; the rest is never read.
        #expect(!source.touches((first + 64)..<(first + 100_000)))
    }

    @Test func nativeLibrariesInsideTheArchiveAreCounted() throws {
        let archive = PyTorchZip.checkpoint(pickle: S.torchCheckpoint(), extra: [.init("archive/lib/ops.so", [1, 2, 3]), .init("archive/ext.dylib", [1])])
        let result = try scan(archive)
        #expect(result.count(of: .artifactNativeCode) == 2)
        #expect(result.document.findings.count == 1)
    }

    @Test func aZipWithoutPickleMembersIsNotACheckpoint() throws {
        let result = try scan(PyTorchZip.build([.init("notes.txt", Array("hello".utf8)), .init("lib/native.so", [1])]))
        #expect(result.container == "ZIP")
        #expect(result.json["pickles"] == nil && result.json["imports"] == nil && result.json["checked"] == nil)
        #expect(result.findings == [.artifactMismatchedContent])
    }

    @Test func aPickleMemberThatIsNotAPickleLeavesNothingToShow() throws {
        let archive = PyTorchZip.build([.init("archive/data.pkl", Array("not a pickle".utf8))])
        #expect(throws: PreviewFailure.malformedDocument) { try scan(archive) }
        let header = PyTorchZip.build([.init("archive/data.pkl", [0x80, 0x02, 0x7F])])
        #expect(throws: PreviewFailure.malformedDocument) { try scan(header) }
        let mixed = PyTorchZip.build([.init("archive/data.pkl", Array("not a pickle".utf8)), .init("archive/b.pkl", S.call("os", "system"))])
        let result = try scan(mixed)
        #expect(result.json["partial"] as? Bool == true && result.json["pickles"] as? Int == 1)
    }

    @Test func truncatedOrCorruptArchivesFailWithoutCrashing() throws {
        let archive = PyTorchZip.checkpoint(pickle: S.torchCheckpoint())
        for cut in [1, 10, 22, archive.count / 2, archive.count - 1] {
            #expect(throws: PreviewFailure.self) { try scan(archive.prefix(archive.count - cut)) }
        }
        var damaged = archive
        damaged[damaged.count - 10] ^= 0xFF
        #expect(throws: PreviewFailure.self) { try scan(damaged) }
    }

    @Test func aSpentReadBudgetEndsTheScanAsPartial() throws {
        let pad = S.binUnicode(String(repeating: "a", count: 10_000))
        let members = (0..<8).map { PyTorchZip.Member("archive/part\($0).pkl", S.join(S.proto2, pad, S.pop, S.global("os", "system\($0)"), S.pop, S.none, S.stop)) }
        let archive = PyTorchZip.build(members)
        // The directory and headers cost about 66 KB of reads; the rest of the budget fits two members.
        let tight = RequestContext(budget: PreviewBudget(maxInputBytes: 90_000, maxMilliseconds: 30_000))
        let result = try scan(archive, context: tight)
        let scanned = try #require(result.json["pickles"] as? Int)
        #expect((1..<8).contains(scanned) && result.json["partial"] as? Bool == true)
        let none = RequestContext(budget: PreviewBudget(maxInputBytes: 60_000, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.inputTooLarge) { try scan(archive, context: none) }
    }

    @Test func scanningStopsWhenCancelled() async throws {
        let archive = PyTorchZip.checkpoint(pickle: S.torchCheckpoint())
        let document = try await CancellationTest.expectStopsActiveParse(budget: .containerScan) { context in
            try PickleAdapter().parse(DataByteSource(archive), context: context)
        }
        #expect(document.origin == .summary)
    }
}

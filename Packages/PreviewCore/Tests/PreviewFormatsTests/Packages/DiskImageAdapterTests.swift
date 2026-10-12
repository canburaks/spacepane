import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Disk image summaries")
struct DiskImageAdapterTests {
    private let context = PackageTestSupport.context
    private let zlibRun: UInt32 = 0x8000_0005
    private let lzfseRun: UInt32 = 0x8000_0007
    private let terminator: UInt32 = 0xFFFF_FFFF

    private func summary(_ data: Data, context: RequestContext = PackageTestSupport.context) throws -> [String: Any] {
        PackageTestSupport.object(try DiskImageAdapter().parse(FileBytes(data: data), context: context))
    }

    @Test func trailerAndPartitionTableAreSummarized() throws {
        let image = PackageFixtures.udif(partitions: [("Apple_partition_map : 0", 63, [1, terminator]),
                                                      ("disk image (Apple_HFS : 1)", 2_000, [zlibRun, lzfseRun, 2, terminator])], flags: 5)
        let summary = try summary(image)
        #expect(summary["udifVersion"] as? Int == 4)
        #expect(summary["sectorCount"] as? Int == 2_063)
        #expect(summary["imageBytes"] as? Int == 2_063 * 512)
        #expect(summary["dataForkBytes"] as? Int == 2_048)
        #expect(summary["segmentCount"] as? Int == 1)
        #expect(summary["internetEnabled"] as? Bool == true)
        let partitions = try #require(summary["partitions"] as? [[String: Any]])
        #expect(partitions.map { $0["name"] as? String } == ["Apple_partition_map : 0", "disk image (Apple_HFS : 1)"])
        #expect(partitions.map { $0["bytes"] as? Int } == [63 * 512, 2_000 * 512])
        #expect(summary["compressions"] as? [String] == ["raw", "zlib", "LZFSE"])
        #expect(summary["partial"] as? Bool == false)
    }

    @Test func internetEnabledFlagFollowsTheTrailer() throws {
        let summary = try summary(PackageFixtures.udif(partitions: [("disk", 8, [1])], flags: 1))
        #expect(summary["internetEnabled"] as? Bool == false)
    }

    @Test func partitionDataIsNeverReadOrDecompressed() throws {
        final class RecordingSource: PreviewByteSource {
            let inner: DataByteSource
            let ranges = Mutex<[Range<Int64>]>([])
            init(_ data: Data) { inner = DataByteSource(data) }
            var byteCount: Int64 { inner.byteCount }
            func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
                ranges.withLock { $0.append(offset..<(offset + Int64(count))) }
                return try inner.read(offset: offset, count: count, context: context)
            }
        }
        let image = PackageFixtures.udif(partitions: [("disk", 8, [zlibRun])])
        let source = RecordingSource(image)
        _ = try DiskImageAdapter().parse(source, context: context)
        let forkEnd = Int64(2_048)
        // Only the head probe may touch the data fork, and only its first eight bytes.
        #expect(source.ranges.withLock { $0.allSatisfy { $0.lowerBound >= forkEnd || $0 == 0..<8 } })
    }

    @Test(arguments: ["encrcdsa", "cdsaencr"])
    func encryptedImagesAreReportedWithoutBeingOpened(signature: String) {
        let image = Data(signature.utf8) + Data(repeating: 0x11, count: 4_096)
        #expect(throws: PreviewFailure.encryptedContent) { try DiskImageAdapter().parse(FileBytes(data: image), context: context) }
    }

    @Test func nonUDIFImagesAreUnsupported() {
        for data in [Data(), Data(repeating: 0, count: 4), Data(repeating: 0x20, count: 1_000_000), Data("hello".utf8)] {
            #expect(throws: PreviewFailure.unsupportedFormat) { try DiskImageAdapter().parse(FileBytes(data: data), context: context) }
        }
    }

    @Test func inconsistentTrailersAreMalformed() throws {
        var image = PackageFixtures.udif(partitions: [("disk", 8, [1])])
        // Point the property list past the trailer.
        let trailerStart = image.count - 512
        image.replaceSubrange((trailerStart + 216)..<(trailerStart + 224), with: PackageFixtures.big(UInt64(image.count + 1_000), 8))
        #expect(throws: PreviewFailure.malformedDocument) { try DiskImageAdapter().parse(FileBytes(data: image), context: context) }
        var badHeader = PackageFixtures.udif(partitions: [("disk", 8, [1])])
        badHeader.replaceSubrange((badHeader.count - 512 + 8)..<(badHeader.count - 512 + 12), with: PackageFixtures.big(100, 4))
        #expect(throws: PreviewFailure.malformedDocument) { try DiskImageAdapter().parse(FileBytes(data: badHeader), context: context) }
        var hugeFork = PackageFixtures.udif(partitions: [("disk", 8, [1])])
        hugeFork.replaceSubrange((hugeFork.count - 512 + 32)..<(hugeFork.count - 512 + 40), with: PackageFixtures.big(UInt64.max, 8))
        #expect(throws: PreviewFailure.malformedDocument) { try DiskImageAdapter().parse(FileBytes(data: hugeFork), context: context) }
    }

    @Test func missingPropertyListStillReportsTheTrailer() throws {
        let summary = try summary(PackageFixtures.udif(partitions: [("disk", 8, [1])], includePropertyList: false))
        #expect(summary["partitions"] == nil)
        #expect(summary["sectorCount"] as? Int == 8)
    }

    @Test func oversizedPartitionTablesAreOmittedAndFlaggedPartial() throws {
        let runs = [UInt32](repeating: zlibRun, count: 40_000) + [terminator]
        let image = PackageFixtures.udif(partitions: [("big", 1_000, runs)])
        let tight = RequestContext(budget: PreviewBudget(maxInputBytes: 65_536, maxMilliseconds: 30_000))
        let summary = try summary(image, context: tight)
        #expect(summary["partitions"] == nil)
        #expect(summary["partial"] as? Bool == true)
        #expect(summary["sectorCount"] as? Int == 1_000)
    }

    @Test func partitionCountIsBounded() throws {
        let partitions = (0..<200).map { ("p\($0)", 8, [UInt32(1)]) }
        let summary = try summary(PackageFixtures.udif(partitions: partitions), context: RequestContext(budget: PreviewBudget(maxInputBytes: 4_194_304, maxMilliseconds: 30_000)))
        #expect((summary["partitions"] as? [Any])?.count == DiskImageAdapter.maximumPartitions)
        #expect(summary["partial"] as? Bool == true)
    }

    @Test func sectorMultiplicationOverflowOmitsTheSize() throws {
        let summary = try summary(PackageFixtures.udif(partitions: [("disk", 8, [1])], sectorsOverride: Int.max))
        #expect(summary["imageBytes"] == nil)
        #expect(summary["udifVersion"] as? Int == 4)
    }

    @Test func malformedPartitionTablesFailClosed() throws {
        var image = PackageFixtures.udif(partitions: [("disk", 8, [1])])
        // Damage the XML property list that follows the 2,048-byte data fork.
        image.replaceSubrange(2_048..<2_068, with: Data(repeating: 0x3C, count: 20))
        #expect(throws: PreviewFailure.self) { try DiskImageAdapter().parse(FileBytes(data: image), context: context) }
    }

    @Test func cancelledRequestsNeverReadTheImage() async {
        let image = PackageFixtures.udif(partitions: [("disk", 8, [1])])
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try DiskImageAdapter().parse(FileBytes(data: image), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

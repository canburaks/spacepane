import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Installer package summaries")
struct InstallerPackageAdapterTests {
    private let context = PackageTestSupport.context
    private let scriptBody = Data("#!/bin/sh\necho \(PackageFixtures.secret)\n".utf8)

    private func productArchive(signers: [Data] = [], stored: Bool = false) -> Data {
        let distribution = PackageFixtures.distribution(references: [("com.example.synthetic.app", "2.0", 4_096), ("com.example.synthetic.tools", "2.0", 128)])
        let app = PackageFixtures.XARNode("App.pkg", children: [
            .init("PackageInfo", data: PackageFixtures.packageInfo(identifier: "com.example.synthetic.app", version: "2.0", files: 40, kilobytes: 4_096)),
            .init("Bom", data: Data("BOMStore".utf8)), .init("Payload", data: Data(repeating: 0x42, count: 2_000)),
            .init("Scripts", data: scriptBody)
        ])
        let tools = PackageFixtures.XARNode("Tools.pkg", children: [
            .init("PackageInfo", data: PackageFixtures.packageInfo(identifier: "com.example.synthetic.tools", installLocation: "/usr/local/bin", scripts: []))
        ])
        return PackageFixtures.xar([.init("Distribution", data: distribution), app, tools], signatureCertificates: signers, stored: stored)
    }

    private func summary(_ data: Data, context: RequestContext = PackageTestSupport.context) throws -> ([String: Any], ParsedTextDocument) {
        let document = try InstallerPackageAdapter().parse(FileBytes(data: data), context: context)
        return (PackageTestSupport.object(document), document)
    }

    @Test func productArchiveReportsDistributionAndComponentFacts() throws {
        let (summary, _) = try summary(productArchive())
        #expect(summary["title"] as? String == "Synthetic Installer")
        #expect(summary["version"] as? String == "3.4.5")
        #expect(summary["minimumOSVersion"] as? String == "11.0")
        #expect(summary["hostArchitectures"] as? [String] == ["x86_64", "arm64"])
        #expect(summary["signatureVerified"] as? Bool == false)
        let packages = try #require(summary["packages"] as? [[String: Any]])
        #expect(packages.count == 2)
        let app = try #require(packages.first { $0["identifier"] as? String == "com.example.synthetic.app" })
        #expect(app["version"] as? String == "2.0")
        #expect(app["installLocation"] as? String == "/Applications")
        #expect(app["installKilobytes"] as? Int == 4_096)
        #expect(app["payloadFiles"] as? Int == 40)
        #expect(app["scripts"] as? [String] == ["preinstall", "postinstall"])
        let tools = try #require(packages.first { $0["identifier"] as? String == "com.example.synthetic.tools" })
        #expect(tools["installLocation"] as? String == "/usr/local/bin")
        #expect(tools["scripts"] == nil)
    }

    @Test func listingCarriesTheTableOfContentsWithNestedPaths() throws {
        let (summary, _) = try summary(productArchive())
        let entries = PackageTestSupport.entries(summary)
        let paths = entries.compactMap { $0["path"] as? String }
        #expect(paths.contains("Distribution") && paths.contains("App.pkg") && paths.contains("App.pkg/PackageInfo") && paths.contains("Tools.pkg/PackageInfo"))
        let payload = try #require(entries.first { $0["path"] as? String == "App.pkg/Payload" })
        #expect(payload["type"] as? String == "file" && payload["bytes"] as? Int == 2_000)
        #expect(payload["modified"] as? String == "2026-01-01T00:00:00Z")
        #expect(entries.first { $0["path"] as? String == "App.pkg" }?["type"] as? String == "directory")
        #expect(summary["archiveFormat"] as? String == "XAR")
        #expect(summary["listedEntries"] as? Int == entries.count)
    }

    @Test func scriptAndPayloadContentsAreNeverShown() throws {
        let (_, document) = try summary(productArchive())
        #expect(!document.text.contains(PackageFixtures.secret))
        #expect(!document.text.contains("#!/bin/sh"))
        #expect(!document.text.contains("BOMStore"))
    }

    @Test func scriptAndPayloadMembersAreNeverRead() throws {
        final class Recorder: PreviewByteSource {
            let inner: DataByteSource
            let ranges = Mutex<[Range<Int64>]>([])
            init(_ data: Data) { inner = DataByteSource(data) }
            var byteCount: Int64 { inner.byteCount }
            func read(offset: Int64, count: Int, context: RequestContext) throws -> Data {
                ranges.withLock { $0.append(offset..<(offset + Int64(count))) }
                return try inner.read(offset: offset, count: count, context: context)
            }
        }
        let archive = productArchive()
        let layout = try XARArchiveReader.read(DataByteSource(archive), context: context, limits: ContainerLimits(context: context))
        let forbidden: [Range<Int64>] = layout.entries.enumerated().compactMap { index, entry in
            guard ["Payload", "Scripts", "Bom"].contains(entry.name ?? ""), let offset = entry.offset, let length = entry.length else { return nil }
            return (layout.heapStart + Int64(offset))..<(layout.heapStart + Int64(offset + length))
        }
        #expect(forbidden.count == 3)
        let source = Recorder(archive)
        let document = try InstallerPackageAdapter().parse(source, context: context)
        #expect(PackageTestSupport.object(document)["title"] as? String == "Synthetic Installer")
        let reads = source.ranges.withLock { $0 }
        #expect(!reads.isEmpty)
        #expect(!reads.contains { read in forbidden.contains { $0.overlaps(read) } })
    }

    @Test func signingCertificateNamesAreListedWithoutClaimingValidity() throws {
        let der = PackageFixtures.certificate(commonName: "Synthetic Installer Signer")
        let (summary, _) = try summary(productArchive(signers: [der, Data("junk".utf8)]))
        #expect(summary["signed"] as? Bool == true)
        #expect(summary["signers"] as? [String] == ["Synthetic Installer Signer"])
        #expect(summary["signatureVerified"] as? Bool == false)
        #expect(try self.summary(productArchive()).0["signed"] == nil)
    }

    @Test func storedMembersAreReadToo() throws {
        let (summary, _) = try summary(productArchive(stored: true))
        #expect(summary["title"] as? String == "Synthetic Installer")
    }

    @Test func flatComponentPackagesWithoutADistributionStillSummarize() throws {
        let archive = PackageFixtures.xar([
            .init("PackageInfo", data: PackageFixtures.packageInfo(identifier: "com.example.flat", version: "9.9")),
            .init("Payload", data: Data(repeating: 1, count: 10))
        ])
        let (summary, _) = try summary(archive)
        #expect(summary["title"] == nil)
        #expect((summary["packages"] as? [[String: Any]])?.first?["identifier"] as? String == "com.example.flat")
    }

    @Test func unreadableMetadataIsOmittedNotFatal() throws {
        // A Distribution declaring an entity is skipped; the rest of the package still previews.
        let hostile = Data("<?xml version=\"1.0\"?><!DOCTYPE x [<!ENTITY e \"boom\">]><installer-gui-script><title>&e;</title></installer-gui-script>".utf8)
        let archive = PackageFixtures.xar([.init("Distribution", data: hostile), .init("PackageInfo", data: PackageFixtures.packageInfo(identifier: "com.example.ok"))])
        let (summary, _) = try summary(archive)
        #expect(summary["title"] == nil)
        #expect((summary["packages"] as? [Any])?.count == 1)
    }

    @Test func malformedArchivesFailClosed() {
        let valid = productArchive()
        let samples: [Data] = [Data(), Data("xar!".utf8), Data(repeating: 0, count: 64), Data(valid.prefix(40)),
                               Data("zip!".utf8) + valid.dropFirst(4)]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try InstallerPackageAdapter().parse(FileBytes(data: data), context: PackageTestSupport.context) }
        }
        var wrongVersion = valid
        wrongVersion.replaceSubrange(6..<8, with: PackageFixtures.big(2, 2))
        #expect(throws: PreviewFailure.unsupportedFormat) { try InstallerPackageAdapter().parse(FileBytes(data: wrongVersion), context: PackageTestSupport.context) }
    }

    @Test func tableOfContentsWithEntitiesIsUnsupported() {
        let toc = Data("<!DOCTYPE x [<!ENTITY e \"boom\">]><xar><toc></toc></xar>".utf8)
        let packed = PackageFixtures.zlibCompress(toc)
        let archive = Data("xar!".utf8) + PackageFixtures.big(28, 2) + PackageFixtures.big(1, 2) + PackageFixtures.big(UInt64(packed.count), 8)
            + PackageFixtures.big(UInt64(toc.count), 8) + PackageFixtures.big(0, 4) + packed
        #expect(throws: PreviewFailure.unsupportedFormat) { try InstallerPackageAdapter().parse(FileBytes(data: archive), context: PackageTestSupport.context) }
    }

    @Test func tableOfContentsDecompressionIsBounded() {
        let toc = Data("<xar><toc>".utf8) + Data(repeating: 0x20, count: 3_000_000) + Data("</toc></xar>".utf8)
        let packed = PackageFixtures.zlibCompress(toc)
        // The header declares a small decoded size while the stream expands far beyond it.
        let archive = Data("xar!".utf8) + PackageFixtures.big(28, 2) + PackageFixtures.big(1, 2) + PackageFixtures.big(UInt64(packed.count), 8)
            + PackageFixtures.big(1_000, 8) + PackageFixtures.big(0, 4) + packed
        #expect(throws: PreviewFailure.self) { try InstallerPackageAdapter().parse(FileBytes(data: archive), context: PackageTestSupport.context) }
    }

    @Test func entryCountIsBounded() {
        let nodes = (0..<3_000).map { PackageFixtures.XARNode("file-\($0)", data: Data([1])) }
        let tight = RequestContext(budget: PreviewBudget(maxInputBytes: 4_194_304, maxJSONNodes: 2_000, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.tooManyNodes) { try InstallerPackageAdapter().parse(FileBytes(data: PackageFixtures.xar(nodes)), context: tight) }
    }

    @Test func largeListingsAreFlaggedPartial() throws {
        let nodes = (0..<2_500).map { PackageFixtures.XARNode("file-\($0)", data: Data([1])) }
        let archive = PackageFixtures.xar(nodes)
        let roomy = RequestContext(budget: PreviewBudget(maxInputBytes: 4_194_304, maxJSONNodes: 100_000, maxTextLines: 100_000, maxMilliseconds: 30_000))
        let (all, _) = try summary(archive, context: roomy)
        #expect(PackageTestSupport.entries(all).count == 2_500 && all["partial"] as? Bool == false)
        // Fewer lines than entries: the listing stops at what fits and says so instead of failing.
        let short = RequestContext(budget: PreviewBudget(maxInputBytes: 4_194_304, maxJSONNodes: 100_000, maxTextLines: 3_000, maxMilliseconds: 30_000))
        let (partial, _) = try summary(archive, context: short)
        #expect(PackageTestSupport.entries(partial).count == PackageSummary.listingCapacity(short))
        #expect(PackageTestSupport.entries(partial).count < 2_500 && partial["partial"] as? Bool == true)
    }

    @Test func aDamagedHeapOmitsOnlyTheUnreadableMetadata() throws {
        // The last member (a PackageInfo) is cut short: the package still previews without it.
        let (summary, _) = try summary(Data(productArchive().dropLast(20)))
        #expect(summary["title"] as? String == "Synthetic Installer")
        #expect((summary["packages"] as? [[String: Any]])?.contains { $0["identifier"] as? String == "com.example.synthetic.app" } == true)
    }

    @Test func unsafeEntryNamesAreSkippedAndFlaggedPartial() throws {
        let archive = PackageFixtures.xar([.init("../escape", data: Data([1])), .init("fine.txt", data: Data([2]))])
        let (summary, _) = try summary(archive)
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String } == ["fine.txt"])
        #expect(summary["partial"] as? Bool == true)
    }

    @Test func cancelledRequestsNeverReadTheArchive() async {
        let archive = productArchive()
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try InstallerPackageAdapter().parse(FileBytes(data: archive), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

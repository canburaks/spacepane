import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Mach-O, icon and bundle-walk primitives")
struct PackageBinaryHeaderTests {
    private let context = PackageTestSupport.context

    @Test func thinHeadersNameTheirArchitecture() {
        #expect(MachOHeader.summary(of: PackageFixtures.thinMachO(cpu: PackageFixtures.arm64CPU)) == MachOSummary(layout: .thin, architectures: ["arm64"]))
        #expect(MachOHeader.summary(of: PackageFixtures.thinMachO(cpu: PackageFixtures.x86_64CPU))?.architectures == ["x86_64"])
        #expect(MachOHeader.summary(of: PackageFixtures.thinMachO(cpu: 7))?.architectures == ["i386"])
        // Big-endian 32-bit PowerPC, as an old universal slice would be.
        let powerPC = PackageFixtures.big(0xFEED_FACE, 4) + PackageFixtures.big(18, 4) + PackageFixtures.big(0, 4) + Data(repeating: 0, count: 32)
        #expect(MachOHeader.summary(of: powerPC)?.architectures == ["ppc"])
    }

    @Test func arm64ESubtypeAndWideARMVariantsAreDistinguished() {
        #expect(MachOHeader.architecture(type: 0x0100_000C, subtype: 2) == "arm64e")
        #expect(MachOHeader.architecture(type: 0x0100_000C, subtype: 0x8000_0002) == "arm64e") // pointer-auth capability bits ignored
        #expect(MachOHeader.architecture(type: 0x0100_000C, subtype: 0) == "arm64")
        #expect(MachOHeader.architecture(type: 0x0200_000C, subtype: 0) == "arm64_32")
        #expect(MachOHeader.architecture(type: 12, subtype: 9) == "arm")
        #expect(MachOHeader.architecture(type: 0x0100_0012, subtype: 0) == "ppc64")
        #expect(MachOHeader.architecture(type: 0x1234, subtype: 0).hasPrefix("cpu 0x"))
    }

    @Test func universalHeadersListEverySliceInOrder() {
        let header = PackageFixtures.universalMachO(cpus: [PackageFixtures.x86_64CPU, PackageFixtures.arm64CPU, 7])
        #expect(MachOHeader.summary(of: header) == MachOSummary(layout: .universal, architectures: ["x86_64", "arm64", "i386"]))
    }

    @Test func nonMachOAndHostileHeadersAreRejected() {
        // A Java class file shares the fat magic: its version words must not read as slice counts.
        let javaClass = PackageFixtures.big(0xCAFE_BABE, 4) + PackageFixtures.big(0x0000_0034, 4) + Data(repeating: 0, count: 64)
        let tooMany = PackageFixtures.big(0xCAFE_BABE, 4) + PackageFixtures.big(10_000, 4) + Data(repeating: 0, count: 64)
        let zero = PackageFixtures.big(0xCAFE_BABE, 4) + PackageFixtures.big(0, 4) + Data(repeating: 0, count: 64)
        let truncatedTable = PackageFixtures.big(0xCAFE_BABE, 4) + PackageFixtures.big(3, 4) + Data(repeating: 0, count: 30)
        for data in [Data(), Data([0xCF]), Data("#!/bin/sh\n".utf8), javaClass, tooMany, zero, truncatedTable, Data(repeating: 0xFF, count: 100)] {
            #expect(MachOHeader.summary(of: data) == nil)
        }
    }

    @Test func fat64TablesUseTheWiderEntries() {
        var data = PackageFixtures.big(0xCAFE_BABF, 4) + PackageFixtures.big(2, 4)
        for cpu in [PackageFixtures.arm64CPU, PackageFixtures.x86_64CPU] {
            data += PackageFixtures.big(cpu, 4) + PackageFixtures.big(0, 4) + PackageFixtures.big(0x4000, 8) + PackageFixtures.big(0x1000, 8) + PackageFixtures.big(14, 4) + PackageFixtures.big(0, 4)
        }
        #expect(MachOHeader.summary(of: data)?.architectures == ["arm64", "x86_64"])
    }

    // MARK: Icons

    @Test func icnsPicksTheLargestPNGAndIgnoresLegacyElements() throws {
        let container = PackageFixtures.icns([("is32", Data(repeating: 0, count: 100)), ("ic07", PackageFixtures.png(width: 128, height: 128)),
                                              ("ic10", PackageFixtures.png(width: 512, height: 512)), ("ic08", PackageFixtures.png(width: 256, height: 256))])
        let image = try #require(try ICNSIcon.largestImage(in: container, context: context))
        #expect(image.pixelWidth == 512 && image.pixelHeight == 512 && image.role == .icon && image.isValid)
    }

    @Test func icnsRejectsMalformedContainers() throws {
        let valid = PackageFixtures.icns([("ic07", PackageFixtures.png(width: 64, height: 64))])
        var lying = valid
        lying.replaceSubrange(4..<8, with: PackageFixtures.big(UInt64(valid.count + 50), 4))
        var shortElement = valid
        shortElement.replaceSubrange(12..<16, with: PackageFixtures.big(2, 4))
        for data in [Data(), Data("icns".utf8), Data(valid.prefix(valid.count - 10)), lying, shortElement, Data(repeating: 0xAA, count: 200),
                     PackageFixtures.icns([("ic07", Data("not a png".utf8))])] {
            #expect(try ICNSIcon.largestImage(in: data, context: context) == nil)
        }
    }

    @Test func iconPNGsAreBoundedInSizeAndDimensions() {
        #expect(PackageIconImages.validatedPNG(PackageFixtures.png(width: 64, height: 32))?.pixelHeight == 32)
        #expect(PackageIconImages.validatedPNG(PackageFixtures.png(width: PackageIconImages.maximumPixelDimension + 1, height: 8)) == nil)
        #expect(PackageIconImages.validatedPNG(Data()) == nil)
        #expect(PackageIconImages.validatedPNG(Data(repeating: 0x89, count: 40)) == nil)
    }

    // MARK: Bundle walk

    private func tree(files: Int, depth: Int = 1) throws -> URL {
        let root = try PackageTestSupport.temporaryDirectory()
        var directory = root
        for level in 0..<depth {
            directory = directory.appendingPathComponent("level-\(level)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in 0..<files { try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent("f\(index).bin")) }
        }
        return root
    }

    @Test func walkSumsRegularFilesAndNeverFollowsLinks() throws {
        let root = try tree(files: 3, depth: 2)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        try DirectoryReadAccess().policy.withoutMaterializing {
        let bundle = try BundleDirectory(url: root, allowance: 1_000)
        let result = try bundle.measure(maximumItems: 1_000, maximumDepth: 8, softDeadline: .now.advanced(by: .seconds(30)), context: context)
        // Two levels with three 10-byte files each, two directories and one (unfollowed) link.
        #expect(result == BundleMeasurement(bytes: 60, items: 9, isPartial: false))
        }
    }

    @Test func walkStopsAtItemDepthAndTimeLimitsAndFlagsPartial() throws {
        let root = try tree(files: 5, depth: 4)
        defer { try? FileManager.default.removeItem(at: root) }
        try DirectoryReadAccess().policy.withoutMaterializing {
        let bundle = try BundleDirectory(url: root, allowance: 1_000)
        let far = ContinuousClock.now.advanced(by: .seconds(30))
        let items = try bundle.measure(maximumItems: 4, maximumDepth: 8, softDeadline: far, context: context)
        #expect(items.isPartial && items.items == 4)
        let shallow = try bundle.measure(maximumItems: 1_000, maximumDepth: 2, softDeadline: far, context: context)
        #expect(shallow.isPartial && shallow.items < 24, "\(shallow)")
        let late = try bundle.measure(maximumItems: 1_000, maximumDepth: 8, softDeadline: .now.advanced(by: .seconds(-1)), context: context)
        #expect(late.isPartial && late.items == 0)
        }
    }

    @Test func bundleReadsDrawOnTheAllowanceAndRefuseUnsafeComponents() throws {
        let root = try tree(files: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 7, count: 100).write(to: root.appendingPathComponent("level-0/data.bin"))
        try DirectoryReadAccess().policy.withoutMaterializing {
        let bundle = try BundleDirectory(url: root, allowance: 150)
        guard case .content(let first) = try bundle.read(["level-0", "data.bin"], limit: 1_000, wholeFile: true, context: context) else {
            Issue.record("Expected content"); return
        }
        #expect(first.count == 100 && bundle.remainingBytes == 50)
        #expect(throws: PreviewFailure.inputTooLarge) { try bundle.read(["level-0", "data.bin"], limit: 1_000, wholeFile: true, context: context) }
        #expect(throws: PreviewFailure.self) { try BundleDirectory(url: root, allowance: 10).read(["level-0", "data.bin"], limit: 1_000, wholeFile: true, context: context) }
        for components in [["..", "x"], ["level-0", "..", "level-0", "data.bin"], ["/etc/passwd"], [""], ["a/b"], [], ["level-0", "missing.bin"]] {
            guard case .absent = try bundle.read(components, limit: 10, wholeFile: false, context: context) else {
                Issue.record("\(components) must be absent"); continue
            }
        }
        guard case .tooLarge = try BundleDirectory(url: root, allowance: 1_000).read(["level-0", "data.bin"], limit: 50, wholeFile: true, context: context) else {
            Issue.record("Expected tooLarge"); return
        }
        guard case .content(let prefix) = try BundleDirectory(url: root, allowance: 1_000).read(["level-0", "data.bin"], limit: 16, wholeFile: false, context: context) else {
            Issue.record("Expected prefix"); return
        }
        #expect(prefix.count == 16)
        }
    }
}

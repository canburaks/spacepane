import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Android package summaries")
struct AndroidPackageAdapterTests {
    private let context = PackageTestSupport.context

    private func manifest(_ data: Data) throws -> AndroidManifestSummary {
        try AndroidBinaryXML.parseManifest(data, context: context)
    }

    @Test func manifestFactsAreExtracted() throws {
        let result = try manifest(PackageFixtures.androidManifest(permissions: ["android.permission.INTERNET", "android.permission.CAMERA", "android.permission.INTERNET"],
                                                                  debuggable: true))
        #expect(result.packageName == "com.example.synthetic")
        #expect(result.versionCode == 42)
        #expect(result.versionName == "1.2.3")
        #expect(result.minimumSDK == "24" && result.targetSDK == "34")
        #expect(result.permissions == ["android.permission.INTERNET", "android.permission.CAMERA"])
        #expect(result.activities == 2 && result.services == 1 && result.receivers == 0 && result.providers == 0)
        #expect(result.isDebuggable == true)
        #expect(result.applicationLabel == nil) // a resource reference is not resolved
    }

    @Test func utf8StringPoolsAndStrippedNamesAreSupported() throws {
        for (utf8, strip) in [(true, false), (false, true), (true, true)] {
            let result = try manifest(PackageFixtures.androidManifest(stripNames: strip, utf8: utf8))
            #expect(result.versionCode == 42 && result.minimumSDK == "24" && result.permissions == ["android.permission.INTERNET"],
                    "utf8: \(utf8) strippedNames: \(strip)")
        }
    }

    @Test func unicodePackageNamesSurvive() throws {
        let result = try manifest(PackageFixtures.androidManifest(package: "com.example.日本語", versionName: "1.0-β"))
        #expect(result.packageName == "com.example.日本語" && result.versionName == "1.0-β")
    }

    @Test func debuggableDefaultsToUnknownWhenAbsent() throws {
        #expect(try manifest(PackageFixtures.androidManifest()).isDebuggable == nil)
        #expect(try manifest(PackageFixtures.androidManifest(debuggable: false)).isDebuggable == false)
    }

    @Test func malformedAndHostileManifestsFailClosed() {
        let valid = PackageFixtures.androidManifest()
        var inflatedChunk = valid
        inflatedChunk.replaceSubrange(12..<16, with: PackageFixtures.little(0x7FFF_FFFF, 4)) // string-pool size
        var badCount = valid
        badCount.replaceSubrange(16..<20, with: PackageFixtures.little(0xFFFF_FFF0, 4)) // string count
        var shortHeader = valid
        shortHeader.replaceSubrange(2..<4, with: PackageFixtures.little(4, 2))
        let samples: [Data] = [Data(), Data("<manifest/>".utf8), Data(valid.prefix(7)), Data(valid.prefix(valid.count / 2)),
                               Data(valid.dropLast(3)), inflatedChunk, badCount, shortHeader, Data(repeating: 0xFF, count: 64)]
        for data in samples {
            #expect(throws: PreviewFailure.self) { try AndroidBinaryXML.parseManifest(data, context: PackageTestSupport.context) }
        }
    }

    @Test func nestingDepthAndElementCountAreBounded() {
        var node = PackageFixtures.AXMLNode.element("leaf", [], [])
        for _ in 0..<100 { node = .element("level", [], [node]) }
        #expect(throws: PreviewFailure.tooManyNodes) { try AndroidBinaryXML.parseManifest(PackageFixtures.axml(node), context: PackageTestSupport.context) }
        let wide = PackageFixtures.AXMLNode.element("manifest", [], (0..<3_000).map { _ in .element("uses-permission", [], []) })
        let tight = RequestContext(budget: PreviewBudget(maxJSONNodes: 1_000, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.tooManyNodes) { try AndroidBinaryXML.parseManifest(PackageFixtures.axml(wide), context: tight) }
    }

    @Test func unbalancedElementsAreMalformed() {
        var data = PackageFixtures.androidManifest()
        // Drop the final end-element chunk (24 bytes) and shrink the document size to match.
        data.removeLast(24)
        data.replaceSubrange(4..<8, with: PackageFixtures.little(UInt64(data.count), 4))
        #expect(throws: PreviewFailure.malformedDocument) { try AndroidBinaryXML.parseManifest(data, context: PackageTestSupport.context) }
    }

    @Test func permissionNamesAreCapped() throws {
        let names = (0..<600).map { "com.example.permission.P\($0)" }
        let result = try manifest(PackageFixtures.androidManifest(permissions: names))
        #expect(result.permissions.count == 512)
    }

    // MARK: Whole package

    private func apk(manifest: Data? = PackageFixtures.androidManifest(), extra: [(String, Data)] = []) -> Data {
        var members: [(path: String, data: Data)] = []
        if let manifest { members.append(("AndroidManifest.xml", manifest)) }
        members.append(("classes.dex", Data("dex\n035\0synthetic".utf8)))
        members.append(("res/layout/main.xml", Data([1, 2, 3])))
        members += extra.map { ($0.0, $0.1) }
        return PackageFixtures.zip(members)
    }

    @Test func packageSummaryAndListing() throws {
        let document = try AndroidPackageAdapter().parse(FileBytes(data: apk()), context: context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["packageName"] as? String == "com.example.synthetic")
        #expect(summary["versionCode"] as? Int == 42 && summary["versionName"] as? String == "1.2.3")
        #expect(summary["minSdkVersion"] as? String == "24" && summary["targetSdkVersion"] as? String == "34")
        #expect(summary["permissionCount"] as? Int == 1 && summary["permissions"] as? [String] == ["android.permission.INTERNET"])
        #expect(summary["activities"] as? Int == 2 && summary["services"] as? Int == 1)
        #expect(summary["archiveFormat"] as? String == "ZIP")
        let entries = PackageTestSupport.entries(summary)
        #expect(entries.compactMap { $0["path"] as? String } == ["AndroidManifest.xml", "classes.dex", "res/layout/main.xml"])
        #expect(entries.allSatisfy { $0["type"] as? String == "file" && $0["bytes"] is Int })
        #expect(!document.text.contains("synthetic\\u0000") && !document.text.contains("dex\\n035"))
    }

    @Test func packagesWithoutAManifestAreMalformed() {
        #expect(throws: PreviewFailure.malformedDocument) { try AndroidPackageAdapter().parse(FileBytes(data: apk(manifest: nil)), context: context) }
        #expect(throws: PreviewFailure.self) { try AndroidPackageAdapter().parse(FileBytes(data: Data("PK".utf8)), context: context) }
        #expect(throws: PreviewFailure.unsupportedFormat) {
            try AndroidPackageAdapter().parse(FileBytes(data: apk(manifest: Data("<manifest package=\"x\"/>".utf8))), context: context)
        }
    }

    @Test func listingsAreBoundedAndFlaggedPartial() throws {
        let extra = (0..<3_000).map { ("assets/a-\($0).bin", Data([1])) }
        let roomy = RequestContext(budget: PreviewBudget(maxInputBytes: 8_388_608, maxJSONNodes: 100_000, maxTextLines: 100_000, maxMilliseconds: 30_000))
        let document = try AndroidPackageAdapter().parse(FileBytes(data: apk(extra: extra)), context: roomy)
        let summary = PackageTestSupport.object(document)
        let capacity = PackageSummary.listingCapacity(roomy)
        #expect(PackageTestSupport.entries(summary).count == min(capacity, 3_003))
        #expect(summary["partial"] as? Bool == (3_003 > capacity))
        let defaults = try AndroidPackageAdapter().parse(FileBytes(data: apk(extra: (0..<2_500).map { ("assets/a-\($0).bin", Data([1])) })),
                                                         context: RequestContext(budget: PreviewBudget(maxInputBytes: 8_388_608, maxMilliseconds: 30_000)))
        #expect(PackageTestSupport.object(defaults)["partial"] as? Bool == true)
    }

    @Test func manifestsAboveTheLimitAreRejectedBeforeBeingRead() {
        let large = apk(manifest: Data(repeating: 0, count: AndroidPackageAdapter.maximumManifestBytes + 1))
        #expect(throws: PreviewFailure.self) {
            try AndroidPackageAdapter().parse(FileBytes(data: large), context: RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)))
        }
    }

    @Test func cancelledRequestsNeverReadTheArchive() async {
        let data = apk()
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try AndroidPackageAdapter().parse(FileBytes(data: data), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }

    // MARK: Android App Bundles (protobuf manifest)

    private func bundle(manifest: Data = PackageFixtures.protoManifest(), extra: [(String, Data)] = []) -> Data {
        var members: [(path: String, data: Data)] = [
            ("BundleConfig.pb", Data([0x0A, 0x00])), ("base/manifest/AndroidManifest.xml", manifest),
            ("base/dex/classes.dex", Data("dex\n035\0".utf8)), ("BUNDLE-METADATA/", Data())
        ]
        members += extra.map { ($0.0, $0.1) }
        return PackageFixtures.zip(members)
    }

    @Test func protobufManifestFactsAreExtracted() throws {
        let result = try AndroidProtoXML.parseManifest(PackageFixtures.protoManifest(permissions: ["android.permission.CAMERA", "android.permission.CAMERA", "android.permission.INTERNET"], debuggable: false, activities: 3), context: context)
        #expect(result.packageName == "com.example.bundle" && result.versionCode == 77 && result.versionName == "9.8.7")
        #expect(result.minimumSDK == "23" && result.targetSDK == "35")
        #expect(result.permissions == ["android.permission.CAMERA", "android.permission.INTERNET"])
        #expect(result.activities == 3 && result.isDebuggable == false)
    }

    @Test func bundleSummaryUsesTheBaseModuleManifest() throws {
        let document = try AndroidPackageAdapter().parse(FileBytes(data: bundle()), context: context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["packageName"] as? String == "com.example.bundle" && summary["versionCode"] as? Int == 77)
        #expect(summary["minSdkVersion"] as? String == "23" && summary["targetSdkVersion"] as? String == "35")
        #expect(summary["permissions"] as? [String] == ["android.permission.CAMERA"] && summary["activities"] as? Int == 1)
        #expect(PackageTestSupport.entries(summary).compactMap { $0["path"] as? String }.contains("base/manifest/AndroidManifest.xml"))
        #expect(!document.text.contains("compiled-item-ignored"))
    }

    @Test func aRootManifestWinsOverTheBaseModuleManifest() throws {
        let both = PackageFixtures.zip([("AndroidManifest.xml", PackageFixtures.androidManifest(package: "com.example.root")),
                                        ("base/manifest/AndroidManifest.xml", PackageFixtures.protoManifest(package: "com.example.base"))])
        #expect(PackageTestSupport.object(try AndroidPackageAdapter().parse(FileBytes(data: both), context: context))["packageName"] as? String == "com.example.root")
    }

    @Test func protobufWithUnknownFieldsAndWireTypesIsSkippedSafely() throws {
        // Extra fields of every legal wire type are skipped; the manifest facts still arrive.
        var manifest = PackageFixtures.protoManifest()
        manifest += PackageFixtures.Proto.number(9, 12_345) + PackageFixtures.Proto.field(10, Data(repeating: 1, count: 20))
        manifest += PackageFixtures.Proto.varint(UInt64(11 << 3 | 1)) + Data(repeating: 0, count: 8)
        manifest += PackageFixtures.Proto.varint(UInt64(12 << 3 | 5)) + Data(repeating: 0, count: 4)
        #expect(try AndroidProtoXML.parseManifest(manifest, context: context).packageName == "com.example.bundle")
    }

    @Test func malformedAndHostileProtobufFailsClosed() {
        let valid = PackageFixtures.protoManifest()
        let lyingLength = PackageFixtures.Proto.varint(UInt64(1 << 3 | 2)) + PackageFixtures.Proto.varint(1_000_000) + Data(repeating: 0, count: 10)
        let unterminatedVarint = Data([0x08, 0xFF, 0xFF, 0xFF])
        let tooLongVarint = Data([0x08]) + Data(repeating: 0xFF, count: 12)
        let groupWireType = Data([0x0B, 0x00])
        let zeroField = Data([0x00, 0x00])
        let noManifest = PackageFixtures.Proto.element("not-a-manifest")
        let twoRoots = valid + valid
        for data in [Data(), Data(valid.prefix(valid.count / 2)), Data(valid.dropLast(1)), lyingLength, unterminatedVarint, tooLongVarint,
                     groupWireType, zeroField, noManifest, twoRoots, Data(repeating: 0x0A, count: 64), Data(repeating: 0xFF, count: 64)] {
            #expect(throws: PreviewFailure.self) { try AndroidProtoXML.parseManifest(data, context: PackageTestSupport.context) }
        }
    }

    @Test func protobufNestingAndElementCountAreBounded() {
        var node = PackageFixtures.Proto.element("leaf")
        for _ in 0..<100 { node = PackageFixtures.Proto.element("level", children: [node]) }
        #expect(throws: PreviewFailure.tooManyNodes) { try AndroidProtoXML.parseManifest(node, context: PackageTestSupport.context) }
        let wide = PackageFixtures.Proto.element("manifest", children: (0..<3_000).map { _ in PackageFixtures.Proto.element("uses-permission") })
        let tight = RequestContext(budget: PreviewBudget(maxJSONNodes: 1_000, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.tooManyNodes) { try AndroidProtoXML.parseManifest(wide, context: tight) }
    }

    @Test func oversizedProtobufAttributeValuesAreDroppedNotFailed() throws {
        let long = String(repeating: "x", count: 10_000)
        let manifest = PackageFixtures.protoManifest(versionName: long)
        let result = try AndroidProtoXML.parseManifest(manifest, context: context)
        #expect(result.versionName == nil && result.packageName == "com.example.bundle")
    }

    @Test func manifestsOfNeitherEncodingAreUnsupported() {
        for content in [Data("<manifest/>".utf8), Data([0x42, 0x42, 0x42, 0x42]), Data()] {
            let archive = PackageFixtures.zip([("base/manifest/AndroidManifest.xml", content)])
            #expect(throws: PreviewFailure.self) { try AndroidPackageAdapter().parse(FileBytes(data: archive), context: context) }
        }
    }

    @Test func cancelledProtobufRequestsNeverParse() async {
        let data = bundle()
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try AndroidPackageAdapter().parse(FileBytes(data: data), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

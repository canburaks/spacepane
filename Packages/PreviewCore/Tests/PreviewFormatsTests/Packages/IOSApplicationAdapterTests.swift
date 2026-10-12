import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("iOS application archive summaries")
struct IOSApplicationAdapterTests {
    private let context = PackageTestSupport.context
    private let root = "Payload/Synthetic.app/"

    private var info: [String: Any] {
        [
            "CFBundleName": "Synthetic", "CFBundleDisplayName": "Synthetic App", "CFBundleIdentifier": "com.example.synthetic",
            "CFBundleShortVersionString": "2.5", "CFBundleVersion": "250", "MinimumOSVersion": "16.0",
            "CFBundleExecutable": "Synthetic", "CFBundleSupportedPlatforms": ["iPhoneOS"], "UIDeviceFamily": [1, 2],
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["synthetic", "synthetic-auth"]], ["CFBundleURLSchemes": ["other"]]],
            "CFBundleDocumentTypes": [["CFBundleTypeName": "Doc"]],
            "NSCameraUsageDescription": "Camera needed", "NSLocationWhenInUseUsageDescription": "Location needed",
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon60x60"], "CFBundleIconName": "AppIcon"]]
        ]
    }

    private func ipa(info: [String: Any]? = nil, profile: Data? = nil, icons: [(String, Data)] = [], extra: [(String, Data)] = [],
                     binaryInfo: Bool = true) -> Data {
        var members: [(path: String, data: Data)] = [
            ("Payload/", Data()),
            (root + "Info.plist", PackageFixtures.plist(info ?? self.info, binary: binaryInfo)),
            (root + "Synthetic", Data("MZ-not-read".utf8))
        ]
        if let profile { members.append((root + "embedded.mobileprovision", profile)) }
        members += icons.map { (root + $0.0, $0.1) }
        members += extra.map { ($0.0, $0.1) }
        return PackageFixtures.zip(members)
    }

    private func summary(_ data: Data, context: RequestContext = PackageTestSupport.context) throws -> ([String: Any], ParsedTextDocument) {
        let document = try IOSApplicationAdapter(now: { PackageTestSupport.now }).parse(FileBytes(data: data), context: context)
        return (PackageTestSupport.object(document), document)
    }

    @Test func infoPropertyListFactsAreSummarized() throws {
        let (summary, _) = try summary(ipa())
        #expect(summary["name"] as? String == "Synthetic" && summary["displayName"] as? String == "Synthetic App")
        #expect(summary["bundleIdentifier"] as? String == "com.example.synthetic")
        #expect(summary["version"] as? String == "2.5" && summary["build"] as? String == "250")
        #expect(summary["minimumOSVersion"] as? String == "16.0")
        #expect(summary["platforms"] as? [String] == ["iPhoneOS"] && summary["deviceFamilies"] as? [String] == ["iPhone", "iPad"])
        #expect(summary["urlSchemes"] as? Int == 3 && summary["documentTypes"] as? Int == 1)
        #expect(summary["usageDescriptions"] as? [String] == ["NSCameraUsageDescription", "NSLocationWhenInUseUsageDescription"])
    }

    @Test func usageDescriptionProseAndSchemeNamesAreNotShown() throws {
        let (_, document) = try summary(ipa())
        for text in ["Camera needed", "Location needed", "synthetic-auth"] { #expect(!document.text.contains(text)) }
    }

    @Test func xmlPropertyListsWork() throws {
        let (summary, _) = try summary(ipa(binaryInfo: false))
        #expect(summary["bundleIdentifier"] as? String == "com.example.synthetic")
    }

    @Test func embeddedProfileUsesTheSharedProfileSummary() throws {
        let profile = PackageFixtures.signedMessage(content: PackageFixtures.profilePropertyList())
        let (summary, document) = try summary(ipa(profile: profile))
        let provisioning = try #require(summary["provisioning"] as? [String: Any])
        #expect(provisioning["name"] as? String == "Synthetic Profile")
        #expect(provisioning["provisionedDevices"] as? Int == 3)
        #expect(provisioning["profileType"] as? String == "development")
        #expect(!document.text.contains("synthetic-device-identifier"))
    }

    @Test func aBrokenProfileIsOmittedWithoutFailingThePreview() throws {
        let (summary, _) = try summary(ipa(profile: Data(repeating: 0xAB, count: 300)))
        #expect(summary["provisioning"] == nil)
        #expect(summary["bundleIdentifier"] as? String == "com.example.synthetic")
    }

    @Test func theLargestDecodableIconPNGIsAttached() throws {
        let small = PackageFixtures.png(width: 120, height: 120)
        let large = PackageFixtures.png(width: 180, height: 180)
        let document = try IOSApplicationAdapter(now: { PackageTestSupport.now }).parse(
            FileBytes(data: ipa(icons: [("AppIcon60x60@2x.png", small), ("AppIcon60x60@3x.png", large), ("Other.png", PackageFixtures.png(width: 512, height: 512))])), context: context)
        let image = try #require(document.images.first)
        #expect(document.images.count == 1)
        #expect(image.role == .icon && image.isValid)
        #expect(image.pixelWidth == 180 && image.pixelHeight == 180)
        #expect(image.data == large)
        // The member name is untrusted text that never passes the privacy stage; `PreviewImage` carries no label field.
    }

    @Test func undecodableIconsAreOmitted() throws {
        let fakePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: 100)
        let document = try IOSApplicationAdapter(now: { PackageTestSupport.now }).parse(
            FileBytes(data: ipa(icons: [("AppIcon60x60@2x.png", fakePNG), ("AppIcon60x60@3x.png", Data("not a png at all, just text".utf8))])), context: context)
        #expect(document.images.isEmpty)
        #expect(PackageTestSupport.object(document)["name"] as? String == "Synthetic")
    }

    @Test func iconsAboveTheEncodedSizeLimitAreSkipped() throws {
        let huge = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(repeating: 0, count: PackageIconImages.maximumEncodedBytes + 10)
        let document = try IOSApplicationAdapter(now: { PackageTestSupport.now }).parse(
            FileBytes(data: ipa(icons: [("AppIcon60x60@2x.png", huge)])), context: context)
        #expect(document.images.isEmpty)
    }

    @Test func iconsOutsideTheAppRootOrWithOtherNamesAreIgnored() throws {
        let png = PackageFixtures.png(width: 64, height: 64)
        let document = try IOSApplicationAdapter(now: { PackageTestSupport.now }).parse(
            FileBytes(data: ipa(icons: [("Frameworks/AppIcon60x60.png", png), ("Unrelated.png", png)])), context: context)
        #expect(document.images.isEmpty)
    }

    @Test func listingCarriesEveryMemberWithSizes() throws {
        let (summary, _) = try summary(ipa(icons: [("AppIcon60x60@2x.png", PackageFixtures.png(width: 16, height: 16))]))
        let paths = PackageTestSupport.entries(summary).compactMap { $0["path"] as? String }
        #expect(paths.contains("Payload/Synthetic.app/Info.plist") && paths.contains("Payload/Synthetic.app/Synthetic"))
        #expect(summary["archiveFormat"] as? String == "ZIP")
        #expect(PackageTestSupport.entries(summary).allSatisfy { $0["modified"] is String })
    }

    @Test func executableAndOtherMembersAreNeverShown() throws {
        let (_, document) = try summary(ipa())
        #expect(!document.text.contains("MZ-not-read"))
    }

    @Test func archivesWithoutAnAppInfoPlistAreMalformed() {
        let empty = PackageFixtures.zip([("Payload/Synthetic.app/Other.txt", Data("x".utf8))])
        #expect(throws: PreviewFailure.malformedDocument) { try IOSApplicationAdapter().parse(FileBytes(data: empty), context: context) }
        let nested = PackageFixtures.zip([("Payload/Synthetic.app/Frameworks/X.framework/Info.plist", PackageFixtures.plist(info))])
        #expect(throws: PreviewFailure.malformedDocument) { try IOSApplicationAdapter().parse(FileBytes(data: nested), context: context) }
        #expect(throws: PreviewFailure.self) { try IOSApplicationAdapter().parse(FileBytes(data: Data("not a zip".utf8)), context: context) }
    }

    @Test func malformedInfoPropertyListsFailClosed() {
        let broken = PackageFixtures.zip([(root + "Info.plist", Data("<plist><dict><key>a</key>".utf8))])
        #expect(throws: PreviewFailure.self) { try IOSApplicationAdapter().parse(FileBytes(data: broken), context: context) }
        let notADictionary = PackageFixtures.zip([(root + "Info.plist", PackageFixtures.plist(["a", "b"]))])
        #expect(throws: PreviewFailure.malformedDocument) { try IOSApplicationAdapter().parse(FileBytes(data: notADictionary), context: context) }
    }

    @Test func truncatedArchivesFailClosed() {
        let valid = ipa()
        for cut in [0, 10, valid.count / 2, valid.count - 5] {
            #expect(throws: PreviewFailure.self) { try IOSApplicationAdapter().parse(FileBytes(data: Data(valid.prefix(cut))), context: context) }
        }
    }

    @Test func infoPropertyListsAboveTheLimitAreRejected() {
        var large = info
        large["Padding"] = String(repeating: "x", count: IOSApplicationAdapter.maximumInfoPropertyListBytes + 100)
        let archive = PackageFixtures.zip([(root + "Info.plist", PackageFixtures.plist(large))])
        #expect(throws: PreviewFailure.inputTooLarge) {
            try IOSApplicationAdapter().parse(FileBytes(data: archive), context: RequestContext(budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)))
        }
    }

    @Test func memberReadsDrawOnTheCumulativeInputBudget() {
        let tight = RequestContext(budget: PreviewBudget(maxInputBytes: 300, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.inputTooLarge) { try IOSApplicationAdapter().parse(FileBytes(data: ipa()), context: tight) }
    }

    @Test func cancelledRequestsNeverReadTheArchive() async {
        let data = ipa()
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try IOSApplicationAdapter().parse(FileBytes(data: data), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

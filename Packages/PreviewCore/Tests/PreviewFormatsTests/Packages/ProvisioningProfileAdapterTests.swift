import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Provisioning profile summaries")
struct ProvisioningProfileAdapterTests {
    private let context = PackageTestSupport.context
    private func adapter() -> ProvisioningProfileAdapter { ProvisioningProfileAdapter(now: { PackageTestSupport.now }) }
    private func signed(_ plist: Data) -> FileBytes { FileBytes(data: PackageFixtures.signedMessage(content: plist)) }

    @Test func cmsEnvelopeIsDecodedAndSummarized() throws {
        let document = try adapter().parse(signed(PackageFixtures.profilePropertyList()), context: context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["name"] as? String == "Synthetic Profile")
        #expect(summary["uuid"] as? String == "00000000-0000-4000-8000-000000000001")
        #expect(summary["appIDName"] as? String == "Synthetic App")
        #expect(summary["teamName"] as? String == "Example Team")
        #expect(summary["teamIdentifier"] as? String == "ABCDE12345")
        #expect(summary["platforms"] as? [String] == ["iOS"])
        #expect(summary["profileType"] as? String == "development")
        #expect(summary["creationDate"] as? String == "2023-11-14T22:13:20Z")
        #expect(summary["expirationDate"] as? String == "2033-05-18T03:33:20Z")
        #expect(summary["expired"] as? Bool == false)
        #expect(summary["provisionedDevices"] as? Int == 3)
        #expect(summary["certificateCount"] as? Int == 1)
        #expect(summary["certificates"] as? [String] == ["Synthetic Developer"])
        #expect(summary["signatureVerified"] as? Bool == false)
        let entitlements = try #require(summary["entitlements"] as? [String: Any])
        #expect(entitlements["get-task-allow"] as? Bool == true)
        #expect(entitlements["application-identifier"] as? String == "ABCDE12345.com.example.synthetic")
    }

    @Test func deviceIdentifiersAndCertificateBytesNeverAppear() throws {
        let document = try adapter().parse(signed(PackageFixtures.profilePropertyList(devices: 5)), context: context)
        #expect(!document.text.contains("synthetic-device-identifier"))
        #expect(!document.text.contains("MII"))
        #expect(PackageTestSupport.object(document)["provisionedDevices"] as? Int == 5)
    }

    @Test func expiredProfilesAreFlagged() throws {
        let plist = PackageFixtures.profilePropertyList(expiration: Date(timeIntervalSince1970: 1_600_000_000))
        let summary = PackageTestSupport.object(try adapter().parse(signed(plist), context: context))
        #expect(summary["expired"] as? Bool == true)
    }

    @Test func profileTypesFollowDevicesAndEntitlements() throws {
        func type(_ data: Data) throws -> String? {
            PackageTestSupport.object(try adapter().parse(signed(data), context: context))["profileType"] as? String
        }
        #expect(try type(PackageFixtures.profilePropertyList(getTaskAllow: false)) == "adHoc")
        #expect(try type(PackageFixtures.profilePropertyList(getTaskAllow: true)) == "development")
        var enterprise = try #require(PackageFixtures.plistObject(PackageFixtures.profilePropertyList()) as? [String: Any])
        enterprise["ProvisionsAllDevices"] = true
        enterprise["ProvisionedDevices"] = nil
        #expect(try type(PackageFixtures.plist(enterprise)) == "enterprise")
        var distribution = enterprise
        distribution["ProvisionsAllDevices"] = nil
        #expect(try type(PackageFixtures.plist(distribution)) == "distribution")
        let summary = PackageTestSupport.object(try adapter().parse(signed(PackageFixtures.plist(distribution)), context: context))
        #expect(summary["provisionedDevices"] == nil)
    }

    @Test func unsignedAndBinaryPropertyListsAreAccepted() throws {
        for binary in [false, true] {
            let plist = PackageFixtures.plist(PackageFixtures.plistObject(PackageFixtures.profilePropertyList()), binary: binary)
            let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: plist), context: context))
            #expect(summary["name"] as? String == "Synthetic Profile")
        }
    }

    @Test func credentialLookingEntitlementValuesAreConcealed() throws {
        let plist = PackageFixtures.profilePropertyList(extraEntitlements: [
            "com.example.api-secret": PackageFixtures.secret,
            "com.example.nested": ["inner-token": PackageFixtures.secret, "plain": "visible-value"],
            "com.example.client-token-list": [PackageFixtures.secret, PackageFixtures.secret]
        ])
        let document = try adapter().parse(signed(plist), context: context)
        let visible = PackageTestSupport.concealedText(document)
        #expect(!visible.contains(PackageFixtures.secret))
        #expect(visible.contains("com.example.api-secret"))
        #expect(visible.contains("visible-value"))
        #expect(document.sensitiveRanges.count >= 4)
        #expect(document.usesStructuredPrivacy)
    }

    @Test func malformedInputsFailClosed() {
        let garbage = [Data(), Data(repeating: 0xAB, count: 200), Data([0x30, 0x80, 0x00, 0x00]),
                       PackageFixtures.signedMessage(content: Data("not a property list".utf8)),
                       PackageFixtures.signedMessage(content: PackageFixtures.plist(["not", "a", "dictionary"])),
                       Data(PackageFixtures.signedMessage(content: PackageFixtures.profilePropertyList()).dropLast(30))]
        for data in garbage {
            #expect(throws: PreviewFailure.self) { try adapter().parse(FileBytes(data: data), context: context) }
        }
    }

    @Test func hostilePropertyListsAreRejectedBeforeFoundationBuildsThem() throws {
        // A binary property list whose only object is an array that refers to itself.
        var cyclic = Data("bplist00".utf8) + Data([0xA1, 0x00, 0x08]) + Data(repeating: 0, count: 6) + Data([1, 1])
        for value: UInt64 in [1, 0, 10] { cyclic += PackageFixtures.big(value, 8) }
        #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(FileBytes(data: cyclic), context: context) }
        let entities = Data("<?xml version=\"1.0\"?><!DOCTYPE plist [<!ENTITY a \"aaaa\">]><plist><dict><key>Name</key><string>&a;</string></dict></plist>".utf8)
        #expect(throws: PreviewFailure.self) { try adapter().parse(FileBytes(data: entities), context: context) }
    }

    @Test func nodeBudgetBoundsEntitlementExpansion() {
        var entitlements: [String: Any] = [:]
        for index in 0..<400 { entitlements["com.example.key-\(index)"] = true }
        let plist = PackageFixtures.profilePropertyList(extraEntitlements: entitlements)
        let tiny = RequestContext(budget: PreviewBudget(maxJSONNodes: 150, maxMilliseconds: 30_000))
        #expect(throws: PreviewFailure.self) { try adapter().parse(signed(plist), context: tiny) }
    }

    @Test func entitlementKeysAreBoundedToTheListLimit() throws {
        var entitlements: [String: Any] = [:]
        for index in 0..<200 { entitlements["com.example.key-\(index)"] = true }
        let plist = PackageFixtures.profilePropertyList(extraEntitlements: entitlements)
        let summary = PackageTestSupport.object(try adapter().parse(signed(plist), context: context))
        #expect((summary["entitlements"] as? [String: Any])?.count == PackageSummary.maximumListItems)
    }

    @Test func cancelledRequestsNeverReachTheDecoder() async {
        let data = signed(PackageFixtures.profilePropertyList())
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try ProvisioningProfileAdapter().parse(data, context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

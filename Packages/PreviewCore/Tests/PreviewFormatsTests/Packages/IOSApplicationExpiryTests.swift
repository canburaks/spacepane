import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// An IPA's embedded provisioning profile reports the same validity findings as a standalone profile
/// (decision 029), against the adapter's injected clock.
@Suite("IPA embedded profile validity")
struct IOSApplicationExpiryTests {
    private static let root = "Payload/Synthetic.app/"

    private func findings(profileExpiringAt expiration: Date?, now: Date = ExpiryFixtures.now) throws -> [PreviewFinding] {
        var members: [(path: String, data: Data)] = [
            ("Payload/", Data()),
            (Self.root + "Info.plist", PackageFixtures.plist(["CFBundleIdentifier": "com.example.synthetic",
                                                              "CFBundleExecutable": "Synthetic"])),
        ]
        if let expiration {
            let profile = PackageFixtures.signedMessage(content: PackageFixtures.profilePropertyList(expiration: expiration))
            members.append((Self.root + "embedded.mobileprovision", profile))
        }
        let document = try IOSApplicationAdapter(now: { now }).parse(FileBytes(data: PackageFixtures.zip(members)),
                                                                      context: PackageTestSupport.context)
        return document.findings
    }

    @Test func anExpiredEmbeddedProfileIsReported() throws {
        #expect(try findings(profileExpiringAt: ExpiryFixtures.after(-ExpiryFixtures.day))
            == [PreviewFinding(kind: .profileExpired, count: 1)])
    }

    @Test func anEmbeddedProfileEndingSoonReportsItsDays() throws {
        #expect(try findings(profileExpiringAt: ExpiryFixtures.after(10 * ExpiryFixtures.day))
            == [PreviewFinding(kind: .profileExpiresSoon, count: 1, detail: .days(10))])
    }

    @Test func noProfileOrALongValidOneReportsNothing() throws {
        #expect(try findings(profileExpiringAt: nil).isEmpty)
        #expect(try findings(profileExpiringAt: ExpiryFixtures.after(400 * ExpiryFixtures.day)).isEmpty)
    }
}

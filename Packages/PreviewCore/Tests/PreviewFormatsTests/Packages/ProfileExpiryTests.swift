import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// The validity findings of provisioning-profile summaries (decision 029): expired and expires soon,
/// against the adapter's injected clock. No test reads the real date.
@Suite("Profile validity findings")
struct ProfileExpiryTests {
    private typealias Fixtures = ExpiryFixtures
    private let day = Fixtures.day

    private static let expired = PreviewFinding(kind: .profileExpired, count: 1)
    private static func soon(_ days: Int) -> PreviewFinding {
        PreviewFinding(kind: .profileExpiresSoon, count: 1, detail: .days(days))
    }

    private func parse(_ plist: Data, signed: Bool = true, now: Date = Fixtures.now) throws -> ParsedTextDocument {
        let bytes = FileBytes(data: signed ? PackageFixtures.signedMessage(content: plist) : plist)
        return try ProvisioningProfileAdapter(now: { now }).parse(bytes, context: PackageTestSupport.context)
    }

    private func findings(endingAfter seconds: TimeInterval, signed: Bool = true, now: Date = Fixtures.now) throws -> [PreviewFinding] {
        try parse(PackageFixtures.profilePropertyList(expiration: Fixtures.after(seconds)), signed: signed, now: now).findings
    }

    // MARK: Expiry

    @Test func aProfileFarFromItsEndHasNoFinding() throws {
        #expect(try findings(endingAfter: 3_650 * day).isEmpty)
        // The shared fixture's own date, 2033-05-18, against the same clock.
        #expect(try parse(PackageFixtures.profilePropertyList()).findings.isEmpty)
    }

    @Test(arguments: ExpiryFixtures.endings)
    func theExpirationDateIsClassifiedAgainstTheClock(_ ending: ExpiryFixtures.Ending) throws {
        let expected: [PreviewFinding] = switch ending.standing {
        case .valid: []
        case .endsSoon(let days): [Self.soon(days)]
        case .expired: [Self.expired]
        }
        #expect(try findings(endingAfter: ending.seconds) == expected)
    }

    @Test func aFractionalSecondPastTheEndIsExpired() throws {
        #expect(try findings(endingAfter: 0, now: Fixtures.after(0.5)) == [Self.expired])
        #expect(try findings(endingAfter: 0, now: Fixtures.after(-0.5)) == [Self.soon(1)])
    }

    @Test func theSameProfileChangesStandingWhenOnlyTheClockMoves() throws {
        let plist = PackageFixtures.profilePropertyList(expiration: Fixtures.after(60 * day))
        #expect(try parse(plist).findings.isEmpty)
        #expect(try parse(plist, now: Fixtures.after(31 * day)).findings == [Self.soon(29)])
        #expect(try parse(plist, now: Fixtures.after(61 * day)).findings == [Self.expired])
    }

    @Test func aProfileWithTwoDatesAnswersForItsExpirationNotItsCreation() throws {
        // The fixture's creation date is 2023-11-14, long before the clock, and says nothing about validity.
        let plist = PackageFixtures.profilePropertyList(expiration: Fixtures.after(3 * day))
        #expect(try parse(plist).findings == [Self.soon(3)])
    }

    @Test func unsignedXMLAndBinaryPropertyListsAreJudgedToo() throws {
        let object = PackageFixtures.plistObject(PackageFixtures.profilePropertyList(expiration: Fixtures.after(-day)))
        for binary in [false, true] {
            let plist = PackageFixtures.plist(object, binary: binary)
            #expect(try parse(plist, signed: false).findings == [Self.expired])
        }
    }

    // MARK: Nothing to judge

    @Test func aProfileWithoutAnExpirationDateHasNoFinding() throws {
        var profile = try #require(PackageFixtures.plistObject(PackageFixtures.profilePropertyList()) as? [String: Any])
        profile["ExpirationDate"] = nil
        let document = try parse(PackageFixtures.plist(profile))
        #expect(document.findings.isEmpty)
        #expect(PackageTestSupport.object(document)["expired"] == nil)
    }

    @Test func anExpirationDateThatIsNotADateHasNoFinding() throws {
        var profile = try #require(PackageFixtures.plistObject(PackageFixtures.profilePropertyList()) as? [String: Any])
        profile["ExpirationDate"] = "2020-01-01"
        #expect(try parse(PackageFixtures.plist(profile)).findings.isEmpty)
    }

    @Test func anExpiredCertificateInsideAValidProfileIsNotTheProfilesFinding() throws {
        var profile = try #require(PackageFixtures.plistObject(PackageFixtures.profilePropertyList()) as? [String: Any])
        profile["DeveloperCertificates"] = [Fixtures.ecCertificate(end: -day), Fixtures.rsaCertificate(bits: 1_024, end: -day)]
        let document = try parse(PackageFixtures.plist(profile))
        #expect(PackageTestSupport.object(document)["certificateCount"] as? Int == 2)
        #expect(document.findings.isEmpty)
    }

    // MARK: Shape

    @Test func findingsCarryNoLinesOrDetailBeyondDaysAndTheSeverityIsTheKindDefault() throws {
        let expiredFinding = try #require(try findings(endingAfter: -day).first)
        #expect(expiredFinding.kind == .profileExpired && expiredFinding.severity == .warning)
        #expect(expiredFinding.lines.isEmpty && expiredFinding.detail == .none && expiredFinding.count == 1)
        let soonFinding = try #require(try findings(endingAfter: 5 * day).first)
        #expect(soonFinding.kind == .profileExpiresSoon && soonFinding.severity == .caution)
        #expect(soonFinding.lines.isEmpty && soonFinding.detail == .days(5) && soonFinding.count == 1)
    }

    @Test func addingFindingsDoesNotChangeTheSummaryDocument() throws {
        let document = try parse(PackageFixtures.profilePropertyList(expiration: Fixtures.after(-day)))
        #expect(document.findings == [Self.expired])
        #expect(document.origin == .summary && document.syntax == .json && document.usesStructuredPrivacy)
        #expect(document.images.isEmpty && document.sensitiveRanges.isEmpty && document.facts == .none)
        let summary = PackageTestSupport.object(document)
        #expect(summary["name"] as? String == "Synthetic Profile")
        #expect(summary["provisionedDevices"] as? Int == 3)
        #expect(summary["signatureVerified"] as? Bool == false)
        // Summary and finding are one decision: the flag and the finding agree, and neither shows a date's value.
        #expect(summary["expired"] as? Bool == true)
        #expect(summary["expirationDate"] as? String == PackageSummary.isoDate(Fixtures.after(-day)))
    }

    @Test func aProfileEndingSoonIsNotFlaggedExpiredInTheSummary() throws {
        let document = try parse(PackageFixtures.profilePropertyList(expiration: Fixtures.after(5 * day)))
        #expect(document.findings == [Self.soon(5)])
        #expect(PackageTestSupport.object(document)["expired"] as? Bool == false)
    }
}

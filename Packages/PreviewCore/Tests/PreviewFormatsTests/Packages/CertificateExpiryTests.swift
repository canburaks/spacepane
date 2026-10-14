import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

/// The validity findings of certificate summaries (decision 029): expired, expires soon, not yet valid
/// and weak RSA keys, all against the adapter's injected clock. No test reads the real date.
@Suite("Certificate validity findings")
struct CertificateExpiryTests {
    private typealias Fixtures = ExpiryFixtures
    private let day = Fixtures.day

    private func findings(_ input: FileBytes, now: Date = Fixtures.now) throws -> [PreviewFinding] {
        try CertificateAdapter(now: { now }).parse(input, context: PackageTestSupport.context).findings
    }

    private func findings(der: Data, now: Date = Fixtures.now) throws -> [PreviewFinding] {
        try findings(FileBytes(data: der), now: now)
    }

    private static func soon(_ days: Int, count: Int = 1) -> PreviewFinding {
        PreviewFinding(kind: .certificateExpiresSoon, count: count, detail: .days(days))
    }
    private static let expired = PreviewFinding(kind: .certificateExpired, count: 1)

    // MARK: Expiry

    @Test func aCertificateFarFromItsEndHasNoFinding() throws {
        #expect(try findings(der: Fixtures.ecCertificate(end: 3_650 * day)).isEmpty)
        // The shared fixture, valid 2026-01-01 to 2036-01-01, against the same clock.
        #expect(try findings(der: PackageFixtures.certificate()).isEmpty)
    }

    @Test(arguments: ExpiryFixtures.endings)
    func theEndOfValidityIsClassifiedAgainstTheClock(_ ending: ExpiryFixtures.Ending) throws {
        let expected: [PreviewFinding] = switch ending.standing {
        case .valid: []
        case .endsSoon(let days): [Self.soon(days)]
        case .expired: [Self.expired]
        }
        #expect(try findings(der: Fixtures.ecCertificate(end: ending.seconds)) == expected)
    }

    @Test func aFractionalSecondPastTheEndIsExpired() throws {
        let der = Fixtures.ecCertificate(end: 0)
        #expect(try findings(der: der, now: Fixtures.after(0.5)) == [Self.expired])
        #expect(try findings(der: der, now: Fixtures.after(-0.5)) == [Self.soon(1)])
    }

    @Test func theSameFileChangesStandingWhenOnlyTheClockMoves() throws {
        let der = Fixtures.ecCertificate(end: 60 * day)
        #expect(try findings(der: der).isEmpty)
        #expect(try findings(der: der, now: Fixtures.after(31 * day)) == [Self.soon(29)])
        #expect(try findings(der: der, now: Fixtures.after(61 * day)) == [Self.expired])
    }

    @Test func expiredAndExpiringSoonAreMutuallyExclusiveForOneCertificate() throws {
        let kinds = Set(try findings(der: Fixtures.ecCertificate(end: -day)).map(\.kind))
        #expect(kinds == [.certificateExpired])
    }

    // MARK: Not yet valid

    @Test func aCertificateThatStartsLaterIsNotYetValid() throws {
        let der = Fixtures.ecCertificate(start: day, end: 3_650 * day)
        #expect(try findings(der: der) == [PreviewFinding(kind: .certificateNotYetValid, count: 1)])
    }

    @Test func theFirstSecondOfValidityIsAlreadyValid() throws {
        #expect(try findings(der: Fixtures.ecCertificate(start: 0, end: 3_650 * day)).isEmpty)
        #expect(try findings(der: Fixtures.ecCertificate(start: 1, end: 3_650 * day))
            == [PreviewFinding(kind: .certificateNotYetValid, count: 1)])
    }

    // MARK: Bundles

    @Test func aBundleReportsEachConditionOnceWithCounts() throws {
        let bundle = Fixtures.bundle([
            Fixtures.ecCertificate(end: -5 * day, commonName: "expired.test", serial: 1),
            Fixtures.ecCertificate(end: 12 * day, commonName: "soon.test", serial: 2),
            Fixtures.ecCertificate(end: 3_650 * day, commonName: "fine.test", serial: 3)
        ])
        #expect(try findings(bundle) == [Self.expired, Self.soon(12)])
    }

    @Test func theSoonestEndingNamesTheDaysAndEveryOneIsCounted() throws {
        let bundle = Fixtures.bundle([
            Fixtures.ecCertificate(end: 20 * day, commonName: "later.test", serial: 1),
            Fixtures.ecCertificate(end: 4.5 * day, commonName: "soonest.test", serial: 2),
            Fixtures.ecCertificate(end: 10 * day, commonName: "middle.test", serial: 3),
            Fixtures.ecCertificate(end: 3_650 * day, commonName: "fine.test", serial: 4)
        ])
        #expect(try findings(bundle) == [Self.soon(5, count: 3)])
    }

    @Test func notYetValidCertificatesInABundleAreCounted() throws {
        let bundle = Fixtures.bundle([
            Fixtures.ecCertificate(start: 2 * day, end: 3_650 * day, serial: 1),
            Fixtures.ecCertificate(start: 40 * day, end: 3_650 * day, serial: 2),
            Fixtures.ecCertificate(end: 3_650 * day, serial: 3)
        ])
        #expect(try findings(bundle) == [PreviewFinding(kind: .certificateNotYetValid, count: 2)])
    }

    @Test func aCertificateCanBeBothNotYetValidAndEndingSoon() throws {
        let der = Fixtures.ecCertificate(start: 3 * day, end: 20 * day)
        #expect(try findings(der: der) == [Self.soon(20), PreviewFinding(kind: .certificateNotYetValid, count: 1)])
    }

    @Test func certificatesBeyondTheInspectionLimitAreNotCounted() throws {
        let one = Fixtures.ecCertificate(end: -day)
        let bundle = Fixtures.bundle(Array(repeating: one, count: CertificateAdapter.maximumCertificates + 8))
        #expect(try findings(bundle) == [PreviewFinding(kind: .certificateExpired, count: CertificateAdapter.maximumCertificates)])
    }

    @Test func unreadableAndNonCertificateBlocksProduceNoFindings() throws {
        let text = PackageFixtures.pem(label: "CERTIFICATE", body: Data("not der".utf8))
            + PackageFixtures.pem(label: "PUBLIC KEY", body: Data(repeating: 1, count: 40))
            + PackageFixtures.pem(label: "RSA PRIVATE KEY", body: Data(repeating: 0x41, count: 120))
        #expect(try findings(FileBytes(data: Data(text.utf8))).isEmpty)
    }

    // MARK: Weak keys

    @Test(arguments: [(512, true), (1_024, true), (1_536, true), (2_048, false), (3_072, false), (4_096, false)])
    func onlyRSAKeysShorterThan2048BitsAreWeak(bits: Int, weak: Bool) throws {
        let result = try findings(der: Fixtures.rsaCertificate(bits: bits, end: 3_650 * day))
        #expect(result == (weak ? [PreviewFinding(kind: .certificateWeakKey, count: 1)] : []))
    }

    @Test func theKeySizeComesFromTheSystemParserForRSA() throws {
        // Guards the assumption behind the weak-key finding: Security names the algorithm "RSA" and
        // reports the modulus size for the certificates this suite builds.
        let details = try #require(CertificateInspector.details(der: Fixtures.rsaCertificate(bits: 1_024, end: day), now: Fixtures.now))
        #expect(details.publicKeyAlgorithm == "RSA")
        #expect(details.publicKeyBits == 1_024)
    }

    @Test func ellipticCurveKeysAreNeverWeak() throws {
        // A P-256 key is 256 bits long, far below 2,048, and is strong.
        let details = try #require(CertificateInspector.details(der: Fixtures.ecCertificate(end: 3_650 * day), now: Fixtures.now))
        #expect(details.publicKeyAlgorithm == "EC" && details.publicKeyBits == 256)
        #expect(try findings(der: Fixtures.ecCertificate(end: 3_650 * day)).isEmpty)
    }

    @Test func shortKeysInABundleAreCounted() throws {
        let bundle = Fixtures.bundle([
            Fixtures.rsaCertificate(bits: 1_024, end: 3_650 * day, commonName: "a.test", serial: 1),
            Fixtures.rsaCertificate(bits: 2_048, end: 3_650 * day, commonName: "b.test", serial: 2),
            Fixtures.rsaCertificate(bits: 1_536, end: 3_650 * day, commonName: "c.test", serial: 3),
            Fixtures.ecCertificate(end: 3_650 * day, serial: 4)
        ])
        #expect(try findings(bundle) == [PreviewFinding(kind: .certificateWeakKey, count: 2)])
    }

    @Test func certificatesMadeByOpenSSLAreRecognizedByKeySize() throws {
        let clock = Fixtures.opensslClock
        #expect(try findings(der: Fixtures.opensslRSA1024, now: clock) == [PreviewFinding(kind: .certificateWeakKey, count: 1)])
        #expect(try findings(der: Fixtures.opensslRSA2048, now: clock).isEmpty)
        // The same certificates against a clock after their end are expired, with the key finding kept.
        let afterEnd = Date(timeIntervalSince1970: 2_145_916_800) // 2038-01-01
        #expect(try findings(der: Fixtures.opensslRSA1024, now: afterEnd).map(\.kind) == [.certificateExpired, .certificateWeakKey])
        #expect(try findings(der: Fixtures.opensslRSA2048, now: afterEnd) == [Self.expired])
    }

    @Test func aShortKeyAndAnExpiredDateAreReportedTogether() throws {
        let der = Fixtures.rsaCertificate(bits: 1_024, end: -day)
        #expect(try findings(der: der) == [Self.expired, PreviewFinding(kind: .certificateWeakKey, count: 1)])
    }

    // MARK: Shape

    @Test func findingsCarryNoLinesOrSourceValuesAndTheSeverityIsTheKindDefault() throws {
        let der = Fixtures.rsaCertificate(bits: 1_024, start: day, end: 5 * day)
        let result = try findings(der: der)
        #expect(Set(result.map(\.kind)) == [.certificateExpiresSoon, .certificateNotYetValid, .certificateWeakKey])
        for finding in result {
            #expect(finding.lines.isEmpty)
            #expect(finding.severity == finding.kind.defaultSeverity)
            if finding.kind != .certificateExpiresSoon { #expect(finding.detail == .none) }
        }
    }

    @Test func addingFindingsDoesNotChangeTheSummaryDocument() throws {
        let document = try CertificateAdapter(now: { Fixtures.now }).parse(
            FileBytes(data: Fixtures.rsaCertificate(bits: 1_024, end: 5 * day)), context: PackageTestSupport.context)
        #expect(!document.findings.isEmpty)
        #expect(document.origin == .summary && document.syntax == .json && document.usesStructuredPrivacy)
        #expect(document.images.isEmpty && document.sensitiveRanges.isEmpty && document.facts == .none)
        let summary = PackageTestSupport.object(document)
        #expect(summary["encoding"] as? String == "DER" && summary["certificateCount"] as? Int == 1)
        let certificate = try #require((summary["certificates"] as? [[String: Any]])?.first)
        #expect(certificate["publicKeyAlgorithm"] as? String == "RSA" && certificate["publicKeyBits"] as? Int == 1_024)
        #expect(certificate["expired"] as? Bool == false)
        // Summary and findings are one decision: the flag and the finding agree.
        let expiredDocument = try CertificateAdapter(now: { Fixtures.after(6 * Fixtures.day) }).parse(
            FileBytes(data: Fixtures.rsaCertificate(bits: 1_024, end: 5 * day)), context: PackageTestSupport.context)
        let flagged = (PackageTestSupport.object(expiredDocument)["certificates"] as? [[String: Any]])?.first?["expired"] as? Bool
        #expect(flagged == true && expiredDocument.findings.contains { $0.kind == .certificateExpired })
    }

    @Test func aCertificateWithNoFindingsStillCarriesAnEmptyList() throws {
        let document = try CertificateAdapter(now: { Fixtures.now }).parse(
            FileBytes(data: PackageFixtures.certificate()), context: PackageTestSupport.context)
        #expect(document.findings.isEmpty)
    }
}

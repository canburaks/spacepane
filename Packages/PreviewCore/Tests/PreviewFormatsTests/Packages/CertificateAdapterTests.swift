import Foundation
import CryptoKit
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Certificate summaries")
struct CertificateAdapterTests {
    private let context = PackageTestSupport.context
    private func adapter(now: Date = PackageTestSupport.now) -> CertificateAdapter { CertificateAdapter(now: { now }) }

    @Test func derCertificateReportsEveryRequestedField() throws {
        let der = PackageFixtures.certificate()
        let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: der), context: context))
        #expect(summary["encoding"] as? String == "DER")
        #expect(summary["certificateCount"] as? Int == 1)
        let certificate = try #require((summary["certificates"] as? [[String: Any]])?.first)
        let subject = try #require(certificate["subject"] as? String)
        #expect(subject.contains("CN=example.test") && subject.contains("O=Example Org") && subject.contains("C=US"))
        #expect(certificate["issuer"] as? String == subject)
        #expect(certificate["serialNumber"] as? String == "12:34:56:78")
        #expect(certificate["notBefore"] as? String == "2026-01-01T00:00:00Z")
        #expect(certificate["notAfter"] as? String == "2036-01-01T00:00:00Z")
        #expect(certificate["expired"] as? Bool == false)
        #expect(certificate["publicKeyAlgorithm"] as? String == "EC")
        #expect(certificate["publicKeyBits"] as? Int == 256)
        #expect(certificate["sha256"] as? String == Data(SHA256.hash(data: der)).hexadecimal(separator: ":"))
        #expect(certificate["sha1"] as? String == Data(Insecure.SHA1.hash(data: der)).hexadecimal(separator: ":"))
        let names = try #require(certificate["subjectAlternativeNames"] as? [String])
        #expect(names.contains("DNS: example.test") && names.contains("DNS: www.example.test") && names.contains("IP: 127.0.0.1"))
    }

    @Test func expiryFollowsTheInjectedClock() throws {
        let der = PackageFixtures.certificate(notBefore: "190101000000Z", notAfter: "200101000000Z")
        let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: der), context: context))
        let certificate = try #require((summary["certificates"] as? [[String: Any]])?.first)
        #expect(certificate["expired"] as? Bool == true)
        let early = PackageTestSupport.object(try adapter(now: Date(timeIntervalSince1970: 1_500_000_000))
            .parse(FileBytes(data: PackageFixtures.certificate()), context: context))
        #expect((early["certificates"] as? [[String: Any]])?.first?["expired"] as? Bool == false)
    }

    @Test func pemBundlesListEveryCertificateAndSkipSurroundingText() throws {
        let first = PackageFixtures.certificate(commonName: "first.test", serial: 1)
        let second = PackageFixtures.certificate(commonName: "second.test", serial: 2)
        let text = "Bag Attributes\n    friendlyName: ignored\n" + PackageFixtures.pem(label: "CERTIFICATE", body: first)
            + "\n# comment\n" + PackageFixtures.pem(label: "CERTIFICATE", body: second, lineLength: 76)
        let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: Data(text.utf8)), context: context))
        #expect(summary["encoding"] as? String == "PEM")
        #expect(summary["certificateCount"] as? Int == 2)
        let subjects = (summary["certificates"] as? [[String: Any]])?.compactMap { $0["subject"] as? String } ?? []
        #expect(subjects.count == 2 && subjects[0].contains("first.test") && subjects[1].contains("second.test"))
    }

    @Test func crlfLineEndingsParse() throws {
        let text = PackageFixtures.pem(label: "CERTIFICATE", body: PackageFixtures.certificate()).replacingOccurrences(of: "\n", with: "\r\n")
        let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: Data(text.utf8)), context: context))
        #expect(summary["certificateCount"] as? Int == 1)
        #expect(summary["unreadableCertificates"] == nil)
    }

    @Test(arguments: ["PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "ENCRYPTED PRIVATE KEY", "OPENSSH PRIVATE KEY", "DSA PRIVATE KEY"])
    func privateKeyBlocksAreCountedButNeverDecodedOrShown(label: String) throws {
        // The body is deliberately a recognizable marker so any decoding or copying would show.
        let body = Data((PackageFixtures.secret + "-private-key-body-bytes").utf8)
        let text = PackageFixtures.pem(label: label, body: body) + PackageFixtures.pem(label: "CERTIFICATE", body: PackageFixtures.certificate())
        let document = try adapter().parse(FileBytes(data: Data(text.utf8)), context: context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["privateKeys"] as? Int == 1)
        #expect(summary["privateKeyKinds"] as? [String] == [label])
        #expect(summary["certificateCount"] as? Int == 1)
        for representation in [document.text, PackageTestSupport.concealedText(document)] {
            #expect(!representation.contains(PackageFixtures.secret))
            #expect(!representation.contains(body.base64EncodedString()))
            #expect(!representation.contains("-----BEGIN"))
        }
        #expect(document.sensitiveRanges.isEmpty)
    }

    @Test func aFileWithOnlyAPrivateKeyStillPreviewsWithoutShowingIt() throws {
        let body = Data(repeating: 0x41, count: 120)
        let text = PackageFixtures.pem(label: "RSA PRIVATE KEY", body: body)
        let document = try adapter().parse(FileBytes(data: Data(text.utf8)), context: context)
        let summary = PackageTestSupport.object(document)
        #expect(summary["privateKeys"] as? Int == 1)
        #expect(summary["certificates"] == nil)
        #expect(!document.text.contains(body.base64EncodedString().prefix(16)))
    }

    @Test func unterminatedPrivateKeyBlocksAreStillHidden() throws {
        let text = "-----BEGIN PRIVATE KEY-----\n" + String(repeating: "QUJD", count: 40) + "\n"
        let document = try adapter().parse(FileBytes(data: Data(text.utf8)), context: context)
        #expect(PackageTestSupport.object(document)["privateKeys"] as? Int == 1)
        #expect(!document.text.contains("QUJD"))
    }

    @Test func malformedCertificateBlocksAreCountedNotShown() throws {
        let valid = PackageFixtures.pem(label: "CERTIFICATE", body: PackageFixtures.certificate())
        let invalidBase64 = "-----BEGIN CERTIFICATE-----\n!!!not base64!!!\n-----END CERTIFICATE-----\n"
        let notACertificate = PackageFixtures.pem(label: "CERTIFICATE", body: Data("not der".utf8))
        let unterminated = "-----BEGIN CERTIFICATE-----\nQUJD\n"
        let summary = PackageTestSupport.object(try adapter().parse(
            FileBytes(data: Data((valid + invalidBase64 + notACertificate + unterminated).utf8)), context: context))
        #expect(summary["certificateCount"] as? Int == 4)
        #expect((summary["certificates"] as? [Any])?.count == 1)
        #expect(summary["unreadableCertificates"] as? Int == 3)
    }

    @Test func otherPEMBlocksAreOnlyCounted() throws {
        let text = PackageFixtures.pem(label: "PUBLIC KEY", body: Data(repeating: 1, count: 40)) + PackageFixtures.pem(label: "CERTIFICATE", body: PackageFixtures.certificate())
        let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: Data(text.utf8)), context: context))
        #expect(summary["otherBlocks"] as? Int == 1)
        #expect(summary["certificateCount"] as? Int == 1)
    }

    @Test func malformedInputsFailClosed() {
        for data in [Data(), Data("plain text, no armor".utf8), Data(repeating: 0xFF, count: 64),
                     Data(PackageFixtures.certificate().dropLast(7)), Data([0x30, 0x82, 0xFF, 0xFF])] {
            #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(FileBytes(data: data), context: context) }
        }
    }

    @Test func certificateCountIsBoundedAndFlaggedPartial() throws {
        let block = PackageFixtures.pem(label: "CERTIFICATE", body: PackageFixtures.certificate())
        let summary = PackageTestSupport.object(try adapter().parse(
            FileBytes(data: Data(String(repeating: block, count: 40).utf8)), context: context))
        #expect((summary["certificates"] as? [Any])?.count == CertificateAdapter.maximumCertificates)
        #expect(summary["certificateCount"] as? Int == 40)
        #expect(summary["partial"] as? Bool == true)
    }

    @Test func blockCountIsBounded() throws {
        let junk = String(repeating: "-----BEGIN DH PARAMETERS-----\nQUJD\n-----END DH PARAMETERS-----\n", count: 100)
        let summary = PackageTestSupport.object(try adapter().parse(FileBytes(data: Data(junk.utf8)), context: context))
        #expect(summary["otherBlocks"] as? Int == CertificateAdapter.maximumBlocks)
        #expect(summary["partial"] as? Bool == true)
    }

    @Test func oversizedDERIsRejectedBeforeParsing() {
        let large = Data([0x30, 0x83, 0x03, 0x00, 0x00]) + Data(repeating: 0, count: CertificateAdapter.maximumCertificateBytes + 10)
        #expect(throws: PreviewFailure.malformedDocument) { try adapter().parse(FileBytes(data: large), context: context) }
    }

    @Test func cancelledRequestsNeverReachTheParser() async {
        let pem = Data(PackageFixtures.pem(label: "CERTIFICATE", body: PackageFixtures.certificate()).utf8)
        let cancelled = await PackageTestSupport.parseIsCancelled { _ = try CertificateAdapter().parse(FileBytes(data: pem), context: RequestContext(budget: .standard)) }
        #expect(cancelled)
    }
}

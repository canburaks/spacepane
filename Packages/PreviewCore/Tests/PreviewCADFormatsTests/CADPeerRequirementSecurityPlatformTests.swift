import Foundation
import Testing
import Security
@testable import PreviewCADFormats

/// Security-framework checks of the CAD peer requirement. They use two code-signing calls that no other test
/// makes (`SecRequirementCopyString`, `SecStaticCodeCheckValidity`), so they sit apart from the string tests:
/// a compile problem here must not hide the string checks.
@Suite("CAD peer requirement in Security") struct CADPeerRequirementSecurityPlatformTests {
    private static let team = "ABCDE12345"

    private func compiledRequirement(identifier: String) throws -> SecRequirement {
        let text = try #require(CADPeerRequirement.text(identifier: identifier, team: Self.team))
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        try #require(status == errSecSuccess)
        return try #require(requirement)
    }

    @Test func securityReadsAllThreeAlternativesBackFromTheCompiledRequirement() throws {
        let requirement = try compiledRequirement(identifier: "org.example.spacepane.preview")
        var canonical: CFString?
        let status = SecRequirementCopyString(requirement, [], &canonical)
        try #require(status == errSecSuccess)
        let text = try #require(canonical as String?)
        // Security may print the team with or without quotes, so each expectation is a fragment.
        #expect(text.contains("anchor apple generic"))
        #expect(text.contains("org.example.spacepane.preview"))
        #expect(text.contains("1.2.840.113635.100.6.1.9"))
        #expect(text.contains("1.2.840.113635.100.6.1.25.1"))
        #expect(text.contains("subject.OU"))
        #expect(text.contains("ABCDE12345"))
    }

    @Test func anAppleSignedPeerWithTheRightIdentifierButNoneOfTheThreeAlternativesIsRejected() throws {
        // /usr/bin/true is signed by Apple, so it satisfies the anchor. Its identifier is read from its own
        // signature, which leaves only the certificate clause to reject it: neither store marker nor the
        // (made-up) team is in its leaf certificate.
        var staticCode: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(URL(fileURLWithPath: "/usr/bin/true") as CFURL, SecCSFlags(), &staticCode)
        try #require(created == errSecSuccess)
        let code = try #require(staticCode)
        var information: CFDictionary?
        let read = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        try #require(read == errSecSuccess)
        let identifier = try #require((information as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String)
        let requirement = try compiledRequirement(identifier: identifier)
        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(), requirement)
        #expect(validity == errSecCSReqFailed)
    }
}

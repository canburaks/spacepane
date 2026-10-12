import Foundation
import Testing
import Security
@testable import PreviewCADFormats

/// The requirement the private CAD service places on its client (decision 027, Q-44). Expected texts are written
/// out in full on purpose: a changed production constant must fail here instead of being followed.
@Suite("CAD peer requirement") struct CADPeerRequirementPlatformTests {
    static let identifier = "org.example.spacepane.preview"
    static let team = "ABCDE12345"

    @Test func acceptsTheMacAppStoreMarkerTheTestFlightMarkerOrTheTeamOrganizationalUnit() throws {
        let text = try #require(CADPeerRequirement.text(identifier: Self.identifier, team: Self.team))
        #expect(text == "anchor apple generic and identifier \"org.example.spacepane.preview\" and (certificate leaf[field.1.2.840.113635.100.6.1.9] exists or certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists or certificate leaf[subject.OU] = \"ABCDE12345\")")
    }

    @Test func offersExactlyThreeAlternativesBehindTheAnchorAndTheIdentifier() throws {
        let text = try #require(CADPeerRequirement.text(identifier: Self.identifier, team: Self.team))
        let opening = "anchor apple generic and identifier \"org.example.spacepane.preview\" and ("
        #expect(text.hasPrefix(opening))
        #expect(text.hasSuffix(")"))
        let alternatives = String(text.dropFirst(opening.count).dropLast()).components(separatedBy: " or ")
        #expect(alternatives == [
            "certificate leaf[field.1.2.840.113635.100.6.1.9] exists",
            "certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists",
            "certificate leaf[subject.OU] = \"ABCDE12345\"",
        ])
    }

    @Test func onlyTheOrganizationalUnitAlternativeNamesTheTeam() throws {
        let text = try #require(CADPeerRequirement.text(identifier: Self.identifier, team: Self.team))
        // The two store forms carry no team of their own, so the team may appear exactly once, in the OU test.
        #expect(text.components(separatedBy: Self.team).count == 2)
        #expect(text.hasSuffix("certificate leaf[subject.OU] = \"ABCDE12345\")"))
        // The identifier clause precedes the alternatives, and nothing else repeats it.
        #expect(text.components(separatedBy: Self.identifier).count == 2)
    }

    @Test func aDifferentTeamChangesNothingButTheOrganizationalUnitValue() throws {
        let first = try #require(CADPeerRequirement.text(identifier: Self.identifier, team: "ABCDE12345"))
        let second = try #require(CADPeerRequirement.text(identifier: Self.identifier, team: "ZYXWV98765"))
        #expect(first != second)
        #expect(first.replacingOccurrences(of: "ABCDE12345", with: "ZYXWV98765") == second)
    }

    @Test func securityCompilesTheRequirementText() throws {
        let text = try #require(CADPeerRequirement.text(identifier: Self.identifier, team: Self.team))
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(text as CFString, [], &requirement)
        #expect(status == errSecSuccess)
        #expect(requirement != nil)
    }

    @Test func acceptsLettersDigitsDotAndHyphenOnly() {
        #expect(CADPeerRequirement.text(identifier: "Org-Example.preview9", team: "Z0z-.") != nil)
        #expect(CADPeerRequirement.isAllowedValue("a"))
    }

    @Test(arguments: ["", " ", "a b", "a\"b", "a\\b", "a\nb", "a\n", "a/b", "a(b)", "a*b", "a;b", "a'b", "a_b",
                      "é", "ı", "a\u{0663}", "a\u{FF21}", "a\u{200B}", "a\0b"])
    func rejectsValuesOutsideTheAllowList(value: String) {
        #expect(CADPeerRequirement.text(identifier: value, team: Self.team) == nil)
        #expect(CADPeerRequirement.text(identifier: Self.identifier, team: value) == nil)
        #expect(!CADPeerRequirement.isAllowedValue(value))
    }

    @Test func aValueCannotCloseTheQuotesAndAddAnAlternative() {
        let injected = "x\" or anchor apple and identifier \"y"
        #expect(CADPeerRequirement.text(identifier: injected, team: Self.team) == nil)
        #expect(CADPeerRequirement.text(identifier: Self.identifier, team: "T\") or (identifier \"y") == nil)
    }
}

/// The code-signing requirement the private CAD import service puts on its one client, the Quick Look preview
/// extension of the same build (decision 006). Both values come from the service's own Info.plist, which Xcode
/// fills from build settings; they are never values from a source file. Each must pass a strict allow-list
/// before it is placed inside requirement text, so an unsigned or malformed development identity makes the
/// service refuse every connection instead of accepting a looser peer.
///
/// The requirement accepts the client's signature in any of the three forms it can take, each anchored to Apple's
/// roots and to the extension's exact signing identifier:
/// - Signed with the team's own Apple Development or Apple Distribution certificate, which carries the team in
///   the leaf certificate's organizational unit (`subject.OU`). Every host observation so far used this form.
///   It is the only form that can name the team.
/// - Delivered through the Mac App Store, where Apple signs the product again with its Mac App Store
///   certificate. The leaf carries the Mac App Store marker extension (1.2.840.113635.100.6.1.9) and no
///   organizational unit.
/// - Delivered through TestFlight, where Apple signs with a different certificate ("TestFlight Beta
///   Distribution"). The leaf carries the TestFlight marker extension (1.2.840.113635.100.6.1.25.1), not the
///   Mac App Store marker, and an organizational unit that reads TESTFLIGHT instead of a team.
/// The two store forms cannot name the team: they rest on the exact identifier clause and on an embedded XPC
/// service being private to the bundle that contains it (Apple documents that for apps; the preview extension
/// reached its own service on 2026-10-04).
///
/// Measured on 2026-10-10 with `codesign` on other vendors' installed apps, not on a SpacePane build: a
/// TestFlight-delivered app failed `codesign --verify -R` with the earlier two-branch shape (Mac App Store marker
/// or team) and passed it with the TestFlight marker added, and Mac App Store apps carry the 6.1.9 marker and no
/// organizational unit. Only an installed TestFlight or Mac App Store build of SpacePane proves the three forms
/// for this product (decision 027, D27).
public enum CADPeerRequirement {
    /// The leaf-certificate extension (OID 1.2.840.113635.100.6.1.9) of Apple's Mac App Store signing certificate.
    /// The requirement language documents this field test with the explicit `exists` keyword.
    private static let macAppStoreLeafMarker = "certificate leaf[field.1.2.840.113635.100.6.1.9] exists"

    /// The leaf-certificate extension (OID 1.2.840.113635.100.6.1.25.1) of the certificate that signs
    /// TestFlight-delivered builds; the Mac App Store marker is absent from it.
    private static let testFlightLeafMarker = "certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists"

    /// Requirement text for the client with signing identifier `identifier` and team `team`, or nil when either
    /// value is empty or holds a character outside ASCII letters, digits, dot and hyphen.
    public static func text(identifier: String, team: String) -> String? {
        guard isAllowedValue(identifier), isAllowedValue(team) else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and (\(macAppStoreLeafMarker) or \(testFlightLeafMarker) or certificate leaf[subject.OU] = \"\(team)\")"
    }

    /// The allow-list: at least one character, each an ASCII letter or digit, a dot or a hyphen. Quotes, spaces,
    /// backslashes, parentheses and non-ASCII digits or letters can never reach the requirement text.
    static func isAllowedValue(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { isAllowedScalar($0) }
    }

    private static func isAllowedScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E: return true
        default: return false
        }
    }
}

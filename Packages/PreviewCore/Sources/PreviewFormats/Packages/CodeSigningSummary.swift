import Foundation
import Security
import PreviewContracts

/// What a bundle's embedded code signature says about it. The signature is read, not validated: no
/// resource is hashed, no trust chain is evaluated, nothing is checked for revocation and notarization
/// is never queried, so none of these facts is a statement that the code is safe or genuine.
struct CodeSigningSummary: Equatable {
    enum Status: String { case signed, adHoc, unsigned, unavailable }
    var status: Status
    var identifier: String?
    var teamIdentifier: String?
    /// Certificate subject names from the leaf (signer) to the root, as stored in the signature.
    var signers: [String] = []
    var hardenedRuntime: Bool?
    var appSandbox: Bool?
    var entitlementKeyCount = 0

    static let unavailable = CodeSigningSummary(status: .unavailable)
    static let unsigned = CodeSigningSummary(status: .unsigned)
}

/// The code-signature facts plus the entitlements, whose values are summarized separately because they
/// are document content whose sensitive-looking entries must be concealed.
struct CodeSignatureReport {
    var summary: CodeSigningSummary
    var entitlements: SummaryValue?
}

/// Seam over the Security framework so privacy behavior is testable without a signed bundle.
protocol CodeSignatureReader: Sendable {
    func read(url: URL, context: RequestContext) throws -> CodeSignatureReport
}

/// Reads signing information through `SecStaticCode`. Any Security failure, which can include sandbox
/// denials inside a Quick Look host, is reported as "not available" rather than raised.
struct SecurityCodeSignatureReader: CodeSignatureReader {
    /// Code-directory flag bits, from the public code-signing header (`CS_ADHOC`, `CS_RUNTIME`).
    private static let adHocFlag: UInt32 = 0x0000_0002
    private static let hardenedRuntimeFlag: UInt32 = 0x0001_0000
    private static let appSandboxEntitlement = "com.apple.security.app-sandbox"

    func read(url: URL, context: RequestContext) throws -> CodeSignatureReport {
        try context.checkpoint()
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
            return CodeSignatureReport(summary: .unavailable)
        }
        try context.checkpoint()
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        try context.checkpoint()
        if status == errSecCSUnsigned { return CodeSignatureReport(summary: .unsigned) }
        guard status == errSecSuccess, let dictionary = information as? [String: Any] else {
            return CodeSignatureReport(summary: .unavailable)
        }
        // Unsigned code can still succeed here, returning only facts such as its main executable.
        guard dictionary[kSecCodeInfoIdentifier as String] != nil || dictionary[kSecCodeInfoUnique as String] != nil else {
            return CodeSignatureReport(summary: .unsigned)
        }
        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber).map { UInt32(truncatingIfNeeded: $0.uint64Value) } ?? 0
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let isAdHoc = flags & Self.adHocFlag != 0
        var summary = CodeSigningSummary(status: isAdHoc ? .adHoc : .signed)
        summary.identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
        summary.teamIdentifier = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        summary.hardenedRuntime = flags & Self.hardenedRuntimeFlag != 0
        summary.signers = certificates.prefix(8).compactMap { SecCertificateCopySubjectSummary($0) as String? }
        var entitlementValues: SummaryValue?
        if let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
            summary.entitlementKeyCount = entitlements.count
            summary.appSandbox = (entitlements[Self.appSandboxEntitlement] as? NSNumber)?.boolValue ?? false
            entitlementValues = PlistValueSummary.entitlements(entitlements)
        } else {
            summary.appSandbox = false
        }
        return CodeSignatureReport(summary: summary, entitlements: entitlementValues)
    }
}

extension CodeSignatureReport {
    /// The `signature` object shown in an application summary.
    func summaryValue() -> SummaryValue {
        var fields = SummaryFields()
        fields.text("status", summary.status.rawValue)
        fields.text("signingIdentifier", summary.identifier)
        fields.text("teamIdentifier", summary.teamIdentifier)
        fields.list("signers", summary.signers)
        fields.flag("hardenedRuntime", summary.hardenedRuntime)
        fields.flag("appSandbox", summary.appSandbox)
        if let entitlements { fields.add("entitlements", entitlements) }
        // The signature is read, never validated, and notarization is never queried.
        fields.flag("signatureVerified", false)
        fields.flag("notarizationChecked", false)
        return fields.value
    }
}

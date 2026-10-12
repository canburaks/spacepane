import Foundation
import Security
import PreviewContracts

/// Summarizes an Apple provisioning profile (`.mobileprovision`, `.provisionprofile`).
///
/// A profile is a CMS signed message whose content is a property list. The message is decoded with
/// the system CMS decoder only to reach that content; the signature is never verified and nothing about
/// the profile's validity or trust is claimed. Device identifiers are never shown, only their count,
/// and embedded certificates are reduced to their subject names.
public struct ProvisioningProfileAdapter: BinaryFormatAdapter {
    private let now: @Sendable () -> Date

    public init() { self.init(now: { Date() }) }
    init(now: @escaping @Sendable () -> Date) { self.now = now }

    public func parse(_ input: FileBytes, context: RequestContext) throws -> ParsedTextDocument {
        try context.checkpoint()
        let profile = try ProvisioningProfileSummary.profile(from: input.data, context: context)
        return try PackageSummary.document(ProvisioningProfileSummary.fields(profile, now: now()).value, context: context)
    }
}

/// Shared by the profile adapter and the iOS archive adapter, which embeds a profile.
enum ProvisioningProfileSummary {
    static let maximumCertificates = 16
    static let maximumCertificateBytes = 16_384

    private static let developerCertificatesKey = "DeveloperCertificates"
    private static let getTaskAllowEntitlement = "get-task-allow"

    /// The profile's property list, decoded from its CMS envelope. Unsigned property lists, which some
    /// tools write, are accepted as they are.
    static func profile(from data: Data, context: RequestContext) throws -> [String: Any] {
        try context.checkpoint()
        guard !data.isEmpty else { throw PreviewFailure.malformedDocument }
        let content = looksLikePropertyList(data) ? data : try CMSContent.extract(data, maximumBytes: context.budget.maxInputBytes, context: context)
        return try BoundedPropertyList.dictionary(content, context: context)
    }

    private static func looksLikePropertyList(_ data: Data) -> Bool {
        if data.starts(with: Array("bplist00".utf8)) { return true }
        // Skip leading whitespace and a byte-order mark; a CMS envelope begins with the binary 0x30 tag.
        let leading = data.prefix(64).first { !$0.isASCIIWhitespace && $0 != 0xEF && $0 != 0xBB && $0 != 0xBF }
        return leading == UInt8(ascii: "<")
    }

    static func fields(_ profile: [String: Any], now: Date) -> SummaryFields {
        var fields = SummaryFields()
        let entitlements = profile["Entitlements"] as? [String: Any] ?? [:]
        fields.text("name", PlistAccess.string(profile, "Name"))
        fields.text("uuid", PlistAccess.string(profile, "UUID"))
        fields.text("appIDName", PlistAccess.string(profile, "AppIDName"))
        fields.text("teamName", PlistAccess.string(profile, "TeamName"))
        fields.text("teamIdentifier", PlistAccess.strings(profile, "TeamIdentifier").first
                    ?? PlistAccess.string(entitlements, "com.apple.developer.team-identifier"))
        fields.list("platforms", PlistAccess.strings(profile, "Platform"))
        fields.text("profileType", profileType(profile, entitlements: entitlements))
        let created = PlistAccess.date(profile, "CreationDate")
        let expires = PlistAccess.date(profile, "ExpirationDate")
        fields.date("creationDate", created)
        fields.date("expirationDate", expires)
        if let expires { fields.flag("expired", expires < now) }
        if let value = PlistValueSummary.entitlements(entitlements) { fields.add("entitlements", value) }
        // Provisioned devices are personal identifiers of the team's hardware: only their number is shown.
        if profile["ProvisionedDevices"] is [Any] { fields.number("provisionedDevices", PlistAccess.array(profile, "ProvisionedDevices").count) }
        fields.flag("provisionsAllDevices", PlistAccess.bool(profile, "ProvisionsAllDevices"))
        let certificates = (profile[developerCertificatesKey] as? [Any])?.compactMap { $0 as? Data } ?? []
        if !certificates.isEmpty {
            fields.number("certificateCount", certificates.count)
            fields.list("certificates", certificates.prefix(maximumCertificates).compactMap(subjectName))
        }
        // The message signature is neither verified nor trusted.
        fields.flag("signatureVerified", false)
        return fields
    }

    /// Raw values mapped to localized labels by the renderer.
    static func profileType(_ profile: [String: Any], entitlements: [String: Any]) -> String {
        if PlistAccess.bool(profile, "ProvisionsAllDevices") == true { return "enterprise" }
        if profile["ProvisionedDevices"] is [Any] {
            return PlistAccess.bool(entitlements, getTaskAllowEntitlement) == true ? "development" : "adHoc"
        }
        return "distribution"
    }

    private static func subjectName(_ der: Data) -> String? {
        guard der.count <= maximumCertificateBytes,
              let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        return SecCertificateCopySubjectSummary(certificate) as String?
    }
}

/// Extracts the encapsulated content of a CMS message without verifying it.
enum CMSContent {
    static func extract(_ data: Data, maximumBytes: Int, context: RequestContext) throws -> Data {
        try context.checkpoint()
        var decoder: CMSDecoder?
        guard CMSDecoderCreate(&decoder) == errSecSuccess, let decoder else { throw PreviewFailure.unavailableContent }
        let updated = data.withUnsafeBytes { buffer -> OSStatus in
            guard let base = buffer.baseAddress else { return errSecParam }
            return CMSDecoderUpdateMessage(decoder, base, buffer.count)
        }
        guard updated == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else {
            throw PreviewFailure.malformedDocument
        }
        try context.checkpoint()
        var encrypted: DarwinBoolean = false
        if CMSDecoderIsContentEncrypted(decoder, &encrypted) == errSecSuccess, encrypted.boolValue {
            throw PreviewFailure.encryptedContent
        }
        var content: CFData?
        guard CMSDecoderCopyContent(decoder, &content) == errSecSuccess, let content else { throw PreviewFailure.malformedDocument }
        let result = content as Data
        guard result.count <= maximumBytes else { throw PreviewFailure.inputTooLarge }
        try context.checkpoint()
        return result
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool { self == 0x20 || (0x09...0x0D).contains(self) }
}
